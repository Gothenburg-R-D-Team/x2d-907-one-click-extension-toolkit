# X2D II recovery: executable Windows procedure

[中文步骤](RECOVERY.zh-CN.md) · [Case overview and principle](README.md)

This follows the October 14, 2026 owner-operated recovery, using an already-authorized
iPhone and Windows. The recorded package was official X2D II firmware **1.3.16.2**.
Other models, firmware versions, fresh-client authorization and hardware faults are
outside this case's validation. The camera decides whether a package is eligible.

## 1. Check the requirements

Continue only if all of these apply:

- The camera is **X2D II 100C**. This is not the first-generation X2D/CFV desktop installer.
- An iPhone previously authorized by this camera can still connect in Phocus and enable
  camera Wi-Fi. If the screen cannot approve a new phone, a new phone is not a substitute.
- You have a Windows computer with Wi-Fi, Python 3.9+ and stable camera battery power.
- You can obtain the complete, unchanged official CIM for this model. Back up accessible
  photos before proceeding; this case does not establish that every fault preserves photos.

If ordinary official update controls work and offer the needed update, use that workflow.
This case addresses a failed camera whose usable upload route remained available.

## 2. Download and prepare the scripts

Download the [toolkit source ZIP](https://github.com/Gothenburg-R-D-Team/x2d-907-one-click-extension-toolkit/archive/refs/heads/main.zip)
(GitHub **Code → Download ZIP**) and extract it completely. You do not need the Mac/Windows
desktop installer. In the extracted repository, open:

```text
src\tools\x2d2_wifi_firmware
```

In File Explorer's address bar for that folder, type `powershell` and press Enter.
The current directory must contain `x2d2_wifi_upgrade.py` and `collect_phocus_client_id.py`.

Check Python:

```powershell
py -3 --version
```

If it is missing or older than 3.9, install Python for Windows from
[python.org](https://www.python.org/downloads/windows/), including the launcher, and reopen
PowerShell in the same folder. The normal HTTP/manual-ID route uses only Python's standard
library: no pip packages, ADB, USB driver replacement or BLE library are required.

Alternatively, a maintainer can create a portable source ZIP with the
[packaging recipe](../../../src/tools/x2d2_wifi_firmware/README.md#portable-package).
For that ZIP, open PowerShell directly in its extracted `X2DII-WiFi-Upgrade` folder;
the script names and commands below are identical.

Download the complete original CIM from [Hasselblad Downloads](https://www.hasselblad.com/downloads/)
for **X2D II 100C**; the [firmware history](https://www.hasselblad.com/x-system/firmware/)
provides version context. Preserve the official filename and extension. The historical
example below is `X2DII_100C_v1_3_16_2(1).cim`; substitute your actual file path.
Do not assume that a newer package has been validated by this case.

## 3. Observe the authorized phone's real client ID

On the already-authorized iPhone:

1. Install [Stream by Stream Lab](https://apps.apple.com/cn/app/stream/id1312141691)
   and start capture. Allow its local VPN configuration if prompted. This step observes
   camera plaintext HTTP; no HTTPS root certificate is required.
2. Use Phocus to enable the camera hotspot and connect the phone to it. Open the camera
   information or album page to generate a read request; do not trigger an update here.
3. Find a request to **`192.168.2.1`, port 80**, with a path beginning **`/v1/`**.
   Select the camera request, not a cloud-service request.
4. Confirm that the matching response is **200 or another 2xx**. Copy the decimal number
   in its request header **`X-Phocus-Client-Id`**. Header names may appear in lowercase.

Use the actual observed number, not the phone UDID, serial number, MAC address or somebody
else's example. Do not post the ID, session JSON or full captures publicly. Stop capture
when finished and return the phone's VPN configuration to its previous state.

If no accepted camera request is visible, stop this route. An empty capture does not prove
the phone has no ID. The [advanced notes](ADVANCED.md) describe optional collection methods,
but USB mirroring and independent BLE session recreation were not used to validate this case.

## 4. Create the session file on Windows

In the script folder's PowerShell, run **this line alone**:

```powershell
$phocusClientId = Read-Host "Paste the actual X-Phocus-Client-Id"
```

At the prompt, paste **only the decimal number** and press Enter. Then run:

```powershell
py -3 .\collect_phocus_client_id.py --observed-id $phocusClientId
```

This creates `phone-client-id.json` and `session.json` in the current folder. Manual
entry records historical acceptance as unverified; the live check in the next step is
mandatory. Saving a number does not create an authorized session.

If your camera has a different local address, verify it from your own phone request and
add `--camera-host ACTUAL_IPV4` to the collector command; do not type `ACTUAL_IPV4` literally.

## 5. Connect Windows and check current authorization

Let Phocus enable camera Wi-Fi, then connect Windows to that hotspot. In this case the
phone and PC could not remain on camera Wi-Fi together. The owner disconnected the phone
from camera Wi-Fi while retaining its existing Bluetooth connection. Preserve whichever
connection state actually passes the probe; do not assume a copied ID stays authorized.
If operating remotely, retain a separate working internet connection for remote control.

Run:

```powershell
py -3 .\x2d2_wifi_upgrade.py probe --session .\session.json
```

Continue only after:

```text
Session accepted by /v1/parameters. No firmware was uploaded.
```

**401/403, timeout or an invalid response means stop before upload.** Check the original
phone connection, camera hotspot and observed ID. Do not substitute a random ID or repeat
firmware POST requests to diagnose authorization. Preserve the state that passed this check.

## 6. Inspect the local firmware, then upload once

First inspect the local file (replace the example path with its real location):

```powershell
py -3 .\x2d2_wifi_upgrade.py inspect "C:\Firmware\X2DII_100C_v1_3_16_2(1).cim"
```

This is offline: it checks the file extension, CIM header, size and computes hashes. It
does **not** authenticate the vendor signature, independently prove model/version
compatibility or upload anything. Select the correct official file yourself; the camera
retains its own eligibility checks.

After the required checks, stable power and accepted session, the following command
**uploads firmware and requests installation**:

```powershell
py -3 .\x2d2_wifi_upgrade.py upload "C:\Firmware\X2DII_100C_v1_3_16_2(1).cim" --session .\session.json --start-upgrade
```

The uploader repeats the read-only preflight immediately before POST. It sends the
complete raw CIM, size/SHA-1 and the installation request. It does not retry POST
automatically, follow redirects or bypass firmware checks.

The recorded successful transfer printed:

```text
Sent 364814336 / 364814336 bytes (100.0%)
Camera returned HTTP 204: start_requested.
Installation completion is NOT confirmed. Check the camera/App before another upload.
Result: upload-result-20261014-151709-696527.json
```

Your result filename will have a different timestamp. **100% is transfer progress;
HTTP 204/start_requested is acceptance of an asynchronous request. Neither proves
installation completion.** `uploaded` without `start_requested` means installation
was not requested by that command; do not mistake upload-only staging for recovery.

## 7. Observe completion and verify the camera

Keep camera power stable while it is updating; do not remove the battery. Follow the
camera/App's displayed update instructions. If the connection disappears, first check
the physical camera—it may already be installing. Do not resend merely because Wi-Fi drops.
This case does not establish a universal update duration.

After the camera finishes, check and record:

- Reported firmware version and normal live view/menu operation.
- A new capture is saved and can be opened in the camera album.
- Normal shutdown and the next normal startup.
- Wi-Fi/Phocus connection if it was previously affected.

These are the checks a new operator should perform; the historical record contains an
owner success report, not a supplied complete checklist. Save the upload result JSON
locally. Even a successful functional check does not prove all historical modifications
were removed or every same-version module was rewritten.

## Stop conditions and common errors

| Observation | Action |
| --- | --- |
| `py` not found | Install Python/launcher, reopen PowerShell and confirm its version. No camera upload occurred. |
| Script/file not found | Check the working folder, complete extraction and quoted actual CIM path. |
| Missing `VHABCIM` header or hash mismatch | Stop; obtain the complete, unchanged correct official package. |
| No authorized phone, no accepted GET, or probe rejected | This route's conditions are not met; do not upload. |
| HTTP rejection after upload | Preserve the exact response/result JSON; do not invent force flags or relabel the firmware. |
| `unknown`, interrupted upload, lost acknowledgement or exit code 3 | The camera may have received the request. Inspect camera/App and preserve records; do not automatically repeat. |
| HTTP 204/start_requested | Observe installation. Do not initiate another POST while it may be running. |
| Camera still fails after apparent installation | Preserve observations and records; this one case cannot diagnose hardware faults or guarantee another recovery. |

For help, open a [toolkit Issue](https://github.com/Gothenburg-R-D-Team/x2d-907-one-click-extension-toolkit/issues)
with the model, reported version, failed stage and redacted output. Remove real client IDs,
session files, captures and personal paths before public sharing.

[Full case](CASE.md) · [Validation](VALIDATION.md) · [All cases](../README.md)
