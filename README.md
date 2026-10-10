# ProxyVeil

FlClash 隐私配置助手，PowerShell 7 原生 Windows 窗口。首版支持 Edge、TUN 和系统代理；保留既有分流、订阅与节点选择。

## 启动

需要 Windows 与 PowerShell 7。双击 `ProxyVeil.cmd` 启动普通权限版，双击 `ProxyVeil.Admin.cmd` 启动管理员版。同一项目两入口；便携包按版本分开。管理员入口请求当前用户 UAC，其他用户授权会被拒绝。

启动器依次查找 PATH、Program Files 下的 PowerShell 7、当前用户的 Codex PowerShell 运行时。均未找到时提示安装 PowerShell 7。ZIP 不含运行时；窗口启动后隐藏控制台。

PowerShell 入口：

```powershell
pwsh -NoProfile -STA -File D:\proj\ProxyVeil\scripts\Launch.ps1
pwsh -NoProfile -STA -File D:\proj\ProxyVeil\scripts\Launch.ps1 -Edition Administrator
```

打开设置，核对自动找到的安装位置与配置目录。未找到时填写 FlClash.exe 或安装目录，以及含 shared_preferences.json 的配置目录。选择连接方式、修复项目与 DNS 代理组。组内应已选择可用代理节点；此应用保留节点选择，不判断节点所在地。

点击“检查并修复”后逐项显示结果。已写入项打勾；权限不足或组织策略冲突显示警告。有快照时按钮改为“还原上次修改”。修改配置会短暂断开 FlClash；默认自动重启，也可先退出软件再关闭此选项。Edge 由用户重启，应用不会关闭浏览器标签。

## 保护范围

| 项目 | TUN | Proxy |
|---|---|---|
| FlClash DNS | 加密解析、关闭系统追加与回落、UDP/TCP 53 接管 | 加密解析，关闭系统追加与回落 |
| Edge DNS | 交给 TUN 接管 | secure DoH，固定 DoH IP 定向走代理组 |
| WebRTC | 限制 Edge 不经代理的 UDP | 同左 |
| IPv6 | 可选关闭 FlClash IPv6 与 IPv6 解析 | 同左 |
| 权限 | 普通版需已运行 FlClashHelperService；管理员版可使用管理员 token 运行 FlClash | 普通版可用；策略写入仍受 ACL 与组织策略约束 |

Windows 11 支持的系统版本使用 Desktop Acrylic。其他版本使用半透明色层。WPF 与玻璃调用已在当前 Windows 11 主机验证；Windows 10 回退尚未实机验证。

Proxy 模式的浏览器 DNS 保护首版覆盖 Edge，其他应用的系统 DNS 需单独检查。关闭 FlClash IPv6 不禁用物理网卡，也不能阻止所有 IP 字面量直连。DNS 修复会清空 nameserver-policy、direct-nameserver、fallback 与节点解析覆盖，并为节点引导设置独立直连加密 DNS；依赖内网 DNS 的站点可能失去解析，使用还原恢复。

普通版不主动提权。管理员版也不会接管 ACL 或覆盖组织机器策略；受限项明确跳过。部分 WebRTC 策略不适用于登录微软账号的 Edge 配置文件，需在 `edge://policy` 核验。[Edge WebRTC 官方说明](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/webrtclocalhostiphandling)。

## 还原与复测

快照位于 `%LOCALAPPDATA%\ProxyVeil`，包含原始配置，可能含订阅凭据；仅当前用户、SYSTEM 与管理员获访问权限。保留此目录直到确认无需还原。还原恢复 FlClash 配置与此应用写入的 Edge 策略；FlClash 根据恢复的偏好处理系统代理。应用不直接修改物理网卡或 Windows DNS。

文件未发生额外变化时逐字节还原。FlClash 仅重新序列化偏好或更新无关字段时，合并还原受管字段并保留其他变化。订阅 YAML、受管偏好或策略被外部修改时停止覆盖，保留快照；先核对冲突原因再重试。失败回退受阻时同样保留快照。

勾选结果表示配置已写入并读回。实际验收：重启 FlClash 与 Edge，在 `edge://policy` 确认策略没有错误；对走代理的检测站比较网页公网出口、WebRTC 公网地址和 DNS 服务，确认未出现本地 ISP 出口与普通网站的 ISP DNS。国内直连站显示本地出口符合分流规则；仅 IP 不一致不足以判断 WebRTC 泄露。节点引导解析属于单独例外。修改后的实际网络泄露测试尚未由本项目在此机器执行。

## 开发

以下命令及 docs 验证记录位于源码项目。便携 ZIP 只包含运行文件与本说明，不含开发脚本或测试记录。

```powershell
pwsh -NoProfile -File D:\proj\ProxyVeil\scripts\Test.ps1
pwsh -NoProfile -STA -File D:\proj\ProxyVeil\scripts\Test-UI.ps1
pwsh -NoProfile -File D:\proj\ProxyVeil\scripts\Build.ps1
pwsh -NoProfile -File D:\proj\ProxyVeil\scripts\Test-Package.ps1
```

测试使用 `work/` 下的隔离配置与模拟策略，不修改本机 FlClash/Edge。构建离线生成普通权限版和管理员版 ZIP，不包含 PowerShell 运行时。验证证据见 `docs/validation/`，规格见 `docs/spec-v1.md`，执行状态见 `STATE.md`。
