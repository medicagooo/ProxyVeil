# Mac 后续验收

本轮在 Windows 开发，原生 CoreFoundation、macOS flock、FlClash 重启及网络未验收。先更新 main 并记录实际提交：

```sh
git pull --ff-only
git rev-parse HEAD
python3 scripts/Test-macOS.py
python3 scripts/Test-macOS-Portable.py
python3 scripts/Test-macOS-Preferences.py
```

确认 Python 3 可用。关闭 FlClash 后执行只读检查，不输出偏好值、订阅或节点：

```sh
./scripts/Launch-macOS.sh inspect --install-path /Applications/FlClash.app --config-directory "$HOME/Library/Application Support/com.follow.clash"
```

通过标准：status=Inspected，preferencesType=string、databaseSchema=10，profile 路径与当前选择一致，preferencesDomain 来自安装包。键缺失、非字符串、未知 schema 或 WAL 未收束应返回 Failed，且配置与本地快照不变。实际域/键仍需这一步确认，夹具不能替代。

准备可恢复的测试配置，明确要在这台 Mac 修改配置后，退出 FlClash，再执行：

```sh
./scripts/Launch-macOS.sh repair --mode TUN --items DNS IPv6 --install-path /Applications/FlClash.app --config-directory "$HOME/Library/Application Support/com.follow.clash"
```

启动 FlClash，确认当前 profile、订阅、选择的节点未变；检查 TUN 与 IPv6 选项是否采用。测试国内站点、代理站点和 DNS，记录浏览器的 IPv6/DNS/WebRTC 结果及测试时间。WebRTC 和 Mac 浏览器 DoH 未被此工具配置，应单独说明；系统/浏览器 DNS 不能从 YAML 推断。

退出 FlClash后，执行 restore 并保留相同 install/config 路径：

```sh
./scripts/Launch-macOS.sh restore --install-path /Applications/FlClash.app --config-directory "$HOME/Library/Application Support/com.follow.clash"
```

确认 status=Restored、active=false；再次启动 FlClash，确认原配置与网络恢复。Proxy 模式另做一轮，用 --mode Proxy；仅 FlClash resolver 与路由在本轮范围内。应用运行时 repair/restore 必须拒绝；managed drift 和中断恢复场景通过夹具测试，不对真实订阅刻意制造故障。

报告仅记录 OS/FlClash/Python 版本、Git SHA、域与键类型、测试通过/失败、无凭据错误摘要。不要提交 active.json、偏好值、数据库、profile 或 .bak。失败时保留本地快照，先诊断再重试。
