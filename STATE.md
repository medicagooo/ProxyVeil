# ProxyVeil execution state

## Objective and scope

Windows PowerShell 7/WPF 的 FlClash + Edge 隐私配置助手，普通权限与管理员入口，TUN/Proxy，可选 DNS/WebRTC/FlClash IPv6，显式修复和可恢复快照；保留国内直连、订阅与节点选择。macOS 使用独立 Python CLI，显式 inspect/repair/restore，WebRTC 与浏览器 DoH 不配置。

当前任务：2026-10-12 用户要求修复发现的错误，编写介绍用途、入口、用法并附图的 README，完成后 push main。登记 `.branch-records/readme-publication-1012/`，开始时 HEAD 为 `055302e840ab08085a9b9d62623bfd36a83536b7`，工作区干净。真实配置仍只读，不执行 Mac 复测。README、图片打包和 Windows 只读检查误报已修正；验证与推送完成状态须结合 `readme-publication.json`、任务事件及 live Git 核对，不从预声明推断成功。

2026-10-12 用户要求实施本机开发方案、review、bug repair、push main，完成 Windows 验收；Mac 原生修复/还原已有历史证据。当前用户要求执行 Windows 测试，并明确无需再次测试 Mac；Windows 10 单独验收已取消。用户随后选择“只完成隔离测试及只读检查”，本轮范围已完成：两套运行时自动测试、实际显示窗口的控件/隔离修复还原和本机只读检查通过。真实 UAC 成功、实际修复后的网络泄露及 Acrylic 模糊效果未完整验收，完整实机状态仍为 partial；这些缺口保留记录，不继续执行或重复询问本机 Repair 授权。未授权部署或 GitHub Release。

## Repository and authoritative records

- 唯一工作区 D:/proj/ProxyVeil。本轮实现使用过 1012-local-development，已核实内容与 main 完全一致并按用户要求删除该本地分支；当前仅保留 main。实现登记 .branch-records/local-development-v1/，清理记录 .branch-records/branch-cleanup-1012/。原审查基线为当时远端 main 8f3e9e40d690e9a6d63779ff3a4c6d4e90287134；foundation f7bb594；原生适配初版 0eda71e。复审修复和验证记录已提交 4989bae38e77215c1f282ce1cd5cfe7a3cdd3755；其后仅有发布声明元数据。具体 HEAD、当前分支与脏状态必须用 live Git 核对。
- 0.1.2 代码、Windows 验收范围声明和 Mac 原生修复/恢复证据已在远端 main；前次本地 main 更新纳入远端 1e96ff59d294e677f67026bb688d54c07f3c6514，并保留本地清理提交 4d133554dbd4b4ec006131c93a5eb509ef82f7d1。本地同步登记 .branch-records/main-update-1012/；该次仅更新本地。当前 README 任务已获明确 push main 授权，将连同已完成的本地 Windows 测试提交正常推送。最终 HEAD、远端和工作区干净状态用 live Git 核对。不得仅为回填成功再提交或推送。
- 当前有效要求 docs/implementation-0.1.2.md；早期方案 docs/local-development-plan.md；原 Windows 规格 docs/spec-v1.md；架构 docs/adr/0001-desktop-and-recovery.md 与 0002-macos-flclash.md；调用/数据边界 docs/agents/domain.md；业务账本 BRANCHES.md。
- 历史身份更正与 Windows/macOS 首版保留于旧记录和 docs/review-0.1.1.md。历史 pending 不得直接重试，需核对远端结果。无 Release 或部署。
- 前次 Windows 测试基线为本地 main 23c56ae7def65502c37fec19e8eb6f7416320839，初始工作区干净；登记 .branch-records/windows-tests-1012/。该次测试和证据仅在本地 main 提交；本次用户已要求推送。前次本地同步已验证并在此前登记更新时清除其 pending。

## Verified work and evidence

- README 任务修复了 `Test-WindowsHost.ps1` 在 Inspect 成功后遇到后续异常仍可 PASS 的问题，以及文件 / 策略变化未计入失败的缺口。`tests/WindowsHost.Assertions.ps1::Assert-PvWindowsHostReport` 是最终报告判断，`scripts/Test-HostReport.ps1` 覆盖 12 个合成报告场景；网络失败单独保留为基线结果。两个运行时各 9 项 suite 通过，本轮核心实际输出为 122 断言。原始错误复现与任务验证见 docs/validation/readme-publication.md/json。
- README 已介绍用途、Windows 普通 / 管理员入口、配置与还原、Mac CLI 和开发构建，修正新版 Mac 布局被拒绝的旧描述。docs/images/ 的三张图片来自隔离夹具；Build 仅打包 PNG，Test-Package 核对引用并验证隔离修复 / 还原。两个 ZIP 本地重建，不上传 Release。
- 本次两个运行时的宿主只读检查也已通过，文件哈希与 Edge 策略前后一致，TUN / Proxy 内存计划和身份保护通过；每次百度 / Google 的默认与显式本地代理 HTTPS 都返回 200。各运行时 windows-host.json 已保存；不作为修复后的泄露测试结果。

- 0.1.2 新增原生偏好后端：应用 bundle ID 定域，读取 flutter.config 字符串，SQLite schema 10 只读核对 profiles.id，修改原始 profile 与受管偏好。config.yaml、数据库、订阅及节点选择不写入。实际键/域/schema 在运行时核对，未知结构拒绝。
- 原生偏好每次调用新 CoreFoundation 子进程，避免进程内缓存；值通过 UTF-8 管道，不进入 argv 或诊断。读取不同步；写同步后由独立进程读回。repair/restore 要求退出 FlClash；Mac 验收记录确认真实写入、读回、恢复和应用重启通过。
- schema 2 先保存 profile 字节和偏好 before/after，再写入；还原核对 bundle 域、配置目录、profile ID、备份哈希和受管漂移，合并保留无关偏好；部分成功保留快照供续接。旧 JSON 布局与 schema 1 还原保留，旧快照仍采用全文件冲突检查。
- portable 16 场景与 preferences 16 场景通过；后者包含生成的 XML/binary plist、只读 SQLite、部分失败、偏好合并、类型漂移、损坏快照和子进程传输。docs/validation/macos-portable.json 与 macos-preferences.json；Windows 用 msvcrt，Mac 用 flock。fixture 成功不证明原生 Mac 行为。
- 当前 Mac 原生验收已完成：FlClash 0.8.99 的 bundle 域为 `com.follow.clash`，`flutter.config` 为字符串，SQLite schema 为 10，当前 profile 与索引一致；TUN + DNS/IPv6 repair、应用重启、restore 均通过，最终配置已恢复。TUN 初次探测中百度与 Google 均超时；恢复后基线与 Proxy 模式中百度返回 HTTP 200，Google 仍超时，DNS/IPv6 未由网络结果确认。证据见 docs/validation/macos-host.json。
- 双轴 review 与复查完成，发现的 YAML 引号键、bool/int 比较、未应用浏览器策略返回和偏好读缓存问题已修复；docs/review-0.1.2.md。IPv6 DNS、无缩进规则、组名注释等回归也已通过。
- Windows 11 Pro N build 26300，PowerShell 7.6.5 和 7.6.6 各 8 项 suite 通过：核心 118 断言、review 7 场景、registry 11 往返、UI/故障/恢复、进度和两个解压包。docs/validation/windows-012.json 与 windows-012/ 各运行时记录；随机 HKCU Software/ProxyVeil.Test-* 已清理，剩余 0。
- 更新本地 main 后重新执行上述全部 Windows 自动测试并重建包，两个运行时均通过。新增 scripts/Test-Desktop.ps1 在两个运行时实际显示 WPF 窗口，UI Automation 验证设置、DNS 勾选、移动、最小化、隔离 worker 修复/还原与关闭；DWM backdrop=3。首个 Idle 捕获因窗口遮挡没有保存；设置、配置完成和还原截图已查看，控件文字可读。截图与属性不足以证明模糊强度，保留该缺口。证据 docs/validation/windows-desktop.json 和各运行时 windows-desktop.json。
- scripts/Test-WindowsHost.ps1 已只读识别 FlClash 0.8.99、当前 profile、TUN 模式和正在运行的 FlClashHelperService；TUN/Proxy 两种真实配置计划只在内存生成，跨用户 SID 与未提权 Administrator 请求正确拒绝。百度/Google 在默认连接和显式 127.0.0.1:7890 代理均返回 HTTP 200。前后 FlClash 文件哈希与 Edge 策略相同，无活动快照。证据 docs/validation/windows-host.json；连通性基线不证明修复后 DNS/WebRTC/IPv6 无泄露。
- 强制 DWM 背景回退渲染及背景核对通过；已查看 idle 与 fallback 截图，控件可读。docs/validation/ui-opaque.png/json。它不能验证真实桌面 Acrylic 或 Windows 10。
- dist/ProxyVeil-0.1.2-Standard.zip 与 Administrator.zip 本机离线重建，两个运行时包测试均通过。大小与 SHA-256 在 docs/validation/packages.json、windows-012.json；dist 忽略且没有上传。两个包不含 Mac CLI、运行时、订阅、状态或备份；Mac 从仓库使用 macos/ 与 scripts/Launch-macOS.sh。

## Locked constraints

Windows Native/PowerShell 7，离线构建。已有 Python 3.12.14 用于本机测试，无新依赖。生产 Mac CLI 拒绝非 macOS，夹具后端没有生产 CLI 参数。配置与注册表测试严格隔离；真实 FlClash/Edge 只读检查，修复必须由用户点击或明确调用 Repair。当前执行用户非管理员。

备份含凭据，Windows 状态默认 %LOCALAPPDATA%/ProxyVeil，Mac 默认 ~/Library/Application Support/ProxyVeil；禁止提交、输出、打包原始订阅或备份。Native helper 错误不包含原值。SQLite 不迁移不写入；待验收的实际版本不得从源码推断。

普通版不主动提权，管理员版必须当前用户 UAC，不接管 ACL/机器策略。Windows Edge 需重启后核验 edge://policy。TUN 与系统网络由 FlClash 权限和节点决定；不修改物理网卡、防火墙，不承诺所有应用无 DNS 泄漏。Mac Proxy 仅配置 FlClash resolver/路由。

## Remaining work

| 优先级 | 工作/状态 | 前置与阻塞 | 预期与验证 |
|---|---|---|---|
| 1 | README 与验证修复；两个运行时回归、包及只读宿主检查通过，当前待发布 | 当前用户明确要求 push main；真实配置只读、Mac 不复测 | 登记推送、提交并正常推送 origin/main，再核对 SHA |
| 2 | Windows 实机 UAC、Repair/Restore 后泄露与完整 Acrylic 视觉验收；未覆盖，不在本轮继续执行 | 用户明确选择仅隔离测试及只读检查；docs/validation/windows-live-plan.md 仅保留备选计划 | 完整实机状态保持 partial，不记为通过；不再索取本轮真实修复授权 |
| 3 | Mac 复测；按用户要求不再执行 | 保留既有 Mac 验收证据和历史网络限制 | 无需重复测试，不修改 macos/ 与 Mac 报告 |
| 4 | 其他代理/浏览器；延期 | 新需求 | 不在本轮启动 |

## Next executable action

继续会话时先执行 `git -C D:/proj/ProxyVeil status --short --branch`，读取 `docs/validation/readme-publication.json` 与当前任务事件，并用 `git ls-remote origin refs/heads/main` 核对发布状态。若已与本地 HEAD 一致，不重复推送，不为回填成功再提交。若尚未发布且验证通过，先按 Git 策略登记精确推送操作、提交登记与任务内容，再执行 `git push origin refs/heads/main:refs/heads/main` 并核对远端 SHA。不执行真实 Repair/Restore、UAC 提权或自动重启 FlClash/Edge；Mac 与 Windows 10 都不再测试。

本机复现：

```powershell
Set-Location D:/proj/ProxyVeil
git status --short
if ($LASTEXITCODE -ne 0) { throw 'status failed' }
pwsh -NoProfile -STA -File scripts/Test-Desktop.ps1
if ($LASTEXITCODE -ne 0) { throw 'desktop failed' }
pwsh -NoProfile -File scripts/Test-WindowsHost.ps1
if ($LASTEXITCODE -ne 0) { throw 'read-only host checks failed' }
pwsh -NoProfile -File scripts/Validate-Registry.ps1
if ($LASTEXITCODE -ne 0) { throw 'registry failed' }
```

完整 Windows 自动验收入口 scripts/Test-WindowsAcceptance.ps1 -PowerShellPaths <已安装PowerShell7路径列表>，会写本地夹具、报告和 ZIP，不修改真实配置。新增桌面测试和只读宿主测试需分别调用上述命令。源码未变且已有当前证据时不重复执行。
