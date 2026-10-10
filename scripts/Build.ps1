#requires -Version 7.0
[CmdletBinding()]
param([switch]$SkipTests)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$version=(Get-Content -LiteralPath "$root\VERSION" -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid package version' }
if (-not $SkipTests) {
    & "$PSScriptRoot\Test.ps1"
    & "$PSScriptRoot\Test-Review.ps1"
    & "$PSScriptRoot\Test-Registry.ps1"
    & (Get-Process -Id $PID).Path -NoProfile -STA -File "$PSScriptRoot\Test-UI.ps1"
    if ($LASTEXITCODE -ne 0) { throw 'UI verification failed' }
    & (Get-Process -Id $PID).Path -NoProfile -STA -File "$PSScriptRoot\Test-UI-Recovery.ps1"
    if ($LASTEXITCODE -ne 0) { throw 'UI progress recovery failed' }
    & (Get-Process -Id $PID).Path -NoProfile -STA -File "$PSScriptRoot\Test-UI-Failure.ps1"
    if ($LASTEXITCODE -ne 0) { throw 'UI failure recovery failed' }
    & "$PSScriptRoot\Test-Progress.ps1"
}
& "$PSScriptRoot\Validate-Registry.ps1"
$dist=Join-Path $root 'dist'; $null=New-Item -ItemType Directory -Path $dist -Force
$artifacts=@()
foreach ($edition in @('Standard','Administrator')) {
    $name="ProxyVeil-$version-$edition"; $stage=Join-Path $root ('work\package-'+[guid]::NewGuid().ToString('N')); $package=Join-Path $stage $name
    $null=New-Item -ItemType Directory -Path "$package\scripts" -Force
    Copy-Item -LiteralPath "$root\src" -Destination $package -Recurse
    Copy-Item -LiteralPath "$PSScriptRoot\Launch.ps1" -Destination "$package\scripts\Launch.ps1"
    Copy-Item -LiteralPath "$root\README.md" -Destination "$package\README.md"
    $launcher=if ($edition -eq 'Standard') { 'ProxyVeil.cmd' } else { 'ProxyVeil.Admin.cmd' }
    Copy-Item -LiteralPath (Join-Path $root $launcher) -Destination (Join-Path $package $launcher)
    $zip=Join-Path $dist "$name.zip"
    Compress-Archive -LiteralPath $package -DestinationPath $zip -Force
    $archive=[IO.Compression.ZipFile]::OpenRead($zip)
    try {
        if (@($archive.Entries | Where-Object FullName -Match 'profiles/|\.bak$|registry\.json$|active\.json$').Count) { throw 'Package contains private configuration' }
        if (-not @($archive.Entries | Where-Object FullName -Like "*/$launcher").Count) { throw 'Package missing entry point' }
    } finally { $archive.Dispose() }
    $artifacts+=@(@{edition=$edition;path="dist/$name.zip";sha256=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash;bytes=(Get-Item -LiteralPath $zip).Length})
}
@{version=$version;builtAt=(Get-Date).ToString('o');runtime='PowerShell 7 on Windows / WPF';offline=$true;bundledRuntime=$false;artifacts=$artifacts} | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath "$dist\manifest.json" -Encoding utf8
Copy-Item -LiteralPath "$dist\manifest.json" -Destination "$root\docs\validation\packages.json" -Force
$artifacts | ForEach-Object { [pscustomobject]$_ } | Format-Table edition,path,bytes
