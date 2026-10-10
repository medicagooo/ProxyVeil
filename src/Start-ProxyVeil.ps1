#requires -Version 7.0
[CmdletBinding()]
param([ValidateSet('Standard','Administrator')][string]$Edition='Standard',[string]$TargetUserSid,[string]$StateDirectory,[string]$FixtureRoot,[switch]$RenderOnly,[string]$RenderPath,[ValidateSet('Idle','Settings','Completed')][string]$RenderState='Idle',[switch]$SmokeTest,[switch]$InjectProgressReadFault)
$ErrorActionPreference='Stop'
if ($InjectProgressReadFault -and -not $FixtureRoot) { throw '故障注入仅允许隔离测试。' }
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
Import-Module "$PSScriptRoot\ProxyVeil.Core.psm1" -Force
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'UI 需要 pwsh -STA。请使用项目启动入口。' }
if (-not $StateDirectory) { $StateDirectory=Get-PvDefaultStateDirectory }
if (-not $TargetUserSid) { $TargetUserSid=Get-PvIdentity }
if ($TargetUserSid -ne (Get-PvIdentity)) { throw '管理员版必须通过当前用户的 UAC 启动。' }
if ($Edition -eq 'Administrator' -and -not $FixtureRoot -and -not (Test-PvAdministrator)) { throw '请使用 ProxyVeil.Admin.cmd 启动管理员版。' }
$xaml=[IO.File]::ReadAllText("$PSScriptRoot\UI\MainWindow.xaml")
$reader=[Xml.XmlNodeReader]::new([xml]$xaml)
$window=[Windows.Markup.XamlReader]::Load($reader)
$ui=@{}
foreach ($name in @('ActionButton','SettingsButton','SettingsPanel','MinimizeButton','CloseButton','TitleBar','ModeLabel','EditionLabel','ModeBox','DnsCheck','RtcCheck','Ipv6Check','RestartCheck','InstallBox','ConfigBox','GroupBox','DetectButton','StatusTitle','StatusDetail','Checklist','Emblem','ResultNote','PolicyButton')) { $ui[$name]=$window.FindName($name) }
$script:busy=$false; $script:worker=$null; $script:rows=@{}; $script:seen=0; $script:resultConsumed=$false
$script:progressReadFaultPending=[bool]$InjectProgressReadFault
$script:active=[bool](Get-PvActiveSnapshot $StateDirectory)
$settingsPath=Join-Path $StateDirectory 'settings.json'
$script:timer=[Windows.Threading.DispatcherTimer]::new(); $script:timer.Interval=[TimeSpan]::FromMilliseconds(200)
$ui.EditionLabel.Text=if ($Edition -eq 'Administrator') { '管理员版' } else { '普通权限版' }
function Sync-PvMode { $ui.ModeLabel.Text="$($ui.ModeBox.SelectedItem.Content) 模式" }
function Set-PvActiveButton {
    $ui.ActionButton.Content=if ($script:active) { '还原上次修改' } else { '检查并修复' }
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
        $ui.StatusDetail.Text='已找到 FlClash。修复会保留原有分流与节点。'
    } catch { $ui.SettingsPanel.Visibility='Visible'; $ui.StatusDetail.Text=$_.Exception.Message }
}
function Set-PvBusy([bool]$Value) {
    $script:busy=$Value
    foreach ($name in @('ActionButton','SettingsButton','SettingsPanel','CloseButton')) { $ui[$name].IsEnabled=-not $Value }
}
function Start-PvWork {
    if ($script:busy) { return }
    $items=@(); if ($ui.DnsCheck.IsChecked) { $items+='DNS' }; if ($ui.RtcCheck.IsChecked) { $items+='WebRTC' }; if ($ui.Ipv6Check.IsChecked) { $items+='IPv6' }
    if (-not $script:active -and -not $items.Count) { $ui.StatusDetail.Text='请在设置中至少选择一项。'; $ui.SettingsPanel.Visibility='Visible'; return }
    $null=New-Item -ItemType Directory -Path $StateDirectory -Force
    $run=Join-Path $StateDirectory ('run-'+[guid]::NewGuid().ToString('N')); $null=New-Item -ItemType Directory -Path $run
    $script:runDirectory=$run; $script:progress=Join-Path $run 'progress.jsonl'; $script:resultPath=Join-Path $run 'result.json'
    $req=@{Action=$(if ($script:active) {'Restore'} else {'Repair'});Edition=$Edition;TargetUserSid=$TargetUserSid;Mode=[string]$ui.ModeBox.SelectedItem.Content;Items=$items;InstallPath=$ui.InstallBox.Text;ConfigDirectory=$ui.ConfigBox.Text;ProxyGroup=$ui.GroupBox.Text;Restart=[bool]$ui.RestartCheck.IsChecked;StateDirectory=$StateDirectory}
    Save-PvJson (Join-Path $run 'request.json') $req
    Save-PvJson $settingsPath @{Mode=$req.Mode;Items=$items;InstallPath=$req.InstallPath;ConfigDirectory=$req.ConfigDirectory;ProxyGroup=$req.ProxyGroup;Restart=$req.Restart}
    $ui.Checklist.Children.Clear(); $script:rows=@{}; $script:seen=0; $script:resultConsumed=$false
    $ui.SettingsPanel.Visibility='Collapsed'; $ui.Emblem.Visibility='Collapsed'; $ui.ResultNote.Visibility='Collapsed'
    $ui.StatusTitle.Text=if ($script:active) { '正在还原' } else { '正在检查并修复' }; $ui.StatusDetail.Text='每一项都先检查，再保存与修改。'
    Set-PvBusy $true
    try {
        $psi=[Diagnostics.ProcessStartInfo]::new(); $psi.FileName=(Get-Process -Id $PID).Path; $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
        foreach ($arg in @('-NoProfile','-NonInteractive','-File',"$PSScriptRoot\Invoke-Worker.ps1",'-RequestPath',(Join-Path $run 'request.json'),'-ProgressPath',$script:progress,'-ResultPath',$script:resultPath)) { $psi.ArgumentList.Add($arg) }
        if ($FixtureRoot) { $psi.ArgumentList.Add('-FixtureRoot'); $psi.ArgumentList.Add($FixtureRoot) }
        $script:worker=[Diagnostics.Process]::Start($psi)
        $script:timer.Start()
    } catch { Set-PvBusy $false; $ui.StatusTitle.Text='无法启动修复'; $ui.StatusDetail.Text=$_.Exception.Message }
}
$script:timer.Add_Tick({
    if (-not $script:worker) { return }
    try {
        if (Test-Path -LiteralPath $script:progress) {
            try {
                if ($script:progressReadFaultPending) { $script:progressReadFaultPending=$false; throw [IO.IOException]::new('Fixture progress sharing conflict') }
                $lines=Read-PvProgressLines $script:progress
            } catch [IO.IOException] {
                if (-not $script:worker.HasExited) { $ui.StatusDetail.Text='等待后台进度文件可读。'; return }
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
                    Show-PvEvent @{id='progress-error';label='进度记录不完整';status='error';detail='后台已退出，将读取最终结果与快照。'}
                    $script:seen=$lines.Length
                }
            }
        }
        if (-not $script:worker.HasExited) { return }
        $script:timer.Stop()
        if (Test-Path -LiteralPath $script:resultPath) { $r=Read-PvJson $script:resultPath }
        else { $r=@{status='Failed';message='后台进程中断。快照已保留，可还原后重试。';active=[bool](Get-PvActiveSnapshot $StateDirectory)} }
        $script:active=[bool]$r.active; Set-PvActiveButton; Set-PvBusy $false
        $ui.StatusTitle.Text=switch ($r.status) { Configured {'所选配置已完成'} Partial {'部分项目需要处理'} Restored {'已还原上次修改'} default {'本次操作未完成'} }
        $ui.StatusDetail.Text=$r.message
        $ui.ResultNote.Visibility='Visible'
        if ($r.status -eq 'Failed') { Show-PvEvent @{id='failure';label='处理结果';status='error';detail=$r.message} }
        $script:resultConsumed=$true
        $script:lastResult=$r
        $script:worker.Dispose(); $script:worker=$null
    } catch {
        $message=$_.Exception.Message
        if (-not $script:worker.HasExited) { $ui.StatusDetail.Text='等待后台完成后读取结果。'; return }
        $script:timer.Stop()
        $script:active=Test-Path -LiteralPath (Join-Path $StateDirectory 'active.json')
        Set-PvActiveButton; Set-PvBusy $false
        $ui.StatusTitle.Text='读取结果失败'; $ui.StatusDetail.Text=$message
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
$window.Add_Closing({ if ($script:busy) { $_.Cancel=$true; $ui.StatusDetail.Text='正在处理配置，请等待完成后关闭。' } })
$window.Add_SourceInitialized({
    if (-not ('ProxyVeilGlass' -as [type])) { Add-Type -TypeDefinition ([IO.File]::ReadAllText("$PSScriptRoot\UI\Glass.cs")) }
    $hwnd=[Windows.Interop.WindowInteropHelper]::new($window).Handle
    $source=[Windows.Interop.HwndSource]::FromHwnd($hwnd); $source.CompositionTarget.BackgroundColor=[Windows.Media.Colors]::Transparent
    $script:glassApplied=[ProxyVeilGlass]::Apply($hwnd)
    if (-not $script:glassApplied) { $window.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#E6E9F1F7') }
})
$savedSettings=$null
if (Test-Path -LiteralPath $settingsPath) {
    try {
        $savedSettings=Read-PvJson $settingsPath
        $ui.InstallBox.Text=[string]$savedSettings.InstallPath
        $ui.ConfigBox.Text=[string]$savedSettings.ConfigDirectory
        $ui.GroupBox.Text=[string]$savedSettings.ProxyGroup
    } catch { $ui.StatusDetail.Text='设置文件不可读取，已使用默认选项。' }
}
Invoke-PvDetect
if ($savedSettings) {
    try {
        $s=$savedSettings
        $ui.ModeBox.SelectedIndex=if ($s.Mode -eq 'TUN') { 0 } else { 1 }
        $ui.DnsCheck.IsChecked='DNS' -in $s.Items; $ui.RtcCheck.IsChecked='WebRTC' -in $s.Items; $ui.Ipv6Check.IsChecked='IPv6' -in $s.Items
        $ui.RestartCheck.IsChecked=[bool]$s.Restart
    } catch { $ui.StatusDetail.Text='设置选项不可读取，已使用默认选项。' }
}
Set-PvActiveButton
if ($script:active) { $ui.StatusTitle.Text='有可还原的修改'; $ui.StatusDetail.Text='快照保存在本机。还原前会核对外部改动。' }
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
    if ($colors.Count -lt 32) { throw '窗口渲染为空，停止生成验证记录。' }
    $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new(); $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $file=[IO.File]::Create($Path); try { $encoder.Save($file) } finally { $file.Dispose() }
}
if ($RenderOnly -or $SmokeTest) {
    if (-not $FixtureRoot) { throw '窗口测试要求隔离 FixtureRoot。' }
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
        if ($script:busy -or -not $script:resultConsumed -or $script:lastResult.status -ne 'Configured') { throw "UI 修复测试失败：$($ui.StatusDetail.Text)" }
        if ($ui.ActionButton.Content -ne '还原上次修改') { throw 'UI 未切换为还原按钮。' }
    }
    if ($RenderPath) {
        Save-PvWindowImage $RenderPath
        Save-PvJson ([IO.Path]::ChangeExtension($RenderPath,'.json')) @{fixture=$true;state=$RenderState;nativeAcrylicAccepted=$script:glassApplied;width=$window.Width;height=$window.Height;actualNetworkTest=$false}
    }
    if ($SmokeTest) {
        $ui.ActionButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        $deadline=(Get-Date).AddSeconds(35)
        while ($script:busy -and (Get-Date) -lt $deadline) {
            $frame=[Windows.Threading.DispatcherFrame]::new(); $pump=[Windows.Threading.DispatcherTimer]::new(); $pump.Interval=[TimeSpan]::FromMilliseconds(40)
            $pump.Add_Tick({ $frame.Continue=$false; $pump.Stop() }.GetNewClosure()); $pump.Start(); [Windows.Threading.Dispatcher]::PushFrame($frame)
        }
        if ($script:busy -or $script:lastResult.status -ne 'Restored' -or $ui.ActionButton.Content -ne '检查并修复') { throw "UI 还原测试失败：$($ui.StatusDetail.Text)" }
        'UI repair/restore events passed'
    }
    $window.Close(); return
}
$window.ShowDialog() | Out-Null
