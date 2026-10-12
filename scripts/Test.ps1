#requires -Version 7.0
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
Import-Module "$root\src\ProxyVeil.Core.psm1" -Force
Set-PvLanguage 'zh-CN' # Keep legacy message assertions independent of the host display language.
. "$root\tests\Fixtures.ps1"
$suite=Join-Path $root ('work\tests-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $suite -Force
$script:assertions=0
function Assert([bool]$Condition,[string]$Name) { if (-not $Condition) { throw "FAIL: $Name" }; $script:assertions++ }
function Assert-Throws([scriptblock]$Code,[string]$Pattern,[string]$Name) {
    $thrown=$false
    try { & $Code | Out-Null } catch { if ($_.Exception.Message -notmatch $Pattern) { throw "FAIL $Name : unexpected $($_.Exception.Message)" }; $thrown=$true }
    Assert $thrown $Name
}
foreach ($file in @(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Extension -in @('.ps1','.psm1') -and $_.FullName -notmatch '\\work\\|\\dist\\' })) {
    $tokens=$null; $errors=$null; $null=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    Assert ($errors.Count -eq 0) "parse $($file.Name)"
}
foreach ($mode in @('TUN','Proxy')) {
 foreach ($edition in @('Standard','Administrator')) {
    $dir=Join-Path $suite "$mode-$edition"; $req=New-PvTestFixture $dir; $req.Mode=$mode; $req.Edition=$edition
    $profile="$dir\config\profiles\123.yaml"; $prefs="$dir\config\shared_preferences.json"
    $beforeProfile=[Convert]::ToBase64String([IO.File]::ReadAllBytes($profile)); $beforePrefs=[Convert]::ToBase64String([IO.File]::ReadAllBytes($prefs)); $beforePolicy=Get-PvPolicy WebRtcRespectOsRoutingTableEnabled $dir
    $r=Invoke-PvOperation $req "$dir\progress.jsonl" $dir
    Assert ($r.status -eq 'Configured' -and $r.active) "$mode/$edition repair"
    $c=Get-PvContext -FixtureRoot $dir
    Assert ($c.Mode -eq $mode) "$mode persisted"
    Assert ($c.Inner.patchClashConfig.mode -eq 'rule' -and $c.Text.Contains('GEOSITE,CN,DIRECT') -and $c.Text.Contains('MATCH,选择代理')) 'domestic routing retained'
    Assert ($c.Text.Contains('password: fixture-only') -and $c.Inner.unrelated.keep -eq 'unchanged') 'unrelated credentials/preferences retained'
    Assert (-not $c.Inner.networkProps.appendSystemDns -and -not $c.Inner.overrideDns) 'system DNS bypass disabled'
    Assert ($c.Text.Contains('https://1.1.1.1/dns-query#选择代理')) 'DoH routed to selected group'
    Assert ($c.Text.Contains('https://223.5.5.5/dns-query#DIRECT') -and $c.Text.Contains('default-nameserver:')) 'encrypted independent bootstrap'
    $policy=Get-PvPolicy DnsOverHttpsMode $dir
    Assert ($policy.Value -eq $(if ($mode -eq 'TUN') {'off'} else {'secure'})) 'mode-specific Edge DNS'
    Assert ((Get-PvPolicy WebRtcLocalhostIpHandling $dir).Value -eq 'disable_non_proxied_udp') 'WebRTC UDP restriction'
    Assert ($c.Inner.networkProps.systemProxy -eq ($mode -eq 'Proxy')) 'system proxy setting'
    if ($mode -eq 'TUN') { Assert ($c.Text.Contains('tcp://any:53') -and $c.Text.Contains('strict-route: true')) 'TCP/UDP DNS interception' }
    else { Assert ($c.Text.Contains('IP-CIDR,1.1.1.1/32,选择代理,no-resolve')) 'browser DoH endpoint routing' }
    Assert-Throws { Invoke-PvOperation $req '' $dir } '已有快照' 'repeat repair preserves first backup'
    $events=@(Get-Content -LiteralPath "$dir\progress.jsonl" | ForEach-Object { $_ | ConvertFrom-Json })
    Assert ($events.Count -gt 7 -and $events[-1].status -eq 'applied') 'progress completion'
    $req.Action='Restore'; $r=Invoke-PvOperation $req "$dir\restore.jsonl" $dir
    Assert ($r.status -eq 'Restored' -and -not $r.active) 'restore completes'
    Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($profile)) -ceq $beforeProfile) 'profile exact-byte restore including BOM'
    Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($prefs)) -ceq $beforePrefs) 'preferences exact-byte restore'
    Assert (Test-PvPolicyEqual (Get-PvPolicy WebRtcRespectOsRoutingTableEnabled $dir) $beforePolicy) 'policy value/type restore'
    Assert (-not (Get-PvPolicy WebRtcLocalhostIpHandling $dir).Exists) 'original missing policy removed'
 }
}
$dir=Join-Path $suite 'selective'; $req=New-PvTestFixture $dir; $req.Items=@('WebRTC'); $before=Get-FileHash -LiteralPath "$dir\config\profiles\123.yaml"
$r=Invoke-PvOperation $req '' $dir
Assert ($r.status -eq 'Configured' -and (Get-FileHash -LiteralPath "$dir\config\profiles\123.yaml").Hash -eq $before.Hash) 'WebRTC-only leaves FlClash bytes'
Assert (-not (Get-PvPolicy DnsOverHttpsMode $dir).Exists) 'unchecked DNS untouched'
$dir=Join-Path $suite 'conflict-file'; $req=New-PvTestFixture $dir; $null=Invoke-PvOperation $req '' $dir
Add-Content -LiteralPath "$dir\config\profiles\123.yaml" -Value '# external modification'
$modifiedHash=(Get-FileHash -LiteralPath "$dir\config\profiles\123.yaml").Hash
$req.Action='Restore'; Assert-Throws { Invoke-PvOperation $req '' $dir } '还原冲突' 'external file conflict stops restore'
Assert ((Get-FileHash -LiteralPath "$dir\config\profiles\123.yaml").Hash -eq $modifiedHash -and [bool](Get-PvActiveSnapshot $req.StateDirectory)) 'conflict retains files and snapshot'
$dir=Join-Path $suite 'conflict-policy'; $req=New-PvTestFixture $dir; $null=Invoke-PvOperation $req '' $dir
Set-PvPolicy WebRtcLocalhostIpHandling @{Exists=$true;Type='String';Value='external'} $dir
$req.Action='Restore'; Assert-Throws { Invoke-PvOperation $req '' $dir } '还原冲突' 'external policy conflict'
Assert ((Get-PvPolicy WebRtcLocalhostIpHandling $dir).Value -eq 'external') 'external policy preserved'
$dir=Join-Path $suite 'resaved-preferences'; $req=New-PvTestFixture $dir; $null=Invoke-PvOperation $req '' $dir
$prefs="$dir\config\shared_preferences.json"; $outer=Read-PvJson $prefs; $inner=ConvertFrom-Json -InputObject $outer['flutter.config'] -AsHashtable
$inner.unrelated.keep='updated by FlClash'; $outer['flutter.config']=ConvertTo-Json -InputObject $inner -Depth 100; $outer['flutter.extra']='new'; Save-PvJson $prefs $outer
$req.Action='Restore'; $r=Invoke-PvOperation $req '' $dir
$c=Get-PvContext -FixtureRoot $dir
Assert ($r.status -eq 'Restored' -and $c.Inner.unrelated.keep -eq 'updated by FlClash' -and $c.Outer['flutter.extra'] -eq 'new') 'unrelated preference changes survive restore'
Assert ($c.Inner.networkProps.appendSystemDns -and $c.Inner.overrideDns -and $c.Inner.patchClashConfig.ipv6) 'owned preferences restored after FlClash resave'
$dir=Join-Path $suite 'owned-field-conflict'; $req=New-PvTestFixture $dir; $null=Invoke-PvOperation $req '' $dir
$prefs="$dir\config\shared_preferences.json"; $outer=Read-PvJson $prefs; $inner=ConvertFrom-Json -InputObject $outer['flutter.config'] -AsHashtable
$inner.patchClashConfig.tun['dns-hijack']=@('external:53'); $outer['flutter.config']=ConvertTo-Json -InputObject $inner -Depth 100; Save-PvJson $prefs $outer
$req.Action='Restore'; Assert-Throws { Invoke-PvOperation $req '' $dir } '受管偏好' 'owned preference conflict blocks restore'
$dir=Join-Path $suite 'deny'; $req=New-PvTestFixture $dir; $store=Read-PvJson "$dir\registry.json"; $store.deny=@('WebRtcLocalhostIpHandling','WebRtcRespectOsRoutingTableEnabled','WebRtcIPHandlingUrl'); Save-PvJson "$dir\registry.json" $store
$r=Invoke-PvOperation $req "$dir\progress.jsonl" $dir
Assert ($r.status -eq 'Partial' -and @($r.items | Where-Object id -eq WebRTC)[0].status -eq 'skipped') 'permission denial is not success'
$req.Action='Restore'; Assert ((Invoke-PvOperation $req '' $dir).status -eq 'Restored') 'successful subset remains restorable'
$dir=Join-Path $suite 'machine'; $req=New-PvTestFixture $dir; $store=Read-PvJson "$dir\registry.json"; $store.machine.DnsOverHttpsMode=@{Exists=$true;Value='automatic';Type='String'}; Save-PvJson "$dir\registry.json" $store
$r=Invoke-PvOperation $req '' $dir
Assert ($r.status -eq 'Partial' -and -not (Get-PvPolicy DnsOverHttpsMode $dir).Exists) 'machine conflict avoids user policy override'
$dir=Join-Path $suite 'rollback'; $req=New-PvTestFixture $dir; $hash=(Get-FileHash -LiteralPath "$dir\config\profiles\123.yaml").Hash; $req.Fault='preferences'
Assert-Throws { Invoke-PvOperation $req '' $dir } '已回退本次改动' 'mid-write failure rollback'
Assert ((Get-FileHash -LiteralPath "$dir\config\profiles\123.yaml").Hash -eq $hash -and -not (Get-PvActiveSnapshot $req.StateDirectory)) 'rollback restores initial file'
$dir=Join-Path $suite 'drift'; $req=New-PvTestFixture $dir; $req.Fault='drift-before-backup'
Assert-Throws { Invoke-PvOperation $req '' $dir } '检查后发生改变' 'pre-write concurrent drift refused'
Assert ([IO.File]::ReadAllText("$dir\config\profiles\123.yaml").Contains('# external drift')) 'pre-write external change preserved'
$dir=Join-Path $suite 'unsupported'; $req=New-PvTestFixture $dir
$profile="$dir\config\profiles\123.yaml"; $text=[IO.File]::ReadAllText($profile); [IO.File]::WriteAllText($profile,($text -replace '(?m)^dns:$','dns: &dns-anchor'))
$hash=(Get-FileHash -LiteralPath $profile).Hash
Assert-Throws { Invoke-PvOperation $req '' $dir } '复杂|锚点' 'unsupported YAML refuses mutation'
Assert ((Get-FileHash -LiteralPath $profile).Hash -eq $hash -and -not (Test-Path -LiteralPath "$dir\state\active.json")) 'unsupported config unchanged'
$dir=Join-Path $suite 'wrong-user'; $req=New-PvTestFixture $dir; $req.TargetUserSid='S-1-5-21-0'
Assert-Throws { Invoke-PvOperation $req '' $dir } '原用户' 'different-user elevation refused'
$dir=Join-Path $suite 'empty'; $req=New-PvTestFixture $dir; $req.Items=@()
Assert-Throws { Invoke-PvOperation $req '' $dir } '请选择有效' 'empty selection refused'
$dir=Join-Path $suite 'concurrent'; $req=New-PvTestFixture $dir; $null=New-Item -ItemType Directory -Path $req.StateDirectory
$lock=[IO.File]::Open((Join-Path $req.StateDirectory 'operation.lock'),'OpenOrCreate','ReadWrite','None')
try { Assert-Throws { Invoke-PvOperation $req '' $dir } '已有操作' 'concurrent operations refused' } finally { $lock.Dispose() }
$dir=Join-Path $suite 'worker'; $req=New-PvTestFixture $dir; Save-PvJson "$dir\request.json" $req
& (Get-Process -Id $PID).Path -NoProfile -File "$root\src\Invoke-Worker.ps1" -RequestPath "$dir\request.json" -ProgressPath "$dir\progress.jsonl" -ResultPath "$dir\result.json" -FixtureRoot $dir
Assert ($LASTEXITCODE -eq 0) 'worker exit code'
Assert ((Read-PvJson "$dir\result.json").status -eq 'Configured') 'worker JSON result'
$dir=Join-Path $suite 'interrupted-restore'; $req=New-PvTestFixture $dir; $null=Invoke-PvOperation $req '' $dir
$snapshot=Get-PvActiveSnapshot $req.StateDirectory
$firstFile=$snapshot.files[0]; [IO.File]::Copy((Join-Path $req.StateDirectory $firstFile.backup),$firstFile.path,$true)
$firstPolicy=$snapshot.policies[0]; Set-PvPolicy $firstPolicy.name $firstPolicy.before $dir
$req.Action='Restore'; $r=Invoke-PvOperation $req '' $dir
Assert ($r.status -eq 'Restored' -and -not (Get-PvActiveSnapshot $req.StateDirectory)) 'resume partially completed restore'
Assert ((Get-FileHash -LiteralPath $firstFile.path).Hash -eq $firstFile.beforeHash) 'resumed restore preserves original bytes'
$dir=Join-Path $suite 'tampered-backup'; $req=New-PvTestFixture $dir; $null=Invoke-PvOperation $req '' $dir
$snapshot=Get-PvActiveSnapshot $req.StateDirectory; $firstFile=$snapshot.files[0]
Add-Content -LiteralPath (Join-Path $req.StateDirectory $firstFile.backup) -Value 'fixture tamper'
$hash=(Get-FileHash -LiteralPath $firstFile.path).Hash
$req.Action='Restore'; Assert-Throws { Invoke-PvOperation $req '' $dir } '快照备份校验失败' 'tampered backup blocks restore'
Assert ((Get-FileHash -LiteralPath $firstFile.path).Hash -eq $hash -and [bool](Get-PvActiveSnapshot $req.StateDirectory)) 'tampered backup leaves live fixture and recovery pointer'
$report=@{at=(Get-Date).ToString('o');assertions=$script:assertions;result='passed';scope='isolated fixture engine, parser and worker';liveConfigurationModified=$false;fixtureDirectory=$suite}
Save-PvJson "$root\docs\validation\engine.json" $report
Write-Output "PASS: $script:assertions assertions. No live configuration modified."
