# Portable delivery
ID: v1/05
Kind: implementation
Status: resolved
Blocked by: 04
Owner: Codex
Session: initial-v1
Worktree: D:/proj/ProxyVeil
Claimed at: not_recorded

## Source

../spec.md；docs/scenario.md。

## Deliverable

离线构建两个权限包；新目录解压后测试真实 UI/worker；README、续接、研究、验证与业务记录。

## Acceptance

源码与 ZIP 入口齐全，无配置快照或订阅；两 ZIP 解压后执行隔离修复/还原；registry 引用验证；任务本地提交。

## Evidence

scripts/Build.ps1、Test-Package.ps1、Validate-Registry.ps1；docs/validation/packages.json、package-smoke.json；STATE.md；最终提交用 git rev-parse HEAD 查询。

## Comments

验收阶段补录；仅本地分发包，无远程发布。包依赖用户安装 PowerShell 7。
