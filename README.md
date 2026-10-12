# ProxyVeil

ProxyVeil 是 FlClash 的隐私配置助手。它为 TUN 或系统代理模式配置 DNS、Edge WebRTC 策略和 FlClash IPv6，并保存可还原的快照。已有订阅、分流和节点选择会保留；代理节点仍由 FlClash 提供。

当前版本 **0.1.2**。Windows 提供 PowerShell 7 / WPF 界面和普通权限、管理员两个入口；macOS 提供独立 Python CLI。

![ProxyVeil 主界面，等待用户发起修复](docs/images/windows-home.png)

本文图片来自 Windows 隔离测试，使用样例配置与模拟策略存储。图片中的“已完成”表示夹具流程成功，真实配置与网络结果需另行核验。

## Windows 启动

需要 Windows、PowerShell 7 和已配置可用节点的 FlClash。源码可以直接运行；自行构建的便携 ZIP 需先完整解压，保留 `src`、`scripts` 和 `docs/images` 目录。

| 入口 | 使用方式 |
|---|---|
| `ProxyVeil.cmd` | 双击启动普通权限版，日常使用从这里开始 |
| `ProxyVeil.Admin.cmd` | 双击启动管理员版，请求当前用户的 UAC 授权 |
| `scripts/Launch.ps1` | 从 PowerShell 启动，可指定 `-Edition Administrator` |

在项目或解压目录运行：

```powershell
pwsh -NoProfile -STA -File ./scripts/Launch.ps1
pwsh -NoProfile -STA -File ./scripts/Launch.ps1 -Edition Administrator
```

启动器依次查找 PATH、Program Files 下的 PowerShell 7 和当前用户的 Codex PowerShell 运行时；未找到时提示安装。ZIP 不包含运行时，窗口打开后隐藏控制台。管理员入口要求同一用户授权，其他用户的 UAC 会被拒绝；提权也不会接管 ACL 或覆盖组织机器策略。

## 使用方式

1. 在 FlClash 中确认订阅可用，并选好代理节点。
2. 打开 ProxyVeil 的“设置”，核对安装位置和配置目录。Windows 配置目录应包含 `shared_preferences.json`；未识别到时可手动填写。
3. 选择 TUN 或 Proxy，勾选需要的修复项目，并选择 DNS 使用的代理组。该组应已选中可用节点，ProxyVeil 不判断节点所在地。
4. 点击“检查并修复”。这会保存快照并写入所选配置；仅打开窗口不会发起修复。
5. 查看逐项结果。默认自动重启 FlClash，连接可能短暂中断；也可先退出 FlClash，再关闭自动重启选项。Edge 需要自行重启。

![设置连接方式、修复项目、安装路径与 DNS 代理组](docs/images/windows-settings.png)

普通权限版使用 TUN 时需要已有的 FlClashHelperService 正在运行。权限不足或组织策略冲突会显示警告；管理员版仍受已有访问权限和机器策略约束。

| 修复项目 | TUN 模式 | Proxy 模式 |
|---|---|---|
| FlClash DNS | 配置加密解析、关闭系统追加与回落，设置 UDP / TCP 53 接管 | 配置加密解析、关闭系统追加与回落 |
| Windows Edge DNS | 关闭浏览器 DoH，交给 TUN 处理 | 配置 secure DoH，将指定 DoH IP 路由到所选代理组 |
| Edge WebRTC | 限制不经代理的 UDP | 同左 |
| FlClash IPv6 | 可选关闭 FlClash IPv6 与 IPv6 解析 | 同左 |

DNS 修复会清空 `nameserver-policy`、`direct-nameserver`、`fallback` 和节点解析覆盖，并为节点引导设置独立的直连加密 DNS。依赖内网 DNS 的站点可能因此无法解析，可用还原恢复。Proxy 模式的浏览器 DNS 配置目前覆盖 Edge，其他应用的系统 DNS 需单独检查；关闭 FlClash IPv6 不会禁用物理网卡。

![隔离修复完成，显示各项结果与还原入口](docs/images/windows-completed.png)

## 还原与验证

有快照时，主按钮变为“还原上次修改”。它恢复 FlClash 配置和本工具写入的 Edge 策略；FlClash 根据恢复的偏好处理系统代理。

Windows 快照保存在 `%LOCALAPPDATA%\ProxyVeil`，可能包含订阅凭据，仅当前用户、SYSTEM 与管理员有访问权限。确认无需还原前请保留此目录，分享截图、提交代码或反馈问题时不要附上原始订阅及备份。

文件没有额外变化时按原始字节还原。FlClash 仅重新序列化偏好或更新无关字段时，会合并还原受管字段，保留其他变化。订阅 YAML、受管偏好或策略出现冲突时停止覆盖并保留快照，先核对冲突原因再重试。

结果打勾表示配置已写入并读回。重启 Edge 后打开 `edge://policy` 检查策略状态，再比较走代理的测试站显示的公网出口、WebRTC 地址和 DNS 服务。国内直连站显示本地出口符合分流规则；地址不同本身不足以判断泄露。`WebRtcLocalhostIpHandling` 需要浏览器重启，且不适用于登录微软账号的 Edge 配置文件，见 [Microsoft 官方策略说明](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/webrtclocalhostiphandling)。

本工具不直接修改物理网卡、系统防火墙或 Windows DNS。受支持的 Windows 11 使用 Desktop Acrylic，其他情况使用半透明背景；实际模糊效果仍需在桌面上确认。

## macOS 入口

macOS 需要 Python 3 与 FlClash，从源码仓库使用 CLI。Windows 便携包不包含 Mac 文件。进入仓库目录后运行：

```sh
sh ./scripts/Launch-macOS.sh inspect
# 新版原生偏好布局：执行 repair / restore 前完全退出 FlClash
sh ./scripts/Launch-macOS.sh repair --mode TUN --items DNS IPv6
sh ./scripts/Launch-macOS.sh restore
```

`inspect` 只读；`repair` 是明确的写入操作，默认快照目录为 `~/Library/Application Support/ProxyVeil`。支持旧版 JSON 布局，以及已识别的原生偏好、SQLite schema 10 和 profile YAML 布局；未知结构会拒绝修改。SQLite 与已生成的 `config.yaml` 不写入，Mac 浏览器 DoH / WebRTC 不配置。

既有 Mac 实机记录已验证 FlClash 0.8.99 原生布局的修复、读回、还原和应用重启，网络验收仍有 Google HTTPS 超时等限制。用法及参数见 [macOS 说明](https://github.com/medicagooo/ProxyVeil/blob/main/macos/README.md)。

## 开发、测试与构建

以下命令在源码仓库根目录执行。构建离线运行，生成 `dist/ProxyVeil-0.1.2-Standard.zip` 和 `dist/ProxyVeil-0.1.2-Administrator.zip`。便携包只含运行文件、README 与示例图片，不含开发测试脚本、订阅或快照。

```powershell
# 核心与界面隔离测试
pwsh -NoProfile -File ./scripts/Test.ps1
pwsh -NoProfile -STA -File ./scripts/Test-UI.ps1
pwsh -NoProfile -File ./scripts/Test-HostReport.ps1

# 构建会先运行回归检查；解压包测试再验证修复与还原
pwsh -NoProfile -File ./scripts/Build.ps1
pwsh -NoProfile -File ./scripts/Test-Package.ps1

# 可选：实际显示的窗口使用夹具；宿主检查只读真实配置
pwsh -NoProfile -STA -File ./scripts/Test-Desktop.ps1
pwsh -NoProfile -File ./scripts/Test-WindowsHost.ps1
```

配置测试使用 `work/` 下的隔离目录和模拟策略；原生注册表测试仅写随机 `HKCU\Software\ProxyVeil.Test-*` 临时键并清理。

Windows 11 上 PowerShell 7.6.5 与 7.6.6 的自动回归、界面流程和两个便携包已有通过记录，实际显示的窗口控件与隔离修复 / 还原也已验证。本机只读网络基线可连通百度与 Google；真实 UAC、Repair / Restore 后的 DNS / WebRTC / IPv6 泄露测试仍未执行。本轮未重复测试 Mac，也未执行单独的 Windows 10 验收。

- [Windows 验证记录](https://github.com/medicagooo/ProxyVeil/blob/main/docs/validation/windows-012.json)
- [Mac 既有实机记录](https://github.com/medicagooo/ProxyVeil/blob/main/docs/validation/macos-host.json)
- [项目规格](https://github.com/medicagooo/ProxyVeil/blob/main/docs/spec-v1.md)
- [执行状态与剩余工作](https://github.com/medicagooo/ProxyVeil/blob/main/STATE.md)
