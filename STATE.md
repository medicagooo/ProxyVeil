# ProxyVeil execution state

## Objective and scope

Windows PowerShell 7/WPF 的 FlClash + Edge 隐私配置助手，普通权限与管理员入口，TUN/Proxy，可选 DNS/WebRTC/FlClash IPv6，显式修复和可恢复快照；保留国内直连、订阅与节点选择。macOS 使用独立 Python CLI，显式 inspect/repair/restore，WebRTC 与浏览器 DoH 不配置。

当前任务：2026-10-12 用户要求删除“收好你的网络出口”，加入随系统显示语言选择的中英文支持，README 默认英文并保留中文；确认方案后明确要求实施、review、bug repair、push main。登记 `.branch-records/windows-i18n-1012/`，任务起点为已验证远端发布的 `c61eea4c4a07a30a1f568b09cee38f60252d9744`，起始工作区干净。按推荐方案仅覆盖 Windows，不修改 / 复测 Mac，真实配置继续只读。有效需求为 `docs/i18n-plan.md`；实现边界为 `docs/validation/i18n-implementation.md`。主要实现已本地提交 5e183561b8326bed73f7e6c294f6e1abd8ba1634；完整验证、双轴 review 和随后发现的渲染问题修复已完成，最后提交包含修复、验证证据及推送声明。最终发布状态须用 live Git 核对，不能从该声明推断成功。

2026-10-12 用户要求实施本机开发方案、review、bug repair、push main，完成 Windows 验收；Mac 原生修复/还原已有历史证据。当前用户要求执行 Windows 测试，并明确无需再次测试 Mac；Windows 10 单独验收已取消。用户随后选择“只完成隔离测试及只读检查”，本轮范围已完成：两套运行时自动测试、实际显示窗口的控件/隔离修复还原和本机只读检查通过。真实 UAC 成功、实际修复后的网络泄露及 Acrylic 模糊效果未完整验收，完整实机状态仍为 partial；这些缺口保留记录，不继续执行或重复询问本机 Repair 授权。未授权部署或 GitHub Release。

## Repository and authoritative records

- 唯一工作区 D:/proj/ProxyVeil。本轮实现使用过 1012-local-development，已核实内容与 main 完全一致并按用户要求删除该本地分支；当前仅保留 main。实现登记 .branch-records/local-development-v1/，清理记录 .branch-records/branch-cleanup-1012/。原审查基线为当时远端 main 8f3e9e40d690e9a6d63779ff3a4c6d4e90287134；foundation f7bb594；原生适配初版 0eda71e。复审修复和验证记录已提交 4989bae38e77215c1f282ce1cd5cfe7a3cdd3755；其后仅有发布声明元数据。具体 HEAD、当前分支与脏状态必须用 live Git 核对。
- 0.1.2 代码、Windows 验收范围声明和 Mac 原生修复/恢复证据已在远端 main；此前本地 main 更新纳入 1e96ff59d294e677f67026bb688d54c07f3c6514。README 发布任务已正常推送并核对 c61eea4，本轮登记更新清除该任务的已解决 pending。当前 i18n 任务也已获明确 push main 授权。最终 HEAD、远端和工作区干净状态用 live Git 核对；不得仅为回填成功再提交或推送。
- 当前有效要求 docs/implementation-0.1.2.md；早期方案 docs/local-development-plan.md；原 Windows 规格 docs/spec-v1.md；架构 docs/adr/0001-desktop-and-recovery.md 与 0002-macos-flclash.md；调用/数据边界 docs/agents/domain.md；业务账本 BRANCHES.md。
- 历史身份更正与 Windows/macOS 首版保留于旧记录和 docs/review-0.1.1.md。历史 pending 不得直接重试，需核对远端结果。无 Release 或部署。
- 前次 Windows 测试基线为本地 main 23c56ae7def65502c37fec19e8eb6f7416320839，初始工作区干净；登记 .branch-records/windows-tests-1012/。该次测试和证据仅在本地 main 提交；本次用户已要求推送。前次本地同步已验证并在此前登记更新时清除其 pending。

## Verified work and evidence

- Windows 文案集中到 src/Locales/en.psd1 与 zh-CN.psd1；Localization 读取当前用户显示语言，zh 变体使用简体中文，其余使用英文。Launch 的同用户 UAC、UI 请求和 worker 参数传递同一 Language；worker 在请求读取前设定语言，损坏请求错误也可翻译。Core 的 Invoke-PvOperation 包装层按请求临时切换并在 finally 恢复，状态 / 配置 / 快照契约保留。标题删除；双语 README 与六张隔离截图已更新。
- 两套 PowerShell 7.6.5 / 7.6.6 各 10 项自动 suite 全通过：核心 125 断言、双语 253 检查、UI / 故障恢复 / 进度、原生临时键、宿主报告门禁和两个权限包。覆盖 TUN / Proxy 双语修复、跨语言还原、失败回退、UI / worker 及损坏请求。缺少 PowerShell 7 时的只读提示在 Windows PowerShell 5.1 读取同一资源；中文资源初次编码不兼容，改为 UTF-8 BOM 后英文 / 中文读回通过。证据 docs/validation/windows-i18n.json 与 docs/review-i18n.md。
- 桌面截图复核发现硬件渲染只显示 DWM 背景但 Automation 仍通过；延迟 2.5 秒仍失败，软件渲染恢复内容。当前窗口 HwndTarget 改为 SoftwareOnly，DWM Acrylic 保留，不改进程级设置或注册表。截图门禁在实际旧路径先失败；补充 review 发现纯深蓝检测误报，增加互斥阈值及 11 项 bitmap 回归后修复。双轴补充审查无未解决问题。修复后两运行时重新通过 UI / 故障 / 双语 / 桌面 / 包测试，中英文实际截图控件可读。此结果不证明模糊强度，也未测性能。

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
| 1 | Windows i18n、默认英文 README、review 和发布 | 实现、完整验证、渲染修复与复审完成；已有 push main 授权；发布须核对 live Git | 提交已登记的任务修复 / 证据，正常推送 origin/main，再核对 SHA；若已一致则完成，不重复推送 |
| 2 | Windows 实机 UAC、Repair/Restore 后泄露与完整 Acrylic 视觉验收；未覆盖，不在本轮继续执行 | 用户明确选择仅隔离测试及只读检查；docs/validation/windows-live-plan.md 仅保留备选计划 | 完整实机状态保持 partial，不记为通过；不再索取本轮真实修复授权 |
| 3 | Mac 复测；按用户要求不再执行 | 保留既有 Mac 验收证据和历史网络限制 | 无需重复测试，不修改 macos/ 与 Mac 报告 |
| 4 | 其他代理/浏览器；延期 | 新需求 | 不在本轮启动 |

## Next executable action

继续会话时先执行 `git -C D:/proj/ProxyVeil status --short --branch`，读取当前 i18n 任务 state/events、docs/validation/windows-i18n.json 与 docs/review-i18n.md，再执行 `git ls-remote origin refs/heads/main` 核对发布状态。完整验证脚本 `.git/codex-operation-records/validate-windows-i18n.ps1` 及修复后针对性复测 `.git/codex-operation-records/verify-render-fix.ps1` 均已完成；无需重复通过项。若远端与本地 HEAD 一致，不重复推送，不为回填成功再提交。若尚未发布，先核对 pending 推送声明、前置提交与远端 c61eea4 起点，再执行 `git push origin refs/heads/main:refs/heads/main` 并核对远端 SHA；远端发生其他变化时重新分析，不强推。不执行真实 Repair/Restore、UAC 提权或自动重启 FlClash/Edge；Mac 与 Windows 10 都不再测试。

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
