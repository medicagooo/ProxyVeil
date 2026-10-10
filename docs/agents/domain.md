# Domain

单上下文。术语: `GLOSSARY.md`；决策: `docs/adr/`；需求: `docs/spec-v1.md`。缺失领域文件时继续，实际出现术语与决策再落盘。FlClash 适配器拥有配置转换；引擎拥有快照与恢复；UI 只提交请求与呈现结果。

`Adapters/FlClash.Yaml.ps1/New-PvConfiguration` 从只读 context 生成 profile/preferences/policy 计划，保持 Core 导出的原有函数契约。仅 DNS 需要代理组；仅 WebRTC 不解析 YAML。Proxy 定向规则采用原列表缩进，保护检查只移除本次插入的前缀。Core 的 `Get-PvContext -SkipDnsGroup` 用于不含 DNS 的修复，Inspect 默认仍识别组。

`Start-ProxyVeil.ps1/Start-PvWork` 将请求交给 `Invoke-Worker.ps1`，后者调用 `ProxyVeil.Core.psm1/Invoke-PvOperation`。worker 写 JSONL 进度与最终 JSON，窗口定时调用 `Progress.ps1/Read-PvProgressLines`；读取允许后台追加和文件替换，部分行重试，后台退出后以结果与快照为准。进度读取异常不能解除正在执行的操作锁。

引擎先持久化 before/after manifest，再写文件或 HKCU Edge 策略；配置文本、字节恢复和失败回退均先写同目录临时文件再替换。每个还原目标接受记录的 before/after；外部偏好仅合并受管字段，YAML 漂移停止覆盖。此契约由 Test.ps1、Test-Progress.ps1 与 Test-UI-Recovery.ps1 覆盖。夹具用模拟注册表；生产路径修改真实用户策略，不能混用。

`Core/Test-PvPolicyEqual` 比较存在性、RegistryValueKind 与 JSON 结构值，保持 MultiString/Binary 的元素边界。UI 的 `Start-PvWork` 同时捕获请求准备与启动失败；快照 JSON 损坏时依据 active.json 的存在性保留还原入口。worker 失败返回相同存在性，不删除快照。回归入口：`scripts/Test-Review.ps1`、`scripts/Test-UI-Failure.ps1`，由 Build.ps1 一并执行。

`Core/Get-PvRegistryValue` 保存未展开的 ExpandString 原文；`Set-PvRegistryValue` 将 JSON 数组恢复为 string[]/byte[]，保留空数组及单元素数组。Get/Set-PvPolicy 生产路径调用这两个内部函数；Test-Registry.ps1 在随机 HKCU Software/ProxyVeil.Test-* 临时键验证同一路径并清理，覆盖 11 个原生类型序列化还原场景，不修改 Edge 策略。
