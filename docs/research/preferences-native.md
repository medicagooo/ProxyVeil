# Native preference contract

Retrieved 2026-10-12. FlClash's pinned contract and Flutter SharedPreferences
sources are in [local-development.md](local-development.md). The actual installed
bundle identifier and flutter.config type are verified at runtime, without
printing their values. Native write/restart acceptance remains a Mac task.

Apple's [CFPreferencesCopyValue](https://developer.apple.com/documentation/corefoundation/cfpreferencescopyvalue(_:_:_:_:))
reads only the specified domain; copied objects must be released.
[CFPreferencesSetValue](https://developer.apple.com/documentation/corefoundation/cfpreferencessetvalue(_:_:_:_:_:))
sets the specified key in that domain.
[CFPreferencesSynchronize](https://developer.apple.com/documentation/corefoundation/cfpreferencessynchronize(_:_:_:))
writes pending changes and reads persistent data. Therefore inspect never calls
Synchronize. Writes synchronize and verify the returned preference string.
The implementation uses current user and any host, with explicit CFString type
checks; no global-domain fallback is used.

[CFStringGetCString](https://developer.apple.com/documentation/corefoundation/cfstringgetcstring(_:_:_:_:))
requires room for a NUL terminator;
[CFStringGetMaximumSizeForEncoding](https://developer.apple.com/documentation/corefoundation/cfstringgetmaximumsizeforencoding(_:_:))
provides an upper bound. ctypes signatures mirror CoreFoundation pointer,
CFIndex, CFTypeID and Boolean types. This ABI is source-supported, but has not
been executed on the current Windows host.

SQLite's [URI parameters](https://www.sqlite.org/uri.html) document mode=ro and
immutable=1. Immutable bypasses locking and change detection, so this adapter
requires FlClash to be stopped for writes and rejects WAL/journal sidecars.
The connection selects only schema version and the active profile ID, closes
explicitly and never creates a schema or writes data. Generated fixtures
assert unchanged database bytes and no WAL/SHM creation.

The preference engine cannot provide atomicity across a file and a native key.
It records both before/after resources first, verifies backups, and retains
the active manifest after partial failure. New snapshots merge only the
managed leaves. Existing JSON/schema-1 snapshots retain their strict full-file
conflict behavior. Concurrent unrelated writers are not coordinated by the
ProxyVeil lock; quitting FlClash and checking drift remain required.
