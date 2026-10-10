# ADR 0001: native desktop and recovery

2026-10-10 / accepted for v1。用户授权在 D:\proj 创建本地项目，保留国内直连，支持 FlClash、TUN/Proxy、两种权限入口、玻璃 UI 与还原。

PowerShell 7 + WPF 复用脚本并离线构建。Windows 11 使用 DWM Desktop Acrylic；较旧版本退化为半透明色层。Standard 和 Administrator 共用引擎，Edition 与实际 token 分别核验；不同用户 UAC 拒绝接管配置。

UI → worker process → Core → YAML adapter / registry。worker 通过 JSONL 反馈；UI 不执行配置写入。修复暂停匹配安装路径的 FlClash，完成或失败后按选项重启；不关闭 Edge。

文件和策略先记录原值再修改。每个 mutation 更新 manifest，异常回退已写项；恢复先全量比对修改后状态，冲突则不写。快照绑定用户 SID，权限文件失效会阻止写入。标准版策略权限不足可跳过；快照保留已成功项。主动 DNS 测试、原始订阅与日志不上传。

文件入口与数据契约见 src/ProxyVeil.Core.psm1、src/Invoke-Worker.ps1、src/Start-ProxyVeil.ps1。适配器只支持已识别的 FlClash 偏好及块格式 YAML，复杂格式拒绝修改。
