# Platform evidence

检索日期：2026-10-10。仅采用官方文档与 FlClash v0.8.99 源码；应用实测范围见 docs/validation。

- [Mihomo DNS](https://wiki.metacubex.one/config/dns/)：nameserver 的 #代理组选择、respect-rules、proxy-server-nameserver 与 default-nameserver。引导 DNS 必须使用 IP；可采用加密解析。代码据此设置独立直连加密引导与网站 DNS 的组选择。
- [Mihomo TUN](https://wiki.metacubex.one/config/inbound/tun/)：auto-route、strict-route、dns-hijack。待网络运行验证，不将配置存在等同于路由生效。
- [Edge WebRTC](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/webrtclocalhostiphandling)：disable_non_proxied_udp 限制非代理 UDP，需重启，不支持微软账号配置文件。其余 WebRTC 策略用于路由表与全站限制，均需 edge://policy 检查。
- [Edge URL WebRTC](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/webrtciphandlingurl) 与 [路由表](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/webrtcrespectosroutingtableenabled)：策略注册表名称与值类型。
- [Edge DNS mode](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/dnsoverhttpsmode)：secure 失败时不回落普通 DNS。
- [Edge DNS templates](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/dnsoverhttpstemplates)：多个 DoH URI 用空格分隔；固定 IP 模板减少服务域名引导。
- [DWM backdrop](https://learn.microsoft.com/en-us/windows/win32/api/dwmapi/ne-dwmapi-dwm_systembackdrop_type)：DWMSBT_TRANSIENTWINDOW 对应 Desktop Acrylic，Windows 11 build 22621 起支持。UI 使用属性 38 与圆角 33，失败退化背景。
- [FlClash v0.8.99](https://github.com/chen08209/FlClash/tree/v0.8.99)：配置模型与状态读取以 lib/models/config.dart、lib/state.dart 为依据。当前本地 shared_preferences.json 结构与运行服务名称只读确认；后续版本逐项核验，不假定兼容所有版本。
- [AliDNS API reference](https://static-aliyun-doc.oss-cn-hangzhou.aliyuncs.com/download%2Fpdf%2F171662%2FAPI_Reference_intl_en-US.pdf)：223.5.5.5 与 223.6.6.6 的 DoH 引导地址。

旧脚本来源：当前任务 outputs/Set-FlClashPrivacy.ps1，仅继承块 YAML 编辑及路径探测函数。选择性修复、后台 UI、权限分版、快照冲突保护与 Proxy 模式为本项目实现。

2026-10-10 恢复类型补充：核对 [.NET RegistryKey 源码](https://raw.githubusercontent.com/dotnet/runtime/main/src/libraries/Microsoft.Win32.Registry/src/Microsoft/Win32/RegistryKey.cs)。SetValue 的 MultiString 要求 string[]，Binary/None 要求 byte[]；GetValue 支持 DoNotExpandEnvironmentNames 保存 ExpandString 原文。实现见 Core/Get-PvRegistryValue、Set-PvRegistryValue，原生临时键验证见 docs/validation/registry.json。
