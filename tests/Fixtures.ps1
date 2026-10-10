function New-PvTestFixture([string]$Root) {
    $null=New-Item -ItemType Directory -Path "$Root\config\profiles" -Force
    [IO.File]::WriteAllText("$Root\FlClash.exe",'fixture marker, never executable')
    $profile=@'
mixed-port: 7890
ipv6: true
dns:
  enable: false
  ipv6: true
  nameserver:
    - 114.114.114.114
  nameserver-policy:
    '+.cn': 223.5.5.5
  fallback:
    - 8.8.8.8
tun:
  enable: false
  stack: mixed
proxies:
  - name: test-node
    type: ss
    server: example.invalid
    port: 443
    cipher: aes-128-gcm
    password: fixture-only
proxy-groups:
  - name: 选择代理
    type: select
    proxies:
      - test-node
rules:
  - GEOSITE,CN,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,选择代理
'@
    [IO.File]::WriteAllText("$Root\config\profiles\123.yaml",$profile,[Text.UTF8Encoding]::new($true))
    $inner=@{currentProfileId='123';patchClashConfig=@{mode='rule';ipv6=$true;tun=@{enable=$false;stack='mixed'}};networkProps=@{systemProxy=$true;appendSystemDns=$true};overrideDns=$true;unrelated=@{keep='unchanged'}}
    @{ 'flutter.config'=(ConvertTo-Json -InputObject $inner -Depth 100 -Compress); 'flutter.other'='retain' } | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath "$Root\config\shared_preferences.json" -Encoding utf8BOM
    @{user=@{WebRtcRespectOsRoutingTableEnabled=@{Exists=$true;Type='DWord';Value=0}};machine=@{};deny=@()} | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath "$Root\registry.json" -Encoding utf8
    @{Action='Repair';Edition='Standard';Mode='TUN';Items=@('DNS','WebRTC','IPv6');InstallPath='';ConfigDirectory='';ProxyGroup='';Restart=$true;StateDirectory="$Root\state";TargetUserSid=(Get-PvIdentity)}
}
