# Windows 第二阶段：回归与兼容性验收

本阶段由 Windows 测试机或 VM 执行，目标是确认 macOS 适配提交没有破坏既有 PowerShell 7/WPF 产品，并补齐 Windows 10 与不同 PowerShell 7 运行时的证据。当前 Mac 没有 `pwsh`，本阶段尚未执行。

## 运行顺序

在干净的 Windows 测试工作区执行：

```powershell
Set-Location D:\proj\ProxyVeil
pwsh -NoProfile -File scripts\Test.ps1
pwsh -NoProfile -STA -File scripts\Test-UI.ps1
pwsh -NoProfile -STA -File scripts\Test-UI-Failure.ps1
pwsh -NoProfile -File scripts\Test-Package.ps1
```

若测试机使用系统默认的 PowerShell 7，也要记录：

```powershell
$PSVersionTable.PSVersion
[System.Environment]::OSVersion.Version
```

## 手工检查

在隔离 FlClash 配置上检查普通入口和管理员入口。分别覆盖 TUN、Proxy、DNS、IPv6 与 WebRTC 单项选择；确认检查、修复、进度显示、失败提示、快照还原和外部修改冲突均符合预期。管理员测试只验证入口和隔离夹具，不应修改真实 Edge 组织策略。

完成一次无凭据的浏览器复测：重启 FlClash 与 Edge，在 `edge://policy` 查看 WebRTC 策略状态；对代理流量检查公网出口、DNS 服务和 WebRTC 地址；确认国内直连仍按原规则工作。不要把订阅、节点、快照或个人策略内容写入验证记录。

## 阶段完成标准

- `Test.ps1`、`Test-UI.ps1`、`Test-UI-Failure.ps1` 和 `Test-Package.ps1` 全部通过。
- Windows 10 和至少一个 Windows 11 环境完成启动与回退 UI 检查。
- 至少记录两个 PowerShell 7 运行时版本，或明确记录无法提供第二个运行时。
- 普通版、管理员版和还原流程均有无凭据结果。
- 将命令输出摘要写入 `docs/validation/windows-stage2.json`，再决定是否重新构建 ZIP。

本阶段不包含新代理、Chrome/Firefox 适配或 GitHub Release；这些需要单独需求和验收范围。
