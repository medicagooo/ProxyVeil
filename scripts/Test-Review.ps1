#requires -Version 7.0
param([switch]$ExpectFailure)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
Import-Module "$root\src\ProxyVeil.Core.psm1" -Force
. "$root\tests\Fixtures.ps1"
$suite=Join-Path $root ('work\review-'+[guid]::NewGuid().ToString('N'))
$script:passed=0; $script:failures=[Collections.Generic.List[string]]::new()
function Check([string]$Name,[scriptblock]$Test) {
    try { & $Test; $script:passed++; "PASS: $Name" }
    catch { $script:failures.Add("${Name}: $($_.Exception.Message)"); "FAIL: $Name" }
}
function Require([bool]$Value,[string]$Message) { if (-not $Value) { throw $Message } }
foreach ($indent in @(0,4)) {
    Check "Proxy DNS rules retain $indent spaces" {
        $dir=Join-Path $suite "indent-$indent"; $req=New-PvTestFixture $dir; $req.Mode='Proxy'; $req.Items=@('DNS')
        $profile="$dir\config\profiles\123.yaml"
        $text=[IO.File]::ReadAllText($profile) -replace '(?m)^  - (GEOSITE|GEOIP|MATCH)',((' '*$indent)+'- $1')
        [IO.File]::WriteAllText($profile,$text)
        $null=Invoke-PvOperation $req '' $dir
        $after=[IO.File]::ReadAllText($profile)
        $ruleBody=($after -split '(?m)^rules:\s*\r?\n',2)[1]
        $bad=@($ruleBody -split '\r?\n' | Where-Object { $_ -match '^( *)-' -and $Matches[1].Length -ne $indent })
        Require ($bad.Count -eq 0) 'Mixed rule indentation makes valid input invalid'
        $req.Action='Restore'; Require ((Invoke-PvOperation $req '' $dir).status -eq 'Restored') 'Restore failed'
    }
}
Check 'Pre-existing endpoint rule remains intact' {
    $dir=Join-Path $suite 'existing-rule'; $req=New-PvTestFixture $dir; $req.Mode='Proxy'; $req.Items=@('DNS')
    $profile="$dir\config\profiles\123.yaml"
    $text=[IO.File]::ReadAllText($profile).Replace('rules:',"rules:`n  - `"IP-CIDR,1.1.1.1/32,选择代理,no-resolve`"")
    [IO.File]::WriteAllText($profile,$text)
    Require ((Invoke-PvOperation $req '' $dir).status -eq 'Configured') 'Existing rule prevents repair'
    $req.Action='Restore'; $null=Invoke-PvOperation $req '' $dir
    Require ([IO.File]::ReadAllText($profile) -ceq $text) 'Existing rule lost'
}
Check 'MultiString external change blocks Restore' {
    $dir=Join-Path $suite 'multistring'; $req=New-PvTestFixture $dir; $req.Items=@('WebRTC')
    Set-PvPolicy WebRtcLocalhostIpHandling @{Exists=$true;Type='MultiString';Value=@('a b','c')} $dir
    $null=Invoke-PvOperation $req '' $dir
    Set-PvPolicy WebRtcLocalhostIpHandling @{Exists=$true;Type='MultiString';Value=@('a','b c')} $dir
    $req.Action='Restore'; $conflict=$false
    try { $null=Invoke-PvOperation $req '' $dir } catch { $conflict=$_.Exception.Message -match '还原冲突' }
    Require $conflict 'Distinct arrays flattened into the same string'
    Require ((Get-PvPolicy WebRtcLocalhostIpHandling $dir).Value[0] -ceq 'a') 'External value overwritten'
}
Check 'Comma group refuses invalid Proxy rule before mutation' {
    $dir=Join-Path $suite 'comma-group'; $req=New-PvTestFixture $dir; $req.Mode='Proxy'; $req.Items=@('DNS')
    $profile="$dir\config\profiles\123.yaml"; [IO.File]::WriteAllText($profile,[IO.File]::ReadAllText($profile).Replace('选择代理','代理,组'))
    $before=(Get-FileHash -LiteralPath $profile).Hash; $rejected=$false
    try { $null=Invoke-PvOperation $req '' $dir } catch { $rejected=$_.Exception.Message -match '代理组|逗号' }
    Require $rejected 'Comma in rule destination accepted'
    Require ((Get-FileHash -LiteralPath $profile).Hash -eq $before) 'Unsupported group mutated files'
}
Check 'WebRTC-only ignores DNS group ambiguity' {
    $dir=Join-Path $suite 'rtc-ambiguous'; $req=New-PvTestFixture $dir; $req.Items=@('WebRTC')
    $profile="$dir\config\profiles\123.yaml"
    $text=[IO.File]::ReadAllText($profile).Replace('rules:',"  - name: other`n    type: select`n    proxies:`n      - test-node`nrules:").Replace('MATCH,选择代理','MATCH,DIRECT')
    [IO.File]::WriteAllText($profile,$text); $hash=(Get-FileHash -LiteralPath $profile).Hash
    Require ((Invoke-PvOperation $req '' $dir).status -eq 'Configured') 'Unselected DNS group blocks WebRTC'
    Require ((Get-FileHash -LiteralPath $profile).Hash -eq $hash) 'WebRTC touched YAML'
}
Check 'WebRTC-only ignores unsupported YAML structures' {
    $dir=Join-Path $suite 'rtc-complex'; $req=New-PvTestFixture $dir; $req.Items=@('WebRTC')
    $profile="$dir\config\profiles\123.yaml"; [IO.File]::WriteAllText($profile,"dns: &dns-anchor {enable: true}`nproxy-groups: []`nrules: []`n")
    $hash=(Get-FileHash -LiteralPath $profile).Hash
    Require ((Invoke-PvOperation $req '' $dir).status -eq 'Configured') 'Unmodified complex YAML blocks Edge repair'
    Require ((Get-FileHash -LiteralPath $profile).Hash -eq $hash) 'Complex profile changed'
    $req.Action='Restore'; Require ((Invoke-PvOperation $req '' $dir).status -eq 'Restored') 'Edge-only restore failed'
}
if ($ExpectFailure) {
    if (-not $script:failures.Count) { throw 'Expected baseline regressions to fail' }
    $script:failures | ForEach-Object { $_ }; return
}
if ($script:failures.Count) { throw ($script:failures -join "`n") }
Save-PvJson "$root\docs\validation\review-regressions.json" @{at=(Get-Date).ToString('o');passed=$script:passed;result='passed';scope='actual Repair/Restore with isolated configurations';liveConfigurationModified=$false}
"PASS: $script:passed review regressions"
