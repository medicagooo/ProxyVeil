# Review and repair 0.1.1

日期：2026-10-10，America/Halifax。固定审查提交：b36d439f19c2cc0b7cbaa800d5cbe2f9c8f1a1e2。仓库仅有根提交，因此以空树 4b825dc642cb6eb9a060e54bf8d69288fbee4904 比较首版全量代码；命令为 `git diff 4b825dc642cb6eb9a060e54bf8d69288fbee4904 b36d439`。提交列表仅 b36d439。Standards 与 Spec 独立并行审查，随后修复。以下定位指向固定提交，修复后的位置见对应函数。

## Standards

- P2，Core:198，`Test-PvPolicyEqual` 使用字符串转换比较值，`['a b','c']` 与 `['a','b c']` 被判相同，违反 ADR 0001 的冲突不写规则。已改为类型及结构值比较，实际 Restore 测试验证外部值不被覆盖。
- P2，UI:64–74，`Start-PvWork` 在 try 之前创建目录及保存请求/设置；文件系统错误逃出窗口事件。已将准备与启动纳入同一异常边界。实际 WPF 按钮测试覆盖目录被文件阻挡及设置路径被目录阻挡。
- P3，domain.md:3 与 Core:96，文档规定适配器负责转换，但 `New-PvConfiguration` 位于恢复引擎。可能属于 Divergent Change。已移至 `Adapters/FlClash.Yaml.ps1`，保留 Core 导出及调用契约。
- P2，修复后复核，`Set-PvPolicy` 未将快照数组转回原生 string[]/byte[]，MultiString/Binary/None 还原失败；ExpandString 快照还会展开环境变量。已补齐类型转换并读取原文。原生临时键测试先复现 8 项失败，再验证 11 项全部通过。

## Spec

- P1，Core:130，Proxy DNS 规则使用固定两空格缩进，破坏合法的无缩进或四空格列表。违反 spec-v1.md 的“国内规则与最终路由保持原样”。已采用输入缩进；零/四空格修复与还原通过。
- P2，Core:88–89、303–314，仅勾选 WebRTC 仍需要 DNS 组及受支持 YAML。违反规格的选择性修改要求。已跳过未选 DNS 的组判断，仅 WebRTC 不解析或修改 YAML。多组无默认路由和复杂 YAML 均通过。

Standards 4 项（首轮 3 项、复核 1 项），最严重 P2；Spec 2 项，最严重 P1。上述项目均已修复。

## Additional regressions

Proxy 保护检查原先删除所有相同 DoH 规则，导致已有规则时拒绝修复；现在只剥离本次新增前缀。逗号代理组会形成无法正确解析的规则目标，现于写入前拒绝。损坏 active.json 曾阻止窗口启动，现保留还原入口并呈现 worker 错误；快照不删除。

证据：`scripts/Test-Review.ps1` 首次 6 个场景全红，修复后加入复杂 YAML 场景，共 7 项通过；`scripts/Test-UI-Failure.ps1` 首次 3 个场景全红，修复后全部通过。完整构建包含既有引擎、UI、进度恢复、并发进度测试；便携包另行解压验证。

版本由 `VERSION` 统一指定，构建与包测试共用。真实 DNS/WebRTC 网络复测、真实 UAC、Windows 10 仍未验证。此次授权发布源码，未对当前电脑执行隐私修改，也未创建 GitHub Release。

原生类型依据：2026-10-10 核对 [.NET RegistryKey 源码](https://raw.githubusercontent.com/dotnet/runtime/main/src/libraries/Microsoft.Win32.Registry/src/Microsoft/Win32/RegistryKey.cs) 的 SetValue 类型处理和 GetValue 环境变量选项；实际运行证据见 docs/validation/registry.json。
