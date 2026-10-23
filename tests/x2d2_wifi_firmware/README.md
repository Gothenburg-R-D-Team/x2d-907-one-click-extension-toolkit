# X2D II case checks

From repository root, run the 12 socket-free parser/identity/mock checks:

```sh
python3 -B -m unittest discover -s tests -p 'test_phone_id.py' -v
```

These are also included in ordinary `unittest discover -s tests`. The only adaptation to
the beta test module is its repository-relative import path; assertions are unchanged.

The additional 10 HTTP/proxy tests intentionally stay outside default test discovery:

```sh
PYTHONPATH=src/tools/x2d2_wifi_firmware python3 -B src/tools/x2d2_wifi_firmware/validation/check_http_simulation.py -v
```

They bind only a localhost simulation and use synthetic firmware/IDs. They cover exact
POST framing, failed preflight, lost receipt/no retry, redirect refusal and a read-only
capture proxy. Neither suite contacts a physical camera, phone, USB or Bluetooth device.

[Case and validation record](../../docs/cases/2026-10-14-x2d-ii-wifi-firmware-recovery/VALIDATION.md)

默认 12 项测试不开 socket；额外 10 项需显式运行，只访问本机模拟服务。离线测试与实机案例证据分开记录。
