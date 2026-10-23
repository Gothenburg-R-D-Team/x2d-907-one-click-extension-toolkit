# Analysis-only reconstruction helpers

Authored helpers used to reconstruct the protected Android DEX for static investigation. They do not install/re-sign an App or perform any camera action. Vendor inputs, generated DEX, disassemblies and derived compiled units are excluded from Git.

`recover_dex_tables.py` consumes the pinned original `classes.dex`; `recover_app_methods.py` consumes `analysis-rebuilt.dex` and its embedded DGC2 records. Exact input/output hashes and reconstruction counts are in the [manifest](../../../../docs/cases/2026-10-14-x2d-ii-wifi-firmware-recovery/ORIGINAL_MANIFEST.json). These scripts are specific to that pinned APK, not a general unpacker.

Set `X2DII_ANALYSIS_WORKDIR` to an external input/output directory containing those files, then invoke the scripts from any location. This archive replaces the original helper's script-relative working directory with that explicit environment input. No path into the toolkit source tree is inferred. Generated reports/DEX must remain outside Git.

```sh
export X2DII_ANALYSIS_WORKDIR=/tmp/x2dii-analysis
python3 -B src/tools/x2d2_wifi_firmware/analysis/recover_dex_tables.py
python3 -B src/tools/x2d2_wifi_firmware/analysis/recover_app_methods.py
```

The remaining DEX helpers need `androguard` and `loguru`; `dump_app.py` takes retained class names as arguments, while `app_index.py` / `app_field_xrefs.py` enumerate relevant strings and ID writers. `annotate_elf.py <ELF> <start-VA> <end-VA>` needs `pyelftools`, `capstone` and `llvm-objdump` on PATH (or `LLVM_OBJDUMP`). It prints static AArch64 annotations; addresses are ELF virtual addresses. Optional analysis dependencies are not included in the operational package.

The original reconstruction was completed locally (16,340 methods). During archive preparation, adapted helpers were syntax-checked only; no vendor binaries were committed or rerun through the archive.

## 中文说明

仅保存自主编写的分析脚本，厂商 APK/DEX/ELF、重建 DEX 与反汇编不入库。脚本限定对应哈希的 Android APK；通过环境变量指定库外工作目录，LLVM 工具也可显式指定。归档路径适配只做语法检查，不能当作又一次重建或实机验证。
