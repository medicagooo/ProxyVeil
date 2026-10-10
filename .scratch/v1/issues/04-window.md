# Glass window and progress
ID: v1/04
Kind: implementation
Status: resolved
Blocked by: 03
Owner: Codex
Session: initial-v1
Worktree: D:/proj/ProxyVeil
Claimed at: not_recorded

## Source

../spec.md；docs/design.md。

## Deliverable

WPF 半透明玻璃窗口；设置、模式与项目；逐行后台进度；有快照时切换还原；恢复按钮后回到修复。

## Acceptance

实际 Button.Click 经子 worker 执行隔离修复/还原；三状态非空渲染；Windows Acrylic API 调用；工作中禁重复操作；设置持久化。

## Evidence

src/Start-ProxyVeil.ps1；src/UI/*；docs/validation/ui.json；docs/validation/ui-idle.png、ui-settings.png、ui-completed.png 及对应 JSON。离屏图不能表现真实背景模糊，API 返回值独立记录。

## Comments

验收阶段补录。Windows 10 回退尚未实机验证。
