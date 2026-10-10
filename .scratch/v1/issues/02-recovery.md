# Snapshot and restore
ID: v1/02
Kind: implementation
Status: resolved
Blocked by: 01
Owner: Codex
Session: initial-v1
Worktree: D:/proj/ProxyVeil
Claimed at: not_recorded

## Source

../spec.md；docs/adr/0001-desktop-and-recovery.md。

## Deliverable

Invoke-PvOperation 持久写前快照；文件字节、策略类型/存在性恢复；偏好无关变化合并；受管变化拒绝覆盖。

## Acceptance

重复修复阻止；独占锁；失败回退；文件/策略漂移阻止还原；偏好重新保存后仍可还原；错误用户 SID 拒绝；跨 worker 进程读写快照。

## Evidence

src/ProxyVeil.Core.psm1；scripts/Test.ps1；docs/validation/engine.json。真实文件只读，无真实恢复操作。

## Comments

验收阶段补录。快照含配置原文，仅本机私有目录保存，包中排除。
