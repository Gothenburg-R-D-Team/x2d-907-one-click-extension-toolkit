# X2D II standalone recovery tools

[Case overview](../../../docs/cases/2026-10-14-x2d-ii-wifi-firmware-recovery/README.md) ·
[English steps](../../../docs/cases/2026-10-14-x2d-ii-wifi-firmware-recovery/RECOVERY.en.md) ·
[中文操作](../../../docs/cases/2026-10-14-x2d-ii-wifi-firmware-recovery/RECOVERY.zh-CN.md)

The operational scripts are copied unchanged from the beta case. They are separate from
the desktop installer. The default route requires Windows, Python 3.9+, an already-authorized
iPhone and a currently accepted Phocus HTTP session. It uses the standard library only.

| Script | Purpose / Validation |
| --- | --- |
| `collect_phocus_client_id.py` | Import an observed decimal ID or accepted HAR request into session files; does not establish a live session. |
| `x2d2_wifi_upgrade.py` | Offline `inspect`, read-only `probe`, explicit `upload ... --start-upgrade`. One owner-operated upload/start and reported recovery on X2D II 1.3.16.2. |
| `collect_iphone_usb_id.py` | Optional iPhone USB network mirror; `pymobiledevice3==11.29.1`, Apple Mobile Device Support. Not target-phone validated. |
| `x2d2_reuse_session.py` | Experimental independent BLE session recreation; Python 3.10+, `bleak==3.0.1`. Not target-camera validated. |

Follow the linked instructions before upload. No firmware or real client ID is included.
`inspect` does not prove model/signature compatibility; `probe` must pass; HTTP 204 is an
asynchronous start acknowledgement rather than installation completion. No POST is retried
automatically. Optional USB/BLE methods are described in the case's `ADVANCED.md`.

## Portable package

From the repository root, create a clean portable source ZIP:

```powershell
py -3 .\src\tools\x2d2_wifi_firmware\package_case.py --output "$env:TEMP\X2DII-WiFi-Upgrade-case.zip"
```

On macOS/Linux:

```sh
python3 -B src/tools/x2d2_wifi_firmware/package_case.py --output /tmp/X2DII-WiFi-Upgrade-case.zip
```

The output must not already exist. Extract the complete ZIP and open PowerShell inside
`X2DII-WiFi-Upgrade`. It contains the scripts at its root, English/Chinese instructions,
case/evidence/provenance, licenses, checksums and the archived offline checks. It contains
no firmware, vendor App, runtime dependency, capture or personal session. Read `README.md`
first; packaging never connects to a camera. This is a source bundle, not a desktop release.

The source license is preserved as [LICENSE.beta-original](LICENSE.beta-original).
New public instructions/packaging follow the [toolkit license](../../../LICENSE);
existing rights and contributor permissions are preserved.

## Validation

From repository root (12 socket-free tests):

```sh
python3 -B -m unittest discover -s tests -p 'test_phone_id.py' -v
```

Explicit localhost HTTP simulation (10 tests, no camera):

```sh
PYTHONPATH=src/tools/x2d2_wifi_firmware python3 -B src/tools/x2d2_wifi_firmware/validation/check_http_simulation.py -v
```

In a portable folder, use `py -3 -m unittest -v test_phone_id.py` and, separately,
`py -3 check_http_simulation.py -v`. The second command opens a local simulation on
127.0.0.1. Neither suite is physical-camera validation.

## 中文说明

操作脚本从 beta 原样迁移，先按案例目录的中文步骤操作。正常 HTTP 路线仅需 Python 标准库。
上述打包命令生成独立源码包，解压后脚本就在 `X2DII-WiFi-Upgrade` 根目录，可直接按教程执行；
打包过程不连接相机，不会带上真实会话或原厂固件，也不修改桌面 App 的版本、安装包和更新通道。
