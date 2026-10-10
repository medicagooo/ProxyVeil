function Get-YamlSection {
    param([string]$Text, [string]$Name)
    $lines = [regex]::Split($Text.TrimStart([char]0xFEFF), '\r?\n')
    $pattern = '^' + [regex]::Escape($Name) + ':\s*(?<tail>.*?)\s*$'
    $found = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $pattern) { $found += $i }
    }
    if ($found.Count -gt 1) { throw "重复的 YAML 顶层字段：$Name" }
    if ($found.Count -eq 0) { return $null }
    $start = $found[0]
    $tail = ([regex]::Match($lines[$start], $pattern)).Groups['tail'].Value
    $end = $lines.Count
    for ($i = $start + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^[^\s#-][^:]*:|^---\s*$|^\.\.\.\s*$') { $end = $i; break }
    }
    [pscustomobject]@{ Lines = $lines; Start = $start; End = $end; Tail = $tail }
}

function Get-YamlSectionText {
    param([string]$Text, [string]$Name)
    $s = Get-YamlSection $Text $Name
    if (-not $s) { return '' }
    return ($s.Lines[$s.Start..($s.End - 1)] -join "`n").TrimEnd()
}

function ConvertFrom-YamlScalar {
    param([string]$Value)
    $v = $Value.Trim()
    if ($v.StartsWith('"')) {
        if ($v -notmatch '^("(?:[^"\\]|\\.)*")\s*(?:#.*)?$') { throw '不支持的 YAML 双引号标量。' }
        $v = $Matches[1]
        try { return [string]($v | ConvertFrom-Json) } catch { throw '不支持的 YAML 双引号转义。' }
    }
    if ($v.StartsWith("'")) {
        if ($v -notmatch "^('(?:[^']|'')*')\s*(?:#.*)?$" ) { throw '不支持的 YAML 单引号。' }
        $v = $Matches[1]
        return $v.Substring(1, $v.Length - 2).Replace("''", "'")
    }
    $v = ($v -replace '\s+#.*$', '').Trim()
    if ($v -in @('[]','{}')) { return $v }
    if ($v -match '^[\[\{&*!>|]') { throw '不支持的 YAML 标量格式。' }
    return $v
}

function ConvertTo-YamlString {
    param([string]$Value)
    return (ConvertTo-Json -InputObject $Value -Compress)
}

function Set-YamlField {
    param([string]$Text, [string]$Section, [string]$Field, [string[]]$Values, [switch]$List)
    $s = Get-YamlSection $Text $Section
    if (-not $s) {
        $Text = $Text.TrimEnd() + "`n${Section}:`n"
        $s = Get-YamlSection $Text $Section
    }
    if ($s.Tail -notmatch '^(?:#.*|\{\s*\}|null|~)?$') {
        throw "不支持 $Section 的内联映射/锚点，未写入配置。"
    }
    $body = [System.Collections.Generic.List[string]]::new()
    for ($i = $s.Start + 1; $i -lt $s.End; $i++) { $body.Add($s.Lines[$i]) }
    $indent = $null
    foreach ($line in $body) {
        if ($line -match '^( +)[\w-]+\s*:') {
            $n = $Matches[1].Length
            if ($null -eq $indent -or $n -lt $indent) { $indent = $n }
        }
        if ($line.Contains("`t")) { throw "${Section} 存在 Tab 缩进，未写入配置。" }
    }
    if ($null -eq $indent) { $indent = 2 }
    $padding = ' ' * $indent
    $keyPattern = '^' + $padding + '(?<key>[\w-]+)\s*:'
    $seen = @{}
    $at = -1
    for ($i = 0; $i -lt $body.Count; $i++) {
        if ($body[$i] -match $keyPattern) {
            $key = $Matches.key
            if ($seen.ContainsKey($key)) { throw "重复 YAML 字段：${Section}.${key}" }
            $seen[$key] = $true
            if ($key -eq $Field) { $at = $i }
        }
        if ($body[$i] -match ('^' + $padding + '(?:<<\s*:|["'']|[&*!])')) {
            throw "${Section} 包含复杂映射键/合并键，未写入配置。"
        }
    }
    if ($at -lt 0) { $at = $body.Count }
    else {
        $last = $body.Count
        for ($i = $at + 1; $i -lt $body.Count; $i++) {
            if ($body[$i] -match $keyPattern) { $last = $i; break }
        }
        $body.RemoveRange($at, $last - $at)
    }
    $insert = [System.Collections.Generic.List[string]]::new()
    if ($List) {
        $insert.Add("${padding}${Field}:")
        foreach ($value in $Values) { $insert.Add("$padding  - $value") }
    } else { $insert.Add("${padding}${Field}: $($Values[0])") }
    $body.InsertRange($at, $insert)
    $out = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $s.Start; $i++) { $out.Add($s.Lines[$i]) }
    $out.Add("${Section}:")
    $out.AddRange($body)
    for ($i = $s.End; $i -lt $s.Lines.Count; $i++) { $out.Add($s.Lines[$i]) }
    return ($out -join "`n").TrimEnd() + "`n"
}

function Get-YamlFieldBlock {
    param([string]$Text, [string]$Section, [string]$Field)
    $s = Get-YamlSection $Text $Section
    if (-not $s) { return $null }
    $indent = $null
    for ($i = $s.Start + 1; $i -lt $s.End; $i++) {
        if ($s.Lines[$i] -match '^( +)[\w-]+\s*:') {
            $n = $Matches[1].Length
            if ($null -eq $indent -or $n -lt $indent) { $indent = $n }
        }
    }
    if ($null -eq $indent) { return $null }
    $padding = ' ' * $indent
    $pattern = '^' + $padding + [regex]::Escape($Field) + ':\s*(.*?)\s*$'
    for ($i = $s.Start + 1; $i -lt $s.End; $i++) {
        if ($s.Lines[$i] -match $pattern) {
            $value = $Matches[1]
            $end = $s.End
            for ($j = $i + 1; $j -lt $s.End; $j++) {
                if ($s.Lines[$j] -match ('^' + $padding + '[\w-]+\s*:')) { $end = $j; break }
            }
            return [pscustomobject]@{ Value = $value; Text = ($s.Lines[$i..($end - 1)] -join "`n") }
        }
    }
    return $null
}

function Get-YamlField {
    param([string]$Text, [string]$Section, [string]$Field)
    $block = Get-YamlFieldBlock $Text $Section $Field
    if (-not $block) { return $null }
    if ($block.Value -match '^\s*[\[{]') { return $block.Value.Trim() }
    return ConvertFrom-YamlScalar $block.Value
}

function Get-ProxyGroupNames {
    param([string]$Text)
    $s = Get-YamlSection $Text 'proxy-groups'
    if (-not $s -or $s.Tail -notmatch '^(#.*)?$') { throw '需要块格式的 proxy-groups。' }
    $names = [System.Collections.Generic.List[string]]::new()
    $itemIndent = $null
    for ($i = $s.Start + 1; $i -lt $s.End; $i++) {
        if ($s.Lines[$i] -match '^(\s*)-\s+(?:name|type|proxies|use|url|interval):') {
            $n = $Matches[1].Length
            if ($null -eq $itemIndent -or $n -lt $itemIndent) { $itemIndent = $n }
        }
    }
    if ($null -eq $itemIndent) { throw '无法识别 proxy-groups 列表。' }
    for ($i = $s.Start + 1; $i -lt $s.End; $i++) {
        $p = '^(?:' + (' ' * $itemIndent) + '-\s+|' + (' ' * ($itemIndent + 2)) + ')name:\s*(.+)$'
        if ($s.Lines[$i] -match $p) { $names.Add((ConvertFrom-YamlScalar $Matches[1])) }
    }
    if ($names.Count -eq 0) { throw '未检测到代理组名称。' }
    return $names.ToArray()
}

function Select-DnsProxyGroup {
    param([string]$Text, [string]$Requested)
    $names = @(Get-ProxyGroupNames $Text)
    if ($Requested) {
        if ($Requested -cnotin $names -or $Requested -in @('DIRECT','REJECT','PASS')) { throw '指定代理组不存在或不是代理组。' }
        return $Requested
    }
    $rules = Get-YamlSectionText $Text 'rules'
    foreach ($line in ($rules -split "`n")) {
        if ($line -match '^\s*-\s*(.+)$') {
            $rule = ConvertFrom-YamlScalar $Matches[1]
            if ($rule -match '^(?:MATCH|FINAL),(.+)$' -and $Matches[1] -cin $names) { return $Matches[1] }
        }
    }
    $usable = @($names | Where-Object { $_ -notin @('DIRECT','REJECT','PASS') })
    if ($usable.Count -eq 1) { return $usable[0] }
    throw '无法自动选定 DNS 代理组。请用 -ProxyGroup 指定现有代理组。'
}

function Resolve-FlClashExecutable {
    param([string]$Hint, [switch]$Quiet)
    function Resolve-Exe([string]$Path) {
        if (-not $Path) { return $null }
        $p = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
        if (Test-Path -LiteralPath $p -PathType Container) { $p = Join-Path $p 'FlClash.exe' }
        if ((Test-Path -LiteralPath $p -PathType Leaf) -and [IO.Path]::GetFileName($p) -ieq 'FlClash.exe') {
            return (Get-Item -LiteralPath $p).FullName
        }
        return $null
    }
    if ($Hint) {
        $resolved = Resolve-Exe $Hint
        if (-not $resolved) { throw 'InstallPath 必须是 FlClash.exe 或其安装目录。' }
        return $resolved
    }
    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($process in @(Get-Process -Name FlClash -ErrorAction SilentlyContinue)) {
        try { if ($process.Path) { $candidates.Add($process.Path) } } catch {}
    }
    foreach ($hive in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
        foreach ($key in @(Get-ChildItem -LiteralPath $hive -ErrorAction SilentlyContinue)) {
            $item = Get-ItemProperty -LiteralPath $key.PSPath
            if ($item.PSObject.Properties['DisplayName'] -and $item.DisplayName -match '(?i)flclash') {
                if ($item.PSObject.Properties['InstallLocation'] -and $item.InstallLocation) { $candidates.Add($item.InstallLocation) }
                if ($item.PSObject.Properties['DisplayIcon'] -and $item.DisplayIcon) { $candidates.Add(($item.DisplayIcon -replace ',\s*\d+$','')) }
            }
        }
    }
    $roots = @($PSScriptRoot, $env:LOCALAPPDATA, $env:ProgramFiles, ${env:ProgramFiles(x86)}, [Environment]::GetFolderPath('MyDocuments'), (Join-Path $env:USERPROFILE 'Downloads'))
    foreach ($root in $roots | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique) {
        $candidates.Add((Join-Path $root 'FlClash.exe'))
        foreach ($directory in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Where-Object Name -Match '(?i)flclash|^programs$|^app$|^apps$')) {
            $candidates.Add($directory.FullName)
            foreach ($sub in @(Get-ChildItem -LiteralPath $directory.FullName -Directory -ErrorAction SilentlyContinue | Where-Object Name -Match '(?i)flclash')) { $candidates.Add($sub.FullName) }
        }
    }
    try {
        $shell = New-Object -ComObject WScript.Shell
        foreach ($root in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('StartMenu'), [Environment]::GetFolderPath('CommonStartMenu'))) {
            if ($root -and (Test-Path -LiteralPath $root)) {
                foreach ($link in @(Get-ChildItem -LiteralPath $root -Filter '*FlClash*.lnk' -Recurse -File -ErrorAction SilentlyContinue)) { $candidates.Add($shell.CreateShortcut($link.FullName).TargetPath) }
            }
        }
    } catch {}
    foreach ($candidate in $candidates) { $resolved = Resolve-Exe $candidate; if ($resolved) { return $resolved } }
    if ($Quiet) { throw '未找到 FlClash；请传入 -InstallPath。' }
    $manual = Read-Host '未找到 FlClash，请输入 FlClash.exe 的完整路径或安装目录'
    return Resolve-FlClashExecutable -Hint $manual -Quiet
}

function Resolve-FlClashConfigDirectory {
    param([string]$Hint, [string]$Exe, [switch]$Quiet)
    $paths = if ($Hint) { @($Hint) } else {
        @((Join-Path $env:APPDATA 'com.follow\clash'), (Join-Path (Split-Path $Exe) 'data\com.follow\clash'), (Join-Path (Split-Path $Exe) 'data'), (Split-Path $Exe))
    }
    foreach ($p in $paths) {
        $expanded = [Environment]::ExpandEnvironmentVariables($p.Trim().Trim('"'))
        if (Test-Path -LiteralPath (Join-Path $expanded 'shared_preferences.json') -PathType Leaf) { return (Get-Item -LiteralPath $expanded).FullName }
    }
    if ($Hint -or $Quiet) { throw '未找到 FlClash 配置目录；请传入 -ConfigDirectory。' }
    return Resolve-FlClashConfigDirectory -Hint (Read-Host '请输入包含 shared_preferences.json 的 FlClash 配置目录') -Exe $Exe -Quiet
}

function Write-AtomicText {
    param([string]$Path, [string]$Text)
    $temp = $Path + '.privacy-' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temp, $Text, [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temp, $Path, $true)
    } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp } }
}

function Write-AtomicBytes([string]$Path,[byte[]]$Bytes) {
    $temp=$Path+'.privacy-'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        [IO.File]::WriteAllBytes($temp,$Bytes)
        [IO.File]::Move($temp,$Path,$true)
    } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp } }
}

# FlClash conversion is owned here; the core calls it before snapshot mutations.
function New-PvConfiguration {
    param($Context, [ValidateSet('TUN','Proxy')][string]$Mode, [string[]]$Items)
    $text = $Context.Text
    $targets = @{}
    if ('WebRTC' -in $Items) {
        $targets.WebRtcLocalhostIpHandling = @{Exists=$true;Value='disable_non_proxied_udp';Type='String'}
        $targets.WebRtcRespectOsRoutingTableEnabled = @{Exists=$true;Value=1;Type='DWord'}
        $targets.WebRtcIPHandlingUrl = @{Exists=$true;Value='[{"handling":"disable_non_proxied_udp","url":"*"}]';Type='String'}
    }
    # Edge-only repair does not parse, select groups from, or rewrite FlClash YAML.
    if ('DNS' -notin $Items -and 'IPv6' -notin $Items) {
        return @{Profile=$text;Preferences=(ConvertTo-Json -InputObject $Context.Outer -Depth 100 -Compress);Policies=$targets}
    }
    if ($text -match '(?m)^---\s*$|^\.\.\.\s*$|^\s*["''](?:dns|tun|rules|proxy-groups)["'']\s*:|^\s*(?:[\w-]+:\s*|-\s*)[&*][\w-]+') { throw '复杂 YAML 或多文档配置需要手动编辑，未修改。' }
    $inner = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Context.Inner -Depth 100) -AsHashtable
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
            if ($Context.Group.Contains(',')) { throw 'Proxy DNS 的代理组名称不能包含逗号，未修改。' }
            $rules = Get-YamlSection $text rules
            if (-not $rules -or $rules.Tail -notmatch '^(#.*)?$') { throw 'Proxy 模式需要块格式 rules。' }
            $ruleIndent=$null
            for ($i=$rules.Start+1;$i -lt $rules.End;$i++) {
                if ($rules.Lines[$i] -match '^( *)-\s+') {
                    if ($null -eq $ruleIndent) { $ruleIndent=$Matches[1] }
                    elseif ($ruleIndent.Length -ne $Matches[1].Length) { throw 'rules 列表缩进不一致，未修改。' }
                } elseif ($rules.Lines[$i] -notmatch '^\s*(?:#.*)?$') { throw '需要单行块格式 rules，未修改。' }
            }
            if ($null -eq $ruleIndent) { $ruleIndent='  ' }
            $extra = @((ConvertTo-YamlString "IP-CIDR,1.1.1.1/32,$($Context.Group),no-resolve"),(ConvertTo-YamlString "IP-CIDR,8.8.8.8/32,$($Context.Group),no-resolve"))
            $lines = [Collections.Generic.List[string]]::new()
            $lines.AddRange([string[]]$rules.Lines)
            $lines.InsertRange($rules.Start+1,[string[]]@($extra | ForEach-Object { "$ruleIndent- $_" }))
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
    foreach ($section in @('proxies','proxy-groups','proxy-providers','rule-providers')) {
        if ((Get-YamlSectionText $text $section) -cne (Get-YamlSectionText $Context.Text $section)) { throw "保护检查失败：$section" }
    }
    $originalRules = Get-YamlSectionText $Context.Text rules
    $resultRules = Get-YamlSectionText $text rules
    if ('DNS' -in $Items -and $Mode -eq 'Proxy') {
        # Remove only this plan's prefix; identical pre-existing rules are user data.
        $ruleLines=[Collections.Generic.List[string]]::new()
        $ruleLines.AddRange([string[]]($resultRules -split "`n"))
        $ruleLines.RemoveRange(1,$extra.Count)
        $resultRules=$ruleLines -join "`n"
    }
    if ($resultRules -cne $originalRules) { throw '原有分流规则保护检查失败。' }
    $outer = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Context.Outer -Depth 100) -AsHashtable
    $outer['flutter.config'] = ConvertTo-Json -InputObject $inner -Depth 100 -Compress
    @{Profile=$text;Preferences=(ConvertTo-Json -InputObject $outer -Depth 100 -Compress);Policies=$targets}
}
