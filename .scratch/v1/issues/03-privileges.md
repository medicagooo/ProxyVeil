# Privilege editions
ID: v1/03
Kind: implementation
Status: resolved
Blocked by: 02
Owner: Codex
Session: initial-v1
Worktree: D:/proj/ProxyVeil
Claimed at: not_recorded

## Source

../spec.md；docs/design.md。

## Deliverable

ProxyVeil.cmd 普通入口；ProxyVeil.Admin.cmd 当前用户 UAC；两版本共用引擎。普通 TUN 校验服务；组织策略冲突及写权限不足跳过。

## Acceptance

隔离运行普通/管理员 × TUN/Proxy 四组合；模拟权限失败不误报成功；其他用户 SID 拒绝；管理员实际运行必须有管理员 token。

## Evidence

scripts/Launch.ps1；src/ProxyVeil.Core.psm1；docs/validation/engine.json；docs/validation/package-smoke.json。UAC 启动路径经代码核验，真实提示与低权限账户运行未实测。

## Comments

验收阶段补录。fixture 的 Administrator 只测试版本行为，不证明真实提权成功。
