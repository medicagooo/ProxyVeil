"""Preference storage for the CLI and generated plist recovery fixtures.

NativePreferences owns only flutter.config in the bundle's current-user,
any-host domain. It never edits a plist on disk or passes values to a process.
See docs/agents/domain.md for callers and recovery constraints.
"""
from __future__ import annotations

import contextlib
import ctypes
import json
from pathlib import Path
import plistlib
import sqlite3
import sys


KEY = "flutter.config"


class PreferenceError(RuntimeError):
    pass


def profile_index(config: Path, profile_id: int) -> int:
    """Verify one profile using a read-only connection to a quiescent database."""
    database = config / "database.sqlite"
    if not database.is_file() or database.is_symlink():
        raise PreferenceError("缺少受支持的 profile 索引。")
    for suffix in ("-wal", "-journal"):
        sidecar = Path(str(database) + suffix)
        if sidecar.exists() and sidecar.stat().st_size:
            raise PreferenceError("数据库存在未收束的日志，请退出 FlClash 后重试。")
    # immutable avoids creating SQLite sidecars; a stopped app and no journal
    # are required because SQLite will not replay WAL in this connection.
    try:
        with contextlib.closing(sqlite3.connect(database.resolve().as_uri() + "?mode=ro&immutable=1", uri=True)) as db:
            version = db.execute("PRAGMA user_version").fetchone()[0]
            if version != 10:
                raise PreferenceError("SQLite schema 不兼容，未修改。")
            rows = db.execute('SELECT id FROM profiles WHERE id = ?', (profile_id,)).fetchall()
            if rows != [(profile_id,)]:
                raise PreferenceError("偏好与 profile 索引不一致。")
            return version
    except sqlite3.Error as exc:
        raise PreferenceError("无法只读核对 profile 索引。") from exc


class PlistPreferences:
    """Generated XML/binary fixtures only; production never constructs this store."""

    def __init__(self, path: Path, domain: str):
        self.path, self.domain = path, domain

    def read(self) -> str:
        value = plistlib.loads(self.path.read_bytes()).get(KEY)
        if not isinstance(value, str):
            raise PreferenceError("flutter.config 必须是字符串。")
        return value

    def write(self, value: str) -> None:
        raw = self.path.read_bytes()
        outer = plistlib.loads(raw)
        outer[KEY] = value
        fmt = plistlib.FMT_BINARY if raw.startswith(b"bplist") else plistlib.FMT_XML
        self.path.write_bytes(plistlib.dumps(outer, fmt=fmt))


class NativePreferences:
    def __init__(self, domain: str):
        if sys.platform != "darwin":
            raise PreferenceError("原生偏好仅支持 macOS。")
        self.domain = domain
        cf = self.cf = ctypes.CDLL('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation')
        signatures = {
            'CFStringCreateWithCString': ([ctypes.c_void_p, ctypes.c_char_p, ctypes.c_uint32], ctypes.c_void_p),
            'CFRelease': ([ctypes.c_void_p], None),
            'CFGetTypeID': ([ctypes.c_void_p], ctypes.c_ulong),
            'CFStringGetTypeID': ([], ctypes.c_ulong),
            'CFStringGetLength': ([ctypes.c_void_p], ctypes.c_long),
            'CFStringGetMaximumSizeForEncoding': ([ctypes.c_long, ctypes.c_uint32], ctypes.c_long),
            'CFStringGetCString': ([ctypes.c_void_p, ctypes.c_void_p, ctypes.c_long, ctypes.c_uint32], ctypes.c_ubyte),
            'CFPreferencesCopyValue': ([ctypes.c_void_p] * 4, ctypes.c_void_p),
            'CFPreferencesSetValue': ([ctypes.c_void_p] * 5, None),
            'CFPreferencesSynchronize': ([ctypes.c_void_p] * 3, ctypes.c_ubyte),
        }
        for name, (args, result) in signatures.items():
            func = getattr(cf, name)
            func.argtypes, func.restype = args, result
        self.user = ctypes.c_void_p.in_dll(cf, 'kCFPreferencesCurrentUser').value
        self.host = ctypes.c_void_p.in_dll(cf, 'kCFPreferencesAnyHost').value

    @contextlib.contextmanager
    def strings(self, *values):
        pointers = []
        try:
            for value in values:
                if '\0' in value:
                    raise PreferenceError("偏好字符串含不支持的空字符。")
                ptr = self.cf.CFStringCreateWithCString(None, value.encode('utf-8'), 0x08000100)
                if not ptr:
                    raise PreferenceError("无法创建原生偏好字符串。")
                pointers.append(ptr)
            yield pointers
        finally:
            for ptr in pointers:
                self.cf.CFRelease(ptr)

    def read(self) -> str:
        with self.strings(KEY, self.domain) as (key, domain):
            # Read does not call Synchronize: that API can flush pending writes.
            ptr = self.cf.CFPreferencesCopyValue(key, domain, self.user, self.host)
            if not ptr:
                raise PreferenceError("当前应用偏好域缺少 flutter.config；请先打开 FlClash 并选择配置。")
            try:
                if self.cf.CFGetTypeID(ptr) != self.cf.CFStringGetTypeID():
                    raise PreferenceError("flutter.config 必须是字符串。")
                size = self.cf.CFStringGetMaximumSizeForEncoding(self.cf.CFStringGetLength(ptr), 0x08000100) + 1
                buffer = ctypes.create_string_buffer(size)
                if not self.cf.CFStringGetCString(ptr, buffer, size, 0x08000100):
                    raise PreferenceError("无法读取原生偏好字符串。")
                return buffer.value.decode('utf-8')
            finally:
                self.cf.CFRelease(ptr)

    def write(self, value: str) -> None:
        with self.strings(KEY, self.domain, value) as (key, domain, payload):
            self.cf.CFPreferencesSetValue(key, payload, domain, self.user, self.host)
            if not self.cf.CFPreferencesSynchronize(domain, self.user, self.host):
                raise PreferenceError("原生偏好同步失败；快照已保留。")


def bundle_domain(executable: Path | None) -> str:
    if executable is None:
        raise PreferenceError("新布局需要 --install-path 指向 FlClash.app。")
    info = executable.parent.parent / 'Info.plist'
    try:
        value = plistlib.loads(info.read_bytes()).get('CFBundleIdentifier')
    except (OSError, ValueError, plistlib.InvalidFileException) as exc:
        raise PreferenceError("无法核对 FlClash bundle 标识。") from exc
    if not isinstance(value, str) or not value or not all(c.isalnum() or c in '.-_' for c in value):
        raise PreferenceError("应用偏好域无效。")
    return value


MANAGED = (
    ('networkProps', 'appendSystemDns'), ('networkProps', 'systemProxy'),
    ('patchClashConfig', 'tun', 'enable'), ('patchClashConfig', 'ipv6'), ('overrideDns',),
)


def merge_restore(before: str, after: str, current: str) -> str:
    """Revert only managed leaves; preserve unrelated settings and absent keys."""
    try:
        old, expected, now = (json.loads(v) for v in (before, after, current))
        if not all(isinstance(v, dict) for v in (old, expected, now)):
            raise ValueError()
        if old.get('currentProfileId') != expected.get('currentProfileId') or now.get('currentProfileId') != old.get('currentProfileId'):
            raise PreferenceError("当前 profile 已切换，停止还原。")
        old_unmanaged, after_unmanaged = (json.loads(v) for v in (before, after))
        for obj in (old_unmanaged, after_unmanaged):
            for path in MANAGED:
                parent = obj
                for part in path[:-1]:
                    parent = parent.get(part, {})
                    if not isinstance(parent, dict):
                        raise PreferenceError('偏好备份结构无效。')
                parent.pop(path[-1], None)
        if old_unmanaged != after_unmanaged:
            raise PreferenceError('偏好备份包含非受管字段修改。')
        sentinel = object()
        def leaf(obj, path):
            for part in path:
                if not isinstance(obj, dict):
                    raise PreferenceError("偏好结构被外部修改。")
                obj = obj.get(part, sentinel)
            return obj
        for path in MANAGED:
            previous, written = leaf(old, path), leaf(expected, path)
            if previous == written:
                continue
            actual = leaf(now, path)
            if actual != previous and actual != written:
                raise PreferenceError("受管偏好被外部修改，快照已保留。")
            parent = now
            for part in path[:-1]:
                parent = parent[part]
            if previous is sentinel:
                parent.pop(path[-1], None)
            else:
                parent[path[-1]] = previous
        return json.dumps(now, ensure_ascii=False, separators=(',', ':'))
    except (ValueError, TypeError, KeyError) as exc:
        raise PreferenceError("恢复偏好格式无效。") from exc
