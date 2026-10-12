#!/usr/bin/env python3
"""Offline tests for the macOS FlClash adapter.

The fixture never touches a real FlClash installation or the user's state
directory. It exercises explicit repair, conflict-safe restore, and the
macOS WebRTC limitation.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "macos" / "proxyveil.py"


def run(*args: str, state: Path, config: Path) -> tuple[int, dict]:
    command = [sys.executable, str(CLI), *args, "--config-directory", str(config), "--state-directory", str(state)]
    completed = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, check=False)
    try:
        payload = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"invalid CLI output: {completed.stdout}\n{completed.stderr}") from exc
    return completed.returncode, payload


def fixture(root: Path) -> Path:
    config = root / "config"
    (config / "profiles").mkdir(parents=True)
    outer = {
        "flutter.config": json.dumps(
            {
                "currentProfileId": 1,
                "networkProps": {"appendSystemDns": True, "systemProxy": False},
                "patchClashConfig": {"ipv6": True, "tun": {"enable": False}},
            },
            separators=(",", ":"),
        )
    }
    (config / "shared_preferences.json").write_text(json.dumps(outer), encoding="utf-8")
    (config / "profiles" / "1.yaml").write_text(
        """proxies:\n  - name: node\n    type: ss\nproxy-groups:\n  - name: Proxy\n    type: select\n    proxies:\n      - node\nrules:\n  - DOMAIN-SUFFIX,example.cn,DIRECT\n  - MATCH,Proxy\ndns:\n  enable: false\n  nameserver:\n    - https://9.9.9.9/dns-query\ntun:\n  enable: false\n  stack: system\nipv6: true\n""",
        encoding="utf-8",
    )
    return config


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="proxyveil-macos-test-") as temp:
        root = Path(temp)
        state = root / "state"
        config = fixture(root)
        profile = config / "profiles" / "1.yaml"
        before = profile.read_bytes()
        code, inspected = run("inspect", state=state, config=config)
        assert code == 0 and inspected["status"] == "Inspected"
        code, repaired = run("repair", "--mode", "Proxy", "--items", "DNS", "IPv6", "WebRTC", "--proxy-group", "Proxy", state=state, config=config)
        assert code == 0 and repaired["status"] == "Partial"
        changed = profile.read_text(encoding="utf-8")
        assert "https://1.1.1.1/dns-query#Proxy" in changed
        assert "IP-CIDR,1.1.1.1/32,Proxy,no-resolve" in changed
        assert "ipv6: false" in changed
        assert (state / "active.json").is_file()
        code, restored = run("restore", state=state, config=config)
        assert code == 0 and restored["status"] == "Restored"
        assert profile.read_bytes() == before
        assert not (state / "active.json").exists()

        # External drift must preserve the snapshot and refuse overwrite.
        run("repair", "--mode", "TUN", "--items", "DNS", "--proxy-group", "Proxy", state=state, config=config)
        profile.write_text(profile.read_text(encoding="utf-8") + "# external change\n", encoding="utf-8")
        code, conflict = run("restore", state=state, config=config)
        assert code == 2 and "外部修改" in conflict["message"] and conflict["active"]

        # A missing snapshot backup must fail as JSON and preserve the snapshot.
        damaged_root = root / "damaged-backup"
        damaged_config = fixture(damaged_root)
        damaged_state = damaged_root / "state"
        run("repair", "--mode", "TUN", "--items", "DNS", "--proxy-group", "Proxy", state=damaged_state, config=damaged_config)
        manifest = json.loads((damaged_state / "active.json").read_text(encoding="utf-8"))
        missing_backup = damaged_state / Path(manifest["files"][0]["backup"]).name
        missing_backup.unlink()
        code, damaged = run("restore", state=damaged_state, config=damaged_config)
        assert code == 2 and "快照备份缺失" in damaged["message"] and damaged["active"]

        # A WebRTC-only request is explicit and harmless on macOS.
        other_state = root / "state-webrtc"
        code, rtc = run("repair", "--items", "WebRTC", state=other_state, config=config)
        assert code == 0 and rtc["status"] == "Partial" and rtc["items"][0]["status"] == "skipped"
    print("PASS: macOS adapter repair/restore/conflict/WebRTC tests")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
