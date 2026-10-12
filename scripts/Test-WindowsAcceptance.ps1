#requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string[]]$PowerShellPaths)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$results=@()
$reports=@('engine','review-regressions','registry','ui','ui-recovery','ui-failure','progress')
foreach ($runtime in $PowerShellPaths) {
    $version=& $runtime -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
    if ($LASTEXITCODE -ne 0) { throw "Cannot query runtime: $runtime" }
    $destination=Join-Path $root "docs/validation/windows-012/$version"
    $null=New-Item -ItemType Directory -Path $destination -Force
    foreach ($suite in @('Test','Test-Review','Test-Registry','Test-UI','Test-UI-Recovery','Test-UI-Failure','Test-Progress')) {
        & $runtime -NoProfile -STA -File (Join-Path $PSScriptRoot "$suite.ps1")
        if ($LASTEXITCODE -ne 0) { throw "$suite failed on $version" }
    }
    foreach ($name in $reports) {
        Copy-Item -LiteralPath (Join-Path $root "docs/validation/$name.json") -Destination $destination -Force
    }
    foreach ($name in @('ui-idle','ui-settings','ui-completed','ui-opaque')) {
        Copy-Item -LiteralPath (Join-Path $root "docs/validation/$name.json") -Destination $destination -Force
    }
    $results+=@{powerShell=$version;runtime=$runtime;result='passed';suites=7;evidence="docs/validation/windows-012/$version"}
}
# All source suites have passed; rebuild once, then verify each runtime against
# the same packages. Package tests use fixtures and do not exercise real UAC.
& $PowerShellPaths[0] -NoProfile -File (Join-Path $PSScriptRoot 'Build.ps1') -SkipTests
if ($LASTEXITCODE -ne 0) { throw 'Build failed' }
foreach ($run in $results) {
    & $run.runtime -NoProfile -STA -File (Join-Path $PSScriptRoot 'Test-Package.ps1')
    if ($LASTEXITCODE -ne 0) { throw "Packages failed on $($run.powerShell)" }
    Copy-Item -LiteralPath (Join-Path $root 'docs/validation/package-smoke.json') -Destination (Join-Path $root $run.evidence) -Force
    $run.suites=8
}
$keys=@(Get-ChildItem -LiteralPath 'HKCU:\Software' | Where-Object PSChildName -Like 'ProxyVeil.Test-*')
if ($keys.Count) { throw 'Native registry test keys remain' }
$manifest=Get-Content -LiteralPath (Join-Path $root 'dist/manifest.json') -Raw | ConvertFrom-Json
$os=Get-CimInstance Win32_OperatingSystem
$report=@{at=[DateTimeOffset]::Now.ToString('o');status='partial';version=$manifest.version;os=$os.Caption;build=$os.BuildNumber;
    automatedResult='passed';runtimes=$results;packages=$manifest.artifacts;registryTestKeysRemaining=$keys.Count;liveConfigurationModified=$false;
    fallback='Forced DWM fallback rendered and background checked on Windows 11';
    excludedAcceptance=@('Separate Windows 10 acceptance waived by user on 2026-10-12');
    outstanding=@('Manual desktop Acrylic and interaction','Real UAC/TUN and network acceptance');
    macOSNativeAcceptance='User will execute docs/validation/macos-acceptance.md'}
$report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $root 'docs/validation/windows-012.json') -Encoding utf8NoBOM
'PASS: Windows automated acceptance and rebuilt packages; native host/network gaps remain'
