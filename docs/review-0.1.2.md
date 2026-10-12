# 0.1.2 双轴审查

2026-10-12。使用 code-review 技能，两个独立 agent 分别静态审查 Standards 与 Spec。固定点为任务开始时远端 main `8f3e9e40d690e9a6d63779ff3a4c6d4e90287134`；初审实现为 `0eda71e`，随后复查本轮修复。diff：`git diff 8f3e9e40d690e9a6d63779ff3a4c6d4e90287134...HEAD`。规格是 `docs/implementation-0.1.2.md`，并参考早期 `docs/local-development-plan.md`；规范来自 AGENTS、领域记录和两个 ADR。

## Standards

1. P2：带引号的 YAML 顶层键可能被忽略，导致追加同名键。已在 plan 阶段拒绝，portable 回归覆盖单双引号 dns/tun/ipv6，确认没有写入配置或快照。
2. P2：Python 的布尔/数字相等可能漏掉受管偏好漂移或 profile 类型变化。已要求严格整数 profile ID，并比较受管值类型与值；回归覆盖 true、1.0、0/1，确认在 profile 写入前拒绝。
3. P2：同一 CoreFoundation 客户端的读缓存可能掩盖外部变化。每次读写改用新客户端子进程；域是唯一应用参数，值走管道，读路径不同步，错误不泄漏值。协议与失败处理测试通过；真实缓存/ABI 行为仍需 Mac 验收。
4. 注释：实现子进程后，旧注释“不给进程传值”不准确。已改为“不把值放入进程参数”。

复审未发现剩余阻断问题；没有值得单独列出的 Fowler smell。agent 未执行测试或修改文件。

## Spec

1. P2：“只接受数字 currentProfileId”“受管偏好漂移或 profile 切换拒绝还原”未被原来的值比较完整满足。严格类型比较与回归已补齐。
2. P2：“不宣称已应用 Mac 浏览器策略”与旧布局返回 DoH 策略冲突。已删除策略生成，两布局均返回 browserDns=not_configured_on_macos；旧 Proxy 响应回归通过。
3. 注释：同一原生进程参数描述已修正。

复审未发现新的要求偏差或范围扩张；schema 2 偏好备份的 profile ID 已绑定 manifest，并在写入前校验。实际 CoreFoundation、重启与网络仍待 Mac 验收。agent 未执行测试或修改文件。

两轴分开计数：Standards 3 项 P2 加 1 处注释，Spec 2 项 P2 加 1 处注释；各轴最高严重度均为 P2，全部已修复，复审无剩余阻断项。

本轮验证：portable 16、preferences 16 均通过，证据见各 JSON；Windows 双运行时各 8 项 suite 和重建的两种 ZIP 通过，见 `docs/validation/windows-012.json`。注册表临时键剩余 0，真实配置未修改。Windows 10、真实桌面、UAC/TUN/网络未执行，不以隔离测试替代。
