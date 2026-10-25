"""Version-independent undo journal for Hasselblad camera modifications.

Offline module. Never contacts a camera. Provides:
  - StockProfile: loads a firmware profile as the "known clean" reference
  - SlotInfo: reads A/B partition slot status from unrd
  - Journal: records file changes, supports atomic install and full restore

The journal lives on-camera at /blackbox/modjournal/ and is self-describing:
any version of this engine can read and restore from any journal it finds.

Slot awareness: the camera has two system slots (A/B). Official updates write
the inactive slot and flip. Mods write the active slot. The journal records
which slot was active at install time and enforces:
  - All mods target the same slot
  - The inactive slot is never modified (it's the crash fallback)
  - A warning is emitted if the inactive slot's state is unknown
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import time
from dataclasses import dataclass, field, asdict
from enum import Enum
from pathlib import Path


class Phase(str, Enum):
    PREPARED = "PREPARED"
    INSTALLED = "INSTALLED"
    RESTORING = "RESTORING"
    RESTORED = "RESTORED"
    FAILED = "FAILED"


class Action(str, Enum):
    CREATED = "created"
    REPLACED = "replaced"


@dataclass
class SlotInfo:
    """A/B partition slot status from unrd."""
    active: int | None = None      # 1 or 2
    inactive: int | None = None    # 1 or 2
    crash_counter: str | None = None
    hbl_upgrading: str | None = None

    def to_dict(self) -> dict:
        return {
            "active": self.active,
            "inactive": self.inactive,
            "crash_counter": self.crash_counter,
            "hbl_upgrading": self.hbl_upgrading,
        }

    @classmethod
    def from_dict(cls, d: dict | None) -> SlotInfo | None:
        if d is None:
            return None
        return cls(
            active=d.get("active"),
            inactive=d.get("inactive"),
            crash_counter=d.get("crash_counter"),
            hbl_upgrading=d.get("hbl_upgrading"),
        )

    @property
    def upgrade_in_progress(self) -> bool:
        return self.hbl_upgrading is not None

    @property
    def has_crash_counter(self) -> bool:
        return self.crash_counter is not None


def read_slot_info() -> SlotInfo:
    """Read A/B slot status from unrd. Raises if unrd is unavailable."""
    try:
        raw = subprocess.check_output(["/sbin/unrd"], text=True, timeout=5)
    except (FileNotFoundError, subprocess.SubprocessError) as e:
        raise RuntimeError(f"cannot read slot info: {e}") from e

    info = SlotInfo()
    for line in raw.splitlines():
        m = re.match(r"slot_(\d+)\.status_active\s+(\d+)", line.strip())
        if m:
            slot, active = int(m.group(1)), int(m.group(2))
            if active == 1:
                info.active = slot
            else:
                info.inactive = slot
        if "crash_counter" in line:
            info.crash_counter = line.split()[-1] if line.split() else "0"
        if "hbl_upgrading" in line:
            info.hbl_upgrading = line.split()[-1] if line.split() else None

    return info


def write_unrd(key: str, value: str) -> None:
    """Write a value to unrd. Raises if unrd is unavailable."""
    try:
        subprocess.check_call(["/sbin/unrd", key, value], timeout=5)
    except (FileNotFoundError, subprocess.SubprocessError) as e:
        raise RuntimeError(f"cannot write unrd {key}={value}: {e}") from e


def run_boot_control(flag: str) -> None:
    """Run boot_control with a single flag. Raises on failure."""
    try:
        subprocess.check_call(["boot_control", flag], timeout=10)
    except (FileNotFoundError, subprocess.SubprocessError) as e:
        raise RuntimeError(f"boot_control {flag} failed: {e}") from e


def make_stub_slot_info(active: int) -> SlotInfo:
    """Build a SlotInfo for testing without a real camera."""
    inactive = 2 if active == 1 else 1
    return SlotInfo(active=active, inactive=inactive)


@dataclass
class JournalEntry:
    path: str
    action: Action
    hash_before: str | None
    hash_after: str
    backup_path: str | None
    mod_id: str
    timestamp: float = 0.0

    def to_dict(self) -> dict:
        return {
            "path": self.path,
            "action": self.action.value,
            "hash_before": self.hash_before,
            "hash_after": self.hash_after,
            "backup_path": self.backup_path,
            "mod_id": self.mod_id,
            "timestamp": self.timestamp,
        }

    @classmethod
    def from_dict(cls, d: dict) -> JournalEntry:
        return cls(
            path=d["path"],
            action=Action(d["action"]),
            hash_before=d.get("hash_before"),
            hash_after=d["hash_after"],
            backup_path=d.get("backup_path"),
            mod_id=d["mod_id"],
            timestamp=d.get("timestamp", 0.0),
        )


@dataclass
class JournalManifest:
    schema: int = 4
    phase: Phase = Phase.PREPARED
    firmware_sha256: str = ""
    profile_version: str = ""
    active_slot: int | None = None
    inactive_slot: int | None = None
    entries: list[JournalEntry] = field(default_factory=list)
    created: float = 0.0
    updated: float = 0.0

    def to_dict(self) -> dict:
        return {
            "schema": self.schema,
            "phase": self.phase.value,
            "firmware_sha256": self.firmware_sha256,
            "profile_version": self.profile_version,
            "active_slot": self.active_slot,
            "inactive_slot": self.inactive_slot,
            "entries": [e.to_dict() for e in self.entries],
            "created": self.created,
            "updated": self.updated,
        }

    @classmethod
    def from_dict(cls, d: dict) -> JournalManifest:
        if d.get("schema") != 4:
            raise ValueError(f"unsupported journal schema {d.get('schema')}")
        return cls(
            schema=d["schema"],
            phase=Phase(d["phase"]),
            firmware_sha256=d["firmware_sha256"],
            profile_version=d.get("profile_version", ""),
            active_slot=d.get("active_slot"),
            inactive_slot=d.get("inactive_slot"),
            entries=[JournalEntry.from_dict(e) for e in d["entries"]],
            created=d.get("created", 0.0),
            updated=d.get("updated", 0.0),
        )


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while chunk := f.read(1 << 20):
            h.update(chunk)
    return h.hexdigest()


def atomic_write_json(path: Path, data: dict) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, indent=1, sort_keys=False) + "\n", encoding="utf-8")
    os.replace(tmp, path)


def atomic_copy(src: Path, dst: Path) -> None:
    tmp = dst.with_suffix(dst.suffix + ".tmp")
    shutil.copy2(src, tmp)
    os.replace(tmp, dst)


class StockProfile:
    """Loaded firmware profile: the known-clean state of every file."""

    def __init__(self, profile_path: Path):
        raw = json.loads(profile_path.read_text(encoding="utf-8"))
        self.firmware = raw["firmware"]
        self.firmware_sha256 = self.firmware["sha256"]
        self._files: dict[str, dict] = {}
        for part_name, part in raw.get("partitions", {}).items():
            if part.get("format") != "ext4":
                continue
            for entry in part.get("entries", []):
                if entry.get("type") == "file" and "sha256" in entry:
                    self._files[entry["path"]] = entry

    def stock_hash(self, path: str) -> str | None:
        entry = self._files.get(path)
        return entry["sha256"] if entry else None

    def is_stock(self, path: str, current_hash: str) -> bool:
        expected = self.stock_hash(path)
        return expected is not None and expected == current_hash

    def has_path(self, path: str) -> bool:
        return path in self._files

    def __contains__(self, path: str) -> bool:
        return path in self._files


class Journal:
    """On-device undo journal with atomic writes and A/B slot awareness.

    journal_root: directory for journal data (on camera: /blackbox/modjournal/)
    system_root: the mounted /system partition (or a stub for testing)
    profile: loaded stock firmware profile
    slot_info: current A/B slot status (None for desktop testing)
    """

    MANIFEST = "manifest.json"
    BACKUPS = "backups"

    def __init__(self, journal_root: Path, system_root: Path, profile: StockProfile,
                 slot_info: SlotInfo | None = None):
        self.root = journal_root
        self.system = system_root
        self.profile = profile
        self.slot_info = slot_info
        self.root.mkdir(parents=True, exist_ok=True)
        (self.root / self.BACKUPS).mkdir(exist_ok=True)

    def _manifest_path(self) -> Path:
        return self.root / self.MANIFEST

    def load(self) -> JournalManifest | None:
        p = self._manifest_path()
        if not p.exists():
            return None
        return JournalManifest.from_dict(json.loads(p.read_text(encoding="utf-8")))

    def _save(self, manifest: JournalManifest) -> None:
        manifest.updated = time.time()
        atomic_write_json(self._manifest_path(), manifest.to_dict())

    def _backup_name(self, path: str, mod_id: str) -> str:
        safe = path.lstrip("/").replace("/", "__")
        return f"{mod_id}__{safe}"

    def _system_path(self, path: str) -> Path:
        return self.system / path.lstrip("/")

    def _check_slot_safety(self, manifest: JournalManifest) -> list[str]:
        """Verify slot state is safe for modification. Returns warnings."""
        warnings = []
        if self.slot_info is None:
            return warnings

        if self.slot_info.upgrade_in_progress:
            raise RuntimeError(
                "firmware upgrade in progress (hbl_upgrading set); "
                "do not modify until upgrade completes"
            )

        if self.slot_info.has_crash_counter:
            raise RuntimeError(
                "crash_counter is set — camera may be in post-upgrade verification; "
                "do not modify until next clean boot"
            )

        if self.slot_info.active is None:
            warnings.append("could not determine active slot from unrd")
            return warnings

        if manifest.active_slot is not None and manifest.active_slot != self.slot_info.active:
            raise RuntimeError(
                f"journal was created on slot {manifest.active_slot} but "
                f"slot {self.slot_info.active} is now active — slots were swapped "
                f"(official update?). Restore mods on the original slot first."
            )

        return warnings

    def _file_overlap(self, manifest: JournalManifest, mod_id: str,
                       paths: set[str]) -> list[str]:
        """Return warnings about files that other mods already touch."""
        warnings = []
        for entry in manifest.entries:
            if entry.mod_id == mod_id:
                continue
            if entry.path in paths:
                warnings.append(
                    f"{entry.path} already modified by {entry.mod_id!r}; "
                    f"restore order matters (LIFO: restore {mod_id!r} before "
                    f"{entry.mod_id!r})"
                )
        return warnings

    def _restore_order_check(self, manifest: JournalManifest,
                              mod_id: str) -> list[str]:
        """Check that restoring mod_id won't break overlapping mods.

        If a later mod also touches a file this mod touched, that later mod
        must be restored first (LIFO). Returns blocking errors.
        """
        mod_paths = {e.path for e in manifest.entries if e.mod_id == mod_id}
        errors = []
        later_mods_seen = False
        for entry in manifest.entries:
            if entry.mod_id == mod_id:
                later_mods_seen = True
                continue
            if later_mods_seen and entry.path in mod_paths:
                errors.append(
                    f"cannot restore {mod_id!r} — {entry.mod_id!r} later "
                    f"modified {entry.path}; restore {entry.mod_id!r} first"
                )
        return errors

    def install_mod(self, mod_id: str, files: dict[str, Path]) -> JournalManifest:
        """Install a mod: back up originals, write new files, record in journal.

        files: {camera_path: local_source_path}
        Returns the updated manifest.
        Warns (but proceeds) if files overlap with another mod.
        """
        manifest = self.load()
        if manifest is None:
            manifest = JournalManifest(
                firmware_sha256=self.profile.firmware_sha256,
                profile_version=self.profile.firmware.get("build", ""),
                created=time.time(),
            )
            if self.slot_info and self.slot_info.active is not None:
                manifest.active_slot = self.slot_info.active
                manifest.inactive_slot = self.slot_info.inactive

        if manifest.phase == Phase.RESTORING:
            raise RuntimeError("journal is mid-restore; complete restore before installing")

        self._check_slot_safety(manifest)

        existing_mods = {e.mod_id for e in manifest.entries}
        if mod_id in existing_mods:
            raise ValueError(f"mod {mod_id!r} already has journal entries; uninstall first")

        self._overlap_warnings = self._file_overlap(
            manifest, mod_id, set(files.keys())
        )

        new_entries = []
        for cam_path, source in files.items():
            sys_file = self._system_path(cam_path)
            source_hash = sha256_file(source)

            if sys_file.exists():
                current_hash = sha256_file(sys_file)
                backup_name = self._backup_name(cam_path, mod_id)
                backup_path = self.root / self.BACKUPS / backup_name
                atomic_copy(sys_file, backup_path)

                entry = JournalEntry(
                    path=cam_path,
                    action=Action.REPLACED,
                    hash_before=current_hash,
                    hash_after=source_hash,
                    backup_path=backup_name,
                    mod_id=mod_id,
                    timestamp=time.time(),
                )
            else:
                entry = JournalEntry(
                    path=cam_path,
                    action=Action.CREATED,
                    hash_before=None,
                    hash_after=source_hash,
                    backup_path=None,
                    mod_id=mod_id,
                    timestamp=time.time(),
                )

            new_entries.append(entry)

        manifest.entries.extend(new_entries)
        manifest.phase = Phase.PREPARED
        self._save(manifest)

        for entry in new_entries:
            source = files[entry.path]
            sys_file = self._system_path(entry.path)
            sys_file.parent.mkdir(parents=True, exist_ok=True)
            atomic_copy(source, sys_file)

        manifest.phase = Phase.INSTALLED
        self._save(manifest)
        return manifest

    def restore_mod(self, mod_id: str) -> JournalManifest:
        """Restore a single mod's changes using the journal.

        Enforces LIFO ordering: if a later mod also modified a file this mod
        touched, that later mod must be restored first.
        """
        manifest = self.load()
        if manifest is None:
            raise RuntimeError("no journal found")

        mod_entries = [e for e in manifest.entries if e.mod_id == mod_id]
        if not mod_entries:
            raise ValueError(f"no journal entries for mod {mod_id!r}")

        if (self.slot_info and self.slot_info.active is not None
                and manifest.active_slot is not None
                and manifest.active_slot != self.slot_info.active):
            raise RuntimeError(
                f"journal targets slot {manifest.active_slot} but "
                f"slot {self.slot_info.active} is now active — "
                f"cannot restore on the wrong slot"
            )

        order_errors = self._restore_order_check(manifest, mod_id)
        if order_errors:
            raise RuntimeError(order_errors[0])

        manifest.phase = Phase.RESTORING
        self._save(manifest)

        for entry in reversed(mod_entries):
            sys_file = self._system_path(entry.path)

            if not sys_file.exists():
                if entry.action == Action.CREATED:
                    pass
                else:
                    raise RuntimeError(
                        f"expected file at {entry.path} but it is missing"
                    )
                continue

            current_hash = sha256_file(sys_file)
            if current_hash != entry.hash_after:
                raise RuntimeError(
                    f"{entry.path}: current hash {current_hash[:16]}… != journal "
                    f"after hash {entry.hash_after[:16]}…; file was modified outside the journal"
                )

            if entry.action == Action.CREATED:
                sys_file.unlink()
            elif entry.action == Action.REPLACED:
                backup = self.root / self.BACKUPS / entry.backup_path
                if not backup.exists():
                    raise RuntimeError(f"backup missing for {entry.path}")
                backup_hash = sha256_file(backup)
                if entry.hash_before and backup_hash != entry.hash_before:
                    raise RuntimeError(
                        f"backup hash mismatch for {entry.path}"
                    )
                atomic_copy(backup, sys_file)

                restored_hash = sha256_file(sys_file)
                if entry.hash_before and restored_hash != entry.hash_before:
                    raise RuntimeError(
                        f"{entry.path}: restored file hash doesn't match recorded before-hash"
                    )

                backup.unlink()

        manifest.entries = [e for e in manifest.entries if e.mod_id != mod_id]
        if manifest.entries:
            manifest.phase = Phase.INSTALLED
        else:
            manifest.phase = Phase.RESTORED
        self._save(manifest)
        return manifest

    def restore_all(self) -> JournalManifest:
        """Restore all mods in reverse order."""
        manifest = self.load()
        if manifest is None:
            raise RuntimeError("no journal found")

        mod_ids = []
        seen = set()
        for entry in reversed(manifest.entries):
            if entry.mod_id not in seen:
                mod_ids.append(entry.mod_id)
                seen.add(entry.mod_id)

        for mod_id in mod_ids:
            manifest = self.restore_mod(mod_id)
        return manifest

    def verify(self) -> list[str]:
        """Check journal integrity without changing anything. Returns list of issues."""
        manifest = self.load()
        if manifest is None:
            return ["no journal found"]

        issues = []
        for entry in manifest.entries:
            sys_file = self._system_path(entry.path)
            if not sys_file.exists():
                if entry.action == Action.REPLACED:
                    issues.append(f"{entry.path}: expected file missing")
                continue

            current_hash = sha256_file(sys_file)
            if current_hash != entry.hash_after:
                issues.append(
                    f"{entry.path}: current hash doesn't match journal "
                    f"(modified outside journal?)"
                )

            if entry.backup_path:
                backup = self.root / self.BACKUPS / entry.backup_path
                if not backup.exists():
                    issues.append(f"{entry.path}: backup file missing")
                elif entry.hash_before:
                    bh = sha256_file(backup)
                    if bh != entry.hash_before:
                        issues.append(f"{entry.path}: backup hash mismatch")

        return issues

    def snapshot(self, dest: Path) -> dict:
        """Create a timestamped snapshot of the entire journal directory.

        Copies manifest + all backups to dest. Returns summary dict.
        Unlike export_restore_kit, this preserves the exact directory layout
        so it can be dropped back in place as a full recovery.
        """
        manifest = self.load()
        if manifest is None:
            raise RuntimeError("no journal to snapshot")

        dest.mkdir(parents=True, exist_ok=True)
        atomic_write_json(dest / self.MANIFEST, manifest.to_dict())
        backup_src = self.root / self.BACKUPS
        backup_dest = dest / self.BACKUPS
        backup_dest.mkdir(exist_ok=True)
        copied = 0
        for f in backup_src.iterdir():
            if f.is_file():
                shutil.copy2(f, backup_dest / f.name)
                copied += 1
        return {
            "entries": len(manifest.entries),
            "backups": copied,
            "phase": manifest.phase.value,
            "dest": str(dest),
        }

    def export_restore_kit(self, dest: Path) -> Path:
        """Export journal + backups so restore can happen from another computer."""
        manifest = self.load()
        if manifest is None:
            raise RuntimeError("no journal to export")
        dest.mkdir(parents=True, exist_ok=True)
        atomic_write_json(dest / self.MANIFEST, manifest.to_dict())
        backup_dest = dest / self.BACKUPS
        backup_dest.mkdir(exist_ok=True)
        for entry in manifest.entries:
            if entry.backup_path:
                src = self.root / self.BACKUPS / entry.backup_path
                if src.exists():
                    shutil.copy2(src, backup_dest / entry.backup_path)
        return dest

    def check_slot_health(self) -> list[str]:
        """Pre-flight slot health check. Returns list of issues/warnings."""
        issues = []
        if self.slot_info is None:
            issues.append("no slot info available (desktop testing mode)")
            return issues

        if self.slot_info.active is None:
            issues.append("cannot determine active slot from unrd")
        if self.slot_info.inactive is None:
            issues.append("cannot determine inactive slot from unrd")
        if self.slot_info.upgrade_in_progress:
            issues.append(
                f"DANGER: firmware upgrade in progress "
                f"(hbl_upgrading={self.slot_info.hbl_upgrading})"
            )
        if self.slot_info.has_crash_counter:
            issues.append(
                f"WARNING: crash_counter={self.slot_info.crash_counter} — "
                f"camera may be verifying a recent update"
            )

        manifest = self.load()
        if manifest and manifest.active_slot is not None:
            if self.slot_info.active != manifest.active_slot:
                issues.append(
                    f"DANGER: journal targets slot {manifest.active_slot} but "
                    f"slot {self.slot_info.active} is now active — slots were "
                    f"swapped since mods were installed"
                )

        return issues

    def preflight_slot_restore(self) -> dict:
        """Assess whether a slot-flip restore is viable. Returns a status dict.

        This is a read-only check — it never modifies the camera.
        Works on-camera only (needs live slot_info).
        """
        result: dict = {
            "viable": False,
            "current_slot": None,
            "target_slot": None,
            "journal_entries": 0,
            "issues": [],
            "steps": [],
        }

        if self.slot_info is None:
            result["issues"].append("no slot info — must run on camera")
            return result

        if self.slot_info.active is None or self.slot_info.inactive is None:
            result["issues"].append("cannot determine both slots from unrd")
            return result

        result["current_slot"] = self.slot_info.active
        result["target_slot"] = self.slot_info.inactive

        if self.slot_info.upgrade_in_progress:
            result["issues"].append(
                f"upgrade in progress (hbl_upgrading={self.slot_info.hbl_upgrading}); "
                "wait for upgrade to finish"
            )
            return result

        if self.slot_info.has_crash_counter:
            result["issues"].append(
                f"crash_counter={self.slot_info.crash_counter}; "
                "camera is mid-verification — do not flip slots"
            )
            return result

        manifest = self.load()
        if manifest:
            result["journal_entries"] = len(manifest.entries)

        result["steps"] = [
            f"clear crash_counter (unrd crash_counter 0)",
            f"set slot {result['target_slot']} active (unrd slot_{result['target_slot']}.status_active 1)",
            f"set slot {result['current_slot']} inactive (unrd slot_{result['current_slot']}.status_active 0)",
            f"mark slot {result['target_slot']} bootable (boot_control -m)",
            "reboot into inactive slot with stock firmware",
        ]
        result["viable"] = True
        return result

    def slot_restore(self, *, dry_run: bool = False) -> dict:
        """Emergency restore: flip to the inactive slot (stock firmware).

        This is the nuclear option — it abandons all mods on the active slot
        and boots the inactive slot, which holds the last official firmware.

        Requires live slot_info (must run on camera).
        With dry_run=True, returns the plan without executing.
        """
        preflight = self.preflight_slot_restore()
        if not preflight["viable"]:
            raise RuntimeError(
                "slot restore not viable: " + "; ".join(preflight["issues"])
            )

        if dry_run:
            preflight["dry_run"] = True
            return preflight

        current = self.slot_info.active
        target = self.slot_info.inactive

        write_unrd("crash_counter", "0")
        write_unrd(f"slot_{target}.status_active", "1")
        write_unrd(f"slot_{current}.status_active", "0")
        run_boot_control("-m")

        manifest = self.load()
        if manifest:
            manifest.phase = Phase.FAILED
            manifest.updated = time.time()
            self._save(manifest)

        return {
            "executed": True,
            "current_slot": current,
            "target_slot": target,
            "action": "slot_flip",
            "journal_marked": "FAILED" if manifest else "no_journal",
            "next": "reboot to complete — inactive slot will become active",
        }

        return issues
