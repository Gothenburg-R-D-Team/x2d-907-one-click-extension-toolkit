# X2D II Wi-Fi firmware recovery / Wi-Fi 原厂固件恢复

**Start here: [English recovery instructions](RECOVERY.en.md) · [中文恢复步骤](RECOVERY.zh-CN.md)**

| Item / 项目 | Scope / 范围 |
| --- | --- |
| Camera / 机型 | X2D II 100C |
| Recorded firmware / 案例固件 | Camera USB readback and original recovery CIM: `1.3.16.2` |
| Recorded host / 操作环境 | Windows and an already-authorized iPhone using Phocus |
| Essential condition / 必要条件 | Phocus can still enable camera Wi-Fi and the camera accepts the current authorized HTTP session. 已授权手机仍可开启相机 Wi-Fi，当前 HTTP 会话验证通过。 |
| Outcome / 结果 | Full 364,814,336-byte upload, HTTP 204/start_requested, followed by owner reports of upgrading and success. 完整上传及启动回执后，机主反馈正在升级并成功。 |
| Limits / 边界 | One owner-operated case; no per-module write logs or complete final integrity audit. USB/BLE fallback tools remain device-unverified. 一次用户操作案例，无逐模块日志或完整最终完整性审计。 |

## Why it worked / 原理

Diagnostic commands over USB and TCP stopped producing replies, but Phocus HTTP requests
under the phone's existing authorization still worked. These are different communication
paths: losing a diagnostic execution channel did not imply that the firmware upload route
was unavailable. Windows validated the current session, sent an unchanged complete official
CIM and requested installation. The camera's own update service retained its checks and
handled installation; no diagnostic-shell partition write, version change or signature
bypass was used. HTTP 204 acknowledged the asynchronous request, not completed installation.

本案 USB／TCP 诊断查询没有回复，但原手机已授权的 Phocus HTTP 通路仍能工作。
不同通路可能有不同可用状态，因此诊断命令失效并不等于固件上传入口失效。
Windows 验证当前会话后，发送完整、未改动的原厂 CIM 并请求安装；具体检查和安装仍由机身升级服务处理。
没有通过诊断 shell 直接写分区，没有修改版本或绕过签名。HTTP 204 只是异步启动回执，完成仍需观察机身。

Matching-version recovery succeeded in this recorded session. It is not evidence of a
universal forced reinstall or proof that every same-version module was rewritten.

本案读回版本与恢复包均为 `1.3.16.2`；这不等于通用强制重刷，也不能证明所有同版本模块均被重写。

## Tools and records / 工具与记录

- [English steps](RECOVERY.en.md) / [中文操作步骤](RECOVERY.zh-CN.md): download, setup, ID collection, probe, upload, results and troubleshooting.
- [Runnable script directory](../../../src/tools/x2d2_wifi_firmware/README.md): Python sources and portable ZIP recipe; no firmware or personal session included.
- [Full bilingual case](CASE.md): fault history, unsuccessful rollback and recovery evidence.
- [Protocol evidence](PROTOCOL_EVIDENCE.md) / [Historical advanced methods](ADVANCED.md): implementation basis and explicitly unvalidated alternatives.
- [Validation](VALIDATION.md), [migration provenance](MIGRATION.json), [historical manifest](ORIGINAL_MANIFEST.json).

These tools are independent from the first-generation desktop installer. Running its
Restore button is not this X2D II procedure. No camera was contacted during public migration.

这些工具独立于一代桌面安装器；本案不是让 X2D II 运行一代工具的恢复按钮。公开迁移过程没有连接或操作相机。

[All cases / 返回案例库](../README.md)
