#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Adapters\FlClash.Yaml.ps1"
. "$PSScriptRoot\Progress.ps1"
$script:PolicyNames = @('WebRtcLocalhostIpHandling','WebRtcRespectOsRoutingTableEnabled','WebRtcIPHandlingUrl','DnsOverHttpsMode','DnsOverHttpsTemplates')

function Get-PvIdentity {
    [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
}
function Test-PvAdministrator {
    $p = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Get-PvDefaultStateDirectory { Join-Path $env:LOCALAPPDATA 'ProxyVeil' }
function Read-PvJson([string]$Path) {
    try { ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($Path)) -AsHashtable }
    catch { throw "JSON 文件不可读取或格式不支持：$([IO.Path]::GetFileName($Path))" }
}
function Save-PvJson([string]$Path, $Value) { Write-AtomicText $Path (ConvertTo-Json -InputObject $Value -Depth 100) }
function Get-PvHash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Get-PvTextHash([string]$Text) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','') }
    finally { $sha.Dispose() }
}

function Get-PvOwnedField($Inner,[string]$Path) {
    $parts=$Path.Split('.'); $node=$Inner
    foreach ($part in $parts) {
        if ($node -isnot [Collections.IDictionary] -or -not $node.Contains($part)) { return @{exists=$false;value=$null} }
        $node=$node[$part]
    }
    @{exists=$true;value=$node}
}
function Test-PvFieldEqual($A,$B) {
    if ([bool]$A.exists -ne [bool]$B.exists) { return $false }
    if (-not $A.exists) { return $true }
    (ConvertTo-Json -InputObject $A.value -Depth 100 -Compress) -ceq (ConvertTo-Json -InputObject $B.value -Depth 100 -Compress)
}
function Get-PvPreferenceFields($Before,[string]$AfterJson) {
    $outer=ConvertFrom-Json -InputObject $AfterJson -AsHashtable
    $after=ConvertFrom-Json -InputObject $outer['flutter.config'] -AsHashtable
    $fields=@()
    foreach ($path in @('patchClashConfig.ipv6','patchClashConfig.tun.enable','patchClashConfig.tun.auto-route','patchClashConfig.tun.strict-route','patchClashConfig.tun.dns-hijack','networkProps.appendSystemDns','networkProps.systemProxy','overrideDns')) {
        $old=Get-PvOwnedField $Before $path; $new=Get-PvOwnedField $after $path
        if (-not (Test-PvFieldEqual $old $new)) { $fields+=@(@{path=$path;before=$old;after=$new}) }
    }
    return ,$fields
}
function Get-PvRestoreFilePlan($File,[string]$Directory) {
    if (-not (Test-Path -LiteralPath $File.path -PathType Leaf)) { throw '还原目标文件不存在。' }
    $hash=Get-PvHash $File.path
    if ($hash -in @($File.beforeHash,$File.afterHash)) { return @{hash=$hash;merge=$false;text=$null} }
    if (-not $File.Contains('fields')) { throw "还原冲突：$([IO.Path]::GetFileName($File.path)) 已被外部修改。快照已保留。" }
    $outer=Read-PvJson $File.path
    try { $inner=ConvertFrom-Json -InputObject $outer['flutter.config'] -AsHashtable } catch { throw '还原冲突：偏好格式改变。' }
    foreach ($field in $File.fields) {
        $current=Get-PvOwnedField $inner $field.path
        if (-not (Test-PvFieldEqual $current $field.before) -and -not (Test-PvFieldEqual $current $field.after)) { throw "还原冲突：受管偏好 $($field.path) 已被外部修改。" }
        $parts=$field.path.Split('.'); $node=$inner
        for ($i=0;$i -lt $parts.Length-1;$i++) {
            if (-not $node.Contains($parts[$i]) -or $node[$parts[$i]] -isnot [Collections.IDictionary]) { throw '还原冲突：偏好层级改变。' }
            $node=$node[$parts[$i]]
        }
        $key=$parts[-1]
        if ($field.before.exists) { $node[$key]=$field.before.value } else { $node.Remove($key) }
    }
    $outer['flutter.config']=ConvertTo-Json -InputObject $inner -Depth 100 -Compress
    @{hash=$hash;merge=$true;text=(ConvertTo-Json -InputObject $outer -Depth 100 -Compress)}
}

function Get-PvContext {
    param([string]$InstallPath, [string]$ConfigDirectory, [string]$ProxyGroup, [string]$FixtureRoot)
    if ($FixtureRoot) { $exe = Join-Path $FixtureRoot 'FlClash.exe'; $dir = Join-Path $FixtureRoot 'config' }
    else { $exe = Resolve-FlClashExecutable -Hint $InstallPath -Quiet; $dir = Resolve-FlClashConfigDirectory -Hint $ConfigDirectory -Exe $exe -Quiet }
    $prefs = Join-Path $dir 'shared_preferences.json'
    $preferencesHash=Get-PvHash $prefs
    $outer = Read-PvJson $prefs
    if ((Get-PvHash $prefs) -ne $preferencesHash) { throw '读取期间偏好改变，请等待 FlClash 保存完成。' }
    if (-not $outer.ContainsKey('flutter.config') -or $outer['flutter.config'] -isnot [string]) { throw '无法识别 FlClash 偏好结构。' }
    try { $inner = ConvertFrom-Json -InputObject $outer['flutter.config'] -AsHashtable } catch { throw '无法解析 FlClash 内部偏好。' }
    if (-not $inner.ContainsKey('currentProfileId') -or [string]$inner.currentProfileId -notmatch '^\d+$') { throw '请先在 FlClash 选择一个配置。' }
    if (-not $inner.ContainsKey('patchClashConfig') -or $inner.patchClashConfig -isnot [Collections.IDictionary] -or -not $inner.patchClashConfig.ContainsKey('tun') -or $inner.patchClashConfig.tun -isnot [Collections.IDictionary] -or -not $inner.ContainsKey('networkProps') -or $inner.networkProps -isnot [Collections.IDictionary]) { throw 'FlClash 偏好版本不兼容，未修改。' }
    $profile = Join-Path $dir "profiles\$($inner.currentProfileId).yaml"
    if (-not (Test-Path -LiteralPath $profile -PathType Leaf)) { throw '找不到已选配置的 YAML 文件。' }
    $profileHash=Get-PvHash $profile
    $text = [IO.File]::ReadAllText($profile)
    if ((Get-PvHash $profile) -ne $profileHash) { throw '读取期间配置改变，请等待订阅更新完成。' }
    $group = if ($ProxyGroup) { Select-DnsProxyGroup $text $ProxyGroup } else { Select-DnsProxyGroup $text '' }
    if ($group -match '[#&\r\n]') { throw '此代理组名称暂不支持 DNS URL 参数，请选择其他组。' }
    $mode = if ($inner.patchClashConfig.tun.ContainsKey('enable') -and $inner.patchClashConfig.tun.enable) { 'TUN' } else { 'Proxy' }
    @{Exe=$exe;Directory=$dir;Preferences=$prefs;Profile=$profile;PreferencesHash=$preferencesHash;ProfileHash=$profileHash;Text=$text;Outer=$outer;Inner=$inner;Group=$group;Groups=@(Get-ProxyGroupNames $text);Mode=$mode}
}

function New-PvConfiguration {
    param($Context, [ValidateSet('TUN','Proxy')][string]$Mode, [string[]]$Items)
    $text = $Context.Text
    if ($text -match '(?m)^---\s*$|^\.\.\.\s*$|^\s*["''](?:dns|tun|rules|proxy-groups)["'']\s*:|^\s*(?:[\w-]+:\s*|-\s*)[&*][\w-]+') { throw '复杂 YAML 或多文档配置需要手动编辑，未修改。' }
    $inner = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Context.Inner -Depth 100) -AsHashtable
    $targets = @{}
    if ('DNS' -in $Items) {
        foreach ($v in @(@('enable','true'),@('respect-rules','true'))) { $text = Set-YamlField $text dns $v[0] @($v[1]) }
        $urls = @((ConvertTo-YamlString "https://1.1.1.1/dns-query#$($Context.Group)"),(ConvertTo-YamlString "https://8.8.8.8/dns-query#$($Context.Group)"))
        $text = Set-YamlField $text dns nameserver $urls -List
        foreach ($key in @('nameserver-policy','fallback','direct-nameserver')) { $text = Set-YamlField $text dns $key @($(if ($key -eq 'nameserver-policy') { '{}' } else { '[]' })) }
        $bootstrap=@('"https://223.5.5.5/dns-query#DIRECT"','"https://223.6.6.6/dns-query#DIRECT"')
        $text = Set-YamlField $text dns 'default-nameserver' $bootstrap -List
        $text = Set-YamlField $text dns 'proxy-server-nameserver' $bootstrap -List
        $text = Set-YamlField $text dns 'proxy-server-nameserver-policy' @('{}')
        $text = Set-YamlField $text dns 'prefer-h3' @('false')
        $inner.overrideDns = $false
        $inner.networkProps.appendSystemDns = $false
        $inner.networkProps.systemProxy = ($Mode -eq 'Proxy')
        $inner.patchClashConfig.tun.enable = ($Mode -eq 'TUN')
        $text = Set-YamlField $text tun enable @($(if ($Mode -eq 'TUN') { 'true' } else { 'false' }))
        if ($Mode -eq 'TUN') {
            foreach ($key in @('auto-route','auto-detect-interface','strict-route')) { $text = Set-YamlField $text tun $key @('true') }
            $text = Set-YamlField $text tun dns-hijack @('any:53','tcp://any:53') -List
            $inner.patchClashConfig.tun['auto-route'] = $true
            $inner.patchClashConfig.tun['strict-route'] = $true
            $inner.patchClashConfig.tun['dns-hijack'] = @('any:53','tcp://any:53')
            $targets.DnsOverHttpsMode = @{Exists=$true;Value='off';Type='String'}
        } else {
            $rules = Get-YamlSection $text rules
            if (-not $rules -or $rules.Tail -notmatch '^(#.*)?$') { throw 'Proxy 模式需要块格式 rules。' }
            $extra = @((ConvertTo-YamlString "IP-CIDR,1.1.1.1/32,$($Context.Group),no-resolve"),(ConvertTo-YamlString "IP-CIDR,8.8.8.8/32,$($Context.Group),no-resolve"))
            $lines = [Collections.Generic.List[string]]::new()
            $lines.AddRange([string[]]$rules.Lines)
            $lines.InsertRange($rules.Start+1,[string[]]@($extra | ForEach-Object { "  - $_" }))
            $text = ($lines -join "`n").TrimEnd() + "`n"
            $targets.DnsOverHttpsMode = @{Exists=$true;Value='secure';Type='String'}
            $targets.DnsOverHttpsTemplates = @{Exists=$true;Value='https://1.1.1.1/dns-query https://8.8.8.8/dns-query';Type='String'}
        }
    }
    if ('IPv6' -in $Items) {
        $inner.patchClashConfig.ipv6 = $false
        $text = Set-YamlField $text dns ipv6 @('false')
        $top = Get-YamlSection $text ipv6
        if ($top) { $ls=[Collections.Generic.List[string]]::new(); $ls.AddRange([string[]]$top.Lines); $ls.RemoveRange($top.Start,$top.End-$top.Start); $ls.Insert($top.Start,'ipv6: false'); $text=($ls -join "`n").TrimEnd()+"`n" }
        else { $text = "ipv6: false`n" + $text }
    }
    if ('WebRTC' -in $Items) {
        $targets.WebRtcLocalhostIpHandling = @{Exists=$true;Value='disable_non_proxied_udp';Type='String'}
        $targets.WebRtcRespectOsRoutingTableEnabled = @{Exists=$true;Value=1;Type='DWord'}
        $targets.WebRtcIPHandlingUrl = @{Exists=$true;Value='[{"handling":"disable_non_proxied_udp","url":"*"}]';Type='String'}
    }
    foreach ($section in @('proxies','proxy-groups','proxy-providers','rule-providers')) {
        if ((Get-YamlSectionText $text $section) -cne (Get-YamlSectionText $Context.Text $section)) { throw "保护检查失败：$section" }
    }
    $originalRules = Get-YamlSectionText $Context.Text rules
    $resultRules = Get-YamlSectionText $text rules
    if ('DNS' -in $Items -and $Mode -eq 'Proxy') {
        $resultRules = ($resultRules -split "`n" | Where-Object { $_ -notin @($extra | ForEach-Object { "  - $_" }) }) -join "`n"
    }
    if ($resultRules -cne $originalRules) { throw '原有分流规则保护检查失败。' }
    $outer = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Context.Outer -Depth 100) -AsHashtable
    $outer['flutter.config'] = ConvertTo-Json -InputObject $inner -Depth 100 -Compress
    @{Profile=$text;Preferences=(ConvertTo-Json -InputObject $outer -Depth 100 -Compress);Policies=$targets}
}

function Get-PvPolicy {
    param([string]$Name,[string]$FixtureRoot,[switch]$Machine)
    if ($Name -notin $script:PolicyNames) { throw '未知策略。' }
    if ($FixtureRoot) {
        $store=Read-PvJson (Join-Path $FixtureRoot 'registry.json'); $side=if ($Machine) { 'machine' } else { 'user' }
        if ($store[$side].ContainsKey($Name)) { return $store[$side][$Name] }
        return @{Exists=$false;Value=$null;Type=$null}
    }
    $base=if ($Machine) { [Microsoft.Win32.Registry]::LocalMachine } else { [Microsoft.Win32.Registry]::CurrentUser }
    $key=$base.OpenSubKey('Software\Policies\Microsoft\Edge',$false)
    try {
        if ($key -and $Name -in $key.GetValueNames()) { return @{Exists=$true;Value=$key.GetValue($Name);Type=$key.GetValueKind($Name).ToString()} }
        return @{Exists=$false;Value=$null;Type=$null}
    } finally { if ($key) { $key.Dispose() } }
}
function Set-PvPolicy {
    param([string]$Name,$Value,[string]$FixtureRoot)
    if ($Name -notin $script:PolicyNames) { throw '未知策略。' }
    if ($FixtureRoot) {
        $path=Join-Path $FixtureRoot 'registry.json'; $store=Read-PvJson $path
        if ($store.ContainsKey('deny') -and $Name -in $store.deny) { throw [UnauthorizedAccessException]::new('策略写入权限不足') }
        if ($Value.Exists) { $store.user[$Name]=$Value } else { $store.user.Remove($Name) }
        Save-PvJson $path $store; return
    }
    $key=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Software\Policies\Microsoft\Edge',$true)
    try {
        if ($Value.Exists) {
            $raw=switch ($Value.Type) { DWord {[int]$Value.Value} QWord {[long]$Value.Value} default {$Value.Value} }
            $key.SetValue($Name,$raw,[Microsoft.Win32.RegistryValueKind]::$($Value.Type))
        }
        else { $key.DeleteValue($Name,$false) }
    } finally { if ($key) { $key.Dispose() } }
}
function Test-PvPolicyEqual($A,$B) {
    if ([bool]$A.Exists -ne [bool]$B.Exists) { return $false }
    if (-not $A.Exists) { return $true }
    $A.Type -ceq $B.Type -and [string]$A.Value -ceq [string]$B.Value
}
function Send-PvProgress {
    param([string]$Path,[string]$Id,[string]$Label,[string]$Status,[string]$Detail)
    $entry=@{id=$Id;label=$Label;status=$Status;detail=$Detail;at=(Get-Date).ToString('o')}
    if ($Path) { [IO.File]::AppendAllText($Path,(ConvertTo-Json -InputObject $entry -Compress)+"`n",[Text.UTF8Encoding]::new($false)) }
}
function Initialize-PvState([string]$Directory,[string]$FixtureRoot) {
    $null=New-Item -ItemType Directory -Path $Directory -Force
    if (-not $FixtureRoot) {
        $acl=[Security.AccessControl.DirectorySecurity]::new()
        $acl.SetAccessRuleProtection($true,$false)
        foreach ($sid in @((Get-PvIdentity),'S-1-5-18','S-1-5-32-544')) {
            $rule=[Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),'FullControl','ContainerInherit,ObjectInherit','None','Allow')
            $acl.AddAccessRule($rule)
        }
        Set-Acl -LiteralPath $Directory -AclObject $acl
    }
}
function Save-PvManifest($Manifest,[string]$Directory) { Save-PvJson (Join-Path $Directory 'active.json') $Manifest }
function Get-PvActiveSnapshot([string]$StateDirectory) {
    $path=Join-Path $StateDirectory 'active.json'
    if (Test-Path -LiteralPath $path) { return Read-PvJson $path }
    return $null
}
function Stop-PvFlClash($Context,[bool]$Restart,[string]$FixtureRoot) {
    if ($FixtureRoot) { return $false }
    $matches=@(Get-Process -Name FlClash -ErrorAction SilentlyContinue | Where-Object { try { $_.Path -ieq $Context.Exe } catch { $false } })
    if ($matches.Count -and -not $Restart) { throw '请先退出 FlClash，或打开自动重启设置，避免运行中的软件覆盖配置。' }
    foreach ($process in $matches) { Stop-Process -Id $process.Id -ErrorAction Stop; $process.WaitForExit(5000) | Out-Null }
    $matches.Count -gt 0
}
function Start-PvFlClash([string]$Exe,[string]$FixtureRoot) {
    if (-not $FixtureRoot) { Start-Process -FilePath $Exe -WindowStyle Hidden | Out-Null }
}

# Repair and Restore share a durable write-ahead manifest. After records are persisted
# before each mutation; recovery accepts either recorded Before or After after interruption.
function Invoke-PvOperation {
    [CmdletBinding()]
    param([Collections.IDictionary]$Request,[string]$ProgressPath,[string]$FixtureRoot)
    $stateDir=[string]$Request.StateDirectory
    if (-not $stateDir) { $stateDir=Get-PvDefaultStateDirectory }
    $sid=Get-PvIdentity
    if ($Request.Contains('TargetUserSid') -and $Request.TargetUserSid -and $Request.TargetUserSid -ne $sid) { throw '请使用原用户的管理员授权，其他用户的 UAC 不支持接管。' }
    if ($Request.Edition -notin @('Standard','Administrator')) { throw '未知权限版本。' }
    if ($Request.Edition -eq 'Administrator' -and -not $FixtureRoot -and -not (Test-PvAdministrator)) { throw '管理员版未获得管理员权限，请通过管理员入口启动。' }
    if ($Request.Action -notin @('Inspect','Repair','Restore')) { throw '未知操作。' }
    if ($Request.Action -eq 'Inspect') {
        $c=Get-PvContext -InstallPath $Request.InstallPath -ConfigDirectory $Request.ConfigDirectory -ProxyGroup $Request.ProxyGroup -FixtureRoot $FixtureRoot
        return @{status='Inspected';installPath=$c.Exe;configDirectory=$c.Directory;mode=$c.Mode;groups=$c.Groups;group=$c.Group;administrator=(Test-PvAdministrator);active=[bool](Get-PvActiveSnapshot $stateDir)}
    }
    Initialize-PvState $stateDir $FixtureRoot
    $lockPath=Join-Path $stateDir 'operation.lock'
    try { $lock=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) } catch { throw '已有操作正在执行。' }
    $resume=$false; $exe=''; $manifest=$null
    try {
        if ($Request.Action -eq 'Restore') {
            $manifest=Get-PvActiveSnapshot $stateDir
            if (-not $manifest) { throw '没有可还原的快照。' }
            if ($manifest.sid -ne $sid) { throw '快照属于其他用户。' }
            Send-PvProgress $ProgressPath 'restore-check' '检查还原快照' 'running' '核对文件与策略是否有外部改动'
            foreach ($f in $manifest.files) {
                if ($f.path -notin @($manifest.profile,$manifest.preferences)) { throw '快照包含无效目标。' }
                if ($f.backup -notmatch ('^'+[regex]::Escape($manifest.id)+'-(?:profile|preferences)\.bak$')) { throw '快照备份路径无效。' }
                $null=Get-PvRestoreFilePlan $f $stateDir
                if ((Get-PvHash (Join-Path $stateDir $f.backup)) -ne $f.beforeHash) { throw '快照备份校验失败。' }
            }
            foreach ($p in $manifest.policies) {
                $current=Get-PvPolicy $p.name $FixtureRoot
                if (-not (Test-PvPolicyEqual $current $p.after) -and -not (Test-PvPolicyEqual $current $p.before)) { throw "还原冲突：策略 $($p.name) 已被外部修改。" }
            }
            $exe=$manifest.exe
            if ($manifest.files.Count) { $resume=Stop-PvFlClash @{Exe=$exe} ([bool]$Request.Restart) $FixtureRoot }
            Send-PvProgress $ProgressPath 'restore-check' '检查还原快照' 'applied' '原值校验通过'
            foreach ($f in $manifest.files) {
                Send-PvProgress $ProgressPath 'restore-files' '还原 FlClash 配置' 'running' '恢复原始字节'
                $filePlan=Get-PvRestoreFilePlan $f $stateDir
                if ((Get-PvHash $f.path) -ne $filePlan.hash) { throw '暂停软件后发现配置改变，停止还原。' }
                if ($filePlan.merge) {
                    Write-AtomicText $f.path $filePlan.text
                    if ((Get-PvHash $f.path) -ne (Get-PvTextHash $filePlan.text)) { throw '偏好合并读回失败。' }
                } else {
                    Write-AtomicBytes $f.path ([IO.File]::ReadAllBytes((Join-Path $stateDir $f.backup)))
                    if ((Get-PvHash $f.path) -ne $f.beforeHash) { throw '文件还原读回失败。' }
                }
            }
            Send-PvProgress $ProgressPath 'restore-files' '还原 FlClash 配置' 'applied' '原配置已恢复'
            foreach ($p in $manifest.policies) {
                $current=Get-PvPolicy $p.name $FixtureRoot
                if (-not (Test-PvPolicyEqual $current $p.after) -and -not (Test-PvPolicyEqual $current $p.before)) { throw "策略 $($p.name) 在还原期间改变，停止还原。" }
                Set-PvPolicy $p.name $p.before $FixtureRoot
                if (-not (Test-PvPolicyEqual (Get-PvPolicy $p.name $FixtureRoot) $p.before)) { throw '策略还原读回失败。' }
            }
            Send-PvProgress $ProgressPath 'restore-policies' '还原 Edge 策略' 'applied' '重启 Edge 后生效'
            $manifest.status='restored'; $manifest.restoredAt=(Get-Date).ToString('o')
            Save-PvJson (Join-Path $stateDir "history-$($manifest.id).json") $manifest
            Remove-Item -LiteralPath (Join-Path $stateDir 'active.json')
            return @{status='Restored';active=$false;message='已还原。请重启 Edge。';items=@()}
        }
        if (Get-PvActiveSnapshot $stateDir) { throw '已有快照，请先还原；不会覆盖最初的备份。' }
        $items=@($Request.Items | Select-Object -Unique)
        if (-not $items.Count -or @($items | Where-Object { $_ -notin @('DNS','WebRTC','IPv6') }).Count) { throw '请选择有效的修复项目。' }
        if ($Request.Mode -notin @('TUN','Proxy')) { throw '请选择 TUN 或 Proxy 模式。' }
        Send-PvProgress $ProgressPath 'detect' '识别 FlClash' 'running' '读取安装位置与当前配置'
        $c=Get-PvContext -InstallPath $Request.InstallPath -ConfigDirectory $Request.ConfigDirectory -ProxyGroup $Request.ProxyGroup -FixtureRoot $FixtureRoot
        $exe=$c.Exe
        if ('DNS' -in $items -and $Request.Mode -eq 'TUN' -and $Request.Edition -eq 'Standard' -and -not $FixtureRoot) {
            $svc=Get-Service -Name FlClashHelperService -ErrorAction SilentlyContinue
            if (-not $svc -or $svc.Status -ne 'Running') { throw '普通权限 TUN 需要运行中的 FlClashHelperService；先在 FlClash 安装服务，或使用管理员版。' }
        }
        $changedFiles=('DNS' -in $items -or 'IPv6' -in $items)
        if ($changedFiles) {
            $resume=Stop-PvFlClash $c ([bool]$Request.Restart) $FixtureRoot
            $c=Get-PvContext -InstallPath $c.Exe -ConfigDirectory $c.Directory -ProxyGroup $c.Group -FixtureRoot $FixtureRoot
        }
        $plan=New-PvConfiguration $c $Request.Mode $items
        Send-PvProgress $ProgressPath 'detect' '识别 FlClash' 'applied' "$($Request.Mode) / 原有分流保留"
        $id=[guid]::NewGuid().ToString('N')
        $manifest=@{schema=1;id=$id;sid=$sid;createdAt=(Get-Date).ToString('o');status='applying';mode=$Request.Mode;edition=$Request.Edition;exe=$exe;profile=$c.Profile;preferences=$c.Preferences;files=@();policies=@();items=$items}
        Save-PvManifest $manifest $stateDir
        $results=[Collections.Generic.List[object]]::new()
        try {
            if ($changedFiles) {
                Send-PvProgress $ProgressPath 'config' '备份并修改 FlClash' 'running' '加密解析、模式与选择项'
                foreach ($f in @(@{path=$c.Profile;text=$plan.Profile;name='profile'},@{path=$c.Preferences;text=$plan.Preferences;name='preferences'})) {
                    $baseline=if ($f.name -eq 'profile') { $c.ProfileHash } else { $c.PreferencesHash }
                    if ($FixtureRoot -and $Request.Contains('Fault') -and $Request.Fault -eq 'drift-before-backup') { [IO.File]::AppendAllText($f.path,"`n# external drift") }
                    if ((Get-PvHash $f.path) -ne $baseline) { throw '配置在检查后发生改变，停止写入。' }
                    $record=@{path=$f.path;backup="$id-$($f.name).bak";beforeHash=$baseline;afterHash=(Get-PvTextHash $f.text)}
                    if ($f.name -eq 'preferences') { $record.fields=Get-PvPreferenceFields $c.Inner $f.text }
                    [IO.File]::Copy($f.path,(Join-Path $stateDir $record.backup),$false)
                    if ((Get-PvHash (Join-Path $stateDir $record.backup)) -ne $baseline) { throw '备份过程中配置发生改变。' }
                    $manifest.files+=@($record); Save-PvManifest $manifest $stateDir
                    if ($FixtureRoot -and $Request.Contains('Fault') -and $Request.Fault -eq $f.name) { throw '隔离故障：配置写入失败' }
                    if ((Get-PvHash $f.path) -ne $record.beforeHash) { throw '配置在备份后发生改变，停止写入。' }
                    Write-AtomicText $f.path $f.text
                    if ((Get-PvHash $f.path) -ne $record.afterHash) { throw '配置读回失败。' }
                }
                Send-PvProgress $ProgressPath 'config' '备份并修改 FlClash' 'applied' '配置已写入并读回'
            }
            foreach ($item in $items) {
                $label=switch ($item) { DNS {'DNS 泄露防护'} WebRTC {'Edge WebRTC 防护'} IPv6 {'代理内 IPv6'} }
                Send-PvProgress $ProgressPath $item $label 'running' '检查选定保护项'
                $names=switch ($item) { DNS {@($plan.Policies.Keys | Where-Object { $_ -like 'Dns*' })} WebRTC {@($plan.Policies.Keys | Where-Object { $_ -like 'WebRtc*' })} IPv6 {@()} }
                $skipped=[Collections.Generic.List[string]]::new()
                foreach ($name in $names) {
                    $target=$plan.Policies[$name]; $machine=Get-PvPolicy $name $FixtureRoot -Machine
                    if ($machine.Exists -and -not (Test-PvPolicyEqual $machine $target)) { $skipped.Add('组织策略冲突'); continue }
                    $before=Get-PvPolicy $name $FixtureRoot
                    $record=@{name=$name;before=$before;after=$target}
                    $manifest.policies+=@($record); Save-PvManifest $manifest $stateDir
                    try {
                        Set-PvPolicy $name $target $FixtureRoot
                        if (-not (Test-PvPolicyEqual (Get-PvPolicy $name $FixtureRoot) $target)) { throw '策略读回失败。' }
                    } catch [UnauthorizedAccessException] {
                        $manifest.policies=@($manifest.policies | Where-Object { $_ -ne $record }); Save-PvManifest $manifest $stateDir
                        $skipped.Add('策略写入权限不足'); continue
                    } catch [Security.SecurityException] {
                        $manifest.policies=@($manifest.policies | Where-Object { $_ -ne $record }); Save-PvManifest $manifest $stateDir
                        $skipped.Add('策略写入权限不足'); continue
                    }
                }
                $status=if ($skipped.Count) { 'skipped' } else { 'applied' }
                $detail=if ($skipped.Count) { ($skipped | Select-Object -Unique) -join '；' } else { switch ($item) { DNS { if ($Request.Mode -eq 'Proxy') {'已配置 Edge 加密 DNS；其他应用需单独检查'} else {'已配置 DNS 接管；节点引导解析单独处理'} } WebRTC {'已写入策略；重启 Edge 后检查策略是否生效'} IPv6 {'FlClash IPv6 关闭；物理网卡保持原设置'} } }
                Send-PvProgress $ProgressPath $item $label $status $detail
                $results.Add(@{id=$item;status=$status;detail=$detail})
            }
            $manifest.status='configured'; Save-PvManifest $manifest $stateDir
        } catch {
            $cause=$_.Exception.Message
            $rollback=$true
            foreach ($p in @($manifest.policies)) {
                try {
                    $current=Get-PvPolicy $p.name $FixtureRoot
                    if (Test-PvPolicyEqual $current $p.after) { Set-PvPolicy $p.name $p.before $FixtureRoot }
                    elseif (-not (Test-PvPolicyEqual $current $p.before)) { $rollback=$false }
                } catch { $rollback=$false }
            }
            foreach ($f in @($manifest.files)) {
                try {
                    $hash=Get-PvHash $f.path
                    if ($hash -eq $f.afterHash) { Write-AtomicBytes $f.path ([IO.File]::ReadAllBytes((Join-Path $stateDir $f.backup))) }
                    elseif ($hash -ne $f.beforeHash) { $rollback=$false }
                } catch { $rollback=$false }
            }
            if ($rollback) { Remove-Item -LiteralPath (Join-Path $stateDir 'active.json') }
            else { $manifest.status='recovery-required'; Save-PvManifest $manifest $stateDir }
            throw "$cause；$(if ($rollback) { '已回退本次改动' } else { '部分回退受阻，请从快照还原' })"
        }
        $active=$manifest.files.Count -gt 0 -or $manifest.policies.Count -gt 0
        if (-not $active) { Remove-Item -LiteralPath (Join-Path $stateDir 'active.json') }
        $partial=@($results | Where-Object { $_.status -eq 'skipped' }).Count -gt 0
        if ($changedFiles -and $Request.Restart -and -not $FixtureRoot) { $resume=$true }
        $restartMessage=if ($changedFiles -and -not $resume) { '；打开 FlClash 后生效' } else { '' }
        @{status=$(if ($partial) {'Partial'} else {'Configured'});active=$active;items=$results.ToArray();message="配置已处理$restartMessage。请重启 Edge 并复测。"}
    } finally {
        try { if ($resume -and $exe) { Start-PvFlClash $exe $FixtureRoot; Send-PvProgress $ProgressPath 'restart' '重启 FlClash' 'applied' '已启动；请检查连接与泄露测试' } }
        finally { $lock.Dispose() }
    }
}
Export-ModuleMember -Function Get-PvContext,Get-PvIdentity,Test-PvAdministrator,Get-PvDefaultStateDirectory,Get-PvActiveSnapshot,Invoke-PvOperation,New-PvConfiguration,Read-PvJson,Save-PvJson,Get-PvPolicy,Set-PvPolicy,Test-PvPolicyEqual,Read-PvProgressLines
