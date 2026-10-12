#!/usr/bin/env python3
"""Test the macOS adapter's file operations on isolated host-native fixtures.

Windows runs use the adapter's msvcrt lock; they do not verify macOS flock,
permissions, process startup or network behavior. The production CLI keeps
its macOS-only platform guard. See docs/local-development-plan.md.
"""

from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import platform
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "macos" / "proxyveil.py"


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


pv = load_module("portable_adapter", CLI)
fixtures = load_module("macos_fixtures", ROOT / "scripts" / "Test-macOS.py")


class PortableAdapterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="proxyveil-portable-")
        self.root = Path(self.temp.name).resolve()
        self.original_state = pv.STATE_DIR
        self.state = self.root / "state"
        pv.STATE_DIR = self.state
        self.config = fixtures.fixture(self.root)
        self.profile = self.config / "profiles" / "1.yaml"
        self.preferences = self.config / "shared_preferences.json"
        self.before = self.bytes()

    def tearDown(self):
        pv.STATE_DIR = self.original_state
        self.temp.cleanup()

    def bytes(self):
        return self.profile.read_bytes(), self.preferences.read_bytes()

    def args(self, command="repair", *options):
        defaults = ["--mode", "Proxy", "--items", "DNS", "IPv6", "--proxy-group", "Proxy"] if command == "repair" and not options else []
        return pv.parser().parse_args([
            command, *defaults, *options,
            "--config-directory", str(self.config), "--state-directory", str(self.state),
        ])

    def active(self):
        return json.loads((self.state / "active.json").read_text(encoding="utf-8"))

    def test_inspect_is_read_only(self):
        self.assertEqual(pv.inspect(self.args("inspect"))["status"], "Inspected")
        self.assertEqual(self.bytes(), self.before)
        self.assertFalse(self.state.exists())

    def test_tun_and_proxy_roundtrip_preserve_routing_and_preferences(self):
        for mode in ("TUN", "Proxy"):
            with self.subTest(mode=mode):
                args = self.args("repair", "--mode", mode, "--items", "DNS", "IPv6", "WebRTC", "--proxy-group", "Proxy")
                result = pv.repair(args)
                self.assertEqual(result["status"], "Partial")
                text = self.profile.read_text(encoding="utf-8")
                self.assertIn("DOMAIN-SUFFIX,example.cn,DIRECT", text)
                self.assertIn("MATCH,Proxy", text)
                self.assertIn("https://1.1.1.1/dns-query#Proxy", text)
                self.assertIn("ipv6: false", text)
                inner = json.loads(json.loads(self.preferences.read_text(encoding="utf-8"))["flutter.config"])
                self.assertEqual(inner["networkProps"]["systemProxy"], mode == "Proxy")
                self.assertEqual(inner["patchClashConfig"]["tun"]["enable"], mode == "TUN")
                self.assertEqual(pv.restore(self.args("restore"))["status"], "Restored")
                self.assertEqual(self.bytes(), self.before)
                self.assertFalse((self.state / "active.json").exists())

    def test_plan_does_not_write(self):
        pv.plan(pv.context(self.config), "TUN", ["DNS", "IPv6"], "Proxy")
        self.assertEqual(self.bytes(), self.before)
        self.assertFalse(self.state.exists())

    def test_webrtc_only_skips_without_state(self):
        result = pv.repair(self.args("repair", "--items", "WebRTC"))
        self.assertEqual(result["items"][0]["status"], "skipped")
        self.assertEqual(self.bytes(), self.before)
        self.assertFalse(self.state.exists())

    def test_repeated_repair_preserves_first_snapshot(self):
        pv.repair(self.args())
        before_manifest = (self.state / "active.json").read_bytes()
        with self.assertRaisesRegex(pv.ProxyVeilError, "已有快照"):
            pv.repair(self.args())
        self.assertEqual((self.state / "active.json").read_bytes(), before_manifest)

    def test_external_drift_preserves_files_and_snapshot(self):
        pv.repair(self.args())
        self.profile.write_bytes(self.profile.read_bytes() + b"# external drift\n")
        changed = self.bytes()
        with self.assertRaisesRegex(pv.ProxyVeilError, "外部修改"):
            pv.restore(self.args("restore"))
        self.assertEqual(self.bytes(), changed)
        self.assertTrue((self.state / "active.json").is_file())

    def test_missing_and_tampered_backups_refuse_all_restore_writes(self):
        pv.repair(self.args())
        backup = Path(self.active()["files"][-1]["backup"])
        original_backup = backup.read_bytes()
        changed = self.bytes()
        for action in ("missing", "tampered"):
            with self.subTest(action=action):
                backup.unlink()
                if action == "tampered":
                    backup.write_bytes(b"fixture tamper")
                with self.assertRaises(pv.ProxyVeilError):
                    pv.restore(self.args("restore"))
                self.assertEqual(self.bytes(), changed)
                self.assertTrue((self.state / "active.json").exists())
                backup.write_bytes(original_backup)

    def test_interrupted_restore_can_resume(self):
        pv.repair(self.args())
        original_write = pv.atomic_bytes

        def interrupt(path, payload):
            if path == self.preferences:
                raise OSError("fixture restore interruption")
            return original_write(path, payload)

        with patch.object(pv, "atomic_bytes", side_effect=interrupt):
            with self.assertRaises(OSError):
                pv.restore(self.args("restore"))
        self.assertEqual(self.profile.read_bytes(), self.before[0])
        self.assertTrue((self.state / "active.json").exists())
        self.assertEqual(pv.restore(self.args("restore"))["status"], "Restored")
        self.assertEqual(self.bytes(), self.before)

    def test_mid_write_failure_rolls_back_and_remains_recoverable(self):
        original_write = pv.atomic_bytes

        def interrupt(path, payload):
            if path == self.preferences:
                raise OSError("fixture repair interruption")
            return original_write(path, payload)

        with patch.object(pv, "atomic_bytes", side_effect=interrupt):
            with self.assertRaises(OSError):
                pv.repair(self.args())
        self.assertEqual(self.bytes(), self.before)
        self.assertTrue((self.state / "active.json").exists())
        self.assertEqual(pv.restore(self.args("restore"))["status"], "Restored")

    def test_native_lock_rejects_another_process_and_releases_after_error(self):
        command = [sys.executable, "-X", "utf8", str(Path(__file__).resolve()), "--probe-lock", str(self.state)]
        with self.assertRaisesRegex(RuntimeError, "fixture lock interruption"):
            with pv.operation_lock(self.state):
                blocked = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", timeout=10)
                self.assertEqual(blocked.returncode, 2, blocked.stdout + blocked.stderr)
                raise RuntimeError("fixture lock interruption")
        released = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", timeout=10)
        self.assertEqual(released.returncode, 0, released.stdout + released.stderr)
        self.assertEqual(self.bytes(), self.before)

    def test_new_layout_still_rejected_before_write(self):
        unsupported = self.root / "unsupported"
        unsupported.mkdir()
        config_yaml = unsupported / "config.yaml"
        config_yaml.write_text("currentProfileId: 1\n", encoding="utf-8")
        with self.assertRaises(pv.ProxyVeilError):
            pv.resolve_config(str(unsupported), None)
        self.assertEqual(config_yaml.read_text(encoding="utf-8"), "currentProfileId: 1\n")
        self.assertFalse(self.state.exists())

    @unittest.skipIf(sys.platform == "darwin", "macOS allows its production CLI")
    def test_production_cli_rejects_other_platforms_without_writes(self):
        for action in ("inspect", "repair", "restore"):
            with self.subTest(action=action):
                options = ["--items", "DNS"] if action == "repair" else []
                command = [sys.executable, "-X", "utf8", str(CLI), action, *options, "--config-directory", str(self.config), "--state-directory", str(self.state)]
                completed = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", timeout=10)
                self.assertEqual(completed.returncode, 2, completed.stderr)
                self.assertEqual(json.loads(completed.stdout)["status"], "Failed")
                self.assertEqual(self.bytes(), self.before)
                self.assertFalse(self.state.exists())


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--probe-lock":
        try:
            with pv.operation_lock(Path(sys.argv[2])):
                print("acquired")
        except pv.ProxyVeilError:
            print("blocked")
            return 2
        return 0
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(PortableAdapterTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    report = {
        "at": datetime.now(timezone.utc).isoformat(),
        "result": "passed" if result.wasSuccessful() else "failed",
        "platform": sys.platform,
        "python": platform.python_version(),
        "tests": result.testsRun,
        "skipped": len(result.skipped),
        "failures": len(result.failures),
        "errors": len(result.errors),
        "scope": "Generated fixtures using the macOS adapter functions and host-native file lock",
        "lockBackend": "msvcrt" if sys.platform == "win32" else "fcntl",
        "macOSFlockExercised": sys.platform == "darwin",
        "nativeHostAcceptance": "not_executed",
        "adapterSha256": hashlib.sha256(CLI.read_bytes()).hexdigest(),
        "liveConfigurationModified": False,
        "scenarios": sorted(name for name in dir(PortableAdapterTests) if name.startswith("test_")),
    }
    report_path = ROOT / "docs" / "validation" / "macos-portable.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
