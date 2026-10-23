# Protocol evidence — 2026-10-14

Protocol derived by static analysis; the original HTTP uploader was subsequently verified in one user-operated X2D II upgrade on 2026-10-14. See the user-reported hardware record below. Independent BLE recreation and USB capture remain hardware-unverified.

## Sources

- Vendor Android APK: Phocus Mobile 1.1.0, linked from https://www.hasselblad.com/downloads/#133
- APK SHA256: `5ee52bbb2b7a3fa708628ba251b409a551ae099697668427cf54b523328ccf68`
- APK URL: https://cdn.hasselblad.com/software/Phocus_Mobile_for_Android/1.1.0/phocus2_v1.1.0_20260914_162851_457_hasselblad_publish_release_signed_guard.apk
- Local extracted X2D II 1.3.16.2 `phocus` executable, from the workspace's existing firmware analysis. Its provenance was not independently authenticated in this task. Hashes are in [MANIFEST.json](ORIGINAL_MANIFEST.json).
- First 4096 bytes of official CIM obtained with a Range GET, from https://cdn.hasselblad.com/firmware/X2D_II_100C_Firmware/1.3.16.2/X2DII_100C_v1_3_16_2(1).cim
- Qt HTTP method values: https://doc.qt.io/qt-6/qhttpserverrequest.html

The Android class tables were reconstructed from the clear DEX map/string-data structures. The embedded `classes.dex.dgc2` relocation records restored 16,340 protected method bodies for static analysis; all restored code-item register counts and instruction allocations matched their placeholders. The analysis DEX is not a runnable/re-signed App. Authored reconstruction scripts are archived under `src/tools/x2d2_wifi_firmware/analysis/`; vendor inputs and generated DEX remain outside Git. The iOS app was not unpacked: its own ID generation and stored string casing are not established.

## Server control flow

Addresses below are virtual addresses in the local `phocus` ELF, not file offsets.

| Evidence | Location | Interpretation |
| --- | --- | --- |
| `/v1/upgrade/<arg>` route | `Httpd::Httpd`, `0xF7A58` | One path argument for the uploaded file name |
| route Method `0x8` | `0xF7AAC` | Qt `Post`, not PUT or multipart form |
| request body buffer selection | `Httpd::requestBufferCallback`, `0xF8A58` | Streams the body to a file in the firmware staging directory |
| active client validation | `Httpd::validateClientId`, `0xFA958` | Nonzero decimal uint32 header must match the active client ID; arbitrary IDs do not authenticate |
| header `X-Phocus-Upload-Info` | `0xF8F28` | Read as plain JSON via `QJsonDocument::fromJson` at `0xF8F78`, not base64 |
| upload-info parser | `readJsonUploadInfo`, `0xFB180` | `size`, `count`, `index` numeric; `sha1`, `model`, `version` strings; `start_upgrade` boolean; unsupported fields rejected |
| upload handler | `Httpd::upgradeCim` lambda, `0x10C950` | Reads size, SHA-1 and start flag; validates size and file hash; renames the completed staged file |
| expected SHA-1 hex parsing | `0x10CADC` | `QByteArray::fromHex`, so a hex digest string is used |
| start flag | `0x10CB44` and `0x10D184` | `start_upgrade=false` saves only; true enters upgrade checks |
| upgrade candidate selection | `0x10D894–0x10DA64` | Matches received filename to an upgrade candidate's `ref` and obtains its `uuid` |
| busy check | `0x10DA6C` | Returns an error when the camera is busy |
| signal | `0x10DDB0` | `Httpd::upgradeReceived(uuid)` |
| successful response | `0x10DE90–0x10DE98` | Returns HTTP 204, while installation remains asynchronous |

The optional model/version/count/index tags are recognized by the parser, but the inspected CIM upload handler consumes only size/SHA-1/start. The script sends that minimum. This exact request construction was subsequently accepted in the user-operated upload/start case recorded below.

The handler invokes the upgrade service's candidate check before emitting a start signal. Replacing the App therefore does **not** establish that same-version installation will be accepted. No `force_upgrade` query/header is invented. The updater's own checks and firmware package remain intact.

## Wire request implemented

```http
POST /v1/upgrade/<URL-escaped-CIM-filename> HTTP/1.1
X-Phocus-Client-Id: <active authorized session uint32>
X-Phocus-Upload-Info: {"size":<complete file bytes>,"sha1":"<hex SHA-1>","start_upgrade":true}
Content-Type: application/octet-stream
Content-Length: <complete file bytes>
Connection: close

<unchanged complete CIM bytes>
```

## Session acquisition and limits

The included capture proxy is a conventional read-only HTTP forwarding proxy. It records the client header only after the configured camera accepts an App GET with a 2xx response. It does not implement the Phocus pairing/keepalive protocol. The original App must retain its active session; the uploader validates it using `GET /v1/parameters` immediately before POST.

Whether the iOS app honors the system HTTP proxy is unverified. Importing existing HTTP/HAR evidence is also supported. Packet-file import only searches complete plaintext headers; it does not reconstruct TCP streams.

## Validation

Twenty-two local tests passed, including the original ten HTTP/proxy tests on `127.0.0.1` and twelve ID/TCP/BLE tests. The ID/BLE tests passed with Python 3.9, 3.13 and 3.15; actual Bleak 3.0.1 requires Python 3.10+. This verifies parsers, request construction and failure handling, not physical hardware acceptance. These tests sent no request to the target phone or camera. The separate physical-camera evidence was supplied by the user.


## Android App identity and recovered startup methods

Names below are the App's retained/obfuscated class names, not iOS classes.

| Method | Static result |
| --- | --- |
| `PhocusApplication.createDeviceId()` | Six random uppercase hexadecimal characters, prefixed with `00`; a generated App ID |
| `PhocusApplication.getDeviceId()` | Reads/writes MMKV key `key_preference_deviceid` |
| `LL3/b.a(Message)` notification-success branch | Parses DeviceId as hexadecimal and stores numeric ID plus 4-byte little-endian form in `Lx6/H.i/j` |
| `PhocusApplication.getLinkUUID()` | Returns `Lx6/H.i` |
| `LM6/a.a(...)` HTTP interceptor | Formats LinkUUID as decimal and adds `X-Phocus-Client-Id` |
| `BleConnectService.startConnectAndAuth()` | Requires BLE connection; invokes `Lf7/h` then `Lx6/H.k()` |
| `Lx6/H.k()` | Sends `Lz6/d(DeviceId)` authorization request and distinguishes already accepted / screen approval pending / rejection |
| `Lz6/d.a()` | UTF-8 length-prefixed DeviceId text and client-name text |
| `Lz6/d.j(reply)` | Payload `[0,1]` accepted; `[0,2]` waiting for on-camera approval; 3 refused, 4 busy, 5 failed, 6 conflict |
| `Lx6/G.invokeSuspend()` | Writes DUML packets to FFF0 service's FFF5 characteristic |
| Notification setup / UUID strings | FFF4 notification characteristic |
| `LB6/a.a()` case `u=3` | Falls through to V1 payload version=1, ID little-endian, inner sequence, type=UNKNOWN(0) |
| `LB6/a.h()` case `u=3` | UNKNOWN, no additional payload |
| `Lb5/c.a()` | Wi-Fi TCP socket `192.168.2.1:9003`; TCP write code adds its own framing. This TCP wire path is not implemented in the new BLE reuse tool. |

DUML authorization packet uses source `02`, destination `07`, flags `40`, cmdset `07`, command `45` hex (69 decimal). BLE V1 hello uses destination `D7`, flags `20`, cmdset `00`, command `FE` and the V1 payload above. CRC8 seed=77 hex, reflected polynomial=8C; CRC16 seed=3692 hex, reflected polynomial=8408. The App's LD6/a arrays independently expose CRC-table witness values 5E and 1189 for table index 1.

Native server corroboration: `V1Client::onV1MessageReceived` at `0x11BDB0` checks protocol version 1 and the authorized ID list. Accepted messages set the active client ID and connected state, before dispatching the inner Phocus message. `setConnected(false)` at `0x11DCA8` clears the active ID; the ping timeout is not an indefinitely reusable HTTP session.

## Reusing an observed iPhone ID

`collect_phocus_client_id.py` imports the real iPhone HTTP ID, not an assumed hardware identifier. A matching successful camera HAR response is recorded as historical evidence. Manual entry is explicitly marked unverified. The offline tool cannot create a live authorized session.

`collect_iphone_usb_id.py` uses the documented PyMobileDevice3 11.29.1 `PcapdService.watch()` USB network mirror. It examines only IPv4 TCP camera port 80, begins reassembly at observed SYNs, and matches the first GET `/v1/` to its response on the same connection. Duplicate/overlapping segments are checked; conflicted streams, fragments, missing SYNs and large prefixes are not accepted. Full captures, cookies and body data are not persisted. Only a successfully matched 2xx pair writes the identity files.

`x2d2_reuse_session.py` is a hardware-unverified candidate: it sends the observed numeric ID as eight uppercase hex characters in the App's authorization structure, then the native V1 hello; it keeps BLE connected during the HTTP operation and responds only to identified Phocus keepalive requests. If existing-ID reuse requires a camera-screen confirmation or is refused, it stops. The HTTP parameters preflight is mandatory before POST. It does not assume that iOS stores the same hexadecimal casing or that the camera ignores the original client's name/connection state. Live `probe` establishes or rejects these assumptions without uploading firmware.

This provides an experimental route to test the user's existing authorization. It does not establish that the current iPhone's session can be recreated on Windows or that the updater accepts reinstalling the same version. Native firmware checks remain intact.

Dependency API sources:
- https://github.com/doronz88/pymobiledevice3/blob/master/pymobiledevice3/services/pcapd.py
- https://doronz88.github.io/pymobiledevice3/installation/
- https://bleak.readthedocs.io/en/stable/api/client.html
- https://apps.apple.com/cn/app/stream/id1312141691


## User-reported physical-camera validation — 2026-10-14

The user operated a remote Windows computer, not the assistant's host. Their already-authorized iPhone provided a Phocus Mobile 4.5.0 (build 39) camera request header and corresponding HTTP 200 response. The numeric client ID was imported into the uploader configuration; the actual ID is omitted from this distributable record.

Observed evidence supplied in the conversation:

1. Windows `x2d2_wifi_upgrade.py probe --session session.json` returned `Session accepted by /v1/parameters. No firmware was uploaded.`
2. Upload of `X2DII_100C_v1_3_16_2(1).cim` reported all 364,814,336 bytes sent and `HTTP 204: start_requested`.
3. Result filename: `upload-result-20261014-151709-696527.json`. The file itself was not supplied/read; only the terminal output was provided.
4. The user reported the physical camera was updating, then confirmed success.

This validates the original HTTP upload/start path under the user's current active-session conditions. It does not validate the optional BLE recreation tool, USB capture tool, perpetual reuse of this ID after a fresh connection, or bypassing the updater's own checks. The earlier recovery thread obtained an ordinary USB version readback of `1.3.16.2`, matching this recovery package. The final version screen and per-module writes were not captured, so this record does not establish that every same-version module was rewritten. See [complete recovery case](CASE.md) for the prior persistent modifications and failed diagnostic rollback.

## 中文说明

本文件保留静态分析的输入哈希、ELF 虚拟地址、HTTP/BLE 结构及验证边界。原 HTTP 上传器后来在用户现场完成一次升级；USB 采集与独立 BLE 会话重建仍未实机验证。完整中文案例见 [案例记录](CASE.md)。
