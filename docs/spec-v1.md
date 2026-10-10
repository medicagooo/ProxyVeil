# ProxyVeil v1

来源：2026-10-10 用户要求将既有 PowerShell 7 脚本扩为 D:\proj 项目。交付终点为本地可运行应用及离线包；不推送、不上线、不自动修复当前机器。

范围：Windows、FlClash、Edge。自动查找运行进程、卸载信息、常用路径及快捷方式；失败允许填写安装目录和配置目录。设置选择 TUN/Proxy、DNS、WebRTC、代理内 IPv6、是否重启 FlClash，以及 DNS 使用的现有代理组。

流程：Idle → Checking → Applying → Configured/Partial/Failed。逐项呈现 pending/running/applied/skipped/error，成功项打勾，跳过项单独标记。有活动快照时按钮为还原；Restore → Idle 或 Conflict。UI 工作期间保持响应，禁止重复修复与关闭。

DNS/TUN：加密网站解析通过所选代理组，关闭回落与系统 DNS 追加，配置 UDP/TCP 53 接管。节点域名引导使用独立加密解析，避免 DNS 依赖循环。DNS/Proxy：TUN 关闭、系统代理开启；Edge secure DoH，两个固定 DoH IP 的定向规则置于既有规则之前，国内规则与最终路由保持原样。其他应用的 OS DNS 不在 Proxy 保护范围。选项 IPv6 只关闭 FlClash IPv6 解析和代理内 IPv6，不改物理网卡。

WebRTC：Edge 限制不经代理的 UDP；能力 API 仍可为 True。策略重启 Edge 生效；微软账号配置可能忽略部分策略，验收查看 edge://policy。组织机器策略优先，存在冲突时跳过并提示。

恢复：原始文件逐字节保存；策略存在性与类型保存；外部改变受管项时拒绝覆盖。订阅、凭据、节点、国内直连条目受保护。快照不含公共源码或分发包。异常与中断可从活动 manifest 继续恢复。

验收：隔离样例验证两种模式、两种权限入口、选择性修改、重复执行保护、恢复、冲突、异常回退、JSONL 进度和窗口事件。真实安装只读识别。实际泄露验收需修复后重启 Edge，比较代理出口、WebRTC 公网地址与 DNS 服务；配置读回不替代此测试。

延期：Chrome/Firefox、其他代理、系统全局 DNS 防火墙、网卡禁用、节点信誉判断、签名安装器、自动更新。
