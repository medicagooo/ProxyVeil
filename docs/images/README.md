# README 图片来源

以下图片是 `scripts/Test-UI.ps1` 生成的 WPF 隔离夹具渲染，分辨率为 620 × 790。来源是任务开始时提交 `055302e840ab08085a9b9d62623bfd36a83536b7` 中的截图；2026-10-12 查看原图后复制到此目录。图中没有真实订阅、节点凭据或快照内容，设置页的路径属于 `work/` 测试目录。后续 UI 测试可重新生成验证目录截图，README 图片保留此次选取的版本。

| README 图片 | 原始证据 | 画面 |
|---|---|---|
| windows-home.png | docs/validation/ui-idle.png | 普通权限 Proxy 模式初始页 |
| windows-settings.png | docs/validation/ui-settings.png | 连接方式、修复项目与样例路径 |
| windows-completed.png | docs/validation/ui-completed.png | 隔离修复结果和还原按钮 |

这些是测试渲染，不能作为桌面 Acrylic 效果或真实网络保护已生效的证据。`scripts/Build.ps1` 只将本目录 PNG 放入便携包，`scripts/Test-Package.ps1` 检查 README 引用的图片是否存在。
