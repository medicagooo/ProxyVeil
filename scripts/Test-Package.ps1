#requires -Version 7.0
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$version=(Get-Content -LiteralPath "$root\VERSION" -Raw).Trim()
Import-Module "$root\src\ProxyVeil.Core.psm1" -Force
. "$root\tests\Fixtures.ps1"
$suite=Join-Path $root ('work\unpack-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $suite -Force
$results=@()
foreach ($edition in @('Standard','Administrator')) {
    $name="ProxyVeil-$version-$edition"
    $zip=Join-Path $root "dist\$name.zip"
    $dir=Join-Path $suite $edition
    [IO.Compression.ZipFile]::ExtractToDirectory($zip,$dir)
    $package=Join-Path $dir $name
    $images=@()
    foreach ($document in @('README.md','README.zh-CN.md')) {
        $readme=Get-Content -LiteralPath (Join-Path $package $document) -Raw
        $references=@([regex]::Matches($readme, '!\[[^\]]*\]\(([^)]+)\)') | ForEach-Object { $_.Groups[1].Value })
        if (-not $references.Count) { throw "$edition $document has no illustrated usage" }
        foreach ($image in $references) {
            if ($image -notmatch '^docs/images/[a-z0-9-]+\.png$' -or -not (Test-Path -LiteralPath (Join-Path $package $image) -PathType Leaf)) {
                throw "$edition $document image missing or outside packaged image directory: $image"
            }
        }
        $other=if ($document -eq 'README.md') { 'README.zh-CN.md' } else { 'README.md' }
        if (-not $readme.Contains("]($other)")) { throw "$edition $document language link missing" }
        $images+=$references
    }
    foreach ($language in @('en','zh-CN')) {
        $fixture=Join-Path $dir "fixture-$language"; $req=New-PvTestFixture $fixture
        & (Get-Process -Id $PID).Path -NoProfile -STA -File "$package\src\Start-ProxyVeil.ps1" -Edition $edition -Language $language -FixtureRoot $fixture -StateDirectory $req.StateDirectory -SmokeTest
        if ($LASTEXITCODE -ne 0) { throw "Extracted $edition/$language package failed" }
        if (Get-PvActiveSnapshot $req.StateDirectory) { throw 'Package restore left an active snapshot' }
    }
    $results+=@(@{edition=$edition;languages=@('en','zh-CN');repairRestore='passed';readmeImages=$images;sha256=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash;realUacTest=$false})
}
Save-PvJson "$root\docs\validation\package-smoke.json" @{at=(Get-Date).ToString('o');scope='Extracted portable UI -> worker -> repair -> restore';liveConfigurationModified=$false;results=$results}
'PASS: both extracted packages'
