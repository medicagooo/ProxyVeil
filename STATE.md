# ProxyVeil execution state

## Objective and scope

用户授权创建 D:/proj/ProxyVeil，将 FlClash 隐私脚本扩为 Windows/PowerShell 7 应用。首版为 FlClash + Edge，支持 TUN/Proxy、普通权限/管理员入口、可选 DNS/WebRTC/代理内 IPv6、磨砂窗口、逐项进度、修复及还原。保留国内直连、订阅与节点选择。

交付终点是本地可运行源码及两个便携 ZIP。未授权推送、远程发布或自动对当前电脑执行修复。所有变更性测试用 work/ 隔离夹具与模拟策略；真实 FlClash 只读识别。不禁用物理网卡，不维护系统防火墙，不覆盖 Chrome/Firefox，不承诺所有应用 DNS 无泄露。

## Repository and authoritative records

- 仓库及唯一工作区：D:/proj/ProxyVeil；任务 initial-v1；分支 1010-initial-v1，用于首版实现。
- 交付提交引用：refs/heads/1010-initial-v1；精确 SHA 用 `git -C D:/proj/ProxyVeil rev-parse refs/heads/1010-initial-v1` 获取。此记录写入首个任务提交；写入时源码与记录待提交，随后由最终 Git 状态检查确认。后续会话须查询 live HEAD/dirty，不沿用旧结论。
- 无远程发布、无 main 集成、无部署。忽略 dist/ 与 work/；包哈希记录在 docs/validation/packages.json。
- 需求权威：docs/spec-v1.md；决策：docs/adr/0001-desktop-and-recovery.md；边界与调用：docs/agents/domain.md；场景：docs/scenario.md。
- tracker：docs/agents/issue-tracker.md；任务 .scratch/v1/spec.md、map.md、issues/01..05；业务登记 BRANCHES.md 与 .branch-records/initial-v1/。
- 工单于验收阶段补录；没有虚构实现前认领。全部 resolved 表示本地交付范围完成，不表示网络验收或 UAC 已测试。

## Verified phase and artifacts

第 6 阶段本地验收与交付；规格、设计、实现、自审、隔离验证与离线包完成；第 8 阶段复盘见 docs/retro.md。第 7 阶段发布不在范围。

验收证据：

- docs/validation/engine.json：114 条断言，包含 PowerShell 解析、四种模式/权限组合、原规则保护、选择性修改、权限拒绝、异常回退、偏好合并、外部冲突、并发操作拒绝、部分还原续接、备份篡改拒绝及真实子进程 worker。
- docs/validation/ui-idle/settings/completed.png 及同名 JSON：离屏 UI，当前 Windows 11 的原生 Acrylic 调用被接受；离屏图不验证真实背景模糊。
- docs/validation/ui-recovery.json 与 progress.json：一次读取故障恢复、真实 worker 追加时的并发共享读取。
- docs/validation/package-smoke.json：普通与管理员包各自解压后执行窗口修复/还原；管理员测试用隔离入口，未触发实际 UAC。
- dist/ProxyVeil-0.1.0-Standard.zip、dist/ProxyVeil-0.1.0-Administrator.zip；dist/manifest.json；不含运行时、订阅、快照或测试目录。
- README.md 说明启动、修复边界、还原及网络复测；docs/research/platforms.md 保存官方依据与检索日期；docs/review-v1.md 保存自审结论。

## Locked decisions and compatibility

PowerShell 7/WPF，源码与 ZIP 分发。启动器依次找 PATH、Program Files PowerShell 7、Codex 用户运行时；管理员版通过当前用户 UAC 启动。当前验收运行时 7.6.5；Windows 11 build 26300。最低运行时与其他 OS 版本未分别实机验证。

安装地址可自动探测或手填；配置需 shared_preferences.json 的 flutter.config 字符串、数字 currentProfileId、patchClashConfig.tun/networkProps 与块式 YAML。FlClash 0.8.99 结构已核验，其他版本遇不兼容时拒绝修改。复杂 YAML/锚点/多文档需要手工处理。

TUN DNS 使用 Mihomo 加密解析、严格路由及 UDP/TCP 53 接管；普通 TUN 要求 FlClashHelperService 已运行。Proxy 开系统代理、关 TUN，并设置 Edge secure DoH 和固定 DoH IP 的组路由；其他应用 DNS 需另验。节点引导走独立直连加密 DNS，避免代理解析循环。清空自定义解析策略可能影响内网站点。

WebRTC 写 HKCU Edge 策略，组织 HKLM 冲突跳过；部分策略不支持微软账号配置文件，重启后查 edge://policy。IPv6 选项只关闭 FlClash IPv6 与 IPv6 解析。只勾 WebRTC 不停止或改写 FlClash 文件。

快照位于 %LOCALAPPDATA%/ProxyVeil，先写 manifest 再修改，记录原始文件及策略类型/存在性。外部 YAML 或受管字段漂移停止覆盖，偏好无关字段合并保留；再次修复须先还原。快照可含凭据，禁止提交、输出或打包。恢复中断接受记录的 before/after，生产修改不经夹具路径。

## Remaining work

| 优先级 | 项目/状态 | 前置与阻塞 | 就绪与结果 | 验证 |
|---|---|---|---|---|
| 1 | 真实网络/UAC 验收；后续，未执行 | 一次性 Windows 用户/VM、FlClash 与可用节点；当前机器修改不在本次范围 | 可执行；核验本机策略生效、DNS 与 WebRTC 行为、回退 | README 复测清单；保存无凭据结果 |
| 2 | Windows 10 / 其他 PS7 运行时；后续 | 对应测试环境 | 待环境；验证回退 UI 与兼容性 | Build.ps1 + Test-Package.ps1，再实际窗口检查 |
| 3 | 新代理、其他浏览器；延期 | 新需求与适配规格 | 不启动；保持现有范围 | 新工单和 fixture |

当前范围没有未解决的实现阻塞或未决产品选择。真实连接、代理组节点可用性、组织策略和用户账户类型由目标机决定，不能从夹具推断。

## Next executable action

接续时先核验交付引用与工作区，再按最新授权选择任务。只读入口：

```powershell
Set-Location D:/proj/ProxyVeil
git status --short
if ($LASTEXITCODE -ne 0) { throw 'git status failed' }
git rev-parse refs/heads/1010-initial-v1
if ($LASTEXITCODE -ne 0) { throw 'delivery ref missing' }
Get-Content -LiteralPath docs/validation/engine.json,docs/validation/package-smoke.json,docs/validation/packages.json
```

重建使用 `pwsh -NoProfile -File D:/proj/ProxyVeil/scripts/Build.ps1`，成功后 `pwsh -NoProfile -File D:/proj/ProxyVeil/scripts/Test-Package.ps1`。这会写隔离测试、验证记录与本地包，不修改当前 FlClash/Edge。实际修复必须由用户点击修复按钮或明确授权对应机器；包路径和 SHA 每次构建重新核对。
