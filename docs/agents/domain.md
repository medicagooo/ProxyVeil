# Domain

单上下文。术语: `GLOSSARY.md`；决策: `docs/adr/`；需求: `docs/spec-v1.md`。缺失领域文件时继续，实际出现术语与决策再落盘。FlClash 适配器拥有配置转换；引擎拥有快照与恢复；UI 只提交请求与呈现结果。

`Start-ProxyVeil.ps1/Start-PvWork` 将请求交给 `Invoke-Worker.ps1`，后者调用 `ProxyVeil.Core.psm1/Invoke-PvOperation`。worker 写 JSONL 进度与最终 JSON，窗口定时调用 `Progress.ps1/Read-PvProgressLines`；读取允许后台追加和文件替换，部分行重试，后台退出后以结果与快照为准。进度读取异常不能解除正在执行的操作锁。

引擎先持久化 before/after manifest，再写文件或 HKCU Edge 策略；配置文本、字节恢复和失败回退均先写同目录临时文件再替换。每个还原目标接受记录的 before/after；外部偏好仅合并受管字段，YAML 漂移停止覆盖。此契约由 Test.ps1、Test-Progress.ps1 与 Test-UI-Recovery.ps1 覆盖。夹具用模拟注册表；生产路径修改真实用户策略，不能混用。
