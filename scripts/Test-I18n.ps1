#requires -Version 7.0
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
Import-Module "$root/src/ProxyVeil.Core.psm1" -Force
. "$root/tests/Fixtures.ps1"
$checks=[Collections.Generic.List[string]]::new()
function Assert-Language([bool]$Condition,[string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $checks.Add($Name)
}
foreach ($culture in @('zh','zh-CN','zh-TW','zh-HK','zh-Hans','zh-Hant')) {
    Assert-Language ((Resolve-PvLanguage -CultureName $culture) -eq 'zh-CN') "Chinese display culture $culture"
}
foreach ($culture in @('en-US','en-GB','fr-FR','ja-JP','')) {
    Assert-Language ((Resolve-PvLanguage -CultureName $culture) -eq 'en') "English fallback for '$culture'"
}
$regional=[Globalization.CultureInfo]::CurrentCulture
try {
    [Globalization.CultureInfo]::CurrentCulture=[Globalization.CultureInfo]::GetCultureInfo('zh-CN')
    Assert-Language ((Resolve-PvLanguage -CultureName 'en-US') -eq 'en') 'Regional formatting does not select UI language'
} finally { [Globalization.CultureInfo]::CurrentCulture=$regional }
Assert-Language ((Resolve-PvLanguage -Language en -CultureName zh-CN) -eq 'en') 'Explicit language overrides display language'
Set-PvLanguage en; $english=Get-PvStrings
Set-PvLanguage zh-CN; $chinese=Get-PvStrings
Assert-Language ((($english.Keys | Sort-Object) -join '|') -ceq (($chinese.Keys | Sort-Object) -join '|')) 'Matching resource keys'
foreach ($key in $english.Keys) {
    $enArgs=@([regex]::Matches($english[$key],'\{\d+\}') | ForEach-Object Value)
    $zhArgs=@([regex]::Matches($chinese[$key],'\{\d+\}') | ForEach-Object Value)
    Assert-Language (($enArgs -join '|') -ceq ($zhArgs -join '|')) "Matching format arguments: $key"
    Set-PvLanguage en; $null=Get-PvText $key -Arguments @('A','B')
    Set-PvLanguage zh-CN; $null=Get-PvText $key -Arguments @('A','B')
}
$unknownRejected=$false
try { $null=Get-PvText 'Missing.Key' } catch { $unknownRejected=$true }
Assert-Language $unknownRejected 'Unknown resource keys rejected'
$xaml=[IO.File]::ReadAllText("$root/src/UI/MainWindow.xaml")
Assert-Language (-not $xaml.Contains('收好你的网络出口')) 'Slogan removed from window'
foreach ($reference in [regex]::Matches($xaml,'\{DynamicResource Text\.([^}]+)\}')) {
    Assert-Language ($english.ContainsKey($reference.Groups[1].Value)) "XAML resource exists: $($reference.Groups[1].Value)"
}
$suite=Join-Path $root ('work/i18n-'+[guid]::NewGuid().ToString('N'))
$languages=@('en','zh-CN'); $flows=@()
foreach ($language in $languages) {
    foreach ($mode in @('TUN','Proxy')) {
        $fixture=Join-Path $suite "$language-$mode"; $req=New-PvTestFixture $fixture
        $req.Language=$language; $req.Mode=$mode
        Set-PvLanguage $(if ($language -eq 'en') { 'zh-CN' } else { 'en' })
        $previous=Get-PvLanguage
        $progress=Join-Path $fixture 'progress.jsonl'
        $result=Invoke-PvOperation $req $progress $fixture
        Assert-Language ($result.status -eq 'Configured') "$language/$mode repair"
        Assert-Language ((Get-PvLanguage) -eq $previous) "$language/$mode request language restored after call"
        if ($language -eq 'en') {
            Assert-Language ($result.message -match '^Configuration processed' -and $result.message -notmatch '[\u4e00-\u9fff]') "$language/$mode translated result"
            Assert-Language ([IO.File]::ReadAllText($progress) -notmatch '[\u4e00-\u9fff]') "$language/$mode translated progress"
        } else { Assert-Language ($result.message -match '^配置已处理') "$language/$mode translated result" }
        $req.Language=$(if ($language -eq 'en') { 'zh-CN' } else { 'en' }); $req.Action='Restore'
        $restored=Invoke-PvOperation $req '' $fixture
        Assert-Language ($restored.status -eq 'Restored' -and -not (Get-PvActiveSnapshot $req.StateDirectory)) "$language/$mode cross-language snapshot restore"
        $req.Action='Repair'; $req.Language=$language; $req.Fault='preferences'
        $failure=''; try { $null=Invoke-PvOperation $req '' $fixture } catch { $failure=$_.Exception.Message }
        Assert-Language ($failure -match $(if ($language -eq 'en') { 'rolled back' } else { '已回退本次改动' })) "$language/$mode translated rollback failure"
        Assert-Language (-not (Get-PvActiveSnapshot $req.StateDirectory)) "$language/$mode failed repair rolled back"
        Assert-Language ((Get-PvLanguage) -eq $previous) "$language/$mode request language restored after failure"
        $flows+=@{language=$language;mode=$mode;repairRestore='passed';failure='passed';crossLanguageRestore='passed'}
    }
    foreach ($state in @('Idle','Settings','Completed')) {
        $fixture=Join-Path $suite "$language-$state"; $req=New-PvTestFixture $fixture
        $path=Join-Path $root "docs/validation/i18n-$language-$($state.ToLower()).png"
        & (Get-Process -Id $PID).Path -NoProfile -STA -File "$root/src/Start-ProxyVeil.ps1" -Language $language -FixtureRoot $fixture -StateDirectory $req.StateDirectory -RenderOnly -RenderState $state -RenderPath $path
        if ($LASTEXITCODE -ne 0) { throw "$language/$state UI render failed" }
        Assert-Language ((Read-PvJson ([IO.Path]::ChangeExtension($path,'.json'))).language -eq $language) "$language/$state UI language"
    }
    $fixture=Join-Path $suite "$language-ui-worker"; $req=New-PvTestFixture $fixture
    & (Get-Process -Id $PID).Path -NoProfile -STA -File "$root/src/Start-ProxyVeil.ps1" -Language $language -FixtureRoot $fixture -StateDirectory $req.StateDirectory -SmokeTest
    if ($LASTEXITCODE -ne 0) { throw "$language UI worker flow failed" }
    $runs=@(Get-ChildItem -LiteralPath $req.StateDirectory -Directory -Filter 'run-*')
    foreach ($run in $runs) {
        $request=Read-PvJson (Join-Path $run.FullName 'request.json'); $result=Read-PvJson (Join-Path $run.FullName 'result.json')
        Assert-Language ($request.Language -eq $language) "$language worker request language"
        Assert-Language ($result.message -match $(if ($language -eq 'en') { '^(Configuration|Restored)' } else { '^(配置|已还原)' })) "$language worker result language"
    }
    $fixture=Join-Path $suite "$language-damaged"; $req=New-PvTestFixture $fixture
    $null=New-Item -ItemType Directory -Path $req.StateDirectory -Force
    [IO.File]::WriteAllText((Join-Path $req.StateDirectory 'active.json'),'{broken')
    & (Get-Process -Id $PID).Path -NoProfile -STA -File "$root/src/Start-ProxyVeil.ps1" -Language $language -FixtureRoot $fixture -StateDirectory $req.StateDirectory -FailureSmokeTest
    if ($LASTEXITCODE -ne 0) { throw "$language UI failure flow failed" }
    $badRequest=Join-Path $fixture 'broken-request.json'; $badResult=Join-Path $fixture 'broken-result.json'
    [IO.File]::WriteAllText($badRequest,'{broken')
    & (Get-Process -Id $PID).Path -NoProfile -File "$root/src/Invoke-Worker.ps1" -Language $language -RequestPath $badRequest -ResultPath $badResult -ProgressPath (Join-Path $fixture 'broken-progress.jsonl') -FixtureRoot $fixture
    if ($LASTEXITCODE -ne 1) { throw "$language malformed worker request did not fail" }
    $failure=Read-PvJson $badResult
    Assert-Language ($failure.status -eq 'Failed' -and $failure.message -match $(if ($language -eq 'en') { '^Cannot read JSON' } else { '^JSON 文件不可读取' })) "$language malformed request uses launch language"
}
Save-PvJson "$root/docs/validation/i18n.json" @{at=[DateTimeOffset]::Now.ToString('o');powerShell=$PSVersionTable.PSVersion.ToString();result='passed';assertions=$checks.Count;checks=$checks.ToArray();flows=$flows;displayCulture=(Get-PvDisplayCulture);liveConfigurationModified=$false;macOSRetested=$false}
"PASS: $($checks.Count) localization checks and bilingual UI/worker flows"
