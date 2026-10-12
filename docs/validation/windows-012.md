# Windows 0.1.2 验收

2026-10-12，Windows 11 Pro N build 26300。本轮自动验收通过，整体状态仍为 partial。

PowerShell 7.6.5 与 7.6.6 各执行 8 项 suite：核心 118 条断言、review 7 场景、原生注册表 11 个往返、WPF 修复/还原、窗口故障、进度恢复、并发进度读取，以及两个解压包。所有测试通过。原生注册表只用随机 HKCU Software/ProxyVeil.Test-*，剩余键为 0；未修改真实 FlClash 或 Edge。

新增测试强制走 DWM Acrylic 不可用后的背景回退，核对背景值并生成 `ui-opaque.png`。已查看本轮设置与回退截图，控件及修复按钮可读；离屏渲染不能验证真实桌面磨砂、窗口移动与点击体验，也不能替代 Windows 10 实机。

0.1.2 Standard 与 Administrator ZIP 已离线重建，包测试在两个 PowerShell 版本分别通过。路径、大小和 SHA-256 见 [windows-012.json](windows-012.json) 与 [packages.json](packages.json)。包仅在本机 dist，未上传 Release；管理员包测试用隔离入口，不声称已通过真实 UAC。

可重现入口：

```powershell
pwsh -NoProfile -File scripts/Test-WindowsAcceptance.ps1 -PowerShellPaths <PowerShell7路径1>,<PowerShell7路径2>
```

此脚本覆盖自动 suites、重建包、包验证和报告，目录由仓库位置确定，测试使用夹具。命令中的路径列表需换成目标机安装的 PowerShell 7。单运行时也可执行，但报告只能证明该运行时。

未执行：Windows 10 实机/VM、真实桌面 Acrylic、实际 UAC、FlClash TUN 权限和网络。当前电脑无已确认可用的 Windows 10 VM/安装介质；本会话未得到该环境信息。真实配置修改须明确授权对应操作，不能以代码修复指令推断。下一步需目标 Windows 环境，按 README 的复测清单验收并追加无凭据结果。Mac 原生验收由用户执行 [macos-acceptance.md](macos-acceptance.md)。
