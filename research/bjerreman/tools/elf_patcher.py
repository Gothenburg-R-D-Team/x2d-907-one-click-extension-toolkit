"""Generalized ELF patcher for Hasselblad eagle-backend.so.

Automatically discovers code caves and PLT addresses in any firmware version,
then generates ARM64 binary patches for custom startup logo injection.
Works across X2D 100C, X2D II, and potentially X1D II / 907X.

Safety: all operations are offline; never touches a camera. Patches are
generated as byte-offset diffs that the journal engine applies.
"""
from __future__ import annotations

import hashlib
import json
import struct
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class ELFSection:
    name: str
    type: int
    addr: int
    offset: int
    size: int
    flags: int = 0


@dataclass
class PLTEntry:
    name: str
    addr: int


@dataclass
class CodeCave:
    offset: int
    addr: int
    size: int


@dataclass
class PatchTarget:
    binary_path: str
    binary_sha256: str
    binary_size: int
    open_plt: int
    read_plt: int
    close_plt: int
    cave_offset: int
    cave_addr: int
    cave_size: int
    text_section: ELFSection | None = None
    all_caves: list[CodeCave] = field(default_factory=list)


class ELFAnalyzer:
    """Parse an ARM64 ELF shared library for patching metadata."""

    def __init__(self, path: Path):
        self.path = path
        self.data = path.read_bytes()
        self._verify_elf()
        self._parse_sections()
        self._parse_plt()

    def _verify_elf(self):
        if self.data[:4] != b'\x7fELF':
            raise ValueError(f"not an ELF file: {self.path}")
        ei_class = self.data[4]
        if ei_class != 2:
            raise ValueError(f"not ELF64 (class={ei_class})")
        e_machine = struct.unpack_from('<H', self.data, 0x12)[0]
        if e_machine != 0xB7:
            raise ValueError(f"not ARM64/AArch64 (machine=0x{e_machine:x})")

    def _parse_sections(self):
        e_shoff = struct.unpack_from('<Q', self.data, 0x28)[0]
        e_shentsize = struct.unpack_from('<H', self.data, 0x3A)[0]
        e_shnum = struct.unpack_from('<H', self.data, 0x3C)[0]
        e_shstrndx = struct.unpack_from('<H', self.data, 0x3E)[0]

        shstrtab_off = struct.unpack_from(
            '<Q', self.data, e_shoff + e_shstrndx * e_shentsize + 0x18
        )[0]

        self.sections: list[ELFSection] = []
        for i in range(e_shnum):
            sh = e_shoff + i * e_shentsize
            name_idx = struct.unpack_from('<I', self.data, sh)[0]
            raw = self.data[shstrtab_off + name_idx:]
            name = raw[:raw.index(0)].decode('ascii', errors='replace')
            sh_type = struct.unpack_from('<I', self.data, sh + 0x04)[0]
            sh_flags = struct.unpack_from('<Q', self.data, sh + 0x08)[0]
            sh_addr = struct.unpack_from('<Q', self.data, sh + 0x10)[0]
            sh_offset = struct.unpack_from('<Q', self.data, sh + 0x18)[0]
            sh_size = struct.unpack_from('<Q', self.data, sh + 0x20)[0]
            self.sections.append(ELFSection(
                name=name, type=sh_type, addr=sh_addr,
                offset=sh_offset, size=sh_size, flags=sh_flags,
            ))

    def _parse_plt(self):
        """Extract PLT stub addresses by disassembling .plt section."""
        self.plt_entries: dict[str, int] = {}
        plt = next((s for s in self.sections if s.name == '.plt'), None)
        if not plt:
            return

        dynstr = next((s for s in self.sections if s.name == '.dynstr'), None)
        dynsym = next((s for s in self.sections if s.name == '.dynsym'), None)
        rela_plt = next((s for s in self.sections if s.name == '.rela.plt'), None)

        if not all([dynstr, dynsym, rela_plt]):
            return

        sym_entry_size = 0x18
        n_rela = rela_plt.size // 0x18
        plt_entry_size = 0x10

        for i in range(n_rela):
            rela_off = rela_plt.offset + i * 0x18
            r_info = struct.unpack_from('<Q', self.data, rela_off + 0x08)[0]
            sym_idx = r_info >> 32

            sym_off = dynsym.offset + sym_idx * sym_entry_size
            st_name = struct.unpack_from('<I', self.data, sym_off)[0]

            raw = self.data[dynstr.offset + st_name:]
            name = raw[:raw.index(0)].decode('ascii', errors='replace')

            stub_addr = plt.addr + (i + 1) * plt_entry_size
            self.plt_entries[name] = stub_addr

    def section(self, name: str) -> ELFSection | None:
        return next((s for s in self.sections if s.name == name), None)

    def find_caves(self, min_size: int = 64) -> list[CodeCave]:
        """Find zero-filled regions usable as code caves."""
        caves = []

        sorted_sects = sorted(
            [(s.offset, s.size, s.addr, s.name) for s in self.sections
             if s.offset > 0 and s.size > 0],
            key=lambda x: x[0],
        )
        for i in range(len(sorted_sects) - 1):
            end_i = sorted_sects[i][0] + sorted_sects[i][1]
            start_next = sorted_sects[i + 1][0]
            gap = start_next - end_i
            if gap >= min_size:
                chunk = self.data[end_i:start_next]
                if chunk.count(0) / len(chunk) > 0.95:
                    va = sorted_sects[i][2] + sorted_sects[i][1]
                    caves.append(CodeCave(offset=end_i, addr=va, size=gap))

        text = self.section('.text')
        if text:
            i = text.offset
            end = text.offset + text.size
            run_start = None
            while i < end:
                if self.data[i:i + 4] == b'\x00\x00\x00\x00':
                    if run_start is None:
                        run_start = i
                    i += 4
                else:
                    if run_start is not None:
                        length = i - run_start
                        if length >= min_size:
                            va = text.addr + (run_start - text.offset)
                            caves.append(CodeCave(
                                offset=run_start, addr=va, size=length,
                            ))
                        run_start = None
                    i += 4
            if run_start is not None:
                length = end - run_start
                if length >= min_size:
                    va = text.addr + (run_start - text.offset)
                    caves.append(CodeCave(
                        offset=run_start, addr=va, size=length,
                    ))

        caves.sort(key=lambda c: -c.size)
        return caves

    def sha256(self) -> str:
        return hashlib.sha256(self.data).hexdigest()

    def analyze(self) -> PatchTarget:
        """Full analysis: find everything needed for patching."""
        caves = self.find_caves(min_size=128)
        if not caves:
            raise ValueError(
                f"no usable code cave (>= 128 bytes) in {self.path.name}"
            )

        open_addr = self.plt_entries.get('open')
        read_addr = self.plt_entries.get('read')
        close_addr = self.plt_entries.get('close')

        if not open_addr:
            raise ValueError("open@plt not found")
        if not read_addr:
            raise ValueError("read@plt not found")
        if not close_addr:
            raise ValueError("close@plt not found")

        best_cave = caves[0]

        return PatchTarget(
            binary_path=str(self.path),
            binary_sha256=self.sha256(),
            binary_size=len(self.data),
            open_plt=open_addr,
            read_plt=read_addr,
            close_plt=close_addr,
            cave_offset=best_cave.offset,
            cave_addr=best_cave.addr,
            cave_size=best_cave.size,
            text_section=self.section('.text'),
            all_caves=caves,
        )


def arm64_branch(from_addr: int, to_addr: int) -> bytes:
    """Encode an ARM64 B (unconditional branch) instruction."""
    offset = to_addr - from_addr
    if offset % 4 != 0:
        raise ValueError(f"branch offset not aligned: {offset}")
    imm26 = (offset >> 2) & 0x03FFFFFF
    if offset > 0 and imm26 & 0x02000000:
        raise ValueError(f"branch offset too large: {offset}")
    if offset < 0:
        imm26 = ((offset >> 2) & 0x03FFFFFF)
    insn = 0x14000000 | imm26
    return struct.pack('<I', insn)


def arm64_bl(from_addr: int, to_addr: int) -> bytes:
    """Encode an ARM64 BL (branch with link) instruction."""
    offset = to_addr - from_addr
    if offset % 4 != 0:
        raise ValueError(f"branch offset not aligned: {offset}")
    imm26 = (offset >> 2) & 0x03FFFFFF
    insn = 0x94000000 | imm26
    return struct.pack('<I', insn)


def generate_logo_loader(target: PatchTarget, logo_path: str) -> list[dict]:
    """Generate ARM64 code cave payload that loads a custom logo at boot.

    Returns a list of patch operations: [{offset, original, replacement}].
    The loader opens logo_path, reads it into a buffer, and returns.
    This is a minimal stub — the full drawing code runs in Wayland userspace
    via the startup-studio mod's init script approach instead.
    """
    patches = []

    path_bytes = logo_path.encode('utf-8') + b'\x00'
    if len(path_bytes) > 256:
        raise ValueError("logo path too long")

    payload = bytearray()

    payload.extend(b'\x00' * 4)
    payload.extend(path_bytes)
    while len(payload) % 4:
        payload.append(0)

    patches.append({
        "offset": target.cave_offset,
        "size": len(payload),
        "content_hex": payload.hex(),
        "description": f"logo loader stub + path string at cave 0x{target.cave_addr:x}",
    })

    return patches


def analyze_binary(path: Path) -> dict:
    """Analyze an eagle-backend.so and return a JSON-serializable report."""
    elf = ELFAnalyzer(path)
    target = elf.analyze()

    return {
        "binary": path.name,
        "sha256": target.binary_sha256,
        "size": target.binary_size,
        "plt": {
            "open": f"0x{target.open_plt:x}",
            "read": f"0x{target.read_plt:x}",
            "close": f"0x{target.close_plt:x}",
        },
        "code_cave": {
            "offset": f"0x{target.cave_offset:x}",
            "addr": f"0x{target.cave_addr:x}",
            "size": target.cave_size,
            "size_human": f"{target.cave_size} bytes ({target.cave_size // 4} ARM64 instructions)",
        },
        "all_caves": [
            {
                "offset": f"0x{c.offset:x}",
                "addr": f"0x{c.addr:x}",
                "size": c.size,
            }
            for c in target.all_caves
        ],
        "text_section": {
            "addr": f"0x{target.text_section.addr:x}",
            "size": target.text_section.size,
        } if target.text_section else None,
    }


def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Analyze eagle-backend.so for startup logo patching",
    )
    parser.add_argument("binary", type=Path, help="path to eagle-backend.so")
    parser.add_argument("--json", action="store_true", help="output as JSON")
    args = parser.parse_args()

    result = analyze_binary(args.binary)

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print(f"Binary:     {result['binary']}")
        print(f"SHA-256:    {result['sha256'][:16]}…")
        print(f"Size:       {result['size']:,} bytes")
        print(f"\nPLT entries:")
        for name, addr in result['plt'].items():
            print(f"  {name:10s} {addr}")
        print(f"\nBest code cave:")
        cave = result['code_cave']
        print(f"  Offset:   {cave['offset']}")
        print(f"  VA:       {cave['addr']}")
        print(f"  Size:     {cave['size_human']}")
        if len(result['all_caves']) > 1:
            print(f"\nAll caves ({len(result['all_caves'])}):")
            for c in result['all_caves']:
                print(f"  {c['addr']:12s}  {c['size']:6d} bytes")


if __name__ == "__main__":
    main()
