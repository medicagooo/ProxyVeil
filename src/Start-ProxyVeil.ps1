#requires -Version 7.0
[CmdletBinding()]
param([ValidateSet('Standard','Administrator')][string]$Edition='Standard',[string]$TargetUserSid,[string]$StateDirectory,[string]$FixtureRoot,[switch]$RenderOnly,[string]$RenderPath,[ValidateSet('Idle','Settings','Completed')][string]$RenderState='Idle',[switch]$SmokeTest,[switch]$InjectProgressReadFault,[switch]$FailureSmokeTest,[switch]$ForceOpaque,[ValidateSet('Auto','en','zh-CN')][string]$Language='Auto')
$ErrorActionPreference='Stop'
Import-Module "$PSScriptRoot\ProxyVeil.Core.psm1" -Force
Set-PvLanguage $Language
$Language=Get-PvLanguage
if ($InjectProgressReadFault -and -not $FixtureRoot) { throw (Get-PvText 'Test.FaultIsolation') }
if ($FailureSmokeTest -and -not $FixtureRoot) { throw (Get-PvText 'Test.FailureIsolation') }
if ($ForceOpaque -and (-not $FixtureRoot -or (-not $RenderOnly -and -not $SmokeTest))) { throw (Get-PvText 'Test.FallbackIsolation') }
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw (Get-PvText 'Error.UiApartment') }
if (-not $StateDirectory) { $StateDirectory=Get-PvDefaultStateDirectory }
if (-not $TargetUserSid) { $TargetUserSid=Get-PvIdentity }
if ($TargetUserSid -ne (Get-PvIdentity)) { throw (Get-PvText 'Error.UiWrongUser') }
if ($Edition -eq 'Administrator' -and -not $FixtureRoot -and -not (Test-PvAdministrator)) { throw (Get-PvText 'Error.UiAdminLauncher') }
$xaml=[IO.File]::ReadAllText("$PSScriptRoot\UI\MainWindow.xaml")
$reader=[Xml.XmlNodeReader]::new([xml]$xaml)
$window=[Windows.Markup.XamlReader]::Load($reader)
foreach ($entry in (Get-PvStrings).GetEnumerator()) { $window.Resources['Text.'+$entry.Key]=$entry.Value }
$ui=@{}
foreach ($name in @('ActionButton','SettingsButton','SettingsPanel','MinimizeButton','CloseButton','TitleBar','ModeLabel','EditionLabel','ModeBox','DnsCheck','RtcCheck','Ipv6Check','RestartCheck','InstallBox','ConfigBox','GroupBox','DetectButton','StatusTitle','StatusDetail','Checklist','Emblem','ResultNote','PolicyButton')) { $ui[$name]=$window.FindName($name) }
$script:busy=$false; $script:worker=$null; $script:rows=@{}; $script:seen=0; $script:resultConsumed=$false
$script:progressReadFaultPending=[bool]$InjectProgressReadFault
$script:active=Test-Path -LiteralPath (Join-Path $StateDirectory 'active.json')
$settingsPath=Join-Path $StateDirectory 'settings.json'
$script:timer=[Windows.Threading.DispatcherTimer]::new(); $script:timer.Interval=[TimeSpan]::FromMilliseconds(200)
$ui.EditionLabel.Text=if ($Edition -eq 'Administrator') { (Get-PvText 'UI.Administrator') } else { (Get-PvText 'UI.Standard') }
function Sync-PvMode { $ui.ModeLabel.Text=(Get-PvText 'UI.Mode' -Arguments @($ui.ModeBox.SelectedItem.Content)) }
function Set-PvActiveButton {
    $ui.ActionButton.Content=if ($script:active) { (Get-PvText 'UI.Restore') } else { (Get-PvText 'UI.Repair') }
    $ui.ActionButton.Background=if ($script:active) { [Windows.Media.BrushConverter]::new().ConvertFromString('#157C70') } else { [Windows.Media.BrushConverter]::new().ConvertFromString('#235EE8') }
}
function Show-PvEvent($Event) {
    if (-not $script:rows.ContainsKey($Event.id)) {
        $row=[Windows.Controls.Grid]::new(); $row.Margin=[Windows.Thickness]::new(0,0,0,16)
        $left=[Windows.Controls.ColumnDefinition]::new(); $left.Width=[Windows.GridLength]::new(32); $row.ColumnDefinitions.Add($left); $row.ColumnDefinitions.Add([Windows.Controls.ColumnDefinition]::new())
        $symbol=[Windows.Controls.TextBlock]::new(); $symbol.FontSize=20; $symbol.FontWeight='SemiBold'; $row.Children.Add($symbol) | Out-Null
        $stack=[Windows.Controls.StackPanel]::new(); [Windows.Controls.Grid]::SetColumn($stack,1); $row.Children.Add($stack) | Out-Null
        $label=[Windows.Controls.TextBlock]::new(); $label.Text=$Event.label; $label.FontWeight='SemiBold'; $stack.Children.Add($label) | Out-Null
        $detail=[Windows.Controls.TextBlock]::new(); $detail.FontSize=12; $detail.Margin=[Windows.Thickness]::new(0,5,0,0); $detail.TextWrapping='Wrap'; $detail.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#607A8D'); $stack.Children.Add($detail) | Out-Null
        $ui.Checklist.Children.Add($row) | Out-Null
        $script:rows[$Event.id]=@{symbol=$symbol;detail=$detail}
    }
    $entry=$script:rows[$Event.id]
    $entry.symbol.Text=switch ($Event.status) { running {'◌'} applied {'✓'} skipped {'!'} error {'×'} default {'○'} }
    $entry.symbol.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString($(switch ($Event.status) { applied {'#157C70'} skipped {'#A86812'} error {'#B22F43'} default {'#235EE8'} }))
    $entry.detail.Text=$Event.detail
}
function Invoke-PvDetect {
    try {
        $c=Get-PvContext -InstallPath $ui.InstallBox.Text -ConfigDirectory $ui.ConfigBox.Text -ProxyGroup $ui.GroupBox.Text -FixtureRoot $FixtureRoot
        $ui.InstallBox.Text=$c.Exe; $ui.ConfigBox.Text=$c.Directory; $ui.GroupBox.Items.Clear()
        foreach ($g in $c.Groups) { $ui.GroupBox.Items.Add($g) | Out-Null }
        $ui.GroupBox.Text=$c.Group
        $ui.ModeBox.SelectedIndex=if ($c.Mode -eq 'TUN') { 0 } else { 1 }
        Sync-PvMode
        $ui.StatusDetail.Text=(Get-PvText 'UI.Detected')
    } catch { $ui.SettingsPanel.Visibility='Visible'; $ui.StatusDetail.Text=$_.Exception.Message }
}
function Set-PvBusy([bool]$Value) {
    $script:busy=$Value
    foreach ($name in @('ActionButton','SettingsButton','SettingsPanel','CloseButton')) { $ui[$name].IsEnabled=-not $Value }
}
function Start-PvWork {
    if ($script:busy) { return }
    $items=@(); if ($ui.DnsCheck.IsChecked) { $items+='DNS' }; if ($ui.RtcCheck.IsChecked) { $items+='WebRTC' }; if ($ui.Ipv6Check.IsChecked) { $items+='IPv6' }
    if (-not $script:active -and -not $items.Count) { $ui.StatusDetail.Text=(Get-PvText 'UI.SelectItem'); $ui.SettingsPanel.Visibility='Visible'; return }
    # Preparation and process launch share the UI failure boundary; no worker starts
    # until request/settings are saved. An unreadable snapshot stays available for recovery.
    try {
    $null=New-Item -ItemType Directory -Path $StateDirectory -Force
    $run=Join-Path $StateDirectory ('run-'+[guid]::NewGuid().ToString('N')); $null=New-Item -ItemType Directory -Path $run
    $script:runDirectory=$run; $script:progress=Join-Path $run 'progress.jsonl'; $script:resultPath=Join-Path $run 'result.json'
    $req=@{Action=$(if ($script:active) {'Restore'} else {'Repair'});Edition=$Edition;TargetUserSid=$TargetUserSid;Mode=[string]$ui.ModeBox.SelectedItem.Content;Items=$items;InstallPath=$ui.InstallBox.Text;ConfigDirectory=$ui.ConfigBox.Text;ProxyGroup=$ui.GroupBox.Text;Restart=[bool]$ui.RestartCheck.IsChecked;StateDirectory=$StateDirectory;Language=$Language}
    Save-PvJson (Join-Path $run 'request.json') $req
    Save-PvJson $settingsPath @{Mode=$req.Mode;Items=$items;InstallPath=$req.InstallPath;ConfigDirectory=$req.ConfigDirectory;ProxyGroup=$req.ProxyGroup;Restart=$req.Restart}
    $ui.Checklist.Children.Clear(); $script:rows=@{}; $script:seen=0; $script:resultConsumed=$false
    $ui.SettingsPanel.Visibility='Collapsed'; $ui.Emblem.Visibility='Collapsed'; $ui.ResultNote.Visibility='Collapsed'
    $ui.StatusTitle.Text=if ($script:active) { (Get-PvText 'UI.Restoring') } else { (Get-PvText 'UI.Repairing') }; $ui.StatusDetail.Text=(Get-PvText 'UI.CheckSaveModify')
    Set-PvBusy $true
        $psi=[Diagnostics.ProcessStartInfo]::new(); $psi.FileName=(Get-Process -Id $PID).Path; $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
        foreach ($arg in @('-NoProfile','-NonInteractive','-File',"$PSScriptRoot\Invoke-Worker.ps1",'-RequestPath',(Join-Path $run 'request.json'),'-ProgressPath',$script:progress,'-ResultPath',$script:resultPath,'-Language',$Language)) { $psi.ArgumentList.Add($arg) }
        if ($FixtureRoot) { $psi.ArgumentList.Add('-FixtureRoot'); $psi.ArgumentList.Add($FixtureRoot) }
        $script:worker=[Diagnostics.Process]::Start($psi)
        $script:timer.Start()
    } catch { Set-PvBusy $false; $ui.StatusTitle.Text=(Get-PvText 'UI.StartFailed'); $ui.StatusDetail.Text=$_.Exception.Message }
}
$script:timer.Add_Tick({
    if (-not $script:worker) { return }
    try {
        if (Test-Path -LiteralPath $script:progress) {
            try {
                if ($script:progressReadFaultPending) { $script:progressReadFaultPending=$false; throw [IO.IOException]::new('Fixture progress sharing conflict') }
                $lines=Read-PvProgressLines $script:progress
            } catch [IO.IOException] {
                if (-not $script:worker.HasExited) { $ui.StatusDetail.Text=(Get-PvText 'UI.WaitProgress'); return }
                # A completed worker's result and snapshot determine the outcome,
                # even if its optional progress log remains unreadable.
                $lines=@()
            }
            # One event per tick makes the checklist reveal sequentially; partial JSONL
            # writes are retried without consuming the line.
            if ($script:seen -lt $lines.Length) {
                try { $event=ConvertFrom-Json -InputObject $lines[$script:seen] -AsHashtable; Show-PvEvent $event; $script:seen++; return }
                catch {
                    if (-not $script:worker.HasExited) { return }
                    Show-PvEvent @{id='progress-error';label=(Get-PvText 'UI.IncompleteProgress');status='error';detail=(Get-PvText 'UI.ReadFinalResult')}
                    $script:seen=$lines.Length
                }
            }
        }
        if (-not $script:worker.HasExited) { return }
        $script:timer.Stop()
        if (Test-Path -LiteralPath $script:resultPath) { $r=Read-PvJson $script:resultPath }
        else { $r=@{status='Failed';message=(Get-PvText 'UI.WorkerInterrupted');active=[bool](Get-PvActiveSnapshot $StateDirectory)} }
        $script:active=[bool]$r.active; Set-PvActiveButton; Set-PvBusy $false
        $ui.StatusTitle.Text=switch ($r.status) { Configured {(Get-PvText 'UI.Configured')} Partial {(Get-PvText 'UI.Partial')} Restored {(Get-PvText 'UI.Restored')} default {(Get-PvText 'UI.Failed')} }
        $ui.StatusDetail.Text=$r.message
        $ui.ResultNote.Visibility='Visible'
        if ($r.status -eq 'Failed') { Show-PvEvent @{id='failure';label=(Get-PvText 'UI.OperationResult');status='error';detail=$r.message} }
        $script:resultConsumed=$true
        $script:lastResult=$r
        $script:worker.Dispose(); $script:worker=$null
    } catch {
        $message=$_.Exception.Message
        if (-not $script:worker.HasExited) { $ui.StatusDetail.Text=(Get-PvText 'UI.WaitResult'); return }
        $script:timer.Stop()
        $script:active=Test-Path -LiteralPath (Join-Path $StateDirectory 'active.json')
        Set-PvActiveButton; Set-PvBusy $false
        $ui.StatusTitle.Text=(Get-PvText 'UI.ResultReadFailed'); $ui.StatusDetail.Text=$message
        $script:resultConsumed=$true; $script:lastResult=@{status='Failed';active=$script:active;message=$message}
        $script:worker.Dispose(); $script:worker=$null
    }
})
$ui.ActionButton.Add_Click({ Start-PvWork })
$ui.SettingsButton.Add_Click({ $ui.SettingsPanel.Visibility=if ($ui.SettingsPanel.Visibility -eq 'Visible') { 'Collapsed' } else { 'Visible' } })
$ui.DetectButton.Add_Click({ Invoke-PvDetect })
$ui.ModeBox.Add_SelectionChanged({ Sync-PvMode })
$ui.MinimizeButton.Add_Click({ $window.WindowState='Minimized' })
$ui.CloseButton.Add_Click({ $window.Close() })
$ui.TitleBar.Add_MouseLeftButtonDown({ if ($_.ChangedButton -eq 'Left') { $window.DragMove() } })
$ui.PolicyButton.Add_Click({ Start-Process -FilePath 'microsoft-edge:edge://policy' | Out-Null })
$window.Add_Closing({ if ($script:busy) { $_.Cancel=$true; $ui.StatusDetail.Text=(Get-PvText 'UI.WaitClose') } })
$window.Add_SourceInitialized({
    if (-not ('ProxyVeilGlass' -as [type])) { Add-Type -TypeDefinition ([IO.File]::ReadAllText("$PSScriptRoot\UI\Glass.cs")) }
    $hwnd=[Windows.Interop.WindowInteropHelper]::new($window).Handle
    $source=[Windows.Interop.HwndSource]::FromHwnd($hwnd); $source.CompositionTarget.BackgroundColor=[Windows.Media.Colors]::Transparent
    # Hardware composition can expose only the DWM backdrop while automation
    # still sees controls. Render this window in software; keep DWM Acrylic.
    $source.CompositionTarget.RenderMode=[Windows.Interop.RenderMode]::SoftwareOnly
    # Fixture coverage forces the same fallback used when DWM rejects Acrylic.
    $script:glassApplied=if ($ForceOpaque) { $false } else { [ProxyVeilGlass]::Apply($hwnd) }
    if (-not $script:glassApplied) { $window.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#E6E9F1F7') }
})
$savedSettings=$null
if (Test-Path -LiteralPath $settingsPath) {
    try {
        $savedSettings=Read-PvJson $settingsPath
        $ui.InstallBox.Text=[string]$savedSettings.InstallPath
        $ui.ConfigBox.Text=[string]$savedSettings.ConfigDirectory
        $ui.GroupBox.Text=[string]$savedSettings.ProxyGroup
    } catch { $ui.StatusDetail.Text=(Get-PvText 'UI.SettingsFileUnreadable') }
}
Invoke-PvDetect
if ($savedSettings) {
    try {
        $s=$savedSettings
        $ui.ModeBox.SelectedIndex=if ($s.Mode -eq 'TUN') { 0 } else { 1 }
        $ui.DnsCheck.IsChecked='DNS' -in $s.Items; $ui.RtcCheck.IsChecked='WebRTC' -in $s.Items; $ui.Ipv6Check.IsChecked='IPv6' -in $s.Items
        $ui.RestartCheck.IsChecked=[bool]$s.Restart
    } catch { $ui.StatusDetail.Text=(Get-PvText 'UI.SettingsUnreadable') }
}
Set-PvActiveButton
if ($script:active) { $ui.StatusTitle.Text=(Get-PvText 'UI.SnapshotAvailable'); $ui.StatusDetail.Text=(Get-PvText 'UI.SnapshotNote') }
function Save-PvWindowImage([string]$Path) {
    $surface=$window.Content
    $window.Content=$null
    $surface.Background=$window.Background
    $surface.Resources=$window.Resources
    [Windows.Documents.TextElement]::SetFontFamily($surface,$window.FontFamily)
    [Windows.Documents.TextElement]::SetFontSize($surface,$window.FontSize)
    [Windows.Documents.TextElement]::SetForeground($surface,$window.Foreground)
    $surface.Measure([Windows.Size]::new($window.Width,$window.Height)); $surface.Arrange([Windows.Rect]::new(0,0,$window.Width,$window.Height)); $surface.UpdateLayout()
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$window.Width,[int]$window.Height,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($surface)
    $window.Content=$surface
    $pixels=[byte[]]::new([int]$window.Width*[int]$window.Height*4)
    $bitmap.CopyPixels($pixels,[int]$window.Width*4,0)
    $colors=[Collections.Generic.HashSet[int]]::new()
    for ($i=0;$i -lt $pixels.Length;$i+=16) { $null=$colors.Add([BitConverter]::ToInt32($pixels,$i)) }
    if ($colors.Count -lt 32) { throw (Get-PvText 'Test.EmptyRender') }
    $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new(); $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $file=[IO.File]::Create($Path); try { $encoder.Save($file) } finally { $file.Dispose() }
}
if ($FailureSmokeTest) {
    $null=[Windows.Interop.WindowInteropHelper]::new($window).EnsureHandle()
    $ui.ActionButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    $deadline=(Get-Date).AddSeconds(15)
    while ($script:busy -and (Get-Date) -lt $deadline) {
        $frame=[Windows.Threading.DispatcherFrame]::new(); $pump=[Windows.Threading.DispatcherTimer]::new(); $pump.Interval=[TimeSpan]::FromMilliseconds(40)
        $pump.Add_Tick({ $frame.Continue=$false; $pump.Stop() }.GetNewClosure()); $pump.Start(); [Windows.Threading.Dispatcher]::PushFrame($frame)
    }
    if ($script:busy -or -not $ui.ActionButton.IsEnabled -or $script:worker) { throw (Get-PvText 'Test.UiFailureRecovery') }
    if ((Test-Path -LiteralPath (Join-Path $StateDirectory 'active.json')) -and $ui.ActionButton.Content -ne (Get-PvText 'UI.Restore')) { throw (Get-PvText 'Test.RestoreEntryMissing') }
    if ($ui.StatusTitle.Text -notin @((Get-PvText 'UI.StartFailed'),(Get-PvText 'UI.Failed'),(Get-PvText 'UI.ResultReadFailed'))) { throw (Get-PvText 'Test.UiFailureMissing') }
    $window.Close(); 'PASS: UI failure handled'; return
}
if ($RenderOnly -or $SmokeTest) {
    if (-not $FixtureRoot) { throw (Get-PvText 'Test.UiFixtureRequired') }
    $null=[Windows.Interop.WindowInteropHelper]::new($window).EnsureHandle()
    if ($RenderState -eq 'Settings') { $ui.SettingsButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent)) }
    if ($SmokeTest -or $RenderState -eq 'Completed') {
        $ui.ActionButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        $deadline=(Get-Date).AddSeconds(35)
        while ($script:busy -and (Get-Date) -lt $deadline) {
            $frame=[Windows.Threading.DispatcherFrame]::new()
            $pump=[Windows.Threading.DispatcherTimer]::new(); $pump.Interval=[TimeSpan]::FromMilliseconds(40)
            $pump.Add_Tick({ $frame.Continue=$false; $pump.Stop() }.GetNewClosure()); $pump.Start(); [Windows.Threading.Dispatcher]::PushFrame($frame)
        }
        if ($script:busy -or -not $script:resultConsumed -or $script:lastResult.status -ne 'Configured') { throw (Get-PvText 'Test.UiRepairFailed' -Arguments @($ui.StatusDetail.Text)) }
        if ($ui.ActionButton.Content -ne (Get-PvText 'UI.Restore')) { throw (Get-PvText 'Test.UiRestoreButton') }
    }
    if ($RenderPath) {
        Save-PvWindowImage $RenderPath
        Save-PvJson ([IO.Path]::ChangeExtension($RenderPath,'.json')) @{fixture=$true;state=$RenderState;language=$Language;nativeAcrylicAccepted=$script:glassApplied;forcedOpaque=[bool]$ForceOpaque;background=$window.Background.ToString();width=$window.Width;height=$window.Height;actualNetworkTest=$false}
    }
    if ($SmokeTest) {
        $ui.ActionButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        $deadline=(Get-Date).AddSeconds(35)
        while ($script:busy -and (Get-Date) -lt $deadline) {
            $frame=[Windows.Threading.DispatcherFrame]::new(); $pump=[Windows.Threading.DispatcherTimer]::new(); $pump.Interval=[TimeSpan]::FromMilliseconds(40)
            $pump.Add_Tick({ $frame.Continue=$false; $pump.Stop() }.GetNewClosure()); $pump.Start(); [Windows.Threading.Dispatcher]::PushFrame($frame)
        }
        if ($script:busy -or $script:lastResult.status -ne 'Restored' -or $ui.ActionButton.Content -ne (Get-PvText 'UI.Repair')) { throw (Get-PvText 'Test.UiRestoreFailed' -Arguments @($ui.StatusDetail.Text)) }
        'UI repair/restore events passed'
    }
    $window.Close(); return
}
$window.ShowDialog() | Out-Null
