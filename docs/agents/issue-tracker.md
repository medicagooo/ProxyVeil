# Tracker

本地 Markdown，根目录 `.scratch/v1/`。spec.md 链接 docs/spec-v1.md，map.md 索引 issues/*.md；STATE.md 链接根目录交接。Kind: implementation。Status 为 needs-triage | needs-info | ready-for-human | ready-for-agent | claimed | resolved | wontfix；Status 是唯一执行状态字段。

每票使用手册 §7.2 的 ID、Kind、Status、Blocked by、Owner、Session、Worktree、Claimed at 与 Source/Deliverable/Acceptance/Evidence/Comments。当前单一 Codex 会话串行写 tracker，不以 Markdown 声称并发领取安全。仅验收后 resolved。外部 issue 经 triage，生成的实施票直接 implement。

v1 规格先于代码落盘；工单在实现验收阶段补录为 resolved，不伪造 ready/claimed 的历史时间。工单证据采用代码与验证文件；未来票按 ready-for-agent → claimed → resolved 执行。网络实测与真实 UAC 尚未验收，记录在 STATE 的后续项，不计入配置单元测试结论。
