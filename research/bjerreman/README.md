# bjerreman research: journaling, slot handling & firmware portability

Independent research into safe, reversible firmware modification for Hasselblad X System cameras.

## What's here

**Tools** — Python modules for mod lifecycle management:

| File | Purpose |
|------|---------|
| `tools/journal.py` | Undo-journal engine with atomic writes, SHA-256 verification, A/B slot awareness |
| `tools/hbjournal.py` | CLI wrapper: status, verify, health, export, slot-restore |
| `tools/mod_install.py` | Mod manifest validation, firmware profile matching, install planning |
| `tools/binary_patcher.py` | Safe binary string patching (same-length, null-padded) |
| `tools/elf_patcher.py` | ELF/ARM64 analysis: section parsing, PLT, code cave discovery |

**Documentation** — self-contained whitepapers and guides:

| File | Covers |
|------|--------|
| `docs/whitepaper-journaling-and-slot-handling.html` | Journal lifecycle, manifest schema v4, install/restore flows, LIFO ordering, emergency slot restore |
| `docs/whitepaper-cross-version-porting.html` | Technique portability tiers, binary porting steps, cross-model feasibility, version matrix |
| `docs/guide-firmware-slot-flip.html` | Emergency A/B slot flip procedure with pre-flight checks |

**Tests** — offline test suite (no camera contact):

| File | What it tests |
|------|---------------|
| `tests/test_journal.py` | 33 tests: install/restore cycles, LIFO, tamper detection, slot awareness, interruption recovery, export, schema roundtrip |
| `tests/fixtures/synthetic_profile.json` | Made-up hashes for standalone testing (no vendor-derived data) |

## Design principles

- **Never contact the camera** without explicit user approval
- **Atomic writes** everywhere: write-to-tmp + os.replace
- **SHA-256 verification** on every file operation
- **LIFO restore ordering** for stacked mods
- **A/B slot safety**: refuse operations during upgrades or on wrong slot
- **No vendor-derived bytes** in this tree — only clean code and synthetic test data

## Running the tests

```bash
cd research/bjerreman
python3 -m unittest tests.test_journal -v
```

All 33 tests run offline against the synthetic profile in `tests/fixtures/`.

## Scope

This is research contributed for the community's benefit. The tools are designed to be camera-model-agnostic across the X System family (X1D, X1D II, X2D, X2D II). Real firmware profiles are generated per-user from firmware they own and are never published.

## License

Follows the repository license.
