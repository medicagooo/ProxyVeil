# ADR 0002: macOS FlClash adapter

2026-10-13 / accepted for the macOS MVP.

The existing PowerShell/WPF implementation remains the Windows product. A
small Python adapter is added for macOS because WPF, DWM, UAC, Windows
registry, and `FlClashHelperService` have no macOS equivalent. The adapter
shares the documented FlClash data contract but keeps platform operations
separate.

The MVP supports explicit `inspect`, `repair`, and `restore` commands for
DNS, TUN/Proxy mode, and FlClash IPv6 settings. It stores snapshots under the
user's Application Support directory, uses `flock` and atomic replacement, and
rejects external drift. It does not claim to configure Edge WebRTC on macOS;
that requires a configuration profile or MDM policy and is reported as a
skipped item.

The adapter supports the block YAML format already accepted by the Windows
adapter. Anchors, multi-document YAML, inline maps, and unsupported layouts
fail before mutation. This keeps the recovery guarantee reviewable without
adding a third-party dependency to the offline build.
