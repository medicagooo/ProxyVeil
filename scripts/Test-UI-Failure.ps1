#requires -Version 7.0
param([switch]$ExpectFailure)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
Import-Module "$root\src\ProxyVeil.Core.psm1" -Force
. "$root\tests\Fixtures.ps1"
$failed=@(); $passed=@()
foreach ($scenario in @('blocked-directory','blocked-settings','corrupt-snapshot')) {
    $dir=Join-Path $root ('work\ui-failure-'+[guid]::NewGuid().ToString('N'))
    $req=New-PvTestFixture $dir
    switch ($scenario) {
        blocked-directory {
            [IO.File]::WriteAllText("$dir\block",'fixture')
            $req.StateDirectory="$dir\block\state"
        }
        blocked-settings { $null=New-Item -ItemType Directory -Path "$($req.StateDirectory)\settings.json" -Force }
        corrupt-snapshot {
            $null=New-Item -ItemType Directory -Path $req.StateDirectory -Force
            [IO.File]::WriteAllText("$($req.StateDirectory)\active.json",'{invalid')
        }
    }
    & (Get-Process -Id $PID).Path -NoProfile -STA -File "$root\src\Start-ProxyVeil.ps1" -FixtureRoot $dir -StateDirectory $req.StateDirectory -FailureSmokeTest
    if ($LASTEXITCODE -ne 0) { $failed+=@($scenario) } else { $passed+=@($scenario) }
    if ($scenario -eq 'corrupt-snapshot' -and [IO.File]::ReadAllText("$($req.StateDirectory)\active.json") -cne '{invalid') { throw 'Corrupt snapshot overwritten' }
}
if ($ExpectFailure) { if (-not $failed.Count) { throw 'Baseline should fail' }; "Baseline failures: $($failed -join ', ')"; return }
if ($failed.Count) { throw "UI failures unhandled: $($failed -join ', ')" }
Save-PvJson "$root\docs\validation\ui-failure.json" @{at=(Get-Date).ToString('o');result='passed';scenarios=$passed;scope='actual WPF action event; local worker where applicable';liveConfigurationModified=$false}
'PASS: UI preparation and snapshot failures'
