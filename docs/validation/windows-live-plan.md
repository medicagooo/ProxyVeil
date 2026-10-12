# Windows 实机验收计划

2026-10-12，D:/proj/ProxyVeil 本地 main。隔离测试、桌面控件测试及真实配置只读识别已完成。用户已明确选择“只完成隔离测试及只读检查”，以下备选计划本轮不执行，也不继续请求授权；保留目标与影响说明供用户未来主动提出新范围时参考。

当前目标：

- FlClash：`C:/Users/medic/OneDrive/Documents/APP/FlClash-0.8.99-windows-amd64/FlClash.exe`，版本 0.8.99。
- 配置目录：`C:/Users/medic/AppData/Roaming/com.follow/clash`。
- 文件：`shared_preferences.json` 和当前选中的 `profiles/365023800137355264.yaml`。执行前重新核对选中 profile；若改变，更新计划。
- 用户策略：`HKCU/Software/Policies/Microsoft/Edge` 下 `WebRtcLocalhostIpHandling`、`WebRtcRespectOsRoutingTableEnabled`、`WebRtcIPHandlingUrl`、`DnsOverHttpsMode`，Proxy 模式另有 `DnsOverHttpsTemplates`。机器策略不写。
- 恢复目录：`C:/Users/medic/AppData/Local/ProxyVeil`，当前无 active.json。原始文件、凭据和快照仅保存在本机，不提交。

普通版使用已经运行的 FlClashHelperService。分别验证 TUN 和 Proxy：显式调用 `Invoke-PvOperation` 的 Repair，项目为 DNS/WebRTC/IPv6，允许通过应用重启 FlClash；保留订阅、节点选择和原有国内直连规则。每种模式测试后调用 Restore，再核对受管偏好、原始 YAML 字节和原生策略类型。失败或外部漂移时保留快照并先诊断，不强制覆盖。

修复会短暂中断网络，修改 FlClash DNS/模式/IPv6 及上述当前用户 Edge 策略。Edge 策略的采用、WebRTC 和浏览器 DNS 验收需要重启浏览器并查看 edge://policy；不自动结束用户已有 Edge 窗口。实际 UAC 成功路径需要用户在安全桌面接受当前用户提权，单独启动管理员入口观察。权限拒绝测试不替代 UAC 成功证据。

本次只读基线见 windows-host.json：百度与 Google 在默认连接和显式 127.0.0.1:7890 代理连接均为 HTTP 200。这不是修复后泄露验收。修复后分别记录国内和代理站点 HTTPS、代理出口、DNS 服务、WebRTC 公网候选及 IPv6 结果；只保存通过/失败与无凭据摘要，不保存原始网络地址或订阅。

真实写入的调用形态如下；不能在授权前执行：

```powershell
Import-Module D:/proj/ProxyVeil/src/ProxyVeil.Core.psm1 -Force
$context = Get-PvContext
$request = @{
    Action = 'Repair'
    Edition = 'Standard'
    TargetUserSid = Get-PvIdentity
    InstallPath = $context.Exe
    ConfigDirectory = $context.Directory
    ProxyGroup = $context.Group
    Mode = 'TUN' # 第二轮为 Proxy；每轮分别还原
    Items = @('DNS', 'WebRTC', 'IPv6')
    Restart = $true
    StateDirectory = Get-PvDefaultStateDirectory
}
Invoke-PvOperation -Request $request
# 网络/浏览器验收完成后使用同一请求、同一恢复目录
$request.Action = 'Restore'
Invoke-PvOperation -Request $request
```

Mac 不再测试；Windows 10 单独验收也不在当前范围。
