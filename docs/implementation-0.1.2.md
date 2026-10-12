# 本机实施与验收要求

2026-10-12。用户要求实施本机开发方案，完成 review、bug repair、Windows 验收并 push main；原生 Mac 验收由用户随后执行。审查基线为开始时远端 main `8f3e9e40d690e9a6d63779ff3a4c6d4e90287134`。

## 适配与恢复

- 保留 JSON 偏好布局及 schema 1 快照还原。新布局由已安装 FlClash.app 的 CFBundleIdentifier 确定偏好域；显式指定域必须相同。只接受 `flutter.config` 字符串与数字 currentProfileId。
- 新布局通过 CoreFoundation 的 current-user/any-host 域读写偏好键，不直接改 plist，不将值放入进程参数。repair/restore 前必须退出 FlClash，防止应用缓存覆盖；inspect 不同步或写偏好。
- SQLite schema 10 仅只读核对 profiles.id；有 WAL/journal 或未知 schema 时拒绝。订阅、节点选择、SQLite 和已应用 config.yaml 不进入写入计划。
- 新快照先保存 profile 原始字节与偏好键 before/after，再修改和读回。受管偏好漂移或 profile 切换拒绝还原；其他内外层偏好合并保留。部分写入或还原失败保留快照，接受资源 before/after 状态续接。
- Windows 本机用生成的 XML/binary plist 和 SQLite 夹具调用上述生产逻辑。生产 CLI 继续拒绝 Windows；原生 CFPreferences、应用重启与网络效果由 Mac 实机验证。
- 修复 IPv6 DNS 遗漏、组名/规则解析和 YAML 复杂格式拒绝；不宣称已应用 Mac 浏览器策略。

## Windows 验收与发布

PowerShell 7.6.5 与 7.6.6 执行核心、review、原生临时注册表、UI、错误/恢复、进度与两个包的测试。新增隔离窗口强制不透明回退验证，明确它不能替代 Windows 10 实机。0.1.2 包应重建并记录 SHA-256。

双轴审查分别检查仓库规范与本要求；发现问题必须修复并补充回归。普通快进集成 main，再推送并核对远端 SHA。不得 force push。实际 FlClash/Edge 修复、真实 UAC/TUN/网络测试、Windows 10 与桌面实机观察需要对应环境或明确的目标操作授权，未执行项留在报告中，不写成通过。
