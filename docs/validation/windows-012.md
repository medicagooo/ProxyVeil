# Windows 0.1.2 验收

2026-10-12，Windows 11 Pro N build 26300。本轮自动验收通过，整体状态仍为 partial。用户随后明确取消 Windows 10 单独验收，以 Windows 11 验收为准；不再需要准备 Windows 10 VM 或 ISO。

PowerShell 7.6.5 与 7.6.6 各执行 8 项 suite：核心 118 条断言、review 7 场景、原生注册表 11 个往返、WPF 修复/还原、窗口故障、进度恢复、并发进度读取，以及两个解压包。所有测试通过。原生注册表只用随机 HKCU Software/ProxyVeil.Test-*，剩余键为 0；未修改真实 FlClash 或 Edge。

新增测试强制走 DWM Acrylic 不可用后的背景回退，核对背景值并生成 `ui-opaque.png`。已查看本轮设置与回退截图，控件及修复按钮可读；离屏渲染不能验证真实桌面磨砂、窗口移动与点击体验，也不能替代 Windows 10 实机。

0.1.2 Standard 与 Administrator ZIP 已离线重建，包测试在两个 PowerShell 版本分别通过。路径、大小和 SHA-256 见 [windows-012.json](windows-012.json) 与 [packages.json](packages.json)。包仅在本机 dist，未上传 Release；管理员包测试用隔离入口，不声称已通过真实 UAC。

可重现入口：

```powershell
pwsh -NoProfile -File scripts/Test-WindowsAcceptance.ps1 -PowerShellPaths <PowerShell7路径1>,<PowerShell7路径2>
```

此脚本覆盖自动 suites、重建包、包验证和报告，目录由仓库位置确定，测试使用夹具。命令中的路径列表需换成目标机安装的 PowerShell 7。单运行时也可执行，但报告只能证明该运行时。

2026-10-12 本地 main 更新后的复测，基线 23c56ae7def65502c37fec19e8eb6f7416320839：上述两套运行时的 8 项 suite 全部重新通过，ZIP 重建并分别通过解压后修复/还原。原生临时注册表键剩余 0。本轮没有执行 Mac 测试，保留既有 Mac 证据；用户明确无需再次复测 Mac。

新增 `scripts/Test-Desktop.ps1` 在两套运行时实际显示原生窗口，使用 UI Automation 验证设置展开、DNS 复选框、窗口移动、最小化/恢复、修复、还原和关闭。修复/还原仍只使用 work/ 夹具和模拟策略。DWM 属性 38 读回为 3，配置的背景类型为 Acrylic；实际模糊效果未完整确认。首个 Idle 截图捕获被遮挡检查拒绝；设置、完成及还原截图已保存并查看，控件文字可读。最新共享截图来自 7.6.6，见 [windows-desktop.json](windows-desktop.json) 与 [windows-desktop-settings.png](windows-desktop-settings.png)。各运行时的独立控件测试报告保存在 windows-012/ 下。

新增 `scripts/Test-WindowsHost.ps1` 只读识别真实 FlClash 0.8.99、当前 profile、TUN 模式、运行中的 FlClashHelperService 和本地 7890 端口。TUN/Proxy 计划只在内存生成；跨用户 SID 和未提权 Administrator 请求均被拒绝。百度与 Google 在默认连接及显式本地代理连接均返回 HTTP 200；FlClash 原始文件与 Edge 策略在探测前后相同，无活动快照。见 [windows-host.json](windows-host.json)。这是当前网络基线，不证明修复后 DNS/WebRTC/IPv6 无泄露。

新增入口：

```powershell
pwsh -NoProfile -STA -File scripts/Test-Desktop.ps1
pwsh -NoProfile -File scripts/Test-WindowsHost.ps1
```

尚未执行真实 UAC 成功路径、真实 Repair/Restore 后的 Edge 策略采用和泄露复测；Acrylic 模糊效果仍待交互观察。实际写入的文件、策略、影响与恢复步骤见 [windows-live-plan.md](windows-live-plan.md)，需用户明确 Repair 授权。Windows 10 独立验收已取消。

桌面测试首次失败原因：窗口句柄有效、可见且输入桌面为 Default，SetForegroundWindow 返回 false。测试改为临时抬高夹具窗口但不取得键盘焦点；高 DPI 坐标改为物理像素，并先检查窗口遮挡再截图。官方行为依据：[SetForegroundWindow](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setforegroundwindow)、[SetWindowPos](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowpos)、[GetWindowRect](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getwindowrect)、[SetThreadDpiAwarenessContext](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setthreaddpiawarenesscontext)，检索日期 2026-10-12。焦点限制是根据本机探测和文档的推断，不计为应用缺陷。
