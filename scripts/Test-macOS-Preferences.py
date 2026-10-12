#!/usr/bin/env python3
"""Exercise new-layout recovery with generated plist/SQLite fixtures only."""
from datetime import datetime, timezone
from contextlib import closing
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import sqlite3
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'macos'))
import proxyveil as pv
from preferences import PlistPreferences, profile_index, merge_restore

spec = importlib.util.spec_from_file_location('fixtures', ROOT / 'scripts' / 'Test-macOS.py')
fixtures = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixtures)


class PreferenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='proxyveil-preferences-')
        self.root = Path(self.temp.name).resolve()
        self.config = fixtures.fixture(self.root)
        outer = json.loads((self.config / pv.PREFERENCE_FILE).read_bytes())
        (self.config / pv.PREFERENCE_FILE).unlink()
        self.plist = self.root / 'generated.plist'
        self.outer = {**outer, 'unrelated': ['fixture', 4]}
        self.plist.write_bytes(plistlib.dumps(self.outer))
        self.store = PlistPreferences(self.plist, 'com.fixture.FlClash')
        self.old = self.store.read()
        self.profile = self.config / 'profiles' / '1.yaml'
        self.original_profile = self.profile.read_bytes()
        self.db = self.config / 'database.sqlite'
        with closing(sqlite3.connect(self.db)) as db:
            with db:
                db.executescript('PRAGMA user_version=10; CREATE TABLE profiles (id INTEGER PRIMARY KEY, selected_map TEXT, url TEXT); INSERT INTO profiles VALUES (1, \'fixture-node\', \'fixture-subscription\');')
        self.db_before = self.db.read_bytes()
        self.state = self.root / 'state'
        self.old_state = pv.STATE_DIR
        pv.STATE_DIR = self.state
        self.factory = patch.object(pv, 'native_store', return_value=self.store)
        self.factory.start()

    def tearDown(self):
        self.factory.stop()
        pv.STATE_DIR = self.old_state
        self.assertEqual(self.db.read_bytes(), self.db_before)
        self.assertFalse(Path(str(self.db) + '-wal').exists())
        self.assertFalse(Path(str(self.db) + '-shm').exists())
        self.temp.cleanup()

    def args(self, action='repair', mode='TUN'):
        options = ['--mode', mode, '--items', 'DNS', 'IPv6', '--proxy-group', 'Proxy'] if action == 'repair' else []
        return pv.parser().parse_args([action, *options, '--config-directory', str(self.config), '--state-directory', str(self.state)])

    def test_inspect_no_state_or_plist_database_writes(self):
        before = self.plist.read_bytes()
        result = pv.inspect(self.args('inspect'))
        self.assertEqual(result['databaseSchema'], 10)
        self.assertEqual(result['preferencesType'], 'string')
        self.assertEqual(self.plist.read_bytes(), before)
        self.assertFalse(self.state.exists())

    def test_xml_binary_and_modes_roundtrip(self):
        for fmt, mode in ((plistlib.FMT_XML, 'TUN'), (plistlib.FMT_BINARY, 'Proxy')):
            with self.subTest(format=fmt, mode=mode):
                self.plist.write_bytes(plistlib.dumps(self.outer, fmt=fmt))
                result = pv.repair(self.args(mode=mode))
                self.assertEqual(result['status'], 'Configured')
                self.assertEqual(plistlib.loads(self.plist.read_bytes())['unrelated'], ['fixture', 4])
                self.assertEqual(self.plist.read_bytes().startswith(b'bplist'), fmt == plistlib.FMT_BINARY)
                self.assertIn('  ipv6: false', self.profile.read_text())
                self.assertIn('DOMAIN-SUFFIX,example.cn,DIRECT', self.profile.read_text())
                pv.restore(self.args('restore'))
                self.assertEqual(self.profile.read_bytes(), self.original_profile)
                self.assertEqual(json.loads(self.store.read()), json.loads(self.old))

    def test_preserve_unrelated_inner_and_outer_preferences(self):
        pv.repair(self.args())
        current = json.loads(self.store.read())
        current['theme'] = 'new-fixture-theme'
        current['networkProps']['unrelated'] = True
        self.store.write(json.dumps(current))
        pv.restore(self.args('restore'))
        restored = json.loads(self.store.read())
        self.assertEqual(restored['theme'], 'new-fixture-theme')
        self.assertTrue(restored['networkProps']['unrelated'])
        self.assertEqual(restored['networkProps']['appendSystemDns'], True)
        self.assertNotIn('overrideDns', restored)

    def test_managed_drift_refuses_before_profile_write(self):
        pv.repair(self.args())
        repaired = self.profile.read_bytes()
        current = json.loads(self.store.read())
        current['patchClashConfig']['tun']['enable'] = 'external'
        self.store.write(json.dumps(current))
        with self.assertRaisesRegex(pv.ProxyVeilError, '外部修改'):
            pv.restore(self.args('restore'))
        self.assertEqual(self.profile.read_bytes(), repaired)
        self.assertTrue((self.state / 'active.json').exists())

    def test_profile_switch_refuses_restore(self):
        pv.repair(self.args())
        current = json.loads(self.store.read())
        current['currentProfileId'] = 2
        self.store.write(json.dumps(current))
        with self.assertRaisesRegex(pv.ProxyVeilError, 'profile'):
            pv.restore(self.args('restore'))

    def test_repeated_repair_keeps_original_manifest(self):
        pv.repair(self.args())
        before = (self.state / 'active.json').read_bytes()
        with self.assertRaisesRegex(pv.ProxyVeilError, '已有快照'):
            pv.repair(self.args())
        self.assertEqual((self.state / 'active.json').read_bytes(), before)

    def test_backup_tamper_and_domain_mismatch_no_write(self):
        pv.repair(self.args())
        active = self.state / 'active.json'
        manifest = json.loads(active.read_bytes())
        changed = self.profile.read_bytes(), self.store.read()
        manifest['domain'] = 'other.fixture'
        active.write_text(json.dumps(manifest))
        with self.assertRaises(pv.ProxyVeilError):
            pv.restore(self.args('restore'))
        manifest['domain'] = self.store.domain
        active.write_text(json.dumps(manifest))
        (self.state / f"{manifest['id']}-preferences.bak").write_bytes(b'fixture tamper')
        with self.assertRaises(pv.ProxyVeilError):
            pv.restore(self.args('restore'))
        self.assertEqual((self.profile.read_bytes(), self.store.read()), changed)

    def test_restore_interruption_resumes(self):
        pv.repair(self.args())
        with patch.object(self.store, 'write', side_effect=OSError('fixture failure')):
            with self.assertRaises(OSError):
                pv.restore(self.args('restore'))
        self.assertEqual(self.profile.read_bytes(), self.original_profile)
        self.assertTrue((self.state / 'active.json').exists())
        pv.restore(self.args('restore'))
        self.assertEqual(json.loads(self.store.read()), json.loads(self.old))

    def test_write_then_sync_failure_keeps_recovery_and_rolls_back_profile(self):
        original_write = self.store.write
        def failing_write(value):
            original_write(value)
            raise OSError('fixture post-write failure')
        with patch.object(self.store, 'write', side_effect=failing_write):
            with self.assertRaises(OSError):
                pv.repair(self.args())
        self.assertEqual(self.profile.read_bytes(), self.original_profile)
        self.assertTrue((self.state / 'active.json').exists())
        pv.restore(self.args('restore'))

    def test_profile_drift_refuses_all_restore_writes(self):
        pv.repair(self.args())
        self.profile.write_bytes(self.profile.read_bytes() + b'# fixture drift\n')
        current = self.store.read()
        with self.assertRaisesRegex(pv.ProxyVeilError, '外部修改'):
            pv.restore(self.args('restore'))
        self.assertEqual(self.store.read(), current)

    def test_unknown_database_schema_and_profile_index_rejected(self):
        with self.assertRaises(pv.ProxyVeilError):
            profile_index(self.config, 999)
        Path(str(self.db) + '-wal').write_bytes(b'fixture pending')
        with self.assertRaisesRegex(pv.ProxyVeilError, '日志'):
            profile_index(self.config, 1)
        Path(str(self.db) + '-wal').unlink()

    def test_missing_or_nonstring_preference_rejected(self):
        for value in ({}, {'flutter.config': 4}):
            self.plist.write_bytes(plistlib.dumps(value))
            with self.assertRaises(pv.ProxyVeilError):
                pv.repair(self.args())
            self.assertFalse(self.state.exists())
            self.assertEqual(self.profile.read_bytes(), self.original_profile)

    def test_invalid_profile_type_rejected(self):
        inner = json.loads(self.old)
        inner['currentProfileId'] = True
        self.store.write(json.dumps(inner))
        with self.assertRaises(pv.ProxyVeilError):
            pv.repair(self.args())

    def test_unmanaged_backup_delta_rejected(self):
        old = json.loads(self.old)
        altered = {**old, 'unmanaged': 'tampered'}
        with self.assertRaises(pv.ProxyVeilError):
            merge_restore(self.old, json.dumps(altered), self.old)


if __name__ == '__main__':
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(PreferenceTests))
    report = {'at': datetime.now(timezone.utc).isoformat(), 'result': 'passed' if result.wasSuccessful() else 'failed',
              'tests': result.testsRun, 'failures': len(result.failures), 'errors': len(result.errors), 'platform': sys.platform,
              'scope': 'Generated XML/binary plist and SQLite fixtures, production schema-2 recovery',
              'nativeCFPreferences': 'not_executed', 'liveConfigurationModified': False,
              'sourceHashes': {name: hashlib.sha256((ROOT / 'macos' / name).read_bytes()).hexdigest() for name in ('proxyveil.py', 'preferences.py')}}
    (ROOT / 'docs' / 'validation' / 'macos-preferences.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    raise SystemExit(0 if result.wasSuccessful() else 1)
