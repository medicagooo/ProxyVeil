#requires -Version 7.0
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
Import-Module "$root\src\ProxyVeil.Core.psm1" -Force
. "$root\tests\Fixtures.ps1"
$dir=Join-Path $root ('work\ui-read-fault-'+[guid]::NewGuid().ToString('N'))
$req=New-PvTestFixture $dir
& (Get-Process -Id $PID).Path -NoProfile -STA -File "$root\src\Start-ProxyVeil.ps1" -FixtureRoot $dir -StateDirectory $req.StateDirectory -SmokeTest -InjectProgressReadFault
if ($LASTEXITCODE -ne 0) { throw 'UI progress read recovery failed' }
Save-PvJson "$root\docs\validation\ui-recovery.json" @{at=(Get-Date).ToString('o');result='passed';fault='single injected progress IOException';scope='UI remains busy and consumes final worker result';liveConfigurationModified=$false}
'PASS: progress read recovery'
