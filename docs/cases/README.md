# Case library / 案例库

Practical incident and recovery records. Each case states its own camera, firmware,
requirements, executable procedure and evidence limits. A case does not extend the
desktop installer's supported models or establish compatibility with another fault.

可执行的故障与恢复案例库。每个案例独立说明机型、固件、适用条件、操作方法、脚本与验证边界；
阅读后先判断是否符合条件，再按对应教程执行。案例不会自动扩大桌面安装器的机型支持范围。

| Date / 日期 | Camera / 机型 | Case and instructions / 案例与教程 | Outcome / 结果 |
| --- | --- | --- | --- |
| 2026-10-14 | X2D II 100C · 1.3.16.2 | [Wi-Fi original-firmware recovery / Wi-Fi 原厂固件恢复](2026-10-14-x2d-ii-wifi-firmware-recovery/README.md) · [English steps](2026-10-14-x2d-ii-wifi-firmware-recovery/RECOVERY.en.md) · [中文步骤](2026-10-14-x2d-ii-wifi-firmware-recovery/RECOVERY.zh-CN.md) | One owner-operated recovery reported successful; full upload and HTTP 204 recorded, module-by-module rewrite unverified. 一次用户操作成功；有完整上传与 204 记录，未验证逐模块重写。 |

## Add another case / 新增案例

Create a sibling directory named `YYYY-MM-DD-model-short-description/`, following
[TEMPLATE.md](TEMPLATE.md), then add a row here. Keep each case's evidence and instructions
in its own directory; reusable source belongs under `src/tools/` and tests under `tests/`.
Link the tools and their exact working directory explicitly. A future case can have a
different recovery method without changing the first case's scripts or validation status.

按照 [TEMPLATE.md](TEMPLATE.md) 新建同级目录 `年-月-日-机型-问题简述/`，再向表格增加一行。
各案例的证据与操作说明独立存放；可复用脚本放 `src/tools/`，测试放 `tests/`，在教程明确链接及运行目录。
新增案例不应覆盖旧案例的方法、证据或验收结论。只记录已实际取得的证据，未验证项明确标记。

[Project README / 返回项目首页](../../README.md)
