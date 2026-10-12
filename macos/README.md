# ProxyVeil macOS MVP

The macOS entry point is an explicit command-line adapter for FlClash. It
supports FlClash 0.8.x style `shared_preferences.json` and profile YAML files
under the macOS Application Support directory.

The adapter deliberately rejects other layouts. On the current test Mac,
FlClash 0.8.99 stores `config.yaml`, `database.sqlite`, and profile YAML files
under `~/Library/Application Support/com.follow.clash`; that layout is recorded
in [macOS host validation](../docs/validation/macos-host.json) and is not yet a
supported repair target.

```sh
./scripts/Launch-macOS.sh inspect
./scripts/Launch-macOS.sh repair --mode Proxy --items DNS IPv6 --proxy-group Proxy
./scripts/Launch-macOS.sh restore
```

The adapter writes only after the user invokes `repair`. It creates a local
snapshot, uses an advisory lock, writes files atomically, and refuses restore
when either the live file or backup has changed. The default state directory is
`~/Library/Application Support/ProxyVeil`; use `--state-directory` for an
isolated test directory.

macOS has no Windows registry or `FlClashHelperService`, so the Windows Edge
WebRTC policy is reported as skipped. TUN permission and Network Extension
approval remain controlled by FlClash and macOS. The MVP changes FlClash's
configuration only; it does not run `sudo`, modify physical interfaces, or
change system firewall/DNS settings.

Test offline with:

```sh
python3 scripts/Test-macOS.py
```

The Windows follow-up acceptance checklist is in
[windows-stage2.md](../docs/validation/windows-stage2.md).
