#requires -Version 7.0
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
Import-Module "$root\src\ProxyVeil.Core.psm1" -Force
. "$root\tests\Fixtures.ps1"
$suite=Join-Path $root ('work\unpack-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $suite -Force
$results=@()
foreach ($edition in @('Standard','Administrator')) {
    $name="ProxyVeil-0.1.0-$edition"
    $zip=Join-Path $root "dist\$name.zip"
    $dir=Join-Path $suite $edition
    [IO.Compression.ZipFile]::ExtractToDirectory($zip,$dir)
    $package=Join-Path $dir $name
    $fixture=Join-Path $dir 'fixture'; $req=New-PvTestFixture $fixture
    & (Get-Process -Id $PID).Path -NoProfile -STA -File "$package\src\Start-ProxyVeil.ps1" -Edition $edition -FixtureRoot $fixture -StateDirectory $req.StateDirectory -SmokeTest
    if ($LASTEXITCODE -ne 0) { throw "Extracted $edition package failed" }
    if (Get-PvActiveSnapshot $req.StateDirectory) { throw 'Package restore left an active snapshot' }
    $results+=@(@{edition=$edition;repairRestore='passed';sha256=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash;realUacTest=$false})
}
Save-PvJson "$root\docs\validation\package-smoke.json" @{at=(Get-Date).ToString('o');scope='Extracted portable UI -> worker -> repair -> restore';liveConfigurationModified=$false;results=$results}
'PASS: both extracted packages'
