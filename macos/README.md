# ProxyVeil macOS

The macOS entry point is an explicit command-line adapter for FlClash. It
supports legacy `shared_preferences.json` and newer native preferences with
SQLite schema 10 and profile YAML files under Application Support.

The installed app's CFBundleIdentifier determines the preference domain.
Only the current-user/any-host `flutter.config` string is changed through
CoreFoundation. SQLite is read-only; applied `config.yaml` is never replaced.
Unknown schemas, types, inconsistent profile IDs and pending WAL fail before
writes. Exit FlClash completely before new-layout repair/restore so its cached
preferences cannot overwrite changes. Native acceptance on the actual Mac is
still pending; the earlier host validation predates this adapter.

```sh
./scripts/Launch-macOS.sh inspect --install-path /Applications/FlClash.app --config-directory "$HOME/Library/Application Support/com.follow.clash"
./scripts/Launch-macOS.sh repair --mode TUN --items DNS IPv6 --install-path /Applications/FlClash.app --config-directory "$HOME/Library/Application Support/com.follow.clash"
./scripts/Launch-macOS.sh restore --install-path /Applications/FlClash.app --config-directory "$HOME/Library/Application Support/com.follow.clash"
```

The adapter writes only after the user invokes `repair`. It creates a local
snapshot, uses an advisory lock, writes files atomically, and refuses restore
when the profile, managed preferences or backup conflict. New snapshots merge
unrelated preference fields and accept partially restored resources on retry.
Existing schema 1 snapshots remain readable. The default state directory is
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
python3 scripts/Test-macOS-Portable.py
python3 scripts/Test-macOS-Preferences.py
```

For Windows-hosted development, run `python scripts/Test-macOS-Portable.py`
with the available Python runtime. It calls the same adapter functions on
generated temporary fixtures and tests the host's native file lock. Windows
uses msvcrt; macOS uses flock. The production CLI remains macOS-only.
Results are saved in `docs/validation/macos-portable.json` and
`docs/validation/macos-preferences.json`. Generated XML/binary plist and SQLite
fixtures exercise production recovery; they do not validate CoreFoundation,
macOS flock, application restart, permissions or network behavior. Follow
[the Mac acceptance steps](../docs/validation/macos-acceptance.md) on the Mac.
macOS browser DoH and WebRTC are not configured. Proxy mode controls FlClash's
resolver and routes; browser/system DNS behavior needs separate verification.

The Windows follow-up acceptance checklist is in
[windows-stage2.md](../docs/validation/windows-stage2.md).
