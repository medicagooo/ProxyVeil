# v1 implementation

| ID | 实施票 | 依赖 | 验收范围 |
|---|---|---|---|
| 01 | [路径与配置计划](issues/01-adapter.md) | none | FlClash 识别，TUN/Proxy，选择性变更 |
| 02 | [快照与恢复](issues/02-recovery.md) | 01 | 原值、异常回退、外部冲突、重复执行保护 |
| 03 | [权限入口](issues/03-privileges.md) | 02 | 两入口、同用户约束、权限降级 |
| 04 | [玻璃窗口](issues/04-window.md) | 03 | 设置、后台逐项进度、修复/还原按钮 |
| 05 | [离线交付](issues/05-delivery.md) | 04 | ZIP 内容检查、解压集成、记录与文档 |

规格、ADR 在实现前记录；工单在验收阶段补录。票 resolved 的含义为其本地配置/窗口/包验收通过，网络泄露与真实 UAC 的后续检查见 STATE。工单没有独立分支；全部实现集成于 1010-initial-v1。
