# README 与 Windows 检查修复

2026-10-12，用户要求修复发现的错误，补全带图片的 README 并推送 main。延续既有边界：真实 FlClash / Edge 只读，测试使用隔离配置，不复测 Mac。

## 检查报告误报

原 `scripts/Test-WindowsHost.ps1` 在成功完成 Inspect 后，如果后续文件哈希等步骤异常，会记录 `inspectionResult=failed`，但最终判断仅查看早先的 Inspect 与计划结果。用成功 Inspect、后续 IOException 的合成报告执行原判断，复现异常报告被接受。文件或策略变化也未进入失败判断。

现由 `tests/WindowsHost.Assertions.ps1::Assert-PvWindowsHostReport` 检查完整结束标记、文件和策略保持不变、TUN / Proxy 两个计划、当前身份所需的权限保护。`Test-WindowsHost.ps1` 保存脱敏 JSON 后调用此判断，缺项、异常或变化会导致非零退出。HTTPS 请求结果作为基线独立保留，失败不等于配置检查失败，也不表示泄露测试通过。

`scripts/Test-HostReport.ps1` 以合成报告验证 12 个场景，不访问真实配置、注册表或网络。`Build.ps1` 和 `Test-WindowsAcceptance.ps1` 已纳入此回归入口。

## README 与包

根 README 介绍项目作用、Windows 普通 / 管理员入口、设置与显式修复流程、快照还原、Mac CLI 及开发构建。删除了“新版 Mac 布局被拒绝”的过时描述，依据既有 `macos-host.json` 说明已验证的原生修复 / 还原与网络限制，没有运行 Mac 测试。

图片来源见 `docs/images/README.md`。`Build.ps1` 复制图片目录的 PNG，`Test-Package.ps1` 在解压后验证 README 图片引用，再运行夹具界面的修复与还原。开发资料链接使用仓库 URL，便携包无需附带全部开发文档。

Edge 的 `WebRtcLocalhostIpHandling` 需要重启且不适用于登录微软账号的配置文件，依据 [Microsoft 官方说明](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/webrtclocalhostiphandling)，检索日期 2026-10-12。

## 验证与发布

本轮结果记录在 `readme-publication.json`：PowerShell 7.6.5 与 7.6.6 各 9 项 suite 通过，包含 122 条核心断言与 12 个检查报告回归场景。两个解压包的三张图片、隔离修复 / 还原通过；两个运行时的真实配置只读检查通过，前后文件与策略保持不变，百度 / Google 四种连接基线均返回 HTTP 200。既有桌面交互证据保留，未重复该测试。

构建产物位于忽略的 `dist/`，不上传 Release。源码发布按 `.branch-records/readme-publication-1012/events.jsonl` 的预声明推送；事件中的 after 是意图，实际远端 SHA 在推送后通过 Git 核对。
