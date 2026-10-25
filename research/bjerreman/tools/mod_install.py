"""Unified mod installer with journal integration.

Offline-first: validates mod manifests against firmware profiles, generates
install/restore plans, and optionally executes them via the journal engine.
All mods are wrapped in journal transactions for safe rollback.

Usage:
  python3 mod_install.py plan <mod.json> <profile.json>     # dry-run plan
  python3 mod_install.py validate <mod.json> <profile.json>  # check compatibility
  python3 mod_install.py batch-plan *.json <profile.json>    # plan multiple mods
"""
from __future__ import annotations

import hashlib
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class ModFile:
    camera_path: str
    action: str
    stock_sha256: str | None
    mod_sha256: str | None
    description: str


@dataclass
class ModManifest:
    mod_id: str
    name: str
    version: str
    target_models: list[str]
    target_firmware: list[str]
    technique: str
    files: list[ModFile]
    init_edits: list[dict] = field(default_factory=list)
    services: list[str] = field(default_factory=list)
    porting_status: dict = field(default_factory=dict)
    restore_notes: str = ""

    @classmethod
    def from_dict(cls, raw: dict) -> ModManifest:
        files = []
        for path, info in raw.get("files", {}).items():
            if isinstance(info, dict):
                files.append(ModFile(
                    camera_path=path,
                    action=info.get("action", "replace"),
                    stock_sha256=info.get("stock_sha256"),
                    mod_sha256=info.get("sha256"),
                    description=info.get("description", ""),
                ))
            else:
                files.append(ModFile(
                    camera_path=path,
                    action="replace",
                    stock_sha256=None,
                    mod_sha256=None,
                    description=str(info),
                ))

        return cls(
            mod_id=raw["mod_id"],
            name=raw.get("name", raw["mod_id"]),
            version=raw.get("version", "0.0.0"),
            target_models=raw.get("target_models", []),
            target_firmware=raw.get("firmware_versions_human", []),
            technique=raw.get("technique", "unknown"),
            files=files,
            init_edits=raw.get("init_edits", []),
            services=raw.get("services", []),
            porting_status=raw.get("porting_status", {}),
            restore_notes=raw.get("restore", {}).get("notes", ""),
        )


@dataclass
class ProfileEntry:
    path: str
    sha256: str
    size: int
    mode: str
    selinux: str


class FirmwareProfile:
    def __init__(self, path: Path):
        raw = json.loads(path.read_text(encoding="utf-8"))
        self.firmware = raw.get("firmware", {})
        self.firmware_sha256 = self.firmware.get("sha256", "")
        self.firmware_version = self.firmware.get("build", "")
        self.firmware_file = self.firmware.get("file", "")
        self.product = self.firmware.get("product", "")

        self._entries: dict[str, ProfileEntry] = {}
        for part_name, part in raw.get("partitions", {}).items():
            for entry in part.get("entries", []):
                if entry.get("type") == "file":
                    self._entries[entry["path"]] = ProfileEntry(
                        path=entry["path"],
                        sha256=entry.get("sha256", ""),
                        size=entry.get("size", 0),
                        mode=entry.get("mode", "0644"),
                        selinux=entry.get("selinux", ""),
                    )

    def _normalize_path(self, path: str) -> str | None:
        """Try the path as-is, then strip known partition prefixes."""
        if path in self._entries:
            return path
        for prefix in ("/system", "/vendor", "/blackbox"):
            if path.startswith(prefix + "/"):
                stripped = path[len(prefix):]
                if stripped in self._entries:
                    return stripped
        return None

    def stock_hash(self, path: str) -> str | None:
        norm = self._normalize_path(path)
        return self._entries[norm].sha256 if norm else None

    def has_file(self, path: str) -> bool:
        return self._normalize_path(path) is not None

    def model_from_filename(self) -> str:
        name = self.firmware_file
        if "X2DII" in name:
            return "X2D II 100C"
        if "X2D" in name:
            return "X2D 100C"
        if "X1D_II" in name:
            return "X1D II 50C"
        if "X1D" in name:
            return "X1D 50C"
        return "Unknown"


@dataclass
class PlanStep:
    action: str
    path: str
    detail: str
    stock_sha256: str | None = None
    risk: str = "low"


@dataclass
class InstallPlan:
    mod_id: str
    mod_name: str
    model: str
    firmware: str
    compatible: bool
    issues: list[str]
    warnings: list[str]
    steps: list[PlanStep]
    journal_entries: int = 0
    technique: str = ""

    def to_dict(self) -> dict:
        return {
            "mod_id": self.mod_id,
            "mod_name": self.mod_name,
            "model": self.model,
            "firmware": self.firmware,
            "compatible": self.compatible,
            "technique": self.technique,
            "issues": self.issues,
            "warnings": self.warnings,
            "steps": [
                {
                    "action": s.action,
                    "path": s.path,
                    "detail": s.detail,
                    "stock_sha256": s.stock_sha256,
                    "risk": s.risk,
                }
                for s in self.steps
            ],
            "journal_entries": self.journal_entries,
        }


def validate_mod(manifest: ModManifest, profile: FirmwareProfile) -> InstallPlan:
    """Validate a mod manifest against a firmware profile."""
    issues = []
    warnings = []
    steps = []

    model = profile.model_from_filename()

    fw_match = True
    if manifest.target_firmware:
        fw_match = any(
            v in profile.firmware_file
            or v in profile.firmware_version
            or v.replace(".", "_") in profile.firmware_file
            for v in manifest.target_firmware
        )
    if not fw_match:
        issues.append(
            f"firmware mismatch: mod targets {manifest.target_firmware}, "
            f"profile is {profile.firmware_file}"
        )

    if manifest.target_models:
        model_norm = model.replace(" ", "").replace("-", "").upper()
        model_match = any(
            m.replace("_", "").replace("-", "").upper() in model_norm
            or model_norm in m.replace("_", "").replace("-", "").upper()
            for m in manifest.target_models
        )
        if not model_match:
            issues.append(
                f"model mismatch: mod targets {manifest.target_models}, "
                f"profile is {model}"
            )

    porting = manifest.porting_status
    model_key = None
    if "X2D II" in model:
        model_key = "x2d_ii"
    elif "X2D" in model:
        model_key = "x2d"
    elif "X1D II" in model:
        model_key = "x1d_ii"

    if model_key and model_key in porting:
        status = porting[model_key]
        if status == "not_started":
            issues.append(f"porting to {model} not started")
        elif status == "in_progress":
            warnings.append(f"porting to {model} in progress — use with caution")

    for mf in manifest.files:
        stock_hash = profile.stock_hash(mf.camera_path)
        if mf.action == "replace" and stock_hash:
            if mf.stock_sha256 and mf.stock_sha256 != stock_hash:
                issues.append(
                    f"stock hash mismatch for {mf.camera_path}: "
                    f"manifest says {mf.stock_sha256[:16]}…, "
                    f"profile says {stock_hash[:16]}…"
                )
            steps.append(PlanStep(
                action="REPLACE",
                path=mf.camera_path,
                detail=f"backup stock ({stock_hash[:12]}…) → install mod",
                stock_sha256=stock_hash,
                risk="medium",
            ))
        elif mf.action == "replace" and not stock_hash:
            if profile.has_file(mf.camera_path):
                warnings.append(f"{mf.camera_path}: in profile but no hash")
            steps.append(PlanStep(
                action="REPLACE",
                path=mf.camera_path,
                detail="file not in profile — will backup if exists",
                risk="medium",
            ))
        elif mf.action == "create":
            if profile.has_file(mf.camera_path):
                warnings.append(
                    f"{mf.camera_path}: marked CREATE but exists in stock"
                )
            steps.append(PlanStep(
                action="CREATE",
                path=mf.camera_path,
                detail="new file — remove on restore",
                risk="low",
            ))
        else:
            steps.append(PlanStep(
                action=mf.action.upper(),
                path=mf.camera_path,
                detail=mf.description or "unknown operation",
                stock_sha256=stock_hash,
                risk="medium",
            ))

    for edit in manifest.init_edits:
        path = edit.get("file", "")
        stock_hash = profile.stock_hash(path)
        transform = edit.get("transform", "unknown")
        steps.append(PlanStep(
            action="EDIT",
            path=path,
            detail=f"{transform} transform; stock hash: {stock_hash[:12] + '…' if stock_hash else 'unknown'}",
            stock_sha256=stock_hash,
            risk="medium" if stock_hash else "high",
        ))

    if manifest.technique == "binary_patch_elf":
        warnings.append(
            "binary ELF patching is version-locked — exact firmware hash required"
        )
    elif manifest.technique == "awk_text_transform":
        pass
    elif manifest.technique == "dlsym_interposition":
        warnings.append(
            "dlsym interposition survives minor updates but verify symbol names"
        )

    return InstallPlan(
        mod_id=manifest.mod_id,
        mod_name=manifest.name,
        model=model,
        firmware=profile.firmware_file,
        compatible=len(issues) == 0,
        issues=issues,
        warnings=warnings,
        steps=steps,
        journal_entries=len(steps),
        technique=manifest.technique,
    )


def print_plan(plan: InstallPlan) -> None:
    """Pretty-print an install plan."""
    status = "COMPATIBLE" if plan.compatible else "INCOMPATIBLE"
    print(f"\n{'=' * 60}")
    print(f"Mod:       {plan.mod_name} ({plan.mod_id})")
    print(f"Target:    {plan.model} / {plan.firmware}")
    print(f"Technique: {plan.technique}")
    print(f"Status:    {status}")
    print(f"{'=' * 60}")

    if plan.issues:
        print(f"\nBLOCKERS ({len(plan.issues)}):")
        for i in plan.issues:
            print(f"  ✗ {i}")

    if plan.warnings:
        print(f"\nWarnings ({len(plan.warnings)}):")
        for w in plan.warnings:
            print(f"  ⚠ {w}")

    if plan.steps:
        print(f"\nInstall plan ({len(plan.steps)} operations):")
        for i, step in enumerate(plan.steps, 1):
            risk_mark = {"low": "·", "medium": "▸", "high": "▸▸"}
            print(f"  {i}. [{step.action:7s}] {step.path}")
            print(f"     {risk_mark.get(step.risk, '?')} {step.detail}")

    print(f"\nJournal entries: {plan.journal_entries}")
    print(f"Restore: journal engine reverses all {plan.journal_entries} operations in LIFO order")


def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Unified mod installer with journal integration",
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("plan", help="Generate install plan (dry run)")
    p.add_argument("mod", type=Path, help="mod manifest JSON")
    p.add_argument("profile", type=Path, help="firmware profile JSON")

    p = sub.add_parser("validate", help="Check mod/firmware compatibility")
    p.add_argument("mod", type=Path, help="mod manifest JSON")
    p.add_argument("profile", type=Path, help="firmware profile JSON")
    p.add_argument("--json", action="store_true")

    p = sub.add_parser("batch-plan", help="Plan multiple mods")
    p.add_argument("mods", type=Path, nargs="+", help="mod manifest JSONs")
    p.add_argument("--profile", "-p", type=Path, required=True)
    p.add_argument("--json", action="store_true")

    args = parser.parse_args()

    if args.cmd == "plan":
        raw = json.loads(args.mod.read_text(encoding="utf-8"))
        manifest = ModManifest.from_dict(raw)
        profile = FirmwareProfile(args.profile)
        plan = validate_mod(manifest, profile)
        print_plan(plan)

    elif args.cmd == "validate":
        raw = json.loads(args.mod.read_text(encoding="utf-8"))
        manifest = ModManifest.from_dict(raw)
        profile = FirmwareProfile(args.profile)
        plan = validate_mod(manifest, profile)
        if args.json:
            print(json.dumps(plan.to_dict(), indent=2))
        else:
            print_plan(plan)
        sys.exit(0 if plan.compatible else 1)

    elif args.cmd == "batch-plan":
        profile = FirmwareProfile(args.profile)
        plans = []
        for mod_path in args.mods:
            raw = json.loads(mod_path.read_text(encoding="utf-8"))
            manifest = ModManifest.from_dict(raw)
            plan = validate_mod(manifest, profile)
            plans.append(plan)

        if args.json:
            print(json.dumps([p.to_dict() for p in plans], indent=2))
        else:
            for plan in plans:
                print_plan(plan)
            print(f"\n{'=' * 60}")
            ok = sum(1 for p in plans if p.compatible)
            print(f"Summary: {ok}/{len(plans)} mods compatible with {profile.model_from_filename()}")
            total_ops = sum(p.journal_entries for p in plans)
            print(f"Total journal entries: {total_ops}")


if __name__ == "__main__":
    main()
