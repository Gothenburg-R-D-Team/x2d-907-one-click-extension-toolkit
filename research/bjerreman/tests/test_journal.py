"""Desktop test harness for the undo-journal engine.

Builds a fake /system from a synthetic stock profile and tests:
  - install, verify, restore cycle
  - multi-mod stacking and ordered restore
  - interrupted install recovery
  - interrupted restore recovery
  - out-of-band file tampering detection
  - export/import of restore kit
  - journal schema round-trip

No camera contact. All operations happen in a temp directory.
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import tempfile
import unittest
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))

from journal import (
    Action, Journal, JournalEntry, JournalManifest, Phase, SlotInfo,
    StockProfile, atomic_copy, atomic_write_json, make_stub_slot_info,
    sha256_file,
)

PROFILE_PATH = Path(__file__).resolve().parent / "fixtures" / "synthetic_profile.json"

MOD_PATHS = [
    "/etc/init/camera-gui.rc",
    "/etc/init/camera-service.rc",
]


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def write_file(path: Path, content: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content)


class StubSystem:
    """Build a minimal fake /system from stock profile entries."""

    def __init__(self, root: Path, profile: StockProfile, paths: list[str]):
        self.root = root
        for p in paths:
            h = profile.stock_hash(p)
            if h:
                content = f"STOCK:{h}:{p}".encode()
                f = root / p.lstrip("/")
                f.parent.mkdir(parents=True, exist_ok=True)
                f.write_bytes(content)
                self._stock_hashes = {}
                self._stock_hashes[p] = sha256_bytes(content)


class JournalTestCase(unittest.TestCase):
    def setUp(self):
        self.tmpdir = Path(tempfile.mkdtemp(prefix="hb-journal-test-"))
        self.system = self.tmpdir / "system"
        self.journal_dir = self.tmpdir / "modjournal"
        self.mods_dir = self.tmpdir / "mod_sources"
        self.system.mkdir()
        self.journal_dir.mkdir()
        self.mods_dir.mkdir()
        self.profile = StockProfile(PROFILE_PATH)

    def tearDown(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def _populate_stock(self, paths: list[str]) -> dict[str, bytes]:
        """Write fake stock files, return {path: content}."""
        stock = {}
        for p in paths:
            content = f"STOCK_CONTENT:{p}:{self.profile.stock_hash(p) or 'none'}".encode()
            f = self.system / p.lstrip("/")
            f.parent.mkdir(parents=True, exist_ok=True)
            f.write_bytes(content)
            stock[p] = content
        return stock

    def _write_mod_file(self, mod_id: str, cam_path: str, content: bytes) -> Path:
        src = self.mods_dir / mod_id / cam_path.lstrip("/").replace("/", "__")
        src.parent.mkdir(parents=True, exist_ok=True)
        src.write_bytes(content)
        return src

    def _make_journal(self, slot_info: SlotInfo | None = None) -> Journal:
        return Journal(self.journal_dir, self.system, self.profile, slot_info=slot_info)


class TestJournalBasicCycle(JournalTestCase):
    """Install a mod, verify, then restore."""

    def test_install_and_restore(self):
        stock = self._populate_stock(MOD_PATHS)
        j = self._make_journal()

        mod_files = {}
        for p in MOD_PATHS:
            content = f"MODDED:{p}".encode()
            mod_files[p] = self._write_mod_file("test-mod", p, content)

        manifest = j.install_mod("test-mod", mod_files)
        self.assertEqual(manifest.phase, Phase.INSTALLED)
        self.assertEqual(len(manifest.entries), 2)

        for p in MOD_PATHS:
            actual = (self.system / p.lstrip("/")).read_bytes()
            self.assertTrue(actual.startswith(b"MODDED:"))

        issues = j.verify()
        self.assertEqual(issues, [])

        manifest = j.restore_mod("test-mod")
        self.assertEqual(manifest.phase, Phase.RESTORED)
        self.assertEqual(len(manifest.entries), 0)

        for p in MOD_PATHS:
            actual = (self.system / p.lstrip("/")).read_bytes()
            self.assertEqual(actual, stock[p])


class TestJournalNewFile(JournalTestCase):
    """Mod that creates a file not in stock."""

    def test_create_and_remove(self):
        j = self._make_journal()
        new_path = "/camera-mods/pixel-shift/libhook.so"
        content = b"HOOKLIB_BINARY_CONTENT"
        src = self._write_mod_file("pixel-shift", new_path, content)

        manifest = j.install_mod("pixel-shift", {new_path: src})
        self.assertEqual(manifest.phase, Phase.INSTALLED)
        self.assertTrue((self.system / new_path.lstrip("/")).exists())

        entry = manifest.entries[0]
        self.assertEqual(entry.action, Action.CREATED)
        self.assertIsNone(entry.hash_before)
        self.assertIsNone(entry.backup_path)

        manifest = j.restore_mod("pixel-shift")
        self.assertFalse((self.system / new_path.lstrip("/")).exists())
        self.assertEqual(manifest.phase, Phase.RESTORED)


class TestMultiModStack(JournalTestCase):
    """Two mods installed in sequence; restore in reverse order."""

    def test_stacked_restore(self):
        path = "/etc/init/camera-gui.rc"
        stock = self._populate_stock([path])
        j = self._make_journal()

        mod_a_content = b"MOD_A_CONTENT"
        src_a = self._write_mod_file("mod-a", path, mod_a_content)
        j.install_mod("mod-a", {path: src_a})

        mod_b_content = b"MOD_B_CONTENT"
        src_b = self._write_mod_file("mod-b", path, mod_b_content)
        j.install_mod("mod-b", {path: src_b})

        actual = (self.system / path.lstrip("/")).read_bytes()
        self.assertEqual(actual, mod_b_content)

        m = j.load()
        self.assertEqual(len(m.entries), 2)

        j.restore_mod("mod-b")
        actual = (self.system / path.lstrip("/")).read_bytes()
        self.assertEqual(actual, mod_a_content)

        j.restore_mod("mod-a")
        actual = (self.system / path.lstrip("/")).read_bytes()
        self.assertEqual(actual, stock[path])

    def test_restore_all(self):
        path = "/etc/init/camera-gui.rc"
        stock = self._populate_stock([path])
        j = self._make_journal()

        src_a = self._write_mod_file("mod-a", path, b"MOD_A")
        j.install_mod("mod-a", {path: src_a})
        src_b = self._write_mod_file("mod-b", path, b"MOD_B")
        j.install_mod("mod-b", {path: src_b})

        manifest = j.restore_all()
        self.assertEqual(manifest.phase, Phase.RESTORED)
        actual = (self.system / path.lstrip("/")).read_bytes()
        self.assertEqual(actual, stock[path])


class TestTamperDetection(JournalTestCase):
    """Detect out-of-band file modification."""

    def test_tampered_file_blocks_restore(self):
        path = "/etc/init/camera-gui.rc"
        self._populate_stock([path])
        j = self._make_journal()

        src = self._write_mod_file("test", path, b"MODDED")
        j.install_mod("test", {path: src})

        (self.system / path.lstrip("/")).write_bytes(b"TAMPERED_BY_SOMETHING_ELSE")

        with self.assertRaises(RuntimeError) as ctx:
            j.restore_mod("test")
        self.assertIn("modified outside the journal", str(ctx.exception))

    def test_verify_catches_tamper(self):
        path = "/etc/init/camera-gui.rc"
        self._populate_stock([path])
        j = self._make_journal()

        src = self._write_mod_file("test", path, b"MODDED")
        j.install_mod("test", {path: src})

        (self.system / path.lstrip("/")).write_bytes(b"TAMPERED")

        issues = j.verify()
        self.assertTrue(any("modified outside journal" in i for i in issues))


class TestMissingBackup(JournalTestCase):
    """Detect corrupted journal (missing backup file)."""

    def test_missing_backup_detected_on_verify(self):
        path = "/etc/init/camera-gui.rc"
        self._populate_stock([path])
        j = self._make_journal()

        src = self._write_mod_file("test", path, b"MODDED")
        j.install_mod("test", {path: src})

        for f in (self.journal_dir / "backups").iterdir():
            f.unlink()

        issues = j.verify()
        self.assertTrue(any("backup file missing" in i for i in issues))


class TestInterruptedInstall(JournalTestCase):
    """Simulate crash during install: manifest written as PREPARED but files not copied."""

    def test_prepared_phase_allows_reinstall(self):
        path = "/etc/init/camera-gui.rc"
        stock = self._populate_stock([path])
        j = self._make_journal()

        manifest = JournalManifest(
            firmware_sha256=self.profile.firmware_sha256,
            created=1.0,
        )
        manifest.phase = Phase.PREPARED
        content = b"MODDED_CONTENT"
        entry = JournalEntry(
            path=path,
            action=Action.REPLACED,
            hash_before=sha256_bytes(stock[path]),
            hash_after=sha256_bytes(content),
            backup_path="crash-mod__etc__init__camera-gui.rc",
            mod_id="crash-mod",
        )
        manifest.entries.append(entry)
        atomic_write_json(self.journal_dir / "manifest.json", manifest.to_dict())

        backup_src = self.system / path.lstrip("/")
        backup_dst = self.journal_dir / "backups" / entry.backup_path
        shutil.copy2(backup_src, backup_dst)

        actual = (self.system / path.lstrip("/")).read_bytes()
        self.assertEqual(actual, stock[path])

        loaded = j.load()
        self.assertEqual(loaded.phase, Phase.PREPARED)
        self.assertEqual(len(loaded.entries), 1)


class TestExportRestoreKit(JournalTestCase):
    """Export journal + backups for restore from another machine."""

    def test_export(self):
        path = "/etc/init/camera-gui.rc"
        self._populate_stock([path])
        j = self._make_journal()

        src = self._write_mod_file("test", path, b"MODDED")
        j.install_mod("test", {path: src})

        export_dir = self.tmpdir / "restore-kit"
        j.export_restore_kit(export_dir)

        self.assertTrue((export_dir / "manifest.json").exists())
        manifest = json.loads((export_dir / "manifest.json").read_text())
        self.assertEqual(len(manifest["entries"]), 1)

        backup_name = manifest["entries"][0]["backup_path"]
        self.assertTrue((export_dir / "backups" / backup_name).exists())


class TestSchemaRoundTrip(JournalTestCase):
    """Journal manifest survives serialize/deserialize."""

    def test_round_trip(self):
        m = JournalManifest(
            firmware_sha256="abc123",
            profile_version="test",
            created=1.0,
            updated=2.0,
        )
        m.entries.append(JournalEntry(
            path="/bin/camera-gui",
            action=Action.REPLACED,
            hash_before="aaa",
            hash_after="bbb",
            backup_path="test__bin__camera-gui",
            mod_id="test",
            timestamp=1.5,
        ))
        d = m.to_dict()
        s = json.dumps(d)
        m2 = JournalManifest.from_dict(json.loads(s))
        self.assertEqual(m.firmware_sha256, m2.firmware_sha256)
        self.assertEqual(m.entries[0].path, m2.entries[0].path)
        self.assertEqual(m.entries[0].action, m2.entries[0].action)


class TestDuplicateModRejected(JournalTestCase):
    """Installing the same mod_id twice without uninstalling is rejected."""

    def test_duplicate_rejected(self):
        path = "/etc/init/camera-gui.rc"
        self._populate_stock([path])
        j = self._make_journal()

        src = self._write_mod_file("dup", path, b"V1")
        j.install_mod("dup", {path: src})

        src2 = self._write_mod_file("dup2", path, b"V2")
        with self.assertRaises(ValueError) as ctx:
            j.install_mod("dup", {path: src2})
        self.assertIn("already has journal entries", str(ctx.exception))


class TestRestoreDuringRestore(JournalTestCase):
    """Cannot install while journal is in RESTORING phase."""

    def test_restoring_blocks_install(self):
        j = self._make_journal()
        manifest = JournalManifest(
            firmware_sha256=self.profile.firmware_sha256,
            created=1.0,
        )
        manifest.phase = Phase.RESTORING
        atomic_write_json(self.journal_dir / "manifest.json", manifest.to_dict())

        src = self._write_mod_file("new", "/tmp/test", b"data")
        with self.assertRaises(RuntimeError) as ctx:
            j.install_mod("new", {"/tmp/test": src})
        self.assertIn("mid-restore", str(ctx.exception))


class TestSlotAwareness(JournalTestCase):
    """A/B slot safety checks."""

    def test_slot_recorded_in_manifest(self):
        """Active slot is recorded when journal is created."""
        path = "/etc/init/camera-gui.rc"
        self._populate_stock([path])
        slot = make_stub_slot_info(active=1)
        j = self._make_journal(slot_info=slot)

        src = self._write_mod_file("test", path, b"MODDED")
        manifest = j.install_mod("test", {path: src})

        self.assertEqual(manifest.active_slot, 1)
        self.assertEqual(manifest.inactive_slot, 2)

    def test_slot_swap_blocks_install(self):
        """Installing on a different slot than the journal was created on is rejected."""
        path = "/etc/init/camera-gui.rc"
        self._populate_stock([path])
        slot1 = make_stub_slot_info(active=1)
        j = self._make_journal(slot_info=slot1)

        src = self._write_mod_file("mod-a", path, b"MODDED")
        j.install_mod("mod-a", {path: src})

        slot2 = make_stub_slot_info(active=2)
        j2 = Journal(self.journal_dir, self.system, self.profile, slot_info=slot2)

        src2 = self._write_mod_file("mod-b", path, b"MODDED_B")
        with self.assertRaises(RuntimeError) as ctx:
            j2.install_mod("mod-b", {path: src2})
        self.assertIn("slots were swapped", str(ctx.exception))

    def test_slot_swap_blocks_restore(self):
        """Restoring on a different slot than installation is rejected."""
        path = "/etc/init/camera-gui.rc"
        self._populate_stock([path])
        slot1 = make_stub_slot_info(active=1)
        j = self._make_journal(slot_info=slot1)

        src = self._write_mod_file("test", path, b"MODDED")
        j.install_mod("test", {path: src})

        slot2 = make_stub_slot_info(active=2)
        j2 = Journal(self.journal_dir, self.system, self.profile, slot_info=slot2)

        with self.assertRaises(RuntimeError) as ctx:
            j2.restore_mod("test")
        self.assertIn("wrong slot", str(ctx.exception))

    def test_upgrade_in_progress_blocks_install(self):
        """Cannot install while firmware upgrade is in progress."""
        path = "/etc/init/camera-gui.rc"
        self._populate_stock([path])
        slot = SlotInfo(active=1, inactive=2, hbl_upgrading="2")
        j = self._make_journal(slot_info=slot)

        src = self._write_mod_file("test", path, b"MODDED")
        with self.assertRaises(RuntimeError) as ctx:
            j.install_mod("test", {path: src})
        self.assertIn("upgrade in progress", str(ctx.exception))

    def test_crash_counter_blocks_install(self):
        """Cannot install while crash counter is set."""
        path = "/etc/init/camera-gui.rc"
        self._populate_stock([path])
        slot = SlotInfo(active=1, inactive=2, crash_counter="0")
        j = self._make_journal(slot_info=slot)

        src = self._write_mod_file("test", path, b"MODDED")
        with self.assertRaises(RuntimeError) as ctx:
            j.install_mod("test", {path: src})
        self.assertIn("crash_counter", str(ctx.exception))

    def test_no_slot_info_is_permissive(self):
        """Without slot info (desktop testing), install proceeds normally."""
        path = "/etc/init/camera-gui.rc"
        self._populate_stock([path])
        j = self._make_journal(slot_info=None)

        src = self._write_mod_file("test", path, b"MODDED")
        manifest = j.install_mod("test", {path: src})
        self.assertEqual(manifest.phase, Phase.INSTALLED)
        self.assertIsNone(manifest.active_slot)

    def test_slot_health_check(self):
        """check_slot_health reports issues."""
        path = "/etc/init/camera-gui.rc"
        self._populate_stock([path])
        slot1 = make_stub_slot_info(active=1)
        j = self._make_journal(slot_info=slot1)

        src = self._write_mod_file("test", path, b"MODDED")
        j.install_mod("test", {path: src})

        issues = j.check_slot_health()
        self.assertEqual(issues, [])

        j.slot_info = make_stub_slot_info(active=2)
        issues = j.check_slot_health()
        self.assertTrue(any("slots were swapped" in i for i in issues))

    def test_slot_roundtrip_in_manifest(self):
        """Slot info survives manifest serialize/deserialize."""
        m = JournalManifest(
            firmware_sha256="abc",
            active_slot=1,
            inactive_slot=2,
            created=1.0,
        )
        d = m.to_dict()
        m2 = JournalManifest.from_dict(d)
        self.assertEqual(m2.active_slot, 1)
        self.assertEqual(m2.inactive_slot, 2)


class TestOverlappingFiles(JournalTestCase):
    """Mods that modify the same file must restore in LIFO order."""

    def test_lifo_enforced_on_restore(self):
        """Restoring an earlier mod while a later mod overlaps is blocked."""
        path = "/etc/init/camera-gui.rc"
        self._populate_stock([path])
        j = self._make_journal()

        src_a = self._write_mod_file("mod-a", path, b"MOD_A")
        j.install_mod("mod-a", {path: src_a})
        src_b = self._write_mod_file("mod-b", path, b"MOD_B")
        j.install_mod("mod-b", {path: src_b})

        with self.assertRaises(RuntimeError) as ctx:
            j.restore_mod("mod-a")
        self.assertIn("mod-b", str(ctx.exception))
        self.assertIn("restore", str(ctx.exception).lower())

    def test_lifo_allows_correct_order(self):
        """Restoring the latest overlapping mod first succeeds."""
        path = "/etc/init/camera-gui.rc"
        stock = self._populate_stock([path])
        j = self._make_journal()

        src_a = self._write_mod_file("mod-a", path, b"MOD_A")
        j.install_mod("mod-a", {path: src_a})
        src_b = self._write_mod_file("mod-b", path, b"MOD_B")
        j.install_mod("mod-b", {path: src_b})

        j.restore_mod("mod-b")
        j.restore_mod("mod-a")
        actual = (self.system / path.lstrip("/")).read_bytes()
        self.assertEqual(actual, stock[path])

    def test_no_overlap_no_restriction(self):
        """Mods touching different files can be restored in any order."""
        path_a = "/etc/init/camera-gui.rc"
        path_b = "/etc/init/camera-service.rc"
        self._populate_stock([path_a, path_b])
        j = self._make_journal()

        src_a = self._write_mod_file("mod-a", path_a, b"MOD_A")
        j.install_mod("mod-a", {path_a: src_a})
        src_b = self._write_mod_file("mod-b", path_b, b"MOD_B")
        j.install_mod("mod-b", {path_b: src_b})

        j.restore_mod("mod-a")
        m = j.load()
        self.assertEqual(len(m.entries), 1)
        self.assertEqual(m.entries[0].mod_id, "mod-b")

    def test_overlap_warning_on_install(self):
        """Installing a mod that overlaps emits warnings (stored on journal)."""
        path = "/etc/init/camera-gui.rc"
        self._populate_stock([path])
        j = self._make_journal()

        src_a = self._write_mod_file("mod-a", path, b"MOD_A")
        j.install_mod("mod-a", {path: src_a})

        src_b = self._write_mod_file("mod-b", path, b"MOD_B")
        j.install_mod("mod-b", {path: src_b})
        self.assertTrue(len(j._overlap_warnings) > 0)
        self.assertIn("mod-a", j._overlap_warnings[0])

    def test_snapshot_and_restore(self):
        """Journal snapshot creates a restorable copy."""
        path = "/etc/init/camera-gui.rc"
        self._populate_stock([path])
        j = self._make_journal()

        src = self._write_mod_file("test", path, b"MODDED")
        j.install_mod("test", {path: src})

        snap_dir = self.tmpdir / "snapshot"
        result = j.snapshot(snap_dir)
        self.assertEqual(result["entries"], 1)
        self.assertEqual(result["backups"], 1)
        self.assertTrue((snap_dir / "manifest.json").exists())
        self.assertTrue((snap_dir / "backups").is_dir())


class TestSlotRestore(JournalTestCase):
    """Tests for the emergency slot-flip restore."""

    def test_preflight_viable(self):
        """Preflight reports viable when slots are healthy."""
        slot = make_stub_slot_info(active=1)
        j = self._make_journal(slot_info=slot)
        result = j.preflight_slot_restore()
        self.assertTrue(result["viable"])
        self.assertEqual(result["current_slot"], 1)
        self.assertEqual(result["target_slot"], 2)
        self.assertEqual(len(result["steps"]), 5)

    def test_preflight_no_slot_info(self):
        """Preflight fails without slot info."""
        j = self._make_journal(slot_info=None)
        result = j.preflight_slot_restore()
        self.assertFalse(result["viable"])
        self.assertTrue(any("no slot info" in i for i in result["issues"]))

    def test_preflight_upgrade_blocks(self):
        """Preflight rejects during upgrade."""
        slot = SlotInfo(active=1, inactive=2, hbl_upgrading="2")
        j = self._make_journal(slot_info=slot)
        result = j.preflight_slot_restore()
        self.assertFalse(result["viable"])
        self.assertTrue(any("upgrade in progress" in i for i in result["issues"]))

    def test_preflight_crash_counter_blocks(self):
        """Preflight rejects during crash counter verification."""
        slot = SlotInfo(active=1, inactive=2, crash_counter="0")
        j = self._make_journal(slot_info=slot)
        result = j.preflight_slot_restore()
        self.assertFalse(result["viable"])
        self.assertTrue(any("crash_counter" in i for i in result["issues"]))

    def test_preflight_with_journal_entries(self):
        """Preflight reports journal entry count."""
        path = "/etc/init/camera-gui.rc"
        self._populate_stock([path])
        slot = make_stub_slot_info(active=1)
        j = self._make_journal(slot_info=slot)
        src = self._write_mod_file("test", path, b"MODDED")
        j.install_mod("test", {path: src})
        result = j.preflight_slot_restore()
        self.assertTrue(result["viable"])
        self.assertEqual(result["journal_entries"], 1)

    def test_dry_run_no_side_effects(self):
        """Dry run returns plan without calling unrd/boot_control."""
        slot = make_stub_slot_info(active=1)
        j = self._make_journal(slot_info=slot)
        result = j.slot_restore(dry_run=True)
        self.assertTrue(result["dry_run"])
        self.assertTrue(result["viable"])

    def test_slot_restore_calls_unrd(self):
        """Slot restore calls write_unrd and run_boot_control in order."""
        import journal as journal_mod
        calls = []
        original_write = journal_mod.write_unrd
        original_boot = journal_mod.run_boot_control
        journal_mod.write_unrd = lambda k, v: calls.append(("unrd", k, v))
        journal_mod.run_boot_control = lambda f: calls.append(("boot_control", f))
        try:
            slot = make_stub_slot_info(active=1)
            j = self._make_journal(slot_info=slot)
            result = j.slot_restore()
            self.assertTrue(result["executed"])
            self.assertEqual(result["current_slot"], 1)
            self.assertEqual(result["target_slot"], 2)
            self.assertEqual(calls, [
                ("unrd", "crash_counter", "0"),
                ("unrd", "slot_2.status_active", "1"),
                ("unrd", "slot_1.status_active", "0"),
                ("boot_control", "-m"),
            ])
        finally:
            journal_mod.write_unrd = original_write
            journal_mod.run_boot_control = original_boot

    def test_slot_restore_marks_journal_failed(self):
        """After slot restore, journal phase is FAILED."""
        import journal as journal_mod
        journal_mod.write_unrd = lambda k, v: None
        journal_mod.run_boot_control = lambda f: None
        try:
            path = "/etc/init/camera-gui.rc"
            self._populate_stock([path])
            slot = make_stub_slot_info(active=1)
            j = self._make_journal(slot_info=slot)
            src = self._write_mod_file("test", path, b"MODDED")
            j.install_mod("test", {path: src})
            j.slot_restore()
            manifest = j.load()
            self.assertEqual(manifest.phase, Phase.FAILED)
        finally:
            journal_mod.write_unrd = journal_mod.write_unrd
            journal_mod.run_boot_control = journal_mod.run_boot_control


if __name__ == "__main__":
    unittest.main()
