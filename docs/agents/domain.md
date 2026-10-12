# Domain

单上下文。术语: `GLOSSARY.md`；决策: `docs/adr/`；需求: `docs/spec-v1.md`。缺失领域文件时继续，实际出现术语与决策再落盘。FlClash 适配器拥有配置转换；引擎拥有快照与恢复；UI 只提交请求与呈现结果。

`Adapters/FlClash.Yaml.ps1/New-PvConfiguration` 从只读 context 生成 profile/preferences/policy 计划，保持 Core 导出的原有函数契约。仅 DNS 需要代理组；仅 WebRTC 不解析 YAML。Proxy 定向规则采用原列表缩进，保护检查只移除本次插入的前缀。Core 的 `Get-PvContext -SkipDnsGroup` 用于不含 DNS 的修复，Inspect 默认仍识别组。

`Start-ProxyVeil.ps1/Start-PvWork` 将请求交给 `Invoke-Worker.ps1`，后者调用 `ProxyVeil.Core.psm1/Invoke-PvOperation`。worker 写 JSONL 进度与最终 JSON，窗口定时调用 `Progress.ps1/Read-PvProgressLines`；读取允许后台追加和文件替换，部分行重试，后台退出后以结果与快照为准。进度读取异常不能解除正在执行的操作锁。

引擎先持久化 before/after manifest，再写文件或 HKCU Edge 策略；配置文本、字节恢复和失败回退均先写同目录临时文件再替换。每个还原目标接受记录的 before/after；外部偏好仅合并受管字段，YAML 漂移停止覆盖。此契约由 Test.ps1、Test-Progress.ps1 与 Test-UI-Recovery.ps1 覆盖。夹具用模拟注册表；生产路径修改真实用户策略，不能混用。

`macos/proxyveil.py/operation_lock` 按宿主平台选择 flock 或 Windows msvcrt 单字节锁；平台模块在获取锁时导入。`main` 仍拒绝非 macOS，Windows 仅通过 `scripts/Test-macOS-Portable.py` 在临时夹具调用同一 context/plan/repair/restore，覆盖恢复和跨进程互斥。此测试不验证 macOS 原生偏好或网络效果；旧 CLI 集成入口 `scripts/Test-macOS.py` 保留。新布局实现和原生验收边界见 `docs/implementation-0.1.2.md`。

`Core/Test-PvPolicyEqual` 比较存在性、RegistryValueKind 与 JSON 结构值，保持 MultiString/Binary 的元素边界。UI 的 `Start-PvWork` 同时捕获请求准备与启动失败；快照 JSON 损坏时依据 active.json 的存在性保留还原入口。worker 失败返回相同存在性，不删除快照。回归入口：`scripts/Test-Review.ps1`、`scripts/Test-UI-Failure.ps1`，由 Build.ps1 一并执行。

`macos/proxyveil.py/context` 新布局接收 `preferences.py/NativePreferences`；应用 bundle 标识决定 current-user/any-host 偏好域，flutter.config 字符串与只读 SQLite schema 10 的 profiles.id 共同定位原始 YAML。`repair_native` 写 schema 2 的持久化备份后修改 profile 与单一偏好键；`restore_native` 核对安装包域、配置目录和备份，再由 `merge_restore` 撤销受管叶字段并保留其他偏好。SQLite、订阅、节点选择及 applied config.yaml 不在写入集合中。应用须退出；原生偏好同步只发生在显式写路径。schema 1 快照仍走旧还原路径。`Test-macOS-Preferences.py` 在生成的 XML/binary plist 和 SQLite 夹具调用同一逻辑；实际 Mac 验收见 `docs/validation/macos-acceptance.md`，本轮要求见 `docs/implementation-0.1.2.md`。

`Start-ProxyVeil.ps1/ForceOpaque` 仅在隔离 RenderOnly/SmokeTest 允许，强制走 DWM 拒绝 Acrylic 后的同一背景回退；`Test-UI.ps1` 核对背景与渲染结果。这不代替 Windows 10 或真实桌面模糊验收。

`preferences.py/NativePreferences` 每次通过 `_helper_main` 创建新的 CoreFoundation 子进程客户端，避免进程内缓存掩盖外部偏好漂移。域是唯一应用参数，偏好值仅走 stdin/stdout 管道；错误响应不包含异常详情或凭据。读取不调用 Synchronize；写入同步后退出，再由新客户端读回永久存储。Mac 上的实际缓存/同步行为仍需原生验收。

`Core/Get-PvRegistryValue` 保存未展开的 ExpandString 原文；`Set-PvRegistryValue` 将 JSON 数组恢复为 string[]/byte[]，保留空数组及单元素数组。Get/Set-PvPolicy 生产路径调用这两个内部函数；Test-Registry.ps1 在随机 HKCU Software/ProxyVeil.Test-* 临时键验证同一路径并清理，覆盖 11 个原生类型序列化还原场景，不修改 Edge 策略。

`scripts/Test-Desktop.ps1` 用独立 pwsh -STA 运行 `Start-ProxyVeil.ps1 -FixtureRoot -StateDirectory` 的实际 ShowDialog；UI Automation 调用设置、复选框、最小化、修复、还原和关闭控件。配置和 worker 写入均在 work/ 夹具，截图仅限该窗口且先核对遮挡；截图缺失单独记录，不能把控件成功当成模糊效果通过。DWM 属性读回只证明背景类型配置。测试临时调整自身线程 DPI 和夹具窗口层级，退出时还原线程并关闭子进程；不调用真实 UAC。

`scripts/Test-WindowsHost.ps1` 调用 Core 的真实 `Get-PvContext`、`Invoke-PvOperation -Action Inspect`、`New-PvConfiguration` 和 `Get-PvPolicy`，TUN/Proxy 计划只在内存生成，不保存原始 profile 或偏好。相同生产入口验证跨用户 SID 和未提权 Administrator 请求在 Inspect 前被拒绝。HttpClient 仅探测当前网络 HTTPS 和从 applied config.yaml 读出的本地 mixed-port；报告无原始策略值、订阅或 IP。文件哈希和策略快照在内存比较，基线连通性不证明修复后的 DNS/WebRTC/IPv6 效果。真实 Repair 的确切目标和授权边界见 docs/validation/windows-live-plan.md。
