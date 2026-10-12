#!/usr/bin/env python3
"""ProxyVeil macOS adapter for FlClash.

This is the macOS MVP entry point. It deliberately owns only macOS concerns
and the small, supported FlClash text format. Repair and restore are always
explicit subcommands; importing or inspecting a configuration never writes.
"""

from __future__ import annotations

import argparse
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
import time
from typing import Any, Iterable


APP_SUPPORT = Path.home() / "Library" / "Application Support"
STATE_DIR = APP_SUPPORT / "ProxyVeil"
PREFERENCE_FILE = "shared_preferences.json"
GENERATED_RULES = (
    'IP-CIDR,1.1.1.1/32,{group},no-resolve',
    'IP-CIDR,8.8.8.8/32,{group},no-resolve',
)


class ProxyVeilError(RuntimeError):
    pass


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
        if path and (path / PREFERENCE_FILE).is_file():
            return path
        raise ProxyVeilError("ConfigDirectory 必须包含 shared_preferences.json。")
    for path in candidate_config_dirs(executable):
        if (path / PREFERENCE_FILE).is_file():
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


def proxy_groups(text: str) -> list[str]:
    section = find_section(text, "proxy-groups")
    if not section or section[3]:
        raise ProxyVeilError("需要块格式的 proxy-groups。")
    lines, start, end, _ = section
    names: list[str] = []
    for line in lines[start + 1 : end]:
        match = re.match(r"^\s*(?:-\s+)?name:\s*(.+?)\s*$", line)
        if match:
            raw = match.group(1).strip().strip('"\'')
            names.append(raw)
    if not names:
        raise ProxyVeilError("未检测到代理组名称。")
    return names


def select_group(text: str, requested: str | None) -> str:
    names = proxy_groups(text)
    if requested:
        if requested not in names or requested in {"DIRECT", "REJECT", "PASS"}:
            raise ProxyVeilError("指定代理组不存在或不是代理组。")
        return requested
    rules = section_text(text, "rules")
    for line in rules.splitlines():
        match = re.match(r"^\s*-\s*(?:MATCH|FINAL),(.+?)\s*$", line)
        if match and match.group(1) in names:
            return match.group(1)
    usable = [name for name in names if name not in {"DIRECT", "REJECT", "PASS"}]
    if len(usable) == 1:
        return usable[0]
    raise ProxyVeilError("无法自动选定 DNS 代理组，请使用 --proxy-group。")


def insert_proxy_rules(text: str, group: str) -> str:
    section = find_section(text, "rules")
    if not section or section[3]:
        raise ProxyVeilError("Proxy 模式需要块格式 rules。")
    lines, start, end, _ = section
    indent = "  "
    for line in lines[start + 1 : end]:
        match = re.match(r"^( +)-\s+", line)
        if match:
            indent = match.group(1)
            break
    generated = [yaml_scalar(template.format(group=group)) for template in GENERATED_RULES]
    body = lines[start + 1 : end]
    body = [line for line in body if not any(line.strip() == f"- {item}" for item in generated)]
    body[0:0] = [f"{indent}- {item}" for item in generated]
    return "\n".join(lines[:start + 1] + body + lines[end:]).rstrip("\n") + "\n"


def context(config_dir: Path) -> dict[str, Any]:
    preferences = config_dir / PREFERENCE_FILE
    try:
        preferences_bytes = preferences.read_bytes()
        outer = json.loads(preferences_bytes.decode("utf-8"))
    except (OSError, UnicodeDecodeError, ValueError) as exc:
        raise ProxyVeilError(f"无法读取 JSON：{preferences.name}") from exc
    if not isinstance(outer, dict) or not isinstance(outer.get("flutter.config"), str):
        raise ProxyVeilError("无法识别 FlClash 偏好结构。")
    try:
        inner = json.loads(outer["flutter.config"])
    except ValueError as exc:
        raise ProxyVeilError("无法解析 FlClash 内部偏好。") from exc
    if not isinstance(inner, dict) or not str(inner.get("currentProfileId", "")).isdigit():
        raise ProxyVeilError("请先在 FlClash 选择一个配置。")
    if not isinstance(inner.get("networkProps"), dict) or not isinstance(inner.get("patchClashConfig"), dict):
        raise ProxyVeilError("FlClash 偏好版本不兼容，未修改。")
    if not isinstance(inner["patchClashConfig"].get("tun"), dict):
        raise ProxyVeilError("FlClash TUN 偏好结构不兼容，未修改。")
    profile = config_dir / "profiles" / f"{inner['currentProfileId']}.yaml"
    if not profile.is_file():
        raise ProxyVeilError("找不到当前 FlClash 配置 YAML。")
    try:
        profile_bytes = profile.read_bytes()
        profile_text = profile_bytes.decode("utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        raise ProxyVeilError("当前 FlClash 配置 YAML 不可读取。") from exc
    return {"preferences": preferences, "profile": profile, "outer": outer, "inner": inner, "profile_text": profile_text, "preferences_hash": hashlib.sha256(preferences_bytes).hexdigest(), "profile_hash": hashlib.sha256(profile_bytes).hexdigest()}


def plan(ctx: dict[str, Any], mode: str, items: list[str], group: str | None) -> tuple[bytes, bytes, str | None, dict[str, str]]:
    text = ctx["profile_text"]
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
            policies["DnsOverHttpsMode"] = "secure"
            policies["DnsOverHttpsTemplates"] = "https://1.1.1.1/dns-query https://8.8.8.8/dns-query"
    if "IPv6" in items:
        inner.setdefault("patchClashConfig", {})["ipv6"] = False
        text = set_top_level_scalar(text, "ipv6", "false")
    for name, original in original_sections.items():
        if section_text(text, name) != original:
            raise ProxyVeilError(f"保护检查失败：{name}")
    outer["flutter.config"] = json.dumps(inner, ensure_ascii=False, separators=(",", ":"))
    return text.encode(), json_bytes(outer), selected_group, policies


@contextlib.contextmanager
def operation_lock(state: Path):
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    with contextlib.suppress(OSError):
        os.chmod(state, 0o700)
    path = state / "operation.lock"
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
    ctx = context(config)
    return {"status": "Inspected", "installPath": str(executable) if executable else None, "configDirectory": str(config), "profile": str(ctx["profile"]), "webRtc": "unsupported-on-macos", "active": (STATE_DIR / "active.json").exists()}


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
    ctx = context(config)
    file_plan, preferences_plan, selected_group, policies = plan(ctx, args.mode, [i for i in args.items if i != "WebRTC"], args.proxy_group)
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
            return {"status": "Partial" if "WebRTC" in args.items else "Configured", "active": True, "group": selected_group, "policies": policies, "items": [{"id": i, "status": "skipped" if i == "WebRTC" else "applied", "detail": "macOS 不支持 Windows Edge 注册表策略。" if i == "WebRTC" else "已写入并读回。"} for i in args.items]}
        except Exception:
            with contextlib.suppress(Exception):
                for record in manifest["files"]:
                    path = Path(record["path"])
                    if sha256(path) == record["afterHash"]:
                        atomic_bytes(path, (STATE_DIR / Path(record["backup"]).name).read_bytes())
            raise


def restore(_: argparse.Namespace) -> dict[str, Any]:
    active = STATE_DIR / "active.json"
    if not active.is_file():
        raise ProxyVeilError("没有可还原的快照。")
    with operation_lock(STATE_DIR):
        manifest = load_json(active)
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
    except ProxyVeilError as exc:
        print(json.dumps({"status": "Failed", "message": str(exc), "active": (STATE_DIR / "active.json").exists()}, ensure_ascii=False, indent=2))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
