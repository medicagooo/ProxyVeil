# 本机开发与 macOS 存储依据

检索日期：2026-10-12（UTC-04:00）。本机环境来自只读系统查询；源码依据固定在 FlClash `v0.8.99` 查询得到的提交 `68c71b8ef9b7486a224972eb371ff153c6b2de0f`。下载的源码保存在忽略目录 `work/flclash-contract/`，继续工作可按下列固定链接重新获取。

## 已核实的数据流

- [Preferences.getConfigMap/saveConfig](https://raw.githubusercontent.com/chen08209/FlClash/68c71b8ef9b7486a224972eb371ff153c6b2de0f/lib/common/preferences.dart) 将应用 Config 序列化为 JSON 字符串，交给 SharedPreferences 读取或保存。[常量](https://raw.githubusercontent.com/chen08209/FlClash/68c71b8ef9b7486a224972eb371ff153c6b2de0f/lib/common/constant.dart) 定义应用键 `config` 与核心键 `clash_config`。
- [shared_preferences 官方说明](https://pub.dev/packages/shared_preferences) 说明 macOS 使用 NSUserDefaults，默认键前缀为 `flutter.`；外部更新可能与插件缓存不同步。[Foundation 插件源码](https://raw.githubusercontent.com/flutter/packages/main/packages/shared_preferences/shared_preferences_foundation/darwin/shared_preferences_foundation/Sources/shared_preferences_foundation/SharedPreferencesPlugin.swift) 的 LegacySharedPreferencesPlugin 调用 UserDefaults.standard。该插件链接是检索时的 main，不代表目标 Mac 实际打包版本；目标应用域和键仍需只读实测。
- [AppPath](https://raw.githubusercontent.com/chen08209/FlClash/68c71b8ef9b7486a224972eb371ff153c6b2de0f/lib/common/path.dart) 给出 `database.sqlite`、`config.yaml` 和 `profiles/<id>.yaml` 路径。[ClashCoreController.getAppliedConfig](https://raw.githubusercontent.com/chen08209/FlClash/68c71b8ef9b7486a224972eb371ff153c6b2de0f/lib/core/controller.dart) 读取 `config.yaml`，getConfig(id) 读取原始 profile。因此 config.yaml 是已应用的核心配置，不能仅凭文件名将其视为应用偏好写入。
- [Config 模型](https://raw.githubusercontent.com/chen08209/FlClash/68c71b8ef9b7486a224972eb371ff153c6b2de0f/lib/models/config.dart) 包含 currentProfileId、networkProps、patchClashConfig 和 overrideDns。[Profiles 表](https://raw.githubusercontent.com/chen08209/FlClash/68c71b8ef9b7486a224972eb371ff153c6b2de0f/lib/database/profiles.dart) 包含 id、url、subscriptionInfo、selectedMap 等字段；fileNames() 由 id 得到 YAML 文件名。[数据库入口](https://raw.githubusercontent.com/chen08209/FlClash/68c71b8ef9b7486a224972eb371ff153c6b2de0f/lib/database/database.dart) 使用 Drift，源码 schemaVersion 为 10。目标数据库版本不能从这个源码值推断。

设计结论：优先适配应用偏好与原始 profile；SQLite 只读核验 profile 索引，保留订阅与节点选择，不直接修改数据库或运行配置。偏好存在性、类型、受管字段和 profile 字节需要共同进入恢复记录。该方案尚未证明目标 Mac 的实际偏好域、键或重启行为。

## 本机验证能力

- [Python fcntl](https://docs.python.org/3.12/library/fcntl.html) 仅在 Unix 提供；将它移入实际锁路径，Windows 可以导入和测试其余逻辑。
- [Python msvcrt.locking](https://docs.python.org/3.12/library/msvcrt.html) 在 Windows 按当前位置锁定字节区间，LK_NBLCK 失败立即报错；范围可超过文件末尾。当前 portable 测试使用这一原生锁验证进程互斥，macOS 继续使用 flock。
- [Python sqlite3](https://docs.python.org/3.12/library/sqlite3.html) 支持 URI 连接与只读模式，可用于后续隔离数据库核验。当前没有执行数据库读写或迁移。
- [Microsoft Hyper-V 安装说明](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/get-started/install-hyper-v) 列出 Windows Pro/Enterprise、硬件和内存要求；启用为管理员操作，可能需要重启。本机 Windows 11 Pro N 有约 31.5 GiB 内存，D 盘约 363.7 GiB 空闲；HypervisorPresent 为 true，但 vmms、Hyper-V 管理模块和常见第三方 VM 管理程序未发现。vmcompute 正在运行，不能据此认为完整 Hyper-V 已就绪。

本机 CPU 虚拟化属性在当前查询中为 false，同时 hypervisor 已存在。未据此判定固件虚拟化关闭；在准备 VM 前应继续核实 Windows 功能及固件状态。当前未启用功能、创建 VM 或重启系统。
