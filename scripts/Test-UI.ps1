#requires -Version 7.0
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
Import-Module "$root\src\ProxyVeil.Core.psm1" -Force
. "$root\tests\Fixtures.ps1"
$suite=Join-Path $root ('work\ui-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $suite -Force
foreach ($state in @('Idle','Settings','Completed')) {
    $dir=Join-Path $suite $state; $req=New-PvTestFixture $dir
    & (Get-Process -Id $PID).Path -NoProfile -STA -File "$root\src\Start-ProxyVeil.ps1" -FixtureRoot $dir -StateDirectory $req.StateDirectory -RenderOnly -RenderState $state -RenderPath "$root\docs\validation\ui-$($state.ToLower()).png"
    if ($LASTEXITCODE -ne 0) { throw "UI render $state failed" }
}
$dir=Join-Path $suite 'events'; $req=New-PvTestFixture $dir
& (Get-Process -Id $PID).Path -NoProfile -STA -File "$root\src\Start-ProxyVeil.ps1" -FixtureRoot $dir -StateDirectory $req.StateDirectory -SmokeTest
if ($LASTEXITCODE -ne 0) { throw 'UI event integration failed' }
Save-PvJson "$root\docs\validation\ui.json" @{at=(Get-Date).ToString('o');result='passed';scope='WPF render, button repair and restore with real isolated worker';nativeAcrylicVisual='not captured by offscreen render';liveConfigurationModified=$false}
'PASS: UI states and repair/restore button events'
