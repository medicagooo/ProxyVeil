# v1 retro

恢复策略比 UI 更影响完成度：FlClash 重启会重新序列化 JSON，整文件哈希冲突会让用户无法还原。因此偏好按受管字段恢复，YAML 订阅仍用哈希保守拒绝覆盖。

离屏 WPF 渲染曾得到空图。处理方式为渲染窗口内容、继承字体资源，并断言颜色数量，避免把成功写出 PNG 视为有效视觉验收。真实背景模糊另记 API 返回值，不用离屏图证明。

窗口读取 JSONL 进度曾阻止后台追加日志，导致操作失败。共享读取改为 FileShare.ReadWrite/Delete；并发测试覆盖真实 worker 的持续写入。另用一次读取故障验证窗口继续等待后台完成，不会提前开放第二次操作。

首次实现已先落规格与 ADR，但未先建立实施票；验收时补录并明确来源，不补造认领时间。下一轮按 ready-for-agent → claimed → resolved 维护票，复用现有 worker/fixture 接缝。

v1 未执行当前机器配置变更、真实 DNS/WebRTC 网络复测或真实 UAC；本地包交付达成后，下一步可在一次性 Windows 用户/VM 上验收这些行为。具体步骤见 STATE 与 README。
