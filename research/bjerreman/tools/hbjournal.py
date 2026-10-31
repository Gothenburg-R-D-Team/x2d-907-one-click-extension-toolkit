#!/usr/bin/env python3
"""CLI for the Hasselblad undo-journal engine.

Offline tool. Never contacts a camera unless explicitly using 'health'
on a live system. All subcommands work against a local journal directory
and stock profile.

Subcommands:
  status   <journal-dir> <profile>           show journal state
  verify   <journal-dir> <system-root> <profile>   check integrity
  health   <journal-dir> <profile>           pre-flight slot check (on camera)
  list     <journal-dir> <profile>           list installed mods
  export   <journal-dir> <profile> <dest>    export restore kit
  dry-run  <mod-manifest> <profile>          preview what a mod would do
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from journal import (
    Journal, JournalManifest, Phase, StockProfile,
    read_slot_info, sha256_file, write_unrd, run_boot_control,
)


def fmt_time(ts: float) -> str:
    if ts == 0:
        return "—"
    return time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(ts))


def cmd_status(args):
    profile = StockProfile(Path(args.profile))
    journal_dir = Path(args.journal_dir)
    manifest_path = journal_dir / "manifest.json"

    if not manifest_path.exists():
        print("No journal found.")
        return

    manifest = JournalManifest.from_dict(
        json.loads(manifest_path.read_text(encoding="utf-8"))
    )

    print(f"Schema:          {manifest.schema}")
    print(f"Phase:           {manifest.phase.value}")
    print(f"Firmware:        {manifest.firmware_sha256[:16]}…")
    print(f"Profile version: {manifest.profile_version or '—'}")
    print(f"Active slot:     {manifest.active_slot or '—'}")
    print(f"Inactive slot:   {manifest.inactive_slot or '—'}")
    print(f"Created:         {fmt_time(manifest.created)}")
    print(f"Updated:         {fmt_time(manifest.updated)}")
    print(f"Entries:         {len(manifest.entries)}")

    mod_ids = []
    seen = set()
    for e in manifest.entries:
        if e.mod_id not in seen:
            mod_ids.append(e.mod_id)
            seen.add(e.mod_id)
    if mod_ids:
        print(f"\nInstalled mods ({len(mod_ids)}):")
        for mid in mod_ids:
            count = sum(1 for e in manifest.entries if e.mod_id == mid)
            print(f"  {mid}  ({count} file{'s' if count != 1 else ''})")


def cmd_verify(args):
    profile = StockProfile(Path(args.profile))
    j = Journal(Path(args.journal_dir), Path(args.system_root), profile)

    issues = j.verify()
    if not issues:
        print("Journal integrity OK — all files and backups match.")
    else:
        print(f"Found {len(issues)} issue(s):")
        for i in issues:
            print(f"  ✗ {i}")
        sys.exit(1)


def cmd_health(args):
    profile = StockProfile(Path(args.profile))
    try:
        slot_info = read_slot_info()
    except RuntimeError as e:
        print(f"Cannot read slot info: {e}")
        print("(This command must run on the camera.)")
        sys.exit(1)

    j = Journal(Path(args.journal_dir), Path("/system"), profile, slot_info=slot_info)
    issues = j.check_slot_health()

    print(f"Active slot:   {slot_info.active or '?'}")
    print(f"Inactive slot: {slot_info.inactive or '?'}")
    if slot_info.crash_counter is not None:
        print(f"Crash counter: {slot_info.crash_counter}")
    if slot_info.hbl_upgrading is not None:
        print(f"Upgrading:     slot {slot_info.hbl_upgrading}")

    if not issues:
        print("\nSlot health OK — safe to proceed.")
    else:
        print(f"\n{len(issues)} issue(s):")
        for i in issues:
            print(f"  {'✗' if 'DANGER' in i else '⚠'} {i}")
        sys.exit(1)


def cmd_list(args):
    profile = StockProfile(Path(args.profile))
    journal_dir = Path(args.journal_dir)
    manifest_path = journal_dir / "manifest.json"

    if not manifest_path.exists():
        print("No journal found — no mods installed.")
        return

    manifest = JournalManifest.from_dict(
        json.loads(manifest_path.read_text(encoding="utf-8"))
    )

    mod_ids = []
    seen = set()
    for e in manifest.entries:
        if e.mod_id not in seen:
            mod_ids.append(e.mod_id)
            seen.add(e.mod_id)

    if not mod_ids:
        print("Journal exists but has no entries.")
        return

    for mid in mod_ids:
        entries = [e for e in manifest.entries if e.mod_id == mid]
        print(f"\n{mid}")
        print(f"  Files: {len(entries)}")
        for e in entries:
            action = "+" if e.action.value == "created" else "~"
            stock_note = ""
            if e.hash_before:
                stock = profile.stock_hash(e.path)
                if stock and stock == e.hash_before:
                    stock_note = " (was stock)"
                else:
                    stock_note = " (was modded)"
            print(f"    {action} {e.path}{stock_note}")


def cmd_export(args):
    profile = StockProfile(Path(args.profile))
    j = Journal(Path(args.journal_dir), Path("/dev/null"), profile)

    dest = Path(args.dest)
    j.export_restore_kit(dest)
    manifest = j.load()
    n_backups = sum(1 for e in manifest.entries if e.backup_path)
    print(f"Exported to {dest}")
    print(f"  {len(manifest.entries)} entries, {n_backups} backup files")
    print(f"  Any journal engine can restore from this kit.")


def cmd_backup(args):
    profile = StockProfile(Path(args.profile))
    journal_dir = Path(args.journal_dir)

    if args.dest:
        dest = Path(args.dest)
    else:
        ts = time.strftime("%Y%m%d_%H%M%S")
        dest = journal_dir.parent / f"modjournal_backup_{ts}"

    j = Journal(journal_dir, Path("/dev/null"), profile)
    result = j.snapshot(dest)
    print(f"Snapshot saved to {result['dest']}")
    print(f"  Phase:   {result['phase']}")
    print(f"  Entries: {result['entries']}")
    print(f"  Backups: {result['backups']} files")
    print(f"\n  To restore from this snapshot, copy it back over the journal directory.")


def cmd_dry_run(args):
    profile = StockProfile(Path(args.profile))
    manifest_path = Path(args.mod_manifest)
    raw = json.loads(manifest_path.read_text(encoding="utf-8"))

    mod_id = raw["mod_id"]
    fw_hashes = raw.get("firmware_sha256", [])
    fw_human = raw.get("firmware_versions_human", [])
    files = raw.get("files", {})

    print(f"Mod:      {mod_id}")
    print(f"Firmware: {', '.join(fw_human) if fw_human else ', '.join(fw_hashes[:2]) if fw_hashes else 'any'}")
    print(f"Files:    {len(files)}")

    fw_match = not fw_hashes or profile.firmware_sha256 in fw_hashes
    print(f"\nProfile:  {profile.firmware.get('file', '?')} ({profile.firmware_sha256[:16]}…)")
    print(f"Match:    {'YES' if fw_match else 'NO — this mod does not target this firmware'}")

    if not fw_match:
        sys.exit(1)

    print(f"\nDry-run install plan:")
    for cam_path, info in files.items():
        stock_hash = profile.stock_hash(cam_path)
        if stock_hash:
            print(f"  ~ {cam_path}")
            print(f"      stock: {stock_hash[:16]}…")
            print(f"      action: REPLACE (backup original)")
        else:
            print(f"  + {cam_path}")
            print(f"      action: CREATE (new file, remove on restore)")

        if isinstance(info, dict) and "sha256" in info:
            print(f"      mod:   {info['sha256'][:16]}…")

    print(f"\nJournal entries that would be created: {len(files)}")
    n_replace = sum(1 for p in files if profile.stock_hash(p))
    n_create = len(files) - n_replace
    print(f"  {n_replace} replacements (backed up), {n_create} new files")


def cmd_slot_restore(args):
    profile = StockProfile(Path(args.profile))
    try:
        slot_info = read_slot_info()
    except RuntimeError as e:
        print(f"Cannot read slot info: {e}")
        print("(This command must run on the camera.)")
        sys.exit(1)

    j = Journal(Path(args.journal_dir), Path("/system"), profile, slot_info=slot_info)

    preflight = j.preflight_slot_restore()

    print(f"Current slot:  {preflight['current_slot']}")
    print(f"Target slot:   {preflight['target_slot']} (inactive, stock firmware)")
    print(f"Journal:       {preflight['journal_entries']} entries")

    if not preflight["viable"]:
        print(f"\nSlot restore NOT viable:")
        for issue in preflight["issues"]:
            print(f"  ✗ {issue}")
        sys.exit(1)

    print(f"\nRestore plan:")
    for i, step in enumerate(preflight["steps"], 1):
        print(f"  {i}. {step}")

    if args.dry_run:
        print("\n[DRY RUN — no changes made]")
        return

    print(f"\n{'='*60}")
    print("WARNING: This will abandon ALL mods on slot "
          f"{preflight['current_slot']} and reboot")
    print(f"into stock firmware on slot {preflight['target_slot']}.")
    print(f"{'='*60}")

    if not args.yes:
        answer = input("\nType YES to proceed: ")
        if answer.strip() != "YES":
            print("Aborted.")
            return

    result = j.slot_restore()
    print(f"\nSlot flip executed:")
    print(f"  From slot {result['current_slot']} → slot {result['target_slot']}")
    print(f"  Journal marked: {result['journal_marked']}")
    print(f"\n  >>> REBOOT NOW to complete restore <<<")


def main():
    p = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    s = p.add_subparsers(dest="cmd", required=True)

    a = s.add_parser("status", help="Show journal state")
    a.add_argument("journal_dir")
    a.add_argument("profile")
    a.set_defaults(fn=cmd_status)

    a = s.add_parser("verify", help="Check journal integrity")
    a.add_argument("journal_dir")
    a.add_argument("system_root")
    a.add_argument("profile")
    a.set_defaults(fn=cmd_verify)

    a = s.add_parser("health", help="Pre-flight slot check (on camera)")
    a.add_argument("journal_dir")
    a.add_argument("profile")
    a.set_defaults(fn=cmd_health)

    a = s.add_parser("list", help="List installed mods")
    a.add_argument("journal_dir")
    a.add_argument("profile")
    a.set_defaults(fn=cmd_list)

    a = s.add_parser("export", help="Export restore kit")
    a.add_argument("journal_dir")
    a.add_argument("profile")
    a.add_argument("dest")
    a.set_defaults(fn=cmd_export)

    a = s.add_parser("backup", help="Snapshot journal to a backup directory")
    a.add_argument("journal_dir")
    a.add_argument("profile")
    a.add_argument("--dest", default=None, help="Destination (default: timestamped sibling)")
    a.set_defaults(fn=cmd_backup)

    a = s.add_parser("dry-run", help="Preview a mod installation")
    a.add_argument("mod_manifest")
    a.add_argument("profile")
    a.set_defaults(fn=cmd_dry_run)

    a = s.add_parser("slot-restore", help="Emergency: flip to inactive stock slot")
    a.add_argument("journal_dir")
    a.add_argument("profile")
    a.add_argument("--dry-run", action="store_true", help="Show plan without executing")
    a.add_argument("--yes", action="store_true", help="Skip confirmation prompt")
    a.set_defaults(fn=cmd_slot_restore)

    args = p.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
