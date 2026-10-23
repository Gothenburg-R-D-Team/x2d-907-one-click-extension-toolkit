> Historical and advanced methods. For the case-validated route, start with [English recovery steps](RECOVERY.en.md) or [中文恢复步骤](RECOVERY.zh-CN.md). USB capture and independent BLE session recreation below remain device-unverified.

# Operations: collect the authorized iPhone ID, then probe/upload from Windows

The user-operated successful route was phone-local request-header collection, Windows HTTP preflight and one original CIM upload/start. USB mirroring and independent BLE recreation are alternatives without target-device validation.

1. On the already-authorized iPhone, enable the camera hotspot in Phocus. A phone-local HTTP capture tool can expose the camera GET request. Select host `192.168.2.1:80`, path `/v1/…`, and verify its matching 2xx response. Copy the actual decimal `X-Phocus-Client-Id`; do not use a phone UDID or invented example ID.
2. In the standalone script folder, run the following first line; answer the prompt with only the ID, then run the next line:

```powershell
$phocusClientId = Read-Host "Paste the observed X-Phocus-Client-Id"
py -3 .\collect_phocus_client_id.py --observed-id $phocusClientId
```

3. Connect Windows to the camera hotspot. At this site the phone and PC could not remain on camera Wi-Fi together. Preserve the existing phone Bluetooth/session state and use a live probe to determine whether HTTP access is still accepted:

```powershell
py -3 .\x2d2_wifi_upgrade.py probe --session .\session.json
```

4. Only after `Session accepted`, keep that connection state and run one upload/start using the complete official firmware:

```powershell
py -3 .\x2d2_wifi_upgrade.py upload "C:\Firmware\X2DII_100C_v1_3_16_2(1).cim" --session .\session.json --start-upgrade
```

5. HTTP 204 means the asynchronous start request was accepted. Observe the camera for completion. Do not repeat an ambiguous POST automatically. The case user subsequently reported upgrading and success.

Manual-ID import records historical acceptance as unverified because it cannot inspect the screenshot; the mandatory live probe resolves current acceptance. `inspect` is offline and sends nothing. `import-session` requires a real capture file; it does not create HAR files.

For the detailed phone-local capture instructions, optional USB collector dependency/setup and experimental BLE fallback, see the Chinese instructions below. Python 3.9+ suffices for the standard-library uploader/HAR tool; actual Bleak 3.0.1 requires Python 3.10+.

---

# iPhone 上采集 Phocus 客户端 ID

适用场景：你远程操作另一台 Windows；对方的 iPhone 已获相机授权，可以连接 Phocus、开启相机 Wi-Fi；相机目前无法在屏幕上确认新设备。

目标是取得相机通信请求中的 `X-Phocus-Client-Id`，并生成 `phone-client-id.json` 和旧上传脚本兼容的 `session.json`。采集不上传固件，也不要求相机确认新客户端。iPhone 对电脑的 USB「信任」是另一件事。

已核实的 Android App 实现：自己生成并保存随机设备 ID，不读取手机 UDID、IMEI、序列号或 Wi-Fi MAC。**iOS 的 ID 生成规则尚未恢复，不能用 Android 的规则替代 iPhone 的真实 ID。**读取 iPhone 实际发出的 HTTP 请求头可以直接取得脚本需要的值，不依赖猜测它的生成规则。

## 方法 A：只在 iPhone 上采集

1. 在对方 iPhone 上安装 [Stream（开发者 Stream Lab，App ID 1312141691）](https://apps.apple.com/cn/app/stream/id1312141691)。同名 App 较多，用这个链接识别。其开发者介绍明确支持手机本机 HTTP 请求抓取。
2. 打开 Stream，启动抓包。如果 iOS 弹出添加 VPN 配置，允许；这是该工具在手机本机采集流量所需的配置。此处只查看相机的明文 HTTP，不需要安装用于 HTTPS 解密的根证书。
3. 让 iPhone 用原来已经授权的 Phocus 连接相机，并保持连接相机 Wi-Fi。打开相机相册，或进入能正常读取相机信息的页面，让 App 发出读取请求。不要点固件更新。
4. 回到 Stream 的请求列表，查找目的地址 `192.168.2.1`、路径以 `/v1/` 开头的 HTTP 请求。不要选哈苏云端网站请求。
5. 打开该请求的「请求头 / Request Headers」，复制 `X-Phocus-Client-Id` 后的十进制数字；同时核对对应响应为 200 或其他 2xx。如果界面将头名字改为小写，意义相同。
6. 把这个数字传到远程 Windows。在脚本目录执行以下第一行；出现提示后，**只粘贴 ID 数字并按回车**，然后执行第二行：

```powershell
$phocusClientId = Read-Host "粘贴 iPhone 请求头中 X-Phocus-Client-Id 的数字"
py -3 .\collect_phocus_client_id.py --observed-id $phocusClientId
```

这会生成两个 JSON 文件。手工录入无法由工具独立核对响应，所以文件中标记 `observed_camera_acceptance: false`；随后仍须做现场会话验证。

如果 Stream 支持导出所选请求为 HAR，可将文件放到脚本目录，并改用：

```powershell
py -3 .\collect_phocus_client_id.py .\phocus-iphone.har
```

HAR 导入会核对相机地址、端口 80、`/v1/`、请求头，以及配对的 2xx 响应。只导出相机的读取请求即可。不要把示例文件名当作已经存在的文件。

用户后来提供了手机本机采集的请求头及对应 200 响应，Windows 也已接受其 ID；未另行记录抓包工具的安装和配置画面。有些局域网请求可能绕过手机抓包工具；如果始终没有相机请求，改用方法 B。不能将空列表解释为 Phocus 没有客户端 ID。

采集结束后停止 Stream，恢复手机原来的 VPN 配置状态。

## 方法 B：iPhone 接远程 Windows，用 USB 采集真实网络流量

这个方法不依赖手机 App 是否遵循 HTTP 代理。iPhone 仍通过 Wi-Fi 连接相机；Windows 从 USB 读取 iPhone 网络流量镜像。**采集时 Windows 不必连接相机热点**，因此没有两台设备争用相机 Wi-Fi 的问题。

1. 在远程 Windows 安装 Apple Mobile Device Support。已有 iTunes 且能识别该 iPhone 时通常已具备。若没有，按 [PyMobileDevice3 Windows 安装说明](https://doronz88.github.io/pymobiledevice3/installation/)安装 iTunes，并确认 Apple Mobile Device Service 正在运行。
2. 用能传数据的 USB 线将 **对方 iPhone 接到远程 Windows**。解锁 iPhone；若手机弹出「信任此电脑」，在手机确认。相机不需要 USB 连接，不需要确认新授权。
3. 在远程 Windows 的工具目录打开 PowerShell，安装采集依赖：

```powershell
py -3 -m pip install pymobiledevice3==11.29.1
```

4. iPhone 保持在相机 Wi-Fi；先退出 Phocus 前台。运行：

```powershell
py -3 .\collect_iphone_usb_id.py --seconds 60
```

5. **等 Windows 终端出现 `READY` 后**，在 iPhone 上重新打开 Phocus，正常连接已授权的相机，打开相册或读取相机信息。采集器只识别开始采集之后新建的 HTTP 连接；若未捕获到，重新运行后再重新打开 App。
6. 发现带有真实 ID 的相机 GET，并看到同一连接的成功响应后，脚本自动结束并显示：

```text
Collected actual Phocus client ID: <手机实际值>
Saved phone-client-id.json and session.json
```

工具不会生成完整 PCAP 文件。它只保存 ID、相机地址、GET 路径和成功状态，不保存其他网站流量、账户请求头、Cookie 或图片正文。

如果没有找到 iPhone，检查 USB 数据线、手机解锁/信任和 Apple Mobile Device Service。只连接一台 iPhone；工具拒绝自行选择多台中的任意一台。

如果提示相机 TCP 包数量为 0，核对 iPhone 正在连接相机热点，并重新打开 Phocus。`192.168.2.1` 来自当前已提供的网络信息；如果相机地址实际不同，运行时用 `--camera-host 实际相机IPv4`。

## 取得 ID 后：先测试现有 HTTP 会话（本次实机已通过）

用户于 2026-10-14 通过这一流程完成机身升级，无需独立 BLE 建会话。

1. 让 iPhone 原有 Phocus 连接开启相机 Wi-Fi，取得手机实际请求 ID。
2. Windows 接入相机热点。现场不允许两台 Wi-Fi 客户端共存时，手机断开相机 Wi-Fi，先保留原来的蓝牙连接。以现场 `probe` 的响应判断会话是否仍有效；不要假设仅有 ID 就能保持授权。
3. 在已有 `session.json` 的脚本目录执行：

```powershell
py -3 .\x2d2_wifi_upgrade.py probe --session .\session.json
```

4. 只有显示 `Session accepted by /v1/parameters` 后，保持刚才的连接状态，执行一次：

```powershell
py -3 .\x2d2_wifi_upgrade.py upload "C:\Firmware\X2DII_100C_v1_3_16_2(1).cim" --session .\session.json --start-upgrade
```

本次用户报告的终端结果是完整 364,814,336 字节上传、`HTTP 204: start_requested`；随后报告机身“正在升级”并最终确认“成功了”。具体记录见 [完整案例](CASE.md)。HTTP 204 本身仍不确认安装完成，须结合机身结果。

如果 `probe` 返回 401/403，先判断原手机会话是否失效；这不是同版本固件拒绝，因为检查尚未发送固件。

## 现有 HTTP 会话不可用时：实验性的独立 BLE 会话复用

`session.json` 中有历史上观测到的 ID，**不表示手机退出后 Windows 已经有有效会话**。旧版 `x2d2_wifi_upgrade.py upload --session ...` 仍然要求活跃的授权会话；不要仅因生成 JSON 就直接上传。

新增 `x2d2_reuse_session.py` 使用 App 的 BLE 授权命令和机身 V1 会话结构，尝试复用同一个 ID。它是协议实验版，iPhone ID 在 Windows 上是否能复用，还要由真实相机响应确认。相机如仍要求屏幕授权，脚本停止，不伪造同意。

远程 Windows 需要 Python 3.10+ 和可用蓝牙。安装依赖：

```powershell
py -3 -m pip install bleak==3.0.1
```

让 iPhone 先开好相机 Wi-Fi，然后退出 Phocus、从 iPhone 设置中断开相机 Wi-Fi 和相机蓝牙连接；让 Windows 接入相机热点。保持 Windows 原有可用的远程网络，例如已连接的以太网。

先扫描相机：

```powershell
py -3 .\x2d2_reuse_session.py scan
```

将扫描返回的相机 `address` 放到命令中：

```powershell
$cameraBleAddress = Read-Host "粘贴 scan 返回的相机 address"
py -3 .\x2d2_reuse_session.py probe --identity .\phone-client-id.json --ble-address $cameraBleAddress
```

只有显示 `Camera accepted the reused ID in BLE and HTTP /v1/parameters.`，才表示本次测试建立的会话被接受。`probe` 退出会断开自己的 BLE 会话，所以之后上传须使用会重新建立和保持会话的命令，不能把已经退出的测试当成持续连接。

若测试通过，下一阶段可在同一工具中重新建会话并上传：

```powershell
py -3 .\x2d2_reuse_session.py upload "C:\Firmware\X2DII_100C_v1_3_16_2(1).cim" --identity .\phone-client-id.json --ble-address $cameraBleAddress --start-upgrade
```

该命令会先做 BLE 和 HTTP 验证，再上传原厂 CIM；不会伪造固件版本。安装启动请求与安装完成仍是两个不同结果。同版本是否被接受由机身决定；这一独立 BLE 复用流程尚未在实机验证。若请求后连接中断、结果为 `unknown`，先查看相机状态，不自动重试。

## 验证范围

本地模拟测试覆盖 HAR 地址/状态筛选、手工 ID 标记、输出配置兼容、USB TCP 乱序/重复/冲突重组、请求与响应配对、CRC 表特征值、BLE 授权被拒或需要屏幕确认时停止，以及旧 HTTP 上传器的失败处理。

已核对 PyMobileDevice3 11.29.1 与 Bleak 3.0.1 的实际包 API。用户已提供 iPhone 请求/200 响应截图、Windows 会话和上传输出，并确认机身升级成功。助手没有直接控制目标设备。USB 采集服务及独立 BLE 会话复用仍未在实机验证。
