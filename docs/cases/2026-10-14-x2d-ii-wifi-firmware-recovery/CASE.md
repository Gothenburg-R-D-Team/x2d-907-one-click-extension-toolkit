# X2D II recovery case: from time-watermark modification failure to Windows firmware reinstall

## Outcome and evidence level

On 2026-10-14, the owner remotely operated another Windows computer and uploaded an original X2D II 100C `1.3.16.2` CIM through the camera's Phocus HTTP API. The Windows session probe succeeded, all 364,814,336 bytes were sent, and the camera returned HTTP 204 with the script state `start_requested`. The owner then reported that the physical camera was upgrading and finally confirmed success.

This is **one user-operated physical-camera success**, supported by request/response screenshots and the pasted Windows terminal output. The assistant did not directly access the remote Windows computer or camera. The upload-result JSON file, pre-update version screen, final version screen and per-module write logs were not supplied. The earlier recovery thread did obtain an ordinary USB version readback of `1.3.16.2`, matching the recovery package; a version screen and per-module rewrite evidence remain absent. The result demonstrates this upload/start route under the active-session conditions used in the case; it does not prove an unconditional same-version force-reflash mechanism or that every equal-version module was rewritten.

This case is archived separately from the first-generation X2D/CFV desktop installer. The companion scripts are standalone recovery/research tools; the desktop application, its firmware gates, payloads, version and updater are not changed.

## Incident origin, symptoms and unsuccessful rollback

### What caused the incident sequence

This was recovery after a persistent camera modification, rather than a failure during an ordinary official CIM update. The operator confirmed that the earlier deployment was performed by WorkBuddy on the remote Windows PC. Supplied reports from the `x2d2-timesync` project describe deployment of a **time-watermark module on 2026-10-13**, followed by abnormal GUI operation after a camera restart. The reports attribute the triggering deployment to that module; the precise runtime crash mechanism remains unconfirmed.

### Reported deployment sequence

The original reports describe this order; those reports are retrospective AI-generated summaries, not a complete independently replayed deployment transcript:

1. Archive/remove five older library/state files under `/data/local`, and identify an old `libx2d2ext_v5.so` (14,968 bytes) versus a newer build (33,144 bytes).
2. Transfer seven payload files to `/data/local/x2d2-timewm/` through the RNDIS TCP path and device-side `busybox nc`.
3. Change `/system/etc/init/camera-gui.rc` so `LD_PRELOAD` loads the time-watermark injection library; deploy `libx2d2-timewm.so` to `/system/lib64/`. The payload also involved `X2d2MasterState.qml`.
4. Place `undo_timewm.sh` under `/data/local/x2d2-timewm/` as a prospective rollback path.
5. Restart the camera. The reports describe GUI crash/restart behavior and a silent command channel afterward. Later observations did not establish the camera's current process state through a live process/log readback.

Because the library and init configuration were written to `/system`, restarting alone did not remove the modification. This was not merely a temporary RAM experiment. No evidence shows that the later successful recovery uploader created the original fault; it was used after these modifications and failed rollback attempts.

### What the later source/asset review established

The earlier recovery thread reviewed owner-supplied evidence bundles without importing or executing the original deployment tools. The review identified:

| Finding | Consequence / evidence limit |
| --- | --- |
| The time-watermark constructor reads `enabled` only for logging and calls overlay registration unconditionally | `enabled=false` does not skip the injection; a saved feature switch is not a complete unload/rollback mechanism |
| Overlay registration attempts to replace the GUI MainScreen `CachedQmlUnit` `qmlData` pointer with an embedded cloned unit | The change affects GUI initialization/runtime; the available constructor/listener/switch paths did not invoke the memory-restore function |
| The clone code uses fixed PIE offsets and changes page protection; runtime checks cover only limited format/pointer conditions | Offline integrity checks alone do not establish full runtime compatibility, original page permissions or coexistence with other modules |
| Reviewed `go_live.sh` backup replaces `camera-gui.rc` before installing/verifying the new library | There is a configuration/library ordering window; this is a deployment weakness, not proof it was the crash trigger |
| The deployment's reported payload verification uses filename matching in `ls` output, with command retries | It does not close every file/hash/metadata/SELinux verification step; matching failure text can produce a false positive |
| The so-called original/pre-watermark RC still loads `libx2d2ext_v5.so` and `libx2d2wifi.so` | Executing that rollback would return to an already-modified state, not a fully untouched factory system |
| An earlier host-side `camera-service.rc.new` additionally preloads `libx2d2afc.so` | This proves a host-side proposed modification exists, not that it was installed or active on the failed camera |

A reviewed host-side time-watermark SO was 33,144 bytes, SHA-256 `a8e3da5cbf4444fbd9ab6d8fb133769bf8ff586fa7a18862f77aefb6dae880f0`, MD5 `3333936be7af718afe109fd87ef03dec`. It was not read back from the camera, so those hashes must not be presented as the device's actual loaded library. Existing logs from 2026-10-13 14:52:00–14:52:30 showed module initialization under different PIDs roughly every five seconds, supporting repeated GUI starts during that historical interval. They did not prove the current process state or the final cloned-library deployment.

These findings explain why a nominal OFF switch and a prepared rollback script did not guarantee recovery. They do **not** distinguish conclusively between symbol/ABI conflict, a QML/clone incompatibility, missing dependencies, startup ordering or another service problem.

### Failure symptoms and recovery attempts before HTTP upload

- Earlier recovery notes recorded no response to the menu key, while some physical keys and ISO/WB pages still reacted. This is more specific than simply saying the camera was completely dead.
- The original reports observed USB/RNDIS network reachability at `192.168.42.2` and open TCP 30303/30304, but no replies to their probes. Some early text `PING` probes were not validated protocol queries. Reachability and open ports alone cannot prove `camera-gui` or the diagnostic service is healthy, dead, or in a crash loop.
- Later owner-operated native WinUSB tests confirmed the ordinary USB control interface (IF4, OUT06, IN87) and returned firmware `1.3.16.2`. A cached diagnostic-bridge status responded with 0/0; camera-service cached status and diagnostic version/shell queries did not respond. A bridge cache response does not prove a working live shell.
- The original historical protocol was obtained and compared with the new probes. Differences in function, interval and newline were corrected; the final fixed model query through TCP and then USB each received **zero bytes within 20 seconds**. The absence of a verified execution channel remained.
- `camera-test` waiting for `CameraProxyDbus::isSynced` was a static-analysis working hypothesis for the blockage. It did not establish that the diagnostic process had crashed or identify the damaged file.
- The available ADB device listing was empty. Preparing a guarded rollback helper and locating `undo_timewm.sh` did not mean a rollback had run. No camera-side file rollback, library deletion, reset or firmware write was completed in that earlier recovery stage.

The diagnostic route was therefore abandoned in favor of the independently working, already-authorized phone/Phocus path. The phone could enable Wi-Fi and issue accepted camera HTTP reads despite the unusable diagnostic execution path.

### Recovery endpoint and remaining uncertainty

Windows used the real phone request ID, passed `/v1/parameters`, uploaded the complete original `1.3.16.2` CIM and received HTTP 204. The owner then reported camera installation and success. The commands and later evidence are recorded in the successful-operation sections below.

The earlier ordinary USB readback also reported `1.3.16.2`, so the record now includes evidence that the recovery package's version matched the reported pre-recovery camera version. This strengthens the same-version recovery context. It still does not establish every module's rewrite, a universal force-update mechanism or post-recovery factory file hashes. No per-module write trace or complete final functional checklist was supplied.

### Source provenance

This case uses two owner-supplied reports (generated 2026-10-14 09:00 and 09:32, China time), plus the local source/asset review and remote recovery notes from the earlier conversation titled “恢复相机设置”. Their SHA-256 values are recorded in [MANIFEST.json](ORIGINAL_MANIFEST.json). The source documents, full evidence ZIPs, camera logs, real identifiers and personal host paths remain outside Git. Their recommendations are historical evidence, not instructions to execute.

The reviewed 139-file bundle's SHA-256 was `ca98de4cf455c49242ea753d30c4c85707d35d3a5d9ab06bd6f1291cb276750e`; the six-file protocol supplement was `14d7aff23f72c67830f2757af536632cd3206ac3a414892f89928d3141803e07`. Review notes recorded that both bundles' listed file hashes matched their contents. This does not authenticate deployment to the camera.

## Case conditions

| Item | Evidence / condition |
| --- | --- |
| Camera | X2D II 100C; camera screen could not be used to approve a new client |
| Phone | An already-authorized iPhone; Phocus could connect and enable camera Wi-Fi |
| iOS App | Screenshot User-Agent: Phocus Mobile 4.5.0, bundle `com.hasselblad.mobile2`, build 39, Alamofire 5.12.0 |
| Operator | Owner remotely controlling another Windows PC; not the assistant's Mac |
| Camera network | Wi-Fi gateway / HTTP host `192.168.2.1:80` |
| Wi-Fi coexistence | Owner observed that the PC disconnected shortly after the phone joined the camera hotspot |
| USB camera network | Earlier PC adapter address `192.168.42.1`; the owner clarified the camera USB connection was already unplugged |
| Phone identity evidence | Actual `X-Phocus-Client-Id` observed in a camera GET; corresponding HTTP 200, JSON content length 1005 |
| Firmware | Original `X2DII_100C_v1_3_16_2(1).cim`, 364,814,336 bytes |
| Physical outcome | Owner: camera “正在升级”, then “成功了” |

The real client ID, photo path, camera identifiers, account-specific paths and screenshots containing those values are intentionally kept outside Git, as required by repository policy. No fake sample ID is represented as usable authorization.

## Investigation and decisions

1. **Intent.** The owner wanted a lightweight Windows script that follows the mobile App's upload/start route, because the App would not offer reinstalling the latest firmware. The camera's inability to approve a new client made reuse of the existing phone authorization relevant.
2. **Server-side protocol first.** Static analysis of the local extracted X2D II `phocus` executable identified the POST upload route, raw-body staging, header parser, active-client validation and asynchronous upgrade signal. First-generation camera networking observations were not used as proof for the X2D II API.
3. **Official Android App cross-check.** The vendor APK retained the upgrade URL and header strings. Its protected DEX initially exposed only wrapper classes and method placeholders. Rebuilding its header/string table and applying the embedded `classes.dex.dgc2` relocation records recovered 16,340 method bodies for static analysis. This located identity generation, authorization, BLE framing and the HTTP interceptor. The analysis reconstruction was not installed or re-signed.
4. **Identity distinction.** The analyzed Android App generates and persists its own ID; that finding was not assumed to describe iOS. The later iPhone screenshot provided the actual decimal uint32 used on the wire, so no UDID/MAC/IMEI guess was needed. The source of the iOS ID remains unestablished.
5. **Initial capture approach did not fit the site.** A PC forwarding proxy required both Wi-Fi clients to remain connected and the App to honor the iOS proxy. The owner observed Wi-Fi contention. The successful route instead collected the header on the already-authorized iPhone, then tested the PC's current HTTP access with that ID.
6. **Alternative tools were prepared.** A read-only iPhone USB network-mirror collector and an experimental BLE existing-ID session tool were implemented and tested offline. Neither was needed for the successful physical-camera operation, so neither is labeled device-validated.
7. **Live acceptance resolved the remaining upload uncertainty.** The PC's `GET /v1/parameters` accepted the actual phone ID. The original HTTP uploader then sent the unchanged official CIM and `start_upgrade=true`; the owner confirmed the subsequent physical upgrade.

Detailed reverse-engineering addresses, binary hashes and reconstruction limits are in [protocol evidence](PROTOCOL_EVIDENCE.md). Addresses are ELF virtual addresses, not file offsets or load-biased runtime addresses.

## Problems encountered and how they were resolved

| Observation | Meaning | Resolution / evidence |
| --- | --- | --- |
| `inspect` first returned file-not-found | The specified local firmware file was unavailable at that path | Correcting the local file placement/path made offline inspection succeed |
| `inspect --start-upgrade` printed a request plan | It hashed the file and displayed the intended request; it did not upload | The later explicit `upload` command performed the network write |
| `import-session phocus-http.har` returned file-not-found | The example HAR did not exist; the importer does not generate a capture | Actual iPhone request-header collection supplied the ID |
| A `Read-Host` prompt was answered with a whole Python command | The command text became a variable value rather than being executed | Instructions separated prompt input from the next PowerShell command |
| PC Wi-Fi dropped after the phone joined | Site-specific coexistence problem; static AP configuration was insufficient proof of support | Avoid relying on a two-client PC proxy; use phone-local capture and live PC probe |
| USB adapter appeared in an earlier `ipconfig` | This did not prove a current USB camera connection | The owner explicitly clarified that USB was unplugged |
| Camera could not approve a new device | Fresh-client pairing was unsuitable | Reuse the already-authorized phone's observed ID; require a live acceptance check |
| HTTP 204 after full upload | The server accepted the upload/start request, but installation remained asynchronous | Owner observed the physical upgrade and reported final success |

## Successful operation sequence

Keep the connection state that produces a successful probe. A copied ID is not an independently established session. In the case, the instructions had the phone enable the hotspot, the Windows PC join it, and retained the original phone Bluetooth connection while avoiding simultaneous phone/PC Wi-Fi contention. The precise Bluetooth lifetime was not independently measured.

From a standalone tool-package folder on Windows:

```powershell
# Paste the actual decimal value observed in the iPhone camera request.
$phocusClientId = Read-Host "Paste the actual X-Phocus-Client-Id"
py -3 .\collect_phocus_client_id.py --observed-id $phocusClientId

# Read-only preflight: proceed only if the current session is accepted.
py -3 .\x2d2_wifi_upgrade.py probe --session .\session.json

# One complete official CIM upload, requesting installation after staging/checks.
py -3 .\x2d2_wifi_upgrade.py upload "C:\Firmware\X2DII_100C_v1_3_16_2(1).cim" --session .\session.json --start-upgrade
```

The relevant output supplied by the owner was:

```text
Session accepted by /v1/parameters. No firmware was uploaded.
Sent 364814336 / 364814336 bytes (100.0%)
Camera returned HTTP 204: start_requested.
Installation completion is NOT confirmed. Check the camera/App before another upload.
Result: upload-result-20261014-151709-696527.json
```

These are excerpts of user-supplied host-tool output, not archived raw camera logs. The JSON filename identifies a reported artifact; the JSON contents were not read.

After that output, the owner first reported that the camera was upgrading and then confirmed success. Do not repeat a POST just because the connection disappears during an update. A server rejection, an interrupted upload and an accepted asynchronous start are different results.

Full phone collection instructions and the fallback BLE probe are in [operations](ADVANCED.md).

## Request actually implemented

```http
POST /v1/upgrade/<URL-escaped-CIM-filename> HTTP/1.1
X-Phocus-Client-Id: <currently accepted decimal uint32>
X-Phocus-Upload-Info: {"size":<file bytes>,"sha1":"<complete file SHA-1 hex>","start_upgrade":true}
Content-Type: application/octet-stream
Content-Length: <file bytes>
Connection: close

<unchanged complete official CIM>
```

The uploader hashes/validates the local file, requires a successful JSON parameters response before POST, streams the raw bytes, detects file changes and does not retry POST or follow redirects. It records `installation_completed=false` even after 204; only subsequent device evidence can establish completion.

Firmware hash values were supplied by the owner's offline inspection (not independently verified against a downloaded complete CIM):

- SHA-1: `17eb99daff82d22b53ef31aaca91dfd7f611e141`
- SHA-256: `9789d6a9843d388034bc12341ad9a97585c25cb98cf11a0da8b768399b4842f6`

The native upgrade service still performs compatibility/candidate checks. No firmware-version alteration, package-signature bypass, guessed `force_upgrade` field or factory-shell command was used.

## Archived materials and reproducibility

- [Standalone tool sources](../../../src/tools/x2d2_wifi_firmware/README.md): HTTP uploader, HAR/header ID collector, USB collector and experimental BLE session helper.
- [Offline regressions](../../../tests/x2d2_wifi_firmware/README.md): 12 default offline mock/parser tests plus 10 explicitly invoked localhost HTTP checks; no physical-camera test is performed by either suite.
- [Protocol reconstruction tools](../../../src/tools/x2d2_wifi_firmware/analysis/README.md): authored analysis helpers only; vendor binary input must be obtained separately.
- [Artifact/hash manifest](ORIGINAL_MANIFEST.json): source hashes, vendor-input hashes, reconstruction counts and the clean standalone-package recipe.

The supplied vendor APK, extracted firmware binaries, DEX files, disassemblies, runtime libraries, real session JSON and full captures are not stored in this repository. The user-delivered local 0.2.1 standalone ZIP is represented by its SHA-256 and source contents; the repository archive can recreate a standalone ZIP without those private/vendor inputs.

## Validation and open limits

| Claim | Status |
| --- | --- |
| Full raw CIM POST/start using the active phone ID from Windows | User-operated X2D II success |
| Upload and final camera upgrade are separate stages | 204 output, then owner upgrade/success reports |
| HTTP framing, file checks, no retry after ambiguous POST, proxy write block | Local mock-camera tests passed |
| HAR status/host filtering, TCP reassembly and ID output | Local tests passed |
| BLE CRC/framing and stop on pending/refused authorization | Local mock tests passed |
| iPhone-local capture of the real header and camera 200 | Owner request/response screenshots |
| Direct iPhone USB network-mirror collector | API checked; not used on the target phone |
| Independent BLE reconstruction of the iPhone session | Not used on the target camera |
| iOS ID generation/storage rules | Unconfirmed |
| Every same-version module forced to rewrite | Not established; before/after module evidence absent |
| Recovery of the earlier non-operable screen specifically | Final “success” reported; no separate detailed functional checklist supplied |

Do not convert this case into a claim of general X2D II support in the first-generation desktop installer. No new physical camera action was performed when archiving or uploading this case.

---

# 中文完整案例：从时间水印改装故障到 Windows 重装原厂固件恢复

## 最终结果

2026-10-14，用户远程操作另一台 Windows，对 X2D II 100C 上传原厂 `1.3.16.2` CIM。先通过 HTTP 会话验证，完整上传 364,814,336 字节，机身返回 `HTTP 204 / start_requested`。用户随后反馈机身“正在升级”，最后确认“成功了”。

这是一次**用户现场执行并反馈成功的实机案例**。助手依据用户提供的 iPhone 请求/响应截图和 Windows 输出记录结果，没有直接控制远程 Windows 或相机。结果 JSON 原文、升级前版本画面、最终版本画面和各模块重写日志均未取得；不能据此宣称“强制重写所有同版本模块”。

## 故障起因、症状与此前恢复尝试

### 事故起点

这次恢复针对的是**持久化改装之后的相机异常**。此前操作员明确确认：故障部署由远程 Windows 上的 WorkBuddy 执行。用户提交的 `x2d2-timesync` 项目报告称，2026-10-13 部署“时间水印”模块，改写 `/system/etc/init/camera-gui.rc` 的 `LD_PRELOAD`，把 `libx2d2-timewm.so` 写入 `/system/lib64/`，涉及 `X2d2MasterState.qml`，并预置 `/data/local/x2d2-timewm/undo_timewm.sh`；相机重启后 GUI 异常、命令通道无回复。

原报告将这次部署列为故障诱因，但具体崩溃机制尚未从现场日志确认。不能把报告中的“GUI 崩溃循环”直接写成当前进程状态的实测结论，也不能根据 ping 或端口开放就断言完全没有变砖风险。此次成功的 Wi-Fi 固件上传是后续恢复步骤，不是最初致故障的操作。

### 审查发现的具体问题

1. 水印库 constructor 读到 `enabled=false` 也继续注册 overlay／注入 MainScreen；“关闭功能”并不完整撤销注入。
2. 注入尝试用固定偏移替换 GUI 的 `CachedQmlUnit.qmlData`，运行态校验不覆盖完整 GUI 哈希、全部克隆结构、原页面权限和其他模块的并发操作；已有内存恢复函数未被现行启动／开关路径调用。
3. 已审查部署备份先替换启动配置，随后才写入新库，存在启动配置引用尚未核实就位的库的窗口；文件名匹配式验证及命令重试也不足以闭合落盘过程。这些是已发现的薄弱点，不等于已经证明它们是唯一崩溃根因。
4. 所谓“原厂”回滚配置实际上仍预加载 `libx2d2ext_v5.so` 和 `libx2d2wifi.so`，只会退回水印之前的改装状态。更早的后台服务配置候选还引用 `libx2d2afc.so`，但没有证据证明它当时已落位或仍在运行。
5. 主机库与历史日志可证明文件内容及过去某个时段的重复初始化，不能代替相机当前库、配置和进程的回读。

因修改写入了 `/system`，重启不会像临时 RAM 补丁一样自动清除。离线完整性检查通过，也不能保证这类运行时注入与机身 GUI 兼容。

### 故障表现及没有成功的恢复路径

前期记录是菜单键无反应、部分物理键及 ISO/WB 页面仍有反馈。USB/RNDIS 网络和端口存在，但诊断命令没有有效回复。后续普通 USB 版本读取成功，返回 `1.3.16.2`；诊断桥缓存能返回 0/0，仍不能证明 shell 可用。

审查原始通信代码、修正查询参数后，TCP 和 USB 的固定型号查询分别等待 20 秒，均收到 0 字节。ADB 列表也为空。因此一直没能取得执行回滚脚本的有效入口；“回滚脚本已准备／已放在设备上”不等于“回滚已执行”。此前恢复阶段没有完成机身文件回滚、删库、复位或固件写入。后台服务未同步是解释诊断阻塞的工作假设，诊断进程具体状态和崩溃根因仍未证实。

之后转向已授权 iPhone 仍可使用的 Phocus 通路：手机打开相机 Wi-Fi，采集真实请求 ID，Windows 通过 HTTP 会话检查，上传完整原厂 `1.3.16.2` CIM 并启动升级，用户确认成功。

### 结论的边界

现在已有此前普通 USB 读回的 `1.3.16.2`，可以记录“相机报告版本与恢复包版本相同”。仍不能据此声称所有同版本模块都被强制重写，或已逐文件校验清除了全部历史改装；最终详细功能验收及原厂文件哈希未取得。

原始报告为用户提供的第三方 AI 回顾，后续源码审查和用户现场诊断属于不同证据层级。完整过程、相关哈希与不确定性按上述分层记录，原始个人资料和设备日志不进入私库。

## 场景与关键限制

目标是通过轻量脚本实现手机 App 的固件上传/启动功能，用于 App 不提供最新版重装入口的场景。手机是已授权的 iPhone，能连接 Phocus 并开启相机热点；相机当时无法在屏幕上授权新客户端。Windows 有蓝牙，但成功流程没有使用新的独立 BLE 授权脚本。

电脑接入相机热点时，手机再接入会导致电脑一段时间后断开。不能依赖手机和电脑长期共存来运行 PC 代理。此前 `ipconfig` 中的 `192.168.42.1` 是电脑端曾出现的 USB 网络适配器；用户明确 USB 已断开，不能将旧适配器条目当作实时连接证据。

## 从分析到可用方法

1. 从 X2D II 机身 `phocus` ELF 还原 HTTP POST 路由、客户端验证、JSON 上传头、完整文件大小/SHA-1 检查，以及异步安装信号。
2. 用官方 Android App 做独立交叉核对。最初保护程序遮蔽类表及方法；随后根据明文 DEX 结构、字符串和 `classes.dex.dgc2` 重定位记录恢复分析副本中的 16,340 个方法。
3. Android 代码显示它自己生成并保存 App ID；这个结论没有直接套用到 iPhone。iOS 的 ID 来源仍未确认；实际 HTTP 请求里的十进制 ID 才是脚本需要的值。
4. PC 代理方案不适合现场热点共存限制，改由 iPhone 本机采集其已经获授权的请求头。用户截图确认 Phocus Mobile 4.5.0 / build 39 请求携带 ID，对应响应为 200 OK、JSON、content-length 1005。
5. Windows 使用这个 ID 请求 `/v1/parameters`，返回 `Session accepted`。此时只读验证通过，尚未发送固件。
6. 保持当时连接状态，执行原版 `x2d2_wifi_upgrade.py upload ... --session session.json --start-upgrade`。全部字节上传，返回 204；再由机身升级状态与用户最终反馈确认完成。

真实客户端 ID、照片路径、设备标识和个人电脑路径按私库规则留在本机，不进入 Git。案例资料使用占位符；占位符不代表可用授权。

## 已排除的误解

- `inspect --start-upgrade` 只是离线检查和请求预览，不上传、不安装。
- 示例 `phocus-http.har` 不会由 `import-session` 自动生成；文件不存在就是缺少采集文件。
- `Read-Host` 出现提示后应只输入所问值；输入整条 Python 命令不会执行该命令。
- 获得历史 ID 不等于 Windows 永远有会话；必须在当时网络/手机状态下 `probe`。
- 204 代表上传及安装启动请求被接受；真正完成仍需要机身后续状态。
- 没有修改固件版本，没有添加未经证实的 force 参数，没有使用工厂 shell 刷写。

## 成功操作与资料入口

完整命令、终端证据摘录和验证边界见本文件英文部分；[操作指南](ADVANCED.md)保留详细 iPhone 采集步骤、HTTP 验证/上传，以及尚未实机使用的 USB/BLE 备用路线。

[协议依据](PROTOCOL_EVIDENCE.md)标明 ELF 虚拟地址、输入哈希及未决问题。[脚本源码](../../../src/tools/x2d2_wifi_firmware/README.md)和 [12 项离线测试及 10 项本机 HTTP 检查](../../../tests/x2d2_wifi_firmware/README.md)可独立运行。厂商 App、原厂固件、DEX、反汇编、运行库和实际会话文件不随案例入库。

这份档案不改变一代 X2D/CFV 安装器的功能支持范围、主程序、版本或更新通道。归档过程不再次连接、安装或重启用户相机。
