#requires -Version 7.0
[CmdletBinding()]
param([string]$PowerShellPath = (Get-Process -Id $PID).Path,[ValidateSet('Auto','en','zh-CN')][string]$Language='Auto')
$ErrorActionPreference = 'Stop'
if (-not $IsWindows -or -not [Environment]::UserInteractive) { throw 'An interactive Windows desktop is required.' }
$root = Split-Path $PSScriptRoot
Import-Module "$root/src/ProxyVeil.Core.psm1" -Force
Set-PvLanguage $Language
$Language=Get-PvLanguage
. "$root/tests/Fixtures.ps1"
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing, System.Windows.Forms
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class PvDesktopNative {
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out Rect rect);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int command);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
    [StructLayout(LayoutKind.Sequential)] public struct Point { public int X, Y; }
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(Point point);
    [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hwnd);
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hwnd, int attribute, out int value, int size);
}
'@
$suite = Join-Path $root ('work/desktop-' + [guid]::NewGuid().ToString('N'))
$request = New-PvTestFixture $suite
$reportPath = Join-Path $root 'docs/validation/windows-desktop.json'
$report = [ordered]@{
    at = [DateTimeOffset]::UtcNow.ToOffset([TimeSpan]::FromHours(-4)).ToString('o')
    result = 'failed'; scope = 'Displayed native WPF window with isolated fixture and UI Automation'
    powerShell = $PSVersionTable.PSVersion.ToString(); language=$Language; fixture = $true
    liveConfigurationModified = $false; realUacTest = $false; actualNetworkTest = $false
    checks = @(); screenshots = @(); captureWarnings = @(); visualCapture = 'pending'
}
$checks = [Collections.Generic.List[string]]::new()
$process = $null
function Wait-PvDesktop([scriptblock]$Condition, [string]$Description, [int]$Seconds = 25) {
    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    do {
        if (& $Condition) { return }
        if ($process.HasExited) { throw "Window exited while waiting: $Description" }
        Start-Sleep -Milliseconds 150
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Timed out: $Description"
}
function Find-PvControl([string]$Id) {
    $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty, $Id)
    $element = $script:windowElement.FindFirst([Windows.Automation.TreeScope]::Descendants, $condition)
    if (-not $element) { throw "Control not found: $Id" }
    return $element
}
function Invoke-PvControl([string]$Id) {
    $element = Find-PvControl $Id
    if (-not $element.Current.IsEnabled) { throw "Control disabled: $Id" }
    $pattern = $element.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern)
    $pattern.Invoke()
}
function Save-PvDesktopImage([string]$Name) {
    # Keep only the fixture window above other windows without taking keyboard focus.
    # Capture its rectangle after checking visible points belong to that window.
    if (-not [PvDesktopNative]::SetWindowPos($script:hwnd, [IntPtr]::new(-1), 0, 0, 0, 0, 0x0013)) { throw 'Cannot raise fixture window for capture.' }
    Start-Sleep -Milliseconds 400
    $rect = [PvDesktopNative+Rect]::new()
    if (-not [PvDesktopNative]::GetWindowRect($script:hwnd, [ref]$rect)) { throw 'Cannot read window bounds.' }
    $bounds = [Drawing.Rectangle]::FromLTRB($rect.Left, $rect.Top, $rect.Right, $rect.Bottom)
    $report.captureBounds = @{x=$bounds.X;y=$bounds.Y;width=$bounds.Width;height=$bounds.Height}
    $report.automationBounds = $script:windowElement.Current.BoundingRectangle.ToString()
    $screen = [Windows.Forms.Screen]::FromHandle($script:hwnd).Bounds
    if (-not $screen.Contains($bounds)) { throw 'Window extends outside the capture screen.' }
    foreach ($xy in @(@(($rect.Left+20),($rect.Top+20)),@(($rect.Right-20),($rect.Bottom-20)),@(($rect.Left+$bounds.Width/2),($rect.Top+$bounds.Height/2)))) {
        $point = [PvDesktopNative+Point]::new(); $point.X = [int]$xy[0]; $point.Y = [int]$xy[1]
        $visible = [PvDesktopNative]::WindowFromPoint($point)
        if ([PvDesktopNative]::GetAncestor($visible, 2) -ne $script:hwnd) {
            $report.captureWarnings += "${Name}: fixture window does not own capture point $($point.X),$($point.Y); no screenshot saved"
            $report.visualCapture = 'unavailable'
            return
        }
    }
    $bitmap = [Drawing.Bitmap]::new($bounds.Width, $bounds.Height)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen($bounds.Location, [Drawing.Point]::Empty, $bounds.Size)
        $bitmap.Save((Join-Path $root "docs/validation/$Name.png"), [Drawing.Imaging.ImageFormat]::Png)
    } finally { $graphics.Dispose(); $bitmap.Dispose() }
    $report.screenshots += "docs/validation/$Name.png"
    if ($report.visualCapture -ne 'unavailable') { $report.visualCapture = 'captured' }
}
try {
    $previousDpiContext = [PvDesktopNative]::SetThreadDpiAwarenessContext([IntPtr]::new(-4))
    if ($previousDpiContext -eq [IntPtr]::Zero) { throw 'Cannot set physical-pixel coordinates for desktop test.' }
    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $PowerShellPath; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    foreach ($arg in @('-NoProfile','-STA','-File',"$root/src/Start-ProxyVeil.ps1",'-FixtureRoot',$suite,'-StateDirectory',$request.StateDirectory,'-Language',$Language)) { $psi.ArgumentList.Add($arg) }
    $process = [Diagnostics.Process]::Start($psi)
    $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync()
    Wait-PvDesktop { $process.Refresh(); $process.MainWindowHandle -ne [IntPtr]::Zero } 'Displayed window'
    $script:hwnd = $process.MainWindowHandle
    $script:windowElement = [Windows.Automation.AutomationElement]::FromHandle($script:hwnd)
    Wait-PvDesktop { [PvDesktopNative]::IsWindowVisible($script:hwnd) -and -not $script:windowElement.Current.IsOffscreen } 'Window visible on desktop'
    $checks.Add('Native window displayed')
    Wait-PvDesktop { (Find-PvControl 'ActionButton').Current.Name -eq (Get-PvText 'UI.Repair') } 'Idle action button'
    Save-PvDesktopImage 'windows-desktop-idle'
    $backdrop = 0
    $hr = [PvDesktopNative]::DwmGetWindowAttribute($script:hwnd, 38, [ref]$backdrop, 4)
    $report.nativeBackdrop = @{hresult=$hr;value=$backdrop;acrylicConfigured=($hr -eq 0 -and $backdrop -eq 3);visualBlur='Requires screenshot observation; attribute alone does not prove blur'}
    if ($hr -eq 0 -and $backdrop -eq 3) { $checks.Add('DWM backdrop attribute reads back as 3') }
    Invoke-PvControl 'SettingsButton'
    Wait-PvDesktop { -not (Find-PvControl 'DnsCheck').Current.IsOffscreen } 'Settings visible'
    $toggle = (Find-PvControl 'DnsCheck').GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern)
    $beforeToggle = $toggle.Current.ToggleState
    $toggle.Toggle()
    if ($toggle.Current.ToggleState -eq $beforeToggle) { throw 'Checkbox did not toggle.' }
    $toggle.Toggle()
    if ($toggle.Current.ToggleState -ne $beforeToggle) { throw 'Checkbox did not return to original state.' }
    $checks.Add('Settings expand and DNS checkbox toggles')
    Save-PvDesktopImage 'windows-desktop-settings'
    Invoke-PvControl 'SettingsButton'
    $rect = [PvDesktopNative+Rect]::new()
    if (-not [PvDesktopNative]::GetWindowRect($script:hwnd, [ref]$rect)) { throw 'Cannot read original window bounds.' }
    $newX = $rect.Left + 16; $newY = $rect.Top + 12
    if (-not [PvDesktopNative]::SetWindowPos($script:hwnd, [IntPtr]::Zero, $newX, $newY, 0, 0, 0x0015)) { throw 'Window move failed.' }
    $moved = [PvDesktopNative+Rect]::new()
    if (-not [PvDesktopNative]::GetWindowRect($script:hwnd, [ref]$moved) -or $moved.Left -ne $newX -or $moved.Top -ne $newY) { throw 'Window move readback failed.' }
    $checks.Add('Window repositioned and bounds read back')
    Invoke-PvControl 'MinimizeButton'
    Wait-PvDesktop { [PvDesktopNative]::IsIconic($script:hwnd) } 'Minimized window'
    $null = [PvDesktopNative]::ShowWindow($script:hwnd, 9)
    Wait-PvDesktop { -not [PvDesktopNative]::IsIconic($script:hwnd) } 'Restored window'
    $checks.Add('Minimize control and native window restore')
    Invoke-PvControl 'ActionButton'
    Wait-PvDesktop { (Find-PvControl 'ActionButton').Current.IsEnabled -and (Find-PvControl 'ActionButton').Current.Name -eq (Get-PvText 'UI.Restore') } 'Fixture repair complete' 45
    $runs = @(Get-ChildItem -LiteralPath $request.StateDirectory -Directory -Filter 'run-*')
    $repair = @(foreach ($run in $runs) { if (Test-Path -LiteralPath "$($run.FullName)/result.json") { Read-PvJson "$($run.FullName)/result.json" } })
    if ($repair.Count -ne 1 -or $repair[0].status -ne 'Configured') { throw 'Fixture repair result was not Configured.' }
    $checks.Add('Displayed action button invokes isolated worker repair')
    Save-PvDesktopImage 'windows-desktop-configured'
    Invoke-PvControl 'ActionButton'
    Wait-PvDesktop { (Find-PvControl 'ActionButton').Current.IsEnabled -and (Find-PvControl 'ActionButton').Current.Name -eq (Get-PvText 'UI.Repair') } 'Fixture restore complete' 45
    if (Get-PvActiveSnapshot $request.StateDirectory) { throw 'Fixture restore left active snapshot.' }
    $runs = @(Get-ChildItem -LiteralPath $request.StateDirectory -Directory -Filter 'run-*')
    $results = @(foreach ($run in $runs) { Read-PvJson "$($run.FullName)/result.json" })
    if ($results.Count -ne 2 -or 'Restored' -notin $results.status) { throw 'Fixture restore result missing.' }
    $checks.Add('Displayed action button restores fixture and clears active snapshot')
    Save-PvDesktopImage 'windows-desktop-restored'
    Invoke-PvControl 'CloseButton'
    if (-not $process.WaitForExit(10000) -or $process.ExitCode -ne 0) { throw 'Window did not close successfully.' }
    $checks.Add('Close control exits window')
    $report.visualCapture = if ($report.captureWarnings.Count -and $report.screenshots.Count) { 'partial' } elseif ($report.screenshots.Count) { 'captured' } else { 'unavailable' }
    $report.result = 'passed'
} catch {
    $report.error = $_.Exception.Message
    throw
} finally {
    if ($process) {
        if (-not $process.HasExited) {
            $null = $process.CloseMainWindow()
            if (-not $process.WaitForExit(3000)) { $process.Kill(); $process.WaitForExit() }
        }
        $report.childExitCode = $process.ExitCode
        if ($report.result -ne 'passed') { $report.childError = $stderr.GetAwaiter().GetResult() }
        $process.Dispose()
    }
    $report.checks = @($checks)
    Save-PvJson $reportPath $report
    if ($previousDpiContext -ne [IntPtr]::Zero) { $null = [PvDesktopNative]::SetThreadDpiAwarenessContext($previousDpiContext) }
}
'PASS: displayed Windows desktop and isolated repair/restore'
