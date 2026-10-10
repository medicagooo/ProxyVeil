#requires -Version 7.0
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
Import-Module "$root\src\ProxyVeil.Core.psm1" -Force
. "$root\tests\Fixtures.ps1"
$dir=Join-Path $root ('work\progress-'+[guid]::NewGuid().ToString('N')); $req=New-PvTestFixture $dir
Save-PvJson "$dir\request.json" $req
$psi=[Diagnostics.ProcessStartInfo]::new(); $psi.FileName=(Get-Process -Id $PID).Path; $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
foreach ($arg in @('-NoProfile','-File',"$root\src\Invoke-Worker.ps1",'-RequestPath',"$dir\request.json",'-ProgressPath',"$dir\progress.jsonl",'-ResultPath',"$dir\result.json",'-FixtureRoot',$dir)) { $psi.ArgumentList.Add($arg) }
$process=[Diagnostics.Process]::Start($psi)
$reads=0; $deadline=(Get-Date).AddSeconds(15)
try {
    while (-not $process.HasExited -and (Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath "$dir\progress.jsonl") { $null=Read-PvProgressLines "$dir\progress.jsonl"; $reads++ }
    }
    if (-not $process.HasExited -or $process.ExitCode -ne 0 -or $reads -eq 0) { throw 'Concurrent progress reading interrupted worker' }
    if ((Read-PvJson "$dir\result.json").status -ne 'Configured') { throw 'Progress sharing broke repair' }
} finally { $process.Dispose() }
$req.Action='Restore'; $null=Invoke-PvOperation $req '' $dir
Save-PvJson "$root\docs\validation\progress.json" @{at=(Get-Date).ToString('o');result='passed';reads=$reads;scope='Concurrent shared-read UI seam / actual worker append';liveConfigurationModified=$false}
'PASS: concurrent progress reading'
