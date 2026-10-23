# Validation and limits / 验证与边界

## Historical device evidence

On 2026-10-14 the owner operated a remote Windows computer. The supplied evidence records:

1. The already-authorized iPhone's camera GET and matching HTTP 200.
2. Windows `/v1/parameters` session acceptance.
3. Complete transfer of 364,814,336 bytes and HTTP 204 / `start_requested`.
4. The owner's subsequent reports that the camera was upgrading and succeeded.

The assistant did not control that camera. The result JSON contents, final version screen,
per-module write logs and complete final functional checklist were not supplied. Earlier
ordinary USB readback reported `1.3.16.2`, matching the uploaded package; every same-version
module being rewritten is unproven. USB mirroring and independent BLE recreation remain
target-device unverified. See [CASE.md](CASE.md).

## Public migration checks — 2026-10-23

The four operational scripts and six analysis helpers retain their beta source bytes.
Only test import setup, packaging and documentation/navigation are adapted for the public
layout. [MIGRATION.json](MIGRATION.json) pins the source commit and records file hashes;
[ORIGINAL_MANIFEST.json](ORIGINAL_MANIFEST.json) is the historical beta manifest with its
original paths and historical results, not a map of the new public directory tree.

Run from repository root:

```sh
python3 -B -m unittest discover -s tests -p 'test_phone_id.py' -v
PYTHONPATH=src/tools/x2d2_wifi_firmware python3 -B src/tools/x2d2_wifi_firmware/validation/check_http_simulation.py -v
python3 -B src/tools/x2d2_wifi_firmware/package_case.py --output /tmp/X2DII-WiFi-Upgrade-case.zip
```

Results on Python 3.15.0 during public migration:

| Check | Result |
| --- | --- |
| Archived parser/identity/mock suite | 12 passed; no sockets or device access |
| Explicit localhost HTTP/proxy simulation | 10 passed on 127.0.0.1; authorization failure prevents POST, ambiguous receipt does not retry |
| Full repository default discovery | 227 run: 186 passed, 41 skipped for existing unavailable inputs; skipped tests are not counted as passes |
| Portable ZIP | Integrity and every bundled checksum checked; four operational files equal migrated sources; no firmware or personal session included |
| Extracted portable folder | 12 offline tests passed; documented manual-ID import and `inspect` CLI exercised with synthetic input only |
| Documentation | 59 relative links in case/tool/test docs resolved; new README case entry resolves; package-local links resolved |
| Publication review | Scanned transferred materials for known personal identifiers, local user paths and token patterns; original source license retained |

No target camera, phone, firmware installation, reboot, capture or new vendor reconstruction
is part of migration validation. No desktop installer or update-channel change is included.

## 中文说明

历史实机证据来自机主的请求／响应截图、终端输出和成功反馈；没有最终完整验收或逐模块重写日志。
公开迁移仅检查脚本一致性、离线测试、本机 HTTP 模拟、打包和文档链接，不再次操作机身。
历史清单保留原路径用于溯源，当前路径见迁移清单及案例入口；备用 USB／BLE 方法不标为实机验证通过。

本次公开迁移的 12 项案例离线测试与 10 项本机 HTTP 检查通过；全库 227 项中 186 项通过、41 项跳过。
独立包校验和、脚本一致性、解压后的 12 项离线测试、模拟输入的 ID 导入／inspect 及文档链接检查通过。
