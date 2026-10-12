# 后续任务：以当前 Windows 电脑为开发主机

2026-10-12（UTC-04:00）。目标是先在本机完成配置适配和恢复逻辑，再将系统权限、应用重启与网络验收留到目标系统。仓库 `D:/proj/ProxyVeil`，任务 `local-development-v1`，分支 `1012-local-development`；起始源码为 `59bd396951fe48cfaf06ecde26c5defffb883155`。

## 当前已完成

已将 macOS 适配器的 fcntl 导入移入实际锁路径。Windows 测试用 msvcrt 原生锁调用同一组 context、plan、repair、restore 函数，macOS 保留 flock。生产 CLI 仍只接受 macOS，没有新增绕过平台检查的参数。

`scripts/Test-macOS-Portable.py` 在临时目录生成夹具，已通过 12 个场景：只读检查与计划、TUN/Proxy 修复和字节还原、WebRTC 跳过、重复修复拒绝、外部变化、备份缺失及篡改、修复回退、还原中断续接、跨进程互斥，以及 Windows 生产入口拒绝。结果见 `docs/validation/macos-portable.json`。Python 使用本机已有的 3.12.14，无新增依赖。

Windows 核心 117 条断言与 WPF 修复/还原 UI 回归通过。已有双 PowerShell 版本和包验收证据仍在 `docs/validation/windows-stage2/`；本次未重建或发布便携包。

## 执行顺序

| 顺序 | 工作与地点 | 开始条件 | 交付与通过标准 |
|---|---|---|---|
| 1 | 本机测试入口；已完成 | 当前 Windows 与现有 Python | 12 个隔离场景通过，Windows CLI 不创建状态，Windows 回归通过 |
| 2 | 确认 macOS 偏好契约；本机源码分析 + Mac 一次只读检查 | 已有固定 FlClash 源码；需目标 Mac 的 bundle ID、偏好域/键及数据类型 | 仅输出键、类型、schema 和路径关系，不输出订阅、节点或完整偏好值；确认 currentProfileId 与 profile 对应 |
| 3 | 偏好存储接口与新布局适配；主要在本机 | 第 2 步契约明确 | 保留 shared_preferences.json；新增 Mac 原生偏好后端和本机模拟后端；相同业务计划覆盖两种存储；未知布局拒绝写入 |
| 4 | 恢复和并发回归；本机 | 新后端能生成计划 | 偏好键与 profile 的 before/after、部分成功、外部修改、备份损坏、重复修复及恢复续接通过；SQLite/订阅/节点选择保持原样 |
| 5 | Windows 10 兼容性；本机 VM | 已核实可用 VM 功能、合法安装介质和目标目录 | Windows 10 启动、回退界面、核心与包测试；独立结果追加到 stage2，保留 Windows 11 证据 |
| 6 | 原生系统和网络验收；Windows VM + 实际 Mac | 完成适配；对应环境的真实 repair 已明确授权 | UAC/TUN、原生偏好读回、FlClash 重启、还原、国内直连和浏览器 DNS/WebRTC 复测；仅保存无凭据摘要 |

第 5 步等待环境时，第 2 至 4 步可继续，不必先迁移开发环境。预计编码和大部分故障回归都能留在 Windows；macOS 的 NSUserDefaults、flock、权限、TUN 和应用运行效果必须在实际 Mac 验证。

## 适配边界

源码表明，`config.yaml` 是已应用的 Mihomo 配置；应用偏好由 SharedPreferences 保存，macOS 使用 NSUserDefaults。详细依据与固定链接见 [本机开发研究](research/local-development.md)。因此下一步不直接覆盖 config.yaml。

候选数据流为：偏好后端读取 Config → 只读核对 currentProfileId 与 SQLite profiles 索引 → 读取原始 profile YAML → 生成受管偏好字段与 YAML 修改计划 → 持久化恢复记录 → 显式 repair 写入并读回。SQLite 不进入写入计划。Mac 偏好写入方式需要验证原生缓存和重启行为；本机可以用生成的 XML/binary plist 夹具验证编码与字段合并，但夹具不能证明修改实际 plist 会被应用采用。

恢复记录需保存偏好键原有存在性、类型、受管字段和 profile 原始字节。写入多个资源时按已完成项恢复，外部受管字段漂移停止覆盖，保留快照供续接；其他偏好字段合并保留。继续支持原有 JSON 布局和已有快照，不以一次性转换替代向后兼容。

本轮范围是测试基础、存储研究与执行方案。新布局的 inspect/repair/restore 尚未实现。没有修改真实 FlClash/Edge 配置、SQLite、系统虚拟化设置；没有部署、推送或 Release。

## 本机命令与下一步

先核对本机测试基础：

```powershell
Set-Location D:/proj/ProxyVeil
& 'C:/Users/medic/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -X utf8 scripts/Test-macOS-Portable.py
if ($LASTEXITCODE -ne 0) { throw 'portable fixture test failed' }
pwsh -NoProfile -File scripts/Validate-Registry.ps1
if ($LASTEXITCODE -ne 0) { throw 'registry validation failed' }
```

随后从 `macos/proxyveil.py/context`、`plan`、`repair` 和 `restore` 开始设计偏好存储接口，使用 `work/flclash-contract/lib/common/preferences.dart`、`lib/common/constant.dart`、`lib/models/config.dart` 和 `lib/database/profiles.dart` 核对字段。先构建本机生成的偏好夹具与只读索引测试；原生偏好域确认前保持生产新布局入口安全拒绝。下一次 Mac 检查只读取应用标识、目标键存在性/类型和 profile 对应关系。
