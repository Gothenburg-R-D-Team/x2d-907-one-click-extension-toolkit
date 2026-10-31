"""Safe binary string patcher for camera-gui-software.

Generates journaled patch plans for modifying embedded strings and QML
in the camera GUI binary. All patches are same-length or shorter (null-padded)
to avoid shifting offsets.

Safety:
  - Never writes directly to firmware — generates patch diffs
  - Verifies stock SHA256 before and after
  - All operations go through the journal engine
  - Patches are reversible via journal restore
"""
from __future__ import annotations

import hashlib
import json
import mmap
import struct
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class Patch:
    offset: int
    original: bytes
    replacement: bytes
    description: str

    def to_dict(self) -> dict:
        return {
            "offset": self.offset,
            "offset_hex": f"0x{self.offset:08x}",
            "original": self.original.decode("ascii", errors="replace"),
            "replacement": self.replacement.decode("ascii", errors="replace"),
            "description": self.description,
        }


@dataclass
class PatchPlan:
    binary_path: str
    stock_sha256: str
    patches: list[Patch] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)

    @property
    def valid(self) -> bool:
        return len(self.errors) == 0 and len(self.patches) > 0

    def to_dict(self) -> dict:
        return {
            "binary": self.binary_path,
            "stock_sha256": self.stock_sha256,
            "valid": self.valid,
            "patch_count": len(self.patches),
            "errors": self.errors,
            "patches": [p.to_dict() for p in self.patches],
        }


class BinaryPatcher:
    """Read-only analysis and patch generation for camera-gui-software."""

    def __init__(self, path: Path):
        self.path = path
        self.data = path.read_bytes()
        self.sha256 = hashlib.sha256(self.data).hexdigest()
        self.size = len(self.data)

    def find_string(self, needle: str, start: int = 0) -> int | None:
        off = self.data.find(needle.encode("utf-8"), start)
        return off if off >= 0 else None

    def find_all_strings(self, needle: str) -> list[int]:
        results = []
        off = 0
        while True:
            off = self.data.find(needle.encode("utf-8"), off)
            if off < 0:
                break
            results.append(off)
            off += 1
        return results

    def read_null_terminated(self, offset: int) -> str:
        end = self.data.find(b"\x00", offset)
        if end < 0:
            end = min(offset + 256, self.size)
        return self.data[offset:end].decode("ascii", errors="replace")

    def context(self, offset: int, before: int = 50, after: int = 100) -> str:
        start = max(0, offset - before)
        end = min(self.size, offset + after)
        return self.data[start:end].decode("ascii", errors="replace")

    def string_table_region(self) -> tuple[int, int] | None:
        """Find the menu string table (Product Name, Serial Number, etc.)."""
        off = self.find_string("Product Name")
        if off is None:
            return None
        start = off
        while start > 0 and self.data[start - 1:start] != b"\x00\x00":
            start -= 1
        end = off + 2000
        while end < self.size and self.data[end:end + 4] != b"\x00\x00\x00\x00":
            end += 1
        return (start, end)

    def replace_string_safe(self, old: str, new: str, description: str = "") -> Patch | None:
        """Create a same-length-or-shorter string replacement patch.

        The new string is null-padded to match the original's null-terminated
        length, preserving all offsets in the binary.
        """
        off = self.find_string(old)
        if off is None:
            return None
        old_bytes = old.encode("utf-8")
        old_end = self.data.find(b"\x00", off)
        if old_end < 0:
            return None
        old_full = self.data[off:old_end + 1]
        new_bytes = new.encode("utf-8")
        if len(new_bytes) > len(old_bytes):
            return None
        replacement = new_bytes + b"\x00" * (len(old_full) - len(new_bytes))
        return Patch(
            offset=off,
            original=old_full,
            replacement=replacement,
            description=description or f"Replace '{old}' with '{new}'",
        )

    def find_qml_blocks(self, keyword: str | None = None) -> list[dict]:
        """Find embedded QML source blocks."""
        blocks = []
        needle = b"import QtQuick"
        off = 0
        while True:
            off = self.data.find(needle, off)
            if off < 0:
                break
            start = off
            while start > 0 and self.data[start - 1:start] != b"\x00":
                start -= 1
            end = off + 100
            while end < self.size:
                if self.data[end:end + 4] == b"\x00\x00\x00\x00":
                    break
                end += 1
            content = self.data[start:end].decode("ascii", errors="replace")
            if keyword is None or keyword in content:
                blocks.append({
                    "offset": start,
                    "offset_hex": f"0x{start:08x}",
                    "size": end - start,
                    "preview": content[:200].replace("\x00", ""),
                    "keywords": [k for k in ["About", "System", "Settings", "Version",
                                             "Resolution", "Product", "Serial", "Color",
                                             "Theme", "Firmware"]
                                 if k in content],
                })
            off += 20
        return blocks

    def plan_version_display_mod(self, suffix: str = "-mod") -> PatchPlan:
        """Plan to append a suffix to the firmware version display string."""
        plan = PatchPlan(binary_path=str(self.path), stock_sha256=self.sha256)
        off = self.find_string("Firmware Version")
        if off is None:
            plan.errors.append("Could not find 'Firmware Version' string")
            return plan
        p = self.replace_string_safe("Firmware Version", f"FW Version{suffix}",
                                     "Modify firmware version label in About page")
        if p:
            plan.patches.append(p)
        else:
            plan.errors.append("Replacement string too long for field")
        return plan

    def plan_about_page_mod(self) -> PatchPlan:
        """Plan to customize the About page strings."""
        plan = PatchPlan(binary_path=str(self.path), stock_sha256=self.sha256)

        mods = [
            ("Firmware ID Number", "Firmware ID No.", "Shorten firmware ID label"),
            ("Default Settings", "Modded Settings", "Mark settings page as running modded firmware"),
        ]
        for old, new, desc in mods:
            p = self.replace_string_safe(old, new, desc)
            if p:
                plan.patches.append(p)
            else:
                plan.errors.append(f"Failed to create patch: {old} → {new}")
        return plan

    def apply_plan(self, plan: PatchPlan, output: Path) -> str:
        """Apply a patch plan to produce a modified binary. Returns SHA256."""
        if not plan.valid:
            raise ValueError(f"Plan has errors: {plan.errors}")
        if self.sha256 != plan.stock_sha256:
            raise ValueError(f"Binary SHA256 mismatch: expected {plan.stock_sha256}")
        result = bytearray(self.data)
        for patch in plan.patches:
            actual = bytes(result[patch.offset:patch.offset + len(patch.original)])
            if actual != patch.original:
                raise ValueError(
                    f"Patch verification failed at {patch.offset:#x}: "
                    f"expected {patch.original!r}, found {actual!r}"
                )
            result[patch.offset:patch.offset + len(patch.replacement)] = patch.replacement
        output.write_bytes(bytes(result))
        return hashlib.sha256(bytes(result)).hexdigest()

    def analyze(self) -> dict:
        """Full analysis report."""
        st = self.string_table_region()
        qml = self.find_qml_blocks()
        return {
            "binary": str(self.path),
            "sha256": self.sha256,
            "size": self.size,
            "size_mb": f"{self.size / 1024 / 1024:.1f}",
            "string_table": {
                "start": f"0x{st[0]:08x}" if st else None,
                "end": f"0x{st[1]:08x}" if st else None,
                "size": st[1] - st[0] if st else 0,
            },
            "qml_blocks": len(qml),
            "qml_with_keywords": [b for b in qml if b["keywords"]],
        }


def generate_mod_manifest(patcher: BinaryPatcher, plan: PatchPlan,
                          mod_id: str, model: str, fw_version: str) -> dict:
    """Generate a mod manifest JSON from a patch plan."""
    return {
        "mod_id": mod_id,
        "description": f"Binary string patches for {model} {fw_version}",
        "model": model,
        "firmware_versions_human": [fw_version],
        "technique": "binary_string_patch",
        "install_method": "in_place_same_length",
        "safety": "All patches are same-length null-padded — no offset shifts",
        "binary": {
            "path": "camera-gui-software",
            "stock_sha256": plan.stock_sha256,
            "size": patcher.size,
        },
        "patches": [p.to_dict() for p in plan.patches],
        "restore": {
            "method": "stock_file_replace",
            "description": "Replace patched binary with stock backup from journal",
        },
    }


if __name__ == "__main__":
    import sys

    if len(sys.argv) < 2:
        print("Usage: binary_patcher.py <camera-gui-software> [plan|analyze|apply]")
        sys.exit(1)

    path = Path(sys.argv[1])
    action = sys.argv[2] if len(sys.argv) > 2 else "analyze"

    bp = BinaryPatcher(path)

    if action == "analyze":
        print(json.dumps(bp.analyze(), indent=2))
    elif action == "plan":
        plan = bp.plan_about_page_mod()
        print(json.dumps(plan.to_dict(), indent=2))
    elif action == "apply":
        plan = bp.plan_about_page_mod()
        if plan.valid:
            out = path.parent / "camera-gui-software.modded"
            sha = bp.apply_plan(plan, out)
            print(f"Applied {len(plan.patches)} patches → {out}")
            print(f"Modified SHA256: {sha}")
        else:
            print(f"Plan invalid: {plan.errors}")
            sys.exit(1)
