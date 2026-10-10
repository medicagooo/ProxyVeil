# ProxyVeil

Windows / PowerShell 7 / WPF。开发与构建离线运行。执行 `pwsh -NoProfile -File scripts/Test.ps1`，UI 验证执行 `pwsh -NoProfile -STA -File scripts/Test-UI.ps1`。

修复只能由用户点击或明确调用 Repair 发起；测试使用隔离目录和模拟策略存储。真实机器只读检查。原始订阅及备份含凭据，保存在用户本地状态目录，禁止提交。

## Agent skills

Tracker: [docs/agents/issue-tracker.md](docs/agents/issue-tracker.md)。领域: [docs/agents/domain.md](docs/agents/domain.md)。标签: [docs/agents/triage-labels.md](docs/agents/triage-labels.md)。架构约束: [docs/adr/0001-desktop-and-recovery.md](docs/adr/0001-desktop-and-recovery.md)。继续执行读 [STATE.md](STATE.md) 与其权威任务指针。Git 登记格式见 [.branch-records/FORMAT.md](.branch-records/FORMAT.md)。
