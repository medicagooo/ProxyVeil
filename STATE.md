# ProxyVeil execution state

## Objective and scope

用户授权创建 D:/proj/ProxyVeil，将 FlClash 隐私脚本扩为 Windows/PowerShell 7 应用；2026-10-13 追加 macOS + FlClash MVP。Windows 首版为 FlClash + Edge，支持 TUN/Proxy、普通权限/管理员入口、可选 DNS/WebRTC/代理内 IPv6、磨砂窗口、逐项进度、修复及还原。macOS MVP 提供显式 Python CLI，支持 FlClash DNS、TUN/Proxy、IPv6、快照与冲突安全还原；WebRTC 报告为跳过。保留国内直连、订阅与节点选择。

首版交付终点为本地源码及两个便携 ZIP。2026-10-10 用户追加授权 review、bug repair 和 push 到 git@github.com:medicagooo/ProxyVeil.git；修复版本 0.1.1 已推送。用户随后要求纠正提交邮箱为 medicago.19@outlook.com；仅本次身份重写允许以原远端 SHA 为 lease 替换 main。未授权自动修复当前电脑或创建 GitHub Release。配置测试使用 work/ 隔离夹具与模拟策略；原生注册表类型测试仅写随机临时键并清理，未修改 Edge 策略。不禁用物理网卡，不维护系统防火墙，不覆盖 Chrome/Firefox，不承诺所有应用 DNS 无泄露。

## Repository and authoritative records

- 仓库及唯一工作区：D:/proj/ProxyVeil；当前任务 macos-support-v1，提交在 main；review-repair-v1 与 initial-v1 保留 Windows 历史。
- 固定审查基线 b36d439f19c2cc0b7cbaa800d5cbe2f9c8f1a1e2；完整 Windows 报告 docs/review-0.1.1.md。Windows 身份更正已完成；本次 macOS 变更直接在 main 上提交，推送前仍查询 live Git，不由待提交文档自报。无部署或 Release。忽略 dist/ 与 work/；包哈希记录在 docs/validation/packages.json。
- 需求权威：docs/spec-v1.md；Windows 决策：docs/adr/0001-desktop-and-recovery.md；macOS 决策：docs/adr/0002-macos-flclash.md；边界与调用：docs/agents/domain.md；场景：docs/scenario.md。
- tracker：docs/agents/issue-tracker.md；首版任务 .scratch/v1/spec.md、map.md、issues/01..05；业务登记 BRANCHES.md 与 .branch-records/initial-v1/、review-repair-v1/。
- 工单于验收阶段补录；没有虚构实现前认领。全部 resolved 表示本地交付范围完成，不表示网络验收或 UAC 已测试。

## Verified phase and artifacts

首版流程与复盘保留于 docs/retro.md。Windows 版本已完成独立 Standards/Spec 审查、修复与离线验证。2026-10-13 完成 macOS MVP 的代码审查、隔离验证和当前 Mac 只读实测；补充记录见 `docs/validation/macos.json` 与 `docs/validation/macos-host.json`。

验收证据：

- docs/validation/engine.json：117 条断言，包含 PowerShell 解析、四种模式/权限组合、原规则保护、选择性修改、权限拒绝、异常回退、偏好合并、外部冲突、并发操作拒绝、部分还原续接、备份篡改拒绝及真实子进程 worker。
- docs/validation/review-regressions.json：7 个配置/还原场景；ui-failure.json：3 个实际窗口错误场景；registry.json：11 个原生类型快照往返，随机 HKCU Software/ProxyVeil.Test-* 临时键在 finally 清理。
- docs/validation/ui-idle/settings/completed.png 及同名 JSON：离屏 UI，当前 Windows 11 的原生 Acrylic 调用被接受；离屏图不验证真实背景模糊。
- docs/validation/ui-recovery.json 与 progress.json：一次读取故障恢复、真实 worker 追加时的并发共享读取。
- docs/validation/package-smoke.json：普通与管理员包各自解压后执行窗口修复/还原；管理员测试用隔离入口，未触发实际 UAC。
- dist/ProxyVeil-0.1.1-Standard.zip、dist/ProxyVeil-0.1.1-Administrator.zip；dist/manifest.json；不含运行时、订阅、快照或测试目录。VERSION 为构建与包测试唯一版本源。
- macos/proxyveil.py、scripts/Launch-macOS.sh、macos/README.md；macOS 不依赖第三方 Python 包，快照默认位于 `~/Library/Application Support/ProxyVeil`，隔离验证见 docs/validation/macos.json。
- docs/validation/macos-host.json：当前 Mac 为 macOS 27.0.1、FlClash 0.8.99；隔离回归通过，真实配置使用 config.yaml/SQLite 布局，inspect 安全拒绝，未执行 repair。
- docs/validation/windows-stage2.md、docs/validation/windows-stage2.json：Windows 第二阶段回归、UI、打包和 Windows 10/11 验收清单，状态 pending。
- README.md 说明启动、修复边界、还原及网络复测；docs/research/platforms.md 保存官方依据与检索日期；docs/review-v1.md 保存自审结论。

## Locked decisions and compatibility

PowerShell 7/WPF，源码与 ZIP 分发。Windows 启动器依次找 PATH、Program Files PowerShell 7、Codex 用户运行时；管理员版通过当前用户 UAC 启动。macOS 使用系统 Python 3 与 `scripts/Launch-macOS.sh`，不运行 sudo。当前 Windows 验收运行时 7.6.5；Windows 11 build 26300；macOS CLI 在本机 Apple Silicon 上通过隔离测试。最低运行时与其他 OS 版本未分别实机验证。

安装地址可自动探测或手填；配置需 shared_preferences.json 的 flutter.config 字符串、数字 currentProfileId、patchClashConfig.tun/networkProps。DNS/IPv6 修改需要受支持的块式 YAML；仅 WebRTC 不解析 YAML 或选择 DNS 组。FlClash 0.8.99 结构已核验，其他版本遇不兼容时拒绝修改。复杂 YAML/锚点/多文档的 DNS 修改需要手工处理。

当前 Mac 实测的 FlClash 0.8.99 使用 `config.yaml`、`database.sqlite` 与 `profiles/*.yaml`，不满足上述 shared_preferences 契约；该布局暂不写入，后续需单独设计适配与迁移测试。

TUN DNS 使用 Mihomo 加密解析、严格路由及 UDP/TCP 53 接管；普通 TUN 要求 FlClashHelperService 已运行。Proxy 开系统代理、关 TUN，并设置 Edge secure DoH 和固定 DoH IP 的组路由；其他应用 DNS 需另验。节点引导走独立直连加密 DNS，避免代理解析循环。清空自定义解析策略可能影响内网站点。

WebRTC 写 HKCU Edge 策略，组织 HKLM 冲突跳过；部分策略不支持微软账号配置文件，重启后查 edge://policy。IPv6 选项只关闭 FlClash IPv6 与 IPv6 解析。只勾 WebRTC 不停止或改写 FlClash 文件。

macOS 不写 Windows 注册表，也不宣称可通过普通用户 plist 修改 Edge WebRTC；WebRTC 选项返回 skipped，并提示使用配置描述文件或 MDM。macOS 快照使用 flock、原子替换和 before/after SHA-256；外部漂移时保留快照并拒绝还原。

快照位于 %LOCALAPPDATA%/ProxyVeil，先写 manifest 再修改，记录原始文件及策略类型/存在性。外部 YAML 或受管字段漂移停止覆盖，偏好无关字段合并保留；再次修复须先还原。快照可含凭据，禁止提交、输出或打包。恢复中断接受记录的 before/after，生产修改不经夹具路径。

## Remaining work

| 优先级 | 项目/状态 | 前置与阻塞 | 就绪与结果 | 验证 |
|---|---|---|---|---|
| 1 | 当前 FlClash config.yaml/SQLite 适配；后续，未执行 | 需要确认 config.yaml 与数据库的写入契约及安全回滚方案 | 当前入口已安全拒绝，未修改真实配置 | docs/validation/macos-host.json |
| 2 | Windows 第二阶段回归；待用户在 Windows 执行 | Windows 10/11、PowerShell 7、FlClash 与可用节点 | 清单已就绪，结果文件 pending | docs/validation/windows-stage2.md |
| 3 | 真实网络/UAC/TUN 权限验收；后续，未执行 | 一次性 Windows/macOS 用户或 VM、FlClash 与可用节点 | 可在兼容布局和目标环境就绪后执行 | README 复测清单；保存无凭据结果 |
| 4 | 新代理、其他浏览器；延期 | 新需求与适配规格 | 不启动；保持现有范围 | 新工单和 fixture |

当前范围没有未解决的实现阻塞或未决产品选择。真实连接、代理组节点可用性、组织策略和用户账户类型由目标机决定，不能从夹具推断。

## Next executable action

本次 Mac 实机只读测试已完成：隔离回归通过，真实 FlClash 因 config.yaml/SQLite 布局被安全拒绝，未修改配置。下一步由用户在 Windows 执行 [Windows 第二阶段清单](docs/validation/windows-stage2.md)，并把结果写入 `docs/validation/windows-stage2.json`。当前 MVP 的 macOS 真实 repair 仍需先完成该布局适配。

```powershell
Set-Location D:/proj/ProxyVeil
git status --short
if ($LASTEXITCODE -ne 0) { throw 'git status failed' }
git ls-remote git@github.com:medicagooo/ProxyVeil.git refs/heads/main
if ($LASTEXITCODE -ne 0) { throw 'remote query failed' }
Get-Content -LiteralPath docs/validation/engine.json,docs/validation/registry.json,docs/validation/package-smoke.json,docs/validation/packages.json,docs/validation/macos.json
```

重建使用 `pwsh -NoProfile -File D:/proj/ProxyVeil/scripts/Build.ps1`，成功后 `pwsh -NoProfile -File D:/proj/ProxyVeil/scripts/Test-Package.ps1`。这会写隔离测试、验证记录与本地包，不修改当前 FlClash/Edge。实际修复必须由用户点击修复按钮或明确授权对应机器；包路径和 SHA 每次构建重新核对。
