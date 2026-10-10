# Terms

- Repair: 对用户选中的配置执行检查、快照、修改和读回。结果只证明配置，泄露验证另计。
- Restore: 恢复此应用快照；遇到外部改动保留快照并拒绝覆盖。
- TUN: FlClash 的虚拟网卡接管模式，需要现有服务或足够权限。
- Proxy: FlClash 的系统代理模式。首版 DNS 保护覆盖 Edge 与交给 FlClash 的解析。
- Edition: Standard 不主动提权；Administrator 入口请求同用户 UAC。权限失败显示跳过。
- Snapshot: 原始文件字节与策略值，加修改后的哈希，用于持久恢复。
