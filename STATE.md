# ProxyVeil execution state

## Objective and scope

Windows PowerShell 7/WPF 的 FlClash + Edge 隐私配置助手，普通权限与管理员入口，TUN/Proxy，可选 DNS/WebRTC/FlClash IPv6，显式修复和可恢复快照；保留国内直连、订阅与节点选择。macOS 使用独立 Python CLI，显式 inspect/repair/restore，WebRTC 与浏览器 DoH 不配置。

2026-10-12 用户要求实施本机开发方案、review、bug repair、push main，完成 Windows 验收；用户随后在 Mac 做原生验收。本轮实现、审查修复和当前 Windows 自动验收已完成。Windows 10、真实桌面、UAC/TUN/网络仍缺环境或明确目标操作授权，整体 Windows 验收为 partial。未授权自动修复本机真实配置、部署或 GitHub Release。

## Repository and authoritative records

- 唯一工作区 D:/proj/ProxyVeil。本轮使用 1012-local-development，登记 .branch-records/local-development-v1/。原审查基线为当时远端 main 8f3e9e40d690e9a6d63779ff3a4c6d4e90287134；foundation f7bb594；原生适配初版 0eda71e。复审修复和验证记录将随当前任务提交。具体 HEAD、当前分支与脏状态必须用 live Git 核对。
- 本交接在提交前更新；此时本轮修复、文档和验收记录待提交，main 集成/push 待执行。计划快进 main，再正常 push 到 git@github.com:medicagooo/ProxyVeil.git refs/heads/main；最终是否发布和 SHA 由 live Git/远端决定，operation.after 仅为意图。不得仅为回填成功再提交或推送。
- 当前有效要求 docs/implementation-0.1.2.md；早期方案 docs/local-development-plan.md；原 Windows 规格 docs/spec-v1.md；架构 docs/adr/0001-desktop-and-recovery.md 与 0002-macos-flclash.md；调用/数据边界 docs/agents/domain.md；业务账本 BRANCHES.md。
- 历史身份更正与 Windows/macOS 首版保留于旧记录和 docs/review-0.1.1.md。历史 pending 不得直接重试，需核对远端结果。无 Release 或部署。

## Verified work and evidence

- 0.1.2 新增原生偏好后端：应用 bundle ID 定域，读取 flutter.config 字符串，SQLite schema 10 只读核对 profiles.id，修改原始 profile 与受管偏好。config.yaml、数据库、订阅及节点选择不写入。实际键/域/schema 在运行时核对，未知结构拒绝。
- 原生偏好每次调用新 CoreFoundation 子进程，避免进程内缓存；值通过 UTF-8 管道，不进入 argv 或诊断。读取不同步；写同步后由独立进程读回。repair/restore 要求退出 FlClash。真实 CoreFoundation ABI/同步与应用重启待 Mac 验收。
- schema 2 先保存 profile 字节和偏好 before/after，再写入；还原核对 bundle 域、配置目录、profile ID、备份哈希和受管漂移，合并保留无关偏好；部分成功保留快照供续接。旧 JSON 布局与 schema 1 还原保留，旧快照仍采用全文件冲突检查。
- portable 16 场景与 preferences 16 场景通过；后者包含生成的 XML/binary plist、只读 SQLite、部分失败、偏好合并、类型漂移、损坏快照和子进程传输。docs/validation/macos-portable.json 与 macos-preferences.json；Windows 用 msvcrt，Mac 用 flock。fixture 成功不证明原生 Mac 行为。
- 双轴 review 与复查完成，发现的 YAML 引号键、bool/int 比较、未应用浏览器策略返回和偏好读缓存问题已修复；docs/review-0.1.2.md。IPv6 DNS、无缩进规则、组名注释等回归也已通过。
- Windows 11 Pro N build 26300，PowerShell 7.6.5 和 7.6.6 各 8 项 suite 通过：核心 118 断言、review 7 场景、registry 11 往返、UI/故障/恢复、进度和两个解压包。docs/validation/windows-012.json 与 windows-012/ 各运行时记录；随机 HKCU Software/ProxyVeil.Test-* 已清理，剩余 0。
- 强制 DWM 背景回退渲染及背景核对通过；已查看 idle 与 fallback 截图，控件可读。docs/validation/ui-opaque.png/json。它不能验证真实桌面 Acrylic 或 Windows 10。
- dist/ProxyVeil-0.1.2-Standard.zip 与 Administrator.zip 本机离线重建，两个运行时包测试均通过。大小与 SHA-256 在 docs/validation/packages.json、windows-012.json；dist 忽略且没有上传。两个包不含 Mac CLI、运行时、订阅、状态或备份；Mac 从仓库使用 macos/ 与 scripts/Launch-macOS.sh。

## Locked constraints

Windows Native/PowerShell 7，离线构建。已有 Python 3.12.14 用于本机测试，无新依赖。生产 Mac CLI 拒绝非 macOS，夹具后端没有生产 CLI 参数。配置与注册表测试严格隔离；真实 FlClash/Edge 只读检查，修复必须由用户点击或明确调用 Repair。当前执行用户非管理员。

备份含凭据，Windows 状态默认 %LOCALAPPDATA%/ProxyVeil，Mac 默认 ~/Library/Application Support/ProxyVeil；禁止提交、输出、打包原始订阅或备份。Native helper 错误不包含原值。SQLite 不迁移不写入；待验收的实际版本不得从源码推断。

普通版不主动提权，管理员版必须当前用户 UAC，不接管 ACL/机器策略。Windows Edge 需重启后核验 edge://policy。TUN 与系统网络由 FlClash 权限和节点决定；不修改物理网卡、防火墙，不承诺所有应用无 DNS 泄漏。Mac Proxy 仅配置 FlClash resolver/路由。

## Remaining work

| 优先级 | 工作/状态 | 前置与阻塞 | 预期与验证 |
|---|---|---|---|
| 1 | 本轮 main 集成及发布；本交接写入时待执行 | 提交修复/记录，登记 merge/push，确认远端 main 未变化 | 正常快进与 push；ls-remote SHA 与本机 main 相同，最终报告 exact SHA |
| 2 | Mac 原生验收；交给用户，尚未执行 | Mac、FlClash、Python，干净工作区更新 main；实际偏好域/类型/schema 尚待核实 | 先隔离测试和只读 inspect，再明确 repair/restore，重启及网络验证；docs/validation/macos-acceptance.md |
| 3 | Windows 10 与桌面；未执行 | 当前未确认可用 VM/ISO，已向用户询问但未得到环境信息 | 启动/回退/操作与 suites 实机通过，追加 OS/运行时证据；windows-012.md |
| 4 | Windows 真实 UAC/TUN/网络；未执行 | 测试用户、FlClash/节点、明确对应真实配置操作授权 | 实际启动提权、配置采用、国内/代理/DNS/WebRTC/IPv6复测与恢复，无凭据摘要 |
| 5 | 其他代理/浏览器；延期 | 新需求 | 不在本轮启动 |

## Next executable action

先在 Windows 完成已声明的正常 main 推送并核对 SHA。后续 Mac 在自己的 ProxyVeil 仓库按 docs/validation/macos-acceptance.md 更新 main，执行三个隔离测试，再退出 FlClash做只读 inspect。不要把“awaiting native acceptance”改成通过，直到保存实际验收证据。

本机复现：

```powershell
Set-Location D:/proj/ProxyVeil
git status --short
if ($LASTEXITCODE -ne 0) { throw 'status failed' }
& 'C:/Users/medic/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -X utf8 scripts/Test-macOS-Portable.py
if ($LASTEXITCODE -ne 0) { throw 'portable failed' }
& 'C:/Users/medic/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -X utf8 scripts/Test-macOS-Preferences.py
if ($LASTEXITCODE -ne 0) { throw 'preferences failed' }
pwsh -NoProfile -File scripts/Validate-Registry.ps1
if ($LASTEXITCODE -ne 0) { throw 'registry failed' }
```

完整 Windows 自动验收入口 scripts/Test-WindowsAcceptance.ps1 -PowerShellPaths <已安装PowerShell7路径列表>，会写本地夹具、报告和 ZIP，不修改真实配置。仅在源码改变或发现未解决问题时重新执行。
