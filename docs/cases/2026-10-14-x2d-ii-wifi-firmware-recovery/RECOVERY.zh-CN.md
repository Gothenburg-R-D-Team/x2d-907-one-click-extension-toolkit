# X2D II 原厂固件恢复：Windows 完整操作步骤

[English instructions](RECOVERY.en.md) · [案例与原理](README.md)

本教程复现 2026-10-14 的用户操作成功路线：已授权 iPhone → Windows 验证会话 → 上传完整原厂固件 → 机身安装。
当时相机普通 USB 读回版本和恢复包均为 **1.3.16.2**。其他机型、其他固件、新客户端授权及硬件故障不在本案验证范围内；固件是否允许安装由机身决定。

## 1．先确认条件

以下条件全部满足才继续：

- 相机为 **X2D II 100C**；这不是一代 X2D／CFV 的桌面安装器。
- 有此前已获该相机授权的 iPhone，Phocus 现在仍能连接并开启相机 Wi-Fi。若相机无法确认新设备，新手机不能替代旧授权。
- Windows 电脑能连接 Wi-Fi，装有 Python 3.9 或更新版本；相机电池电量充足、供电稳定。
- 已取得对应机型完整、未改动的原厂 CIM。照片仍可访问时先备份；本案例不能保证所有故障下照片都完好。

如果官方界面正常且提供所需固件更新，可使用官方更新流程。本案处理的是界面异常但仍保留上传通路的设备。

## 2．下载脚本并准备环境

下载 [toolkit 源码 ZIP](https://github.com/Gothenburg-R-D-Team/x2d-907-one-click-extension-toolkit/archive/refs/heads/main.zip)
（GitHub 页面 **Code → Download ZIP**），然后**完整解压**。这里不需要下载桌面 App 安装包。

打开解压后仓库里的：

```text
src\tools\x2d2_wifi_firmware
```

在此文件夹的资源管理器地址栏输入 `powershell` 并回车。当前目录应能看到
`x2d2_wifi_upgrade.py` 和 `collect_phocus_client_id.py`。

检查 Python：

```powershell
py -3 --version
```

若找不到 `py`，或版本低于 3.9，从 [Python 官方 Windows 下载页](https://www.python.org/downloads/windows/)
安装 Python 及启动器，再在同一目录重新打开 PowerShell。正常 HTTP／手工 ID 路线仅使用标准库，
不用安装 pip 依赖、ADB、替换 USB 驱动或安装蓝牙库。

也可以由维护者按[打包方法](../../../src/tools/x2d2_wifi_firmware/README.md#portable-package)
生成独立源码 ZIP。收到该包时，直接在完整解压后的 `X2DII-WiFi-Upgrade` 目录打开 PowerShell，后续命令完全相同。

从[哈苏官方下载](https://www.hasselblad.com/downloads/)取得 **X2D II 100C** 对应的完整原厂 `.cim`，
版本说明见[固件历史](https://www.hasselblad.com/x-system/firmware/)。保留官方原始文件名和后缀。
下面使用当时的 `X2DII_100C_v1_3_16_2(1).cim` 举例，路径换成你自己的真实位置。
较新版本不能仅因存在于官网，就视为已经通过本案例验证。

## 3．取得原手机实际使用的客户端 ID

在**已授权的 iPhone** 上操作：

1. 安装 [Stream（开发者 Stream Lab）](https://apps.apple.com/cn/app/stream/id1312141691)，启动抓包；如提示添加本机 VPN 配置，按需允许。本步骤只查看相机明文 HTTP，不需要安装 HTTPS 解密根证书。
2. 用 Phocus 开启相机热点，手机连接该热点。打开相机信息或相册页面，触发一次读取请求；此时不要点固件更新。
3. 在 Stream 中找到发往 **`192.168.2.1`、端口 80**，路径以 **`/v1/`** 开头的请求。不要选哈苏云端网站请求。
4. 核对它对应的响应为 **200 或其他 2xx**。
5. 打开请求头，复制 **`X-Phocus-Client-Id`** 后面的十进制数字。头名显示为小写也一样。

必须使用实际请求里的数字，不能填写 UDID、手机序列号、MAC 地址或其他人的示例 ID。
不要公开 ID、会话 JSON 或完整抓包。采集结束后停止 Stream，恢复手机原来的 VPN 配置状态。

如果没有抓到相机已接受的请求，先停止这条路线。空列表不能证明手机没有 ID；
[高级说明](ADVANCED.md)中虽有备用采集方式，但 USB 镜像采集和独立 BLE 会话重建均未通过本案实机验证。

## 4．在 Windows 生成会话文件

在脚本目录的 PowerShell 中，**先单独执行这一行**：

```powershell
$phocusClientId = Read-Host "粘贴实际 X-Phocus-Client-Id"
```

出现输入提示后，**只粘贴刚才的数字并回车**，不要把下一条 Python 命令粘进输入提示。
随后执行：

```powershell
py -3 .\collect_phocus_client_id.py --observed-id $phocusClientId
```

当前目录会生成 `phone-client-id.json` 和 `session.json`。手工输入不能让脚本核实截图中的历史响应，
因此记录为历史接受状态未验证；下一步现场 `probe` 不能省略。保存一个 ID 不等于建立了有效会话。

如果你的相机局域网地址不同，先从自己的手机请求确认实际 IPv4，再在上述采集命令末尾增加
`--camera-host 实际IPv4`，将“实际IPv4”替换成真实数字地址。

## 5．电脑连接相机热点，验证当前会话

让原手机 Phocus 开好相机 Wi-Fi，再让 Windows 接入相机热点。本案现场手机和电脑同时连接热点会发生掉线，
后来让手机断开相机 Wi-Fi，保留原来的蓝牙连接。以现场 `probe` 为准，保持实际验证通过的连接状态，
不要假设拿到 ID 就会一直有效。远程协助时，电脑需另保留可用的互联网连接，避免切热点导致远程控制断开。

执行：

```powershell
py -3 .\x2d2_wifi_upgrade.py probe --session .\session.json
```

只有显示以下内容才继续：

```text
Session accepted by /v1/parameters. No firmware was uploaded.
```

**出现 401／403、超时或响应异常时，停止上传。** 检查原手机连接、热点和实际 ID。
不要靠猜 ID 或反复发送固件来测试授权；验证成功后保持当时的连接状态。

## 6．先检查文件，再上传一次

先做本地检查，路径替换为固件实际位置，保留双引号：

```powershell
py -3 .\x2d2_wifi_upgrade.py inspect "C:\Firmware\X2DII_100C_v1_3_16_2(1).cim"
```

这一步只检查后缀、CIM 文件头、大小并计算哈希，**不上传**，也不独立验证厂商签名或证明机型／版本兼容。
应由操作者选择正确原厂文件，机身仍会执行自己的安装资格检查。

确认条件、文件和会话无误、供电稳定后，以下命令会**上传固件并请求启动安装**：

```powershell
py -3 .\x2d2_wifi_upgrade.py upload "C:\Firmware\X2DII_100C_v1_3_16_2(1).cim" --session .\session.json --start-upgrade
```

上传器会在 POST 前再次执行只读会话检查，随后发送完整原始 CIM、大小／SHA-1 和安装请求。
它不会自动重试 POST、跟随重定向或绕过机身固件检查。

本案例当时的成功传输输出为：

```text
Sent 364814336 / 364814336 bytes (100.0%)
Camera returned HTTP 204: start_requested.
Installation completion is NOT confirmed. Check the camera/App before another upload.
Result: upload-result-20261014-151709-696527.json
```

你得到的结果文件时间戳会不同。**100% 只是上传进度，HTTP 204／start_requested 只是接受异步安装请求，
两者都不等于安装完成。** 如果状态为 `uploaded` 而不是 `start_requested`，说明该命令没有请求安装，
不能把仅暂存固件当作恢复完成。

## 7．观察安装，完成后验收

相机正在升级时保持供电，不拔电池，按机身／App 的实际提示操作。
若网络断开，先看实体机身是否已经进入升级，**不要因为掉线就重新上传**。本案例没有确定通用的安装耗时。

安装结束后，操作者应逐项记录：

- 固件版本、取景和菜单是否正常。
- 能否拍摄新照片、保存并在相机相册中打开。
- 能否正常关机及再次正常启动。
- 原先受影响的 Wi-Fi／Phocus 连接是否恢复。

这些是新操作者应完成的检查；历史案例只有机主成功反馈，没有收到完整逐项验收表。
将上传结果 JSON 留在本地。即使功能正常，也不能仅凭此证明所有历史改动均已清除或每个同版本模块均已重写。

## 停止条件与常见问题

| 看到的结果 | 处理 |
| --- | --- |
| 找不到 `py` | 安装 Python／启动器，重新打开 PowerShell 并确认版本；此时没有上传。 |
| 找不到脚本或固件文件 | 检查完整解压、当前目录及带双引号的真实固件路径。 |
| 缺少 `VHABCIM` 文件头或哈希不符 | 停止，重新取得完整、未改动、正确机型的原厂包。 |
| 没有旧授权手机、没有成功读取请求、probe 被拒 | 本路线条件未满足，不继续上传。 |
| 上传后返回 HTTP 拒绝 | 保留准确响应和结果文件，不自行添加 force 参数或修改固件版本。 |
| `unknown`、上传中断、回执丢失或退出码 3 | 相机可能已经收到请求，先检查机身／App 并保留记录，不自动重复。 |
| HTTP 204／start_requested | 观察安装，可能还在升级时不要再次 POST。 |
| 看似升级结束后仍异常 | 保留现象和记录；本次成功案例不能代替硬件诊断或保证再次恢复。 |

需要帮助时可在 [toolkit Issues](https://github.com/Gothenburg-R-D-Team/x2d-907-one-click-extension-toolkit/issues)
提供机型、报告版本、失败阶段及脱敏输出；公开前移除真实 ID、会话文件、抓包和个人路径。

[完整案例](CASE.md) · [验证范围](VALIDATION.md) · [全部案例](../README.md)
