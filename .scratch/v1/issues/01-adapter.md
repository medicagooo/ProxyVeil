# FlClash adapter and plans
ID: v1/01
Kind: implementation
Status: resolved
Blocked by: none
Owner: Codex
Session: initial-v1
Worktree: D:/proj/ProxyVeil
Claimed at: not_recorded

## Source

../spec.md；docs/spec-v1.md；docs/research/platforms.md。

## Deliverable

Get-PvContext 自动识别，失败允许 UI 手填；New-PvConfiguration 生成所选保护项的 TUN/Proxy 配置，保留节点与分流。

## Acceptance

两模式、选择性修改、复杂 YAML 拒绝、节点/国内规则保留、DoH 代理路由与独立节点引导、偏好模式读回。

## Evidence

src/Adapters/FlClash.Yaml.ps1；src/ProxyVeil.Core.psm1 的 Get-PvContext/New-PvConfiguration；scripts/Test.ps1；docs/validation/engine.json。真实安装只读识别，网络保护未实测。

## Comments

验收阶段补录；不推定测试覆盖所有 FlClash 版本。
