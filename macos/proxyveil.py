#!/usr/bin/env python3
"""ProxyVeil macOS adapter for FlClash.

This is the macOS MVP entry point. It deliberately owns only macOS concerns
and the small, supported FlClash text format. Repair and restore are always
explicit subcommands; importing or inspecting a configuration never writes.
"""

from __future__ import annotations

import argparse
import contextlib
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
from typing import Any, Iterable

from preferences import NativePreferences, PreferenceError, bundle_domain, merge_restore, profile_index


APP_SUPPORT = Path.home() / "Library" / "Application Support"
STATE_DIR = APP_SUPPORT / "ProxyVeil"
PREFERENCE_FILE = "shared_preferences.json"
GENERATED_RULES = (
    'IP-CIDR,1.1.1.1/32,{group},no-resolve',
    'IP-CIDR,8.8.8.8/32,{group},no-resolve',
)


ProxyVeilError = PreferenceError


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def valid_hash(value: Any) -> bool:
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def atomic_bytes(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=f".{path.name}.proxyveil-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
    finally:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(name)


def secure_file(path: Path) -> None:
    with contextlib.suppress(OSError):
        os.chmod(path, 0o600)


def json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n").encode()


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise ProxyVeilError(f"无法读取 JSON：{path.name}") from exc


def expand_path(value: str | None) -> Path | None:
    if not value:
        return None
    return Path(os.path.expandvars(os.path.expanduser(value.strip().strip('"')))).resolve()


def resolve_app(hint: str | None) -> Path | None:
    candidates: list[Path] = []
    if hint:
        candidates.append(expand_path(hint))  # type: ignore[arg-type]
    candidates.extend(
        [
            Path("/Applications/FlClash.app"),
            Path.home() / "Applications" / "FlClash.app",
        ]
    )
    for app in candidates:
        if app.is_file() and app.name == "FlClash":
            return app
        if app.is_dir() and app.suffix == ".app":
            executable = app / "Contents" / "MacOS" / "FlClash"
            if executable.exists():
                return executable
    for process in ("FlClash", "flclash"):
        found = shutil.which(process)
        if found:
            return Path(found).resolve()
    return None


def candidate_config_dirs(executable: Path | None) -> Iterable[Path]:
    known = [
        APP_SUPPORT / "com.follow.clash",
        APP_SUPPORT / "com.follow.FlClash",
        APP_SUPPORT / "FlClash",
        APP_SUPPORT / "com.follow" / "clash",
    ]
    if executable:
        app = executable
        for parent in (app.parent, app.parent.parent, app.parent.parent.parent):
            known.extend([parent / "data", parent / "config"])
    seen: set[Path] = set()
    for path in known:
        if path not in seen:
            seen.add(path)
            yield path
    if APP_SUPPORT.exists():
        # FlClash uses path_provider's Application Support directory. Scan only
        # one level to avoid traversing unrelated application data.
        for path in APP_SUPPORT.iterdir():
            if path.is_dir() and path not in seen:
                seen.add(path)
                yield path


def resolve_config(hint: str | None, executable: Path | None) -> Path:
    if hint:
        path = expand_path(hint)
        if path and ((path / PREFERENCE_FILE).is_file() or ((path / 'database.sqlite').is_file() and (path / 'profiles').is_dir())):
            return path
        raise ProxyVeilError("ConfigDirectory 必须包含 JSON 偏好或 SQLite/profile 布局。")
    for path in candidate_config_dirs(executable):
        if (path / PREFERENCE_FILE).is_file() or ((path / 'database.sqlite').is_file() and (path / 'profiles').is_dir()):
            return path
    raise ProxyVeilError("未找到 FlClash 配置目录，请使用 --config-directory。")


def find_section(text: str, name: str) -> tuple[list[str], int, int, str] | None:
    lines = text.replace("\r\n", "\n").splitlines()
    matches = [i for i, line in enumerate(lines) if re.match(rf"^{re.escape(name)}:\s*", line)]
    if len(matches) > 1:
        raise ProxyVeilError(f"重复的 YAML 顶层字段：{name}")
    if not matches:
        return None
    start = matches[0]
    end = len(lines)
    for i in range(start + 1, len(lines)):
        if re.match(r"^[^\s#-][^:]*:\s*", lines[i]) or re.match(r"^(---|\.\.\.)\s*$", lines[i]):
            end = i
            break
    tail = re.sub(rf"^{re.escape(name)}:\s*", "", lines[start]).strip()
    return lines, start, end, tail


def section_text(text: str, name: str) -> str:
    section = find_section(text, name)
    if not section:
        return ""
    lines, start, end, _ = section
    return "\n".join(lines[start:end]).rstrip()


def set_yaml_field(text: str, section_name: str, field: str, values: list[str], *, as_list: bool = False) -> str:
    section = find_section(text, section_name)
    lines = text.replace("\r\n", "\n").splitlines()
    if section is None:
        text = text.rstrip("\n") + f"\n{section_name}:\n"
        section = find_section(text, section_name)
        assert section is not None
        lines, start, end, tail = section
    else:
        lines, start, end, tail = section
    if tail and not re.fullmatch(r"(?:#.*|\{\s*\}|null|~)", tail):
        raise ProxyVeilError(f"不支持 {section_name} 的内联映射，未写入配置。")
    body = lines[start + 1 : end]
    indent = None
    for line in body:
        if "\t" in line:
            raise ProxyVeilError(f"{section_name} 存在 Tab 缩进，未写入配置。")
        match = re.match(r"^( +)[\w-]+\s*:", line)
        if match:
            indent = min(indent, len(match.group(1))) if indent is not None else len(match.group(1))
    indent = indent or 2
    padding = " " * indent
    seen = set()
    for line in body:
        match = re.match(rf'^{re.escape(padding)}([\w-]+)\s*:', line)
        if match:
            if match.group(1) in seen:
                raise ProxyVeilError(f'重复 YAML 字段：{section_name}.{match.group(1)}')
            seen.add(match.group(1))
        if re.match(rf'''^{re.escape(padding)}(?:<<\s*:|["'&*!])''', line):
            raise ProxyVeilError(f'{section_name} 包含复杂映射键，未修改。')
    key_re = re.compile(rf"^{re.escape(padding)}{re.escape(field)}\s*:")
    starts = [i for i, line in enumerate(body) if key_re.match(line)]
    if len(starts) > 1:
        raise ProxyVeilError(f"重复 YAML 字段：{section_name}.{field}")
    insert_at = len(body)
    if starts:
        insert_at = starts[0]
        end_at = len(body)
        key_any = re.compile(rf"^{re.escape(padding)}[\w-]+\s*:")
        for i in range(insert_at + 1, len(body)):
            if key_any.match(body[i]):
                end_at = i
                break
        del body[insert_at:end_at]
    rendered = [f"{padding}{field}:"] + [f"{padding}  - {v}" for v in values] if as_list else [f"{padding}{field}: {values[0]}"]
    body[insert_at:insert_at] = rendered
    return "\n".join(lines[:start] + [f"{section_name}:"] + body + lines[end:]).rstrip("\n") + "\n"


def set_top_level_scalar(text: str, name: str, value: str) -> str:
    section = find_section(text, name)
    lines = text.replace("\r\n", "\n").splitlines()
    if section:
        _, start, end, _ = section
        lines[start:end] = [f"{name}: {value}"]
    else:
        lines.insert(0, f"{name}: {value}")
    return "\n".join(lines).rstrip("\n") + "\n"


def yaml_scalar(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def read_yaml_scalar(raw: str) -> str:
    if raw.startswith('"'):
        match = re.fullmatch(r'("(?:[^"\\]|\\.)*")\s*(?:#.*)?', raw)
        if not match:
            raise ProxyVeilError('不支持的 YAML 双引号标量。')
        try:
            return json.loads(match.group(1))
        except ValueError as exc:
            raise ProxyVeilError('不支持的 YAML 双引号转义。') from exc
    if raw.startswith("'"):
        match = re.fullmatch(r"('(?:[^']|'')*')\s*(?:#.*)?", raw)
        if not match:
            raise ProxyVeilError('不支持的 YAML 单引号标量。')
        return match.group(1)[1:-1].replace("''", "'")
    raw = re.sub(r'\s+#.*$', '', raw).strip()
    if not raw or raw[0] in '[{&*!>|':
        raise ProxyVeilError('不支持的 YAML 标量。')
    return raw


def proxy_groups(text: str) -> list[str]:
    section = find_section(text, "proxy-groups")
    if not section or (section[3] and not section[3].startswith('#')):
        raise ProxyVeilError("需要块格式的 proxy-groups。")
    lines, start, end, _ = section
    names: list[str] = []
    for line in lines[start + 1 : end]:
        match = re.match(r"^\s*(?:-\s+)?name:\s*(.+?)\s*$", line)
        if match:
            raw = read_yaml_scalar(match.group(1).strip())
            names.append(raw)
    if not names:
        raise ProxyVeilError("未检测到代理组名称。")
    return names


def select_group(text: str, requested: str | None) -> str:
    names = proxy_groups(text)
    if any(',' in name or '#' in name or '\n' in name or '\r' in name for name in names) or len(names) != len(set(names)):
        raise ProxyVeilError('代理组名称含分隔符或重复，无法安全生成 DNS 路由。')
    if requested:
        if requested not in names or requested in {"DIRECT", "REJECT", "PASS"}:
            raise ProxyVeilError("指定代理组不存在或不是代理组。")
        return requested
    rules = section_text(text, "rules")
    for line in rules.splitlines():
        item = re.match(r'^\s*-\s*(.+?)\s*$', line)
        match = re.fullmatch(r'(?:MATCH|FINAL),(.+)', read_yaml_scalar(item.group(1))) if item else None
        if match and match.group(1) in names:
            return match.group(1)
    usable = [name for name in names if name not in {"DIRECT", "REJECT", "PASS"}]
    if len(usable) == 1:
        return usable[0]
    raise ProxyVeilError("无法自动选定 DNS 代理组，请使用 --proxy-group。")


def insert_proxy_rules(text: str, group: str) -> str:
    section = find_section(text, "rules")
    if not section or (section[3] and not section[3].startswith('#')):
        raise ProxyVeilError("Proxy 模式需要块格式 rules。")
    lines, start, end, _ = section
    indent = "  "
    for line in lines[start + 1 : end]:
        match = re.match(r"^( *)-\s+", line)
        if match:
            indent = match.group(1)
            break
    generated = [yaml_scalar(template.format(group=group)) for template in GENERATED_RULES]
    body = lines[start + 1 : end]
    body = [line for line in body if not any(line.strip() == f"- {item}" for item in generated)]
    body[0:0] = [f"{indent}- {item}" for item in generated]
    return "\n".join(lines[:start + 1] + body + lines[end:]).rstrip("\n") + "\n"


def native_store(args, executable, *, writing=False):
    domain = bundle_domain(executable)
    requested = getattr(args, 'preferences_domain', None)
    if requested and requested != domain:
        raise ProxyVeilError("偏好域与应用 bundle 标识不一致。")
    if writing:
        running = subprocess.run(['/usr/bin/pgrep', '-x', 'FlClash'], capture_output=True, check=False)
        if running.returncode != 1:
            raise ProxyVeilError("请完全退出 FlClash 后执行 repair/restore。")
    return NativePreferences(domain)


def context(config_dir: Path, store=None) -> dict[str, Any]:
    preferences = config_dir / PREFERENCE_FILE
    try:
        if store is None:
            preferences_bytes = preferences.read_bytes()
            outer = json.loads(preferences_bytes.decode("utf-8"))
        else:
            outer = {'flutter.config': store.read()}
            preferences_bytes = json_bytes(outer)
    except (OSError, UnicodeDecodeError, ValueError) as exc:
        raise ProxyVeilError(f"无法读取 JSON：{preferences.name}") from exc
    if not isinstance(outer, dict) or not isinstance(outer.get("flutter.config"), str):
        raise ProxyVeilError("无法识别 FlClash 偏好结构。")
    try:
        inner = json.loads(outer["flutter.config"])
    except ValueError as exc:
        raise ProxyVeilError("无法解析 FlClash 内部偏好。") from exc
    if not isinstance(inner, dict) or type(inner.get("currentProfileId")) is not int or inner['currentProfileId'] < 0:
        raise ProxyVeilError("请先在 FlClash 选择一个配置。")
    if not isinstance(inner.get("networkProps"), dict) or not isinstance(inner.get("patchClashConfig"), dict):
        raise ProxyVeilError("FlClash 偏好版本不兼容，未修改。")
    if not isinstance(inner["patchClashConfig"].get("tun"), dict):
        raise ProxyVeilError("FlClash TUN 偏好结构不兼容，未修改。")
    profile = config_dir / "profiles" / f"{inner['currentProfileId']}.yaml"
    if profile.is_symlink() or profile.resolve().parent != (config_dir.resolve() / 'profiles'):
        raise ProxyVeilError("profile 路径越出配置目录，未修改。")
    if not profile.is_file():
        raise ProxyVeilError("找不到当前 FlClash 配置 YAML。")
    try:
        profile_bytes = profile.read_bytes()
        profile_text = profile_bytes.decode("utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        raise ProxyVeilError("当前 FlClash 配置 YAML 不可读取。") from exc
    schema = profile_index(config_dir, inner['currentProfileId']) if store else None
    return {"preferences": preferences, "profile": profile, "outer": outer, "inner": inner, "profile_text": profile_text, "preferences_hash": hashlib.sha256(preferences_bytes).hexdigest(), "profile_hash": hashlib.sha256(profile_bytes).hexdigest(), 'store': store, 'databaseSchema': schema}


def plan(ctx: dict[str, Any], mode: str, items: list[str], group: str | None) -> tuple[bytes, bytes, str | None, dict[str, str]]:
    text = ctx["profile_text"]
    if re.search(r'''^["'][^\n]+["']\s*:''', text, re.MULTILINE):
        raise ProxyVeilError('不支持带引号的 YAML 顶层键，未修改。')
    if re.search(r'^(?:---|\.\.\.)\s*(?:#.*)?$', text, re.MULTILINE) or text.startswith('\ufeff'):
        raise ProxyVeilError('不支持带文档标记或 BOM 的 YAML，未修改。')
    if re.search(r'(?:^\s*<<\s*:|:\s+[&*][\w-]+|^\s*-\s+[&*][\w-]+)', text, re.MULTILINE):
        raise ProxyVeilError('不支持 YAML 锚点或合并键，未修改。')
    original_sections = {name: section_text(text, name) for name in ("proxies", "proxy-groups", "proxy-providers", "rule-providers")}
    inner = json.loads(json.dumps(ctx["inner"]))
    outer = json.loads(json.dumps(ctx["outer"]))
    policies: dict[str, str] = {}
    selected_group = None
    if "DNS" in items:
        selected_group = select_group(text, group)
        text = set_yaml_field(text, "dns", "enable", ["true"])
        text = set_yaml_field(text, "dns", "respect-rules", ["true"])
        text = set_yaml_field(text, "dns", "nameserver", [yaml_scalar(f"https://1.1.1.1/dns-query#{selected_group}"), yaml_scalar(f"https://8.8.8.8/dns-query#{selected_group}")], as_list=True)
        text = set_yaml_field(text, "dns", "nameserver-policy", ["{}"])
        text = set_yaml_field(text, "dns", "fallback", ["[]"])
        text = set_yaml_field(text, "dns", "direct-nameserver", ["[]"])
        bootstrap = [yaml_scalar("https://223.5.5.5/dns-query#DIRECT"), yaml_scalar("https://223.6.6.6/dns-query#DIRECT")]
        text = set_yaml_field(text, "dns", "default-nameserver", bootstrap, as_list=True)
        text = set_yaml_field(text, "dns", "proxy-server-nameserver", bootstrap, as_list=True)
        text = set_yaml_field(text, "dns", "proxy-server-nameserver-policy", ["{}"])
        text = set_yaml_field(text, "dns", "prefer-h3", ["false"])
        inner.setdefault("networkProps", {})["appendSystemDns"] = False
        inner["networkProps"]["systemProxy"] = mode == "Proxy"
        inner["patchClashConfig"]["tun"]["enable"] = mode == "TUN"
        inner["overrideDns"] = False
        text = set_yaml_field(text, "tun", "enable", ["true" if mode == "TUN" else "false"])
        if mode == "TUN":
            for field in ("auto-route", "auto-detect-interface", "strict-route"):
                text = set_yaml_field(text, "tun", field, ["true"])
            text = set_yaml_field(text, "tun", "dns-hijack", ["any:53", "tcp://any:53"], as_list=True)
        else:
            text = insert_proxy_rules(text, selected_group)
    if "IPv6" in items:
        inner.setdefault("patchClashConfig", {})["ipv6"] = False
        text = set_top_level_scalar(text, "ipv6", "false")
        text = set_yaml_field(text, 'dns', 'ipv6', ['false'])
    for name, original in original_sections.items():
        if section_text(text, name) != original:
            raise ProxyVeilError(f"保护检查失败：{name}")
    outer["flutter.config"] = json.dumps(inner, ensure_ascii=False, separators=(",", ":"))
    return text.encode(), json_bytes(outer), selected_group, policies


@contextlib.contextmanager
def operation_lock(state: Path):
    """Serialize fixture and production operations using the host's native lock.

    Windows-hosted tests call the same repair/restore functions in temporary
    directories. The production CLI still rejects hosts other than macOS;
    macOS retains flock. See docs/local-development-plan.md for coverage.
    """
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    with contextlib.suppress(OSError):
        os.chmod(state, 0o700)
    path = state / "operation.lock"
    if sys.platform == "win32":
        import msvcrt

        with path.open("a+b") as stream:
            stream.seek(0)
            try:
                msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
            except OSError as exc:
                raise ProxyVeilError("已有操作正在执行，或无法获取操作锁。") from exc
            try:
                yield
            finally:
                stream.seek(0)
                msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
        return

    import fcntl

    with path.open("a+") as stream:
        try:
            fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise ProxyVeilError("已有操作正在执行。") from exc
        try:
            yield
        finally:
            fcntl.flock(stream.fileno(), fcntl.LOCK_UN)


def inspect(args: argparse.Namespace) -> dict[str, Any]:
    executable = resolve_app(args.install_path)
    config = resolve_config(args.config_directory, executable)
    store = None if (config / PREFERENCE_FILE).is_file() else native_store(args, executable)
    ctx = context(config, store)
    return {"status": "Inspected", "installPath": str(executable) if executable else None, "configDirectory": str(config), "profile": str(ctx["profile"]), 'preferencesDomain': store.domain if store else None, 'preferencesKey': 'flutter.config', 'preferencesType': 'string', 'databaseSchema': ctx['databaseSchema'], "webRtc": "unsupported-on-macos", "active": (STATE_DIR / "active.json").exists()}


def repair(args: argparse.Namespace) -> dict[str, Any]:
    if not args.items:
        raise ProxyVeilError("请选择至少一项修复项目。")
    invalid = set(args.items) - {"DNS", "IPv6", "WebRTC"}
    if invalid:
        raise ProxyVeilError(f"未知修复项目：{', '.join(sorted(invalid))}")
    if "WebRTC" in args.items and len(args.items) == 1:
        return {"status": "Partial", "items": [{"id": "WebRTC", "status": "skipped", "detail": "macOS 不使用 Windows Edge 注册表策略，请通过配置描述文件管理。"}], "active": (STATE_DIR / "active.json").exists()}
    executable = resolve_app(args.install_path)
    config = resolve_config(args.config_directory, executable)
    store = None if (config / PREFERENCE_FILE).is_file() else native_store(args, executable, writing=True)
    ctx = context(config, store)
    file_plan, preferences_plan, selected_group, policies = plan(ctx, args.mode, [i for i in args.items if i != "WebRTC"], args.proxy_group)
    if store:
        return repair_native(args, config, ctx, file_plan, preferences_plan, selected_group)
    with operation_lock(STATE_DIR):
        if (STATE_DIR / "active.json").exists():
            raise ProxyVeilError("已有快照，请先 restore；不会覆盖最初备份。")
        if sha256(ctx["profile"]) != ctx["profile_hash"] or sha256(ctx["preferences"]) != ctx["preferences_hash"]:
            raise ProxyVeilError("配置在检查后发生改变，停止写入。")
        manifest = {"schema": 1, "platform": "macos", "id": f"{time.time_ns():x}", "mode": args.mode, "items": args.items, "configDirectory": str(config), "files": []}
        for path, payload, label in ((ctx["profile"], file_plan, "profile"), (ctx["preferences"], preferences_plan, "preferences")):
            before = sha256(path)
            backup = STATE_DIR / f"{manifest['id']}-{label}.bak"
            shutil.copyfile(path, backup)
            secure_file(backup)
            record = {"path": str(path), "label": label, "backup": str(backup), "beforeHash": before, "afterHash": hashlib.sha256(payload).hexdigest()}
            manifest["files"].append(record)
        atomic_bytes(STATE_DIR / "active.json", json_bytes(manifest))
        secure_file(STATE_DIR / "active.json")
        try:
            for record, payload in zip(manifest["files"], (file_plan, preferences_plan)):
                path = Path(record["path"])
                if sha256(path) != record["beforeHash"]:
                    raise ProxyVeilError("配置在备份后发生改变，停止写入。")
                atomic_bytes(path, payload)
                if sha256(path) != record["afterHash"]:
                    raise ProxyVeilError("配置读回失败。")
            return {"status": "Partial" if "WebRTC" in args.items else "Configured", "active": True, "group": selected_group, "policies": policies, 'browserDns': 'not_configured_on_macos', "items": [{"id": i, "status": "skipped" if i == "WebRTC" else "applied", "detail": "macOS 不支持 Windows Edge 注册表策略。" if i == "WebRTC" else "已写入并读回。"} for i in args.items]}
        except Exception:
            with contextlib.suppress(Exception):
                for record in manifest["files"]:
                    path = Path(record["path"])
                    if sha256(path) == record["afterHash"]:
                        atomic_bytes(path, (STATE_DIR / Path(record["backup"]).name).read_bytes())
            raise


def repair_native(args, config, ctx, file_plan, preferences_plan, selected_group):
    """Persist both resource backups before writing; retain partial recovery.

    schema 2 stores one profile file and one preference key. SQLite and applied
    config.yaml stay outside the write set. restore_native accepts before/after
    resource states and merges unrelated inner preferences. schema 1 remains
    readable by restore for existing JSON snapshots.
    """
    store = ctx['store']
    before = ctx['outer']['flutter.config']
    after = json.loads(preferences_plan)['flutter.config']
    with operation_lock(STATE_DIR):
        if (STATE_DIR / 'active.json').exists():
            raise ProxyVeilError("已有快照，请先 restore；不会覆盖最初备份。")
        if sha256(ctx['profile']) != ctx['profile_hash'] or store.read() != before:
            raise ProxyVeilError("配置在检查后发生改变，停止写入。")
        profile_index(config, ctx['inner']['currentProfileId'])
        ident = f'{time.time_ns():x}'
        profile_backup = STATE_DIR / f'{ident}-profile.bak'
        pref_backup = STATE_DIR / f'{ident}-preferences.bak'
        shutil.copyfile(ctx['profile'], profile_backup)
        atomic_bytes(pref_backup, json_bytes({'before': before, 'after': after}))
        for backup in (profile_backup, pref_backup):
            secure_file(backup)
        if sha256(profile_backup) != ctx['profile_hash']:
            raise ProxyVeilError('备份期间 profile 发生改变，停止写入。')
        manifest = {'schema': 2, 'platform': 'macos', 'id': ident, 'mode': args.mode, 'items': args.items,
                    'configDirectory': str(config.resolve()), 'domain': store.domain, 'key': 'flutter.config',
                    'profileId': ctx['inner']['currentProfileId'], 'beforeHash': ctx['profile_hash'],
                    'afterHash': hashlib.sha256(file_plan).hexdigest(), 'preferencesBackupHash': sha256(pref_backup)}
        active = STATE_DIR / 'active.json'
        atomic_bytes(active, json_bytes(manifest))
        secure_file(active)
        try:
            if sha256(ctx['profile']) != manifest['beforeHash'] or store.read() != before:
                raise ProxyVeilError('备份后配置发生改变，停止写入。')
            atomic_bytes(ctx['profile'], file_plan)
            if sha256(ctx['profile']) != manifest['afterHash']:
                raise ProxyVeilError('profile 读回失败。')
            if store.read() != before:
                raise ProxyVeilError('偏好在写入前发生改变，停止写入。')
            store.write(after)
            if store.read() != after:
                raise ProxyVeilError('原生偏好读回失败。')
        except Exception:
            # Each resource rolls back independently; failure on one must not
            # prevent recovery of the other. Keep the manifest for retry.
            with contextlib.suppress(Exception):
                current = store.read()
                if current == after:
                    store.write(before)
            with contextlib.suppress(Exception):
                if sha256(ctx['profile']) == manifest['afterHash']:
                    atomic_bytes(ctx['profile'], profile_backup.read_bytes())
            raise
        return {'status': 'Partial' if 'WebRTC' in args.items else 'Configured', 'active': True, 'group': selected_group,
                'items': [{'id': item, 'status': 'skipped' if item == 'WebRTC' else 'applied'} for item in args.items],
                'browserDns': 'not_configured_on_macos'}


def restore_native(args, manifest):
    if manifest.get('platform') != 'macos' or not isinstance(manifest.get('id'), str) or not re.fullmatch('[0-9a-f]+', manifest['id']):
        raise ProxyVeilError('快照格式无效。')
    if type(manifest.get('profileId')) is not int or manifest['profileId'] < 0 or manifest.get('key') != 'flutter.config':
        raise ProxyVeilError('快照目标无效。')
    if not all(valid_hash(manifest.get(key)) for key in ('beforeHash', 'afterHash', 'preferencesBackupHash')):
        raise ProxyVeilError('快照哈希无效。')
    config = expand_path(args.config_directory)
    if config is None or str(config) != manifest.get('configDirectory'):
        raise ProxyVeilError('还原新布局需 --config-directory 匹配快照目录。')
    store = native_store(args, resolve_app(args.install_path), writing=True)
    if store.domain != manifest.get('domain'):
        raise ProxyVeilError('快照偏好域与应用不一致。')
    profile = config / 'profiles' / f"{manifest['profileId']}.yaml"
    if profile.is_symlink() or profile.resolve().parent != config / 'profiles':
        raise ProxyVeilError('快照 profile 路径无效。')
    profile_index(config, manifest['profileId'])
    profile_backup = STATE_DIR / f"{manifest['id']}-profile.bak"
    pref_backup = STATE_DIR / f"{manifest['id']}-preferences.bak"
    for backup, expected in ((profile_backup, manifest['beforeHash']), (pref_backup, manifest['preferencesBackupHash'])):
        if backup.is_symlink() or not backup.is_file() or sha256(backup) != expected:
            raise ProxyVeilError('快照备份缺失或校验失败，已停止还原。')
    original = profile_backup.read_bytes()
    prefs = load_json(pref_backup)
    if not isinstance(prefs, dict) or set(prefs) != {'before', 'after'} or not all(isinstance(v, str) for v in prefs.values()):
        raise ProxyVeilError('偏好备份无效。')
    try:
        original_preferences = json.loads(prefs['before'])
        if type(original_preferences.get('currentProfileId')) is not int or original_preferences['currentProfileId'] != manifest['profileId']:
            raise ProxyVeilError('偏好备份与快照 profile 不一致。')
    except (ValueError, AttributeError) as exc:
        raise ProxyVeilError('偏好备份无效。') from exc
    current_hash = sha256(profile)
    if current_hash not in {manifest['beforeHash'], manifest['afterHash']}:
        raise ProxyVeilError('profile 已被外部修改，快照已保留。')
    current = store.read()
    restored = merge_restore(prefs['before'], prefs['after'], current)
    if sha256(profile) != current_hash or store.read() != current:
        raise ProxyVeilError('还原检查后配置发生改变，快照已保留。')
    atomic_bytes(profile, original)
    if sha256(profile) != manifest['beforeHash']:
        raise ProxyVeilError('profile 还原读回失败。')
    if store.read() != current:
        raise ProxyVeilError('偏好在还原前发生改变，快照已保留。')
    store.write(restored)
    if store.read() != restored:
        raise ProxyVeilError('偏好还原读回失败。')
    atomic_bytes(STATE_DIR / f"history-{manifest['id']}.json", json_bytes(manifest))
    (STATE_DIR / 'active.json').unlink()
    return {'status': 'Restored', 'active': False}


def restore(args: argparse.Namespace) -> dict[str, Any]:
    active = STATE_DIR / "active.json"
    if not active.is_file():
        raise ProxyVeilError("没有可还原的快照。")
    with operation_lock(STATE_DIR):
        manifest = load_json(active)
        if isinstance(manifest, dict) and manifest.get('schema') == 2:
            return restore_native(args, manifest)
        if not isinstance(manifest, dict) or manifest.get("schema") != 1 or manifest.get("platform") != "macos" or not isinstance(manifest.get("files"), list) or not isinstance(manifest.get("id"), str) or not re.fullmatch(r"[0-9a-f]+", manifest["id"]):
            raise ProxyVeilError("快照格式或平台不受支持。")
        try:
            config_root = Path(manifest["configDirectory"]).resolve()
        except (KeyError, TypeError, ValueError) as exc:
            raise ProxyVeilError("快照缺少有效配置目录。") from exc
        records = manifest.get("files", [])
        if len(records) != 2:
            raise ProxyVeilError("快照文件记录数量无效，已停止还原。")
        labels: set[str] = set()
        for record in records:
            if not isinstance(record, dict) or not all(key in record for key in ("path", "label", "backup", "beforeHash", "afterHash")):
                raise ProxyVeilError("快照文件记录无效，已停止还原。")
            if not valid_hash(record["beforeHash"]) or not valid_hash(record["afterHash"]):
                raise ProxyVeilError("快照哈希无效，已停止还原。")
            try:
                path = Path(record["path"]).resolve()
                backup = Path(record["backup"]).resolve()
                path.relative_to(config_root)
            except (TypeError, ValueError, OSError) as exc:
                raise ProxyVeilError("快照目标路径无效，已停止还原。") from exc
            if record.get("label") not in {"profile", "preferences"} or record["label"] in labels or backup.parent != STATE_DIR.resolve() or backup.name != f"{manifest['id']}-{record['label']}.bak":
                raise ProxyVeilError("快照备份路径无效，已停止还原。")
            labels.add(record["label"])
            if not path.is_file():
                raise ProxyVeilError(f"还原目标不存在：{path.name}，快照已保留。")
            try:
                current_hash = sha256(path)
            except OSError as exc:
                raise ProxyVeilError(f"无法读取还原目标：{path.name}，快照已保留。") from exc
            if current_hash not in {record["beforeHash"], record["afterHash"]}:
                raise ProxyVeilError(f"还原冲突：{path.name} 已被外部修改，快照已保留。")
            if not backup.is_file():
                raise ProxyVeilError(f"快照备份缺失：{backup.name}，已停止还原。")
            try:
                backup_hash = sha256(backup)
            except OSError as exc:
                raise ProxyVeilError(f"无法读取快照备份：{backup.name}，已停止还原。") from exc
            if backup_hash != record["beforeHash"]:
                raise ProxyVeilError("快照备份校验失败，已停止还原。")
        for record in manifest["files"]:
            atomic_bytes(Path(record["path"]), Path(record["backup"]).read_bytes())
        history = STATE_DIR / f"history-{manifest['id']}.json"
        atomic_bytes(history, json_bytes(manifest))
        active.unlink()
    return {"status": "Restored", "active": False}


def parser() -> argparse.ArgumentParser:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--install-path")
    common.add_argument("--config-directory")
    common.add_argument('--preferences-domain', help='Must match the installed FlClash bundle identifier')
    common.add_argument("--state-directory", default=str(STATE_DIR))
    root = argparse.ArgumentParser(prog="proxyveil-macos", description="ProxyVeil macOS FlClash adapter")
    sub = root.add_subparsers(dest="command", required=True)
    sub.add_parser("inspect", parents=[common])
    repair_cmd = sub.add_parser("repair", parents=[common])
    repair_cmd.add_argument("--mode", choices=("TUN", "Proxy"), default="TUN")
    repair_cmd.add_argument("--items", nargs="+", choices=("DNS", "IPv6", "WebRTC"), required=True)
    repair_cmd.add_argument("--proxy-group")
    sub.add_parser("restore", parents=[common])
    return root


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    global STATE_DIR
    STATE_DIR = expand_path(args.state_directory) or STATE_DIR
    if sys.platform != "darwin":
        print(json.dumps({"status": "Failed", "message": "macOS 入口只能在 macOS 上运行。", "active": False}, ensure_ascii=False, indent=2))
        return 2
    try:
        result = inspect(args) if args.command == "inspect" else repair(args) if args.command == "repair" else restore(args)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (ProxyVeilError, OSError) as exc:
        message = str(exc) if isinstance(exc, ProxyVeilError) else '文件或系统操作失败；保留快照后重试。'
        print(json.dumps({"status": "Failed", "message": message, "active": (STATE_DIR / "active.json").exists()}, ensure_ascii=False, indent=2))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
