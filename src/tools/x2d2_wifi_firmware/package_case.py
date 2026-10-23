"""Build an allowlisted portable X2D II case source bundle; no camera access."""
import argparse
import hashlib
from pathlib import Path
import re
import zipfile


CASE = "docs/cases/2026-10-14-x2d-ii-wifi-firmware-recovery"
SOURCES = "src/tools/x2d2_wifi_firmware"
PUBLIC = "https://github.com/Gothenburg-R-D-Team/x2d-907-one-click-extension-toolkit/blob/main/"


def portable_links(data, source_path, root, included):
    """Keep bundled links local; make other repository references public URLs."""
    text = data.decode("utf-8")

    def replace(match):
        label, destination = match.groups()
        path, separator, anchor = destination.partition("#")
        if not path or re.match(r"[a-zA-Z][a-zA-Z0-9+.-]*:", path):
            return match.group(0)
        resolved = (root / source_path).parent.joinpath(path).resolve()
        relative = resolved.relative_to(root).as_posix()
        destination = included.get(relative, PUBLIC + relative)
        if separator:
            destination += "#" + anchor
        return "[" + label + "](" + destination + ")"

    return re.sub(r"\[([^\]\n]+)\]\(([^)\s]+)\)", replace, text).encode("utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = args.repo_root.resolve()
    files = {name: SOURCES + "/" + name for name in (
        "x2d2_wifi_upgrade.py", "collect_phocus_client_id.py",
        "collect_iphone_usb_id.py", "x2d2_reuse_session.py")}
    files.update({name: CASE + "/" + name for name in (
        "RECOVERY.en.md", "RECOVERY.zh-CN.md", "CASE.md", "ADVANCED.md",
        "PROTOCOL_EVIDENCE.md", "ORIGINAL_MANIFEST.json", "MIGRATION.json", "VALIDATION.md")})
    files["OVERVIEW.md"] = CASE + "/README.md"
    files["test_phone_id.py"] = "tests/x2d2_wifi_firmware/test_phone_id.py"
    files["check_http_simulation.py"] = SOURCES + "/validation/check_http_simulation.py"
    files["LICENSE.beta-original"] = SOURCES + "/LICENSE.beta-original"
    files["LICENSE.toolkit"] = "LICENSE"
    included = {path: name for name, path in files.items()}
    blobs = {}
    for name, source in files.items():
        data = (root / source).read_bytes()
        blobs[name] = portable_links(data, source, root, included) if name.endswith(".md") else data
    blobs["README.md"] = (
        "# X2D II Wi-Fi recovery case / 原厂固件恢复案例\n\n"
        "Start with [English instructions](RECOVERY.en.md) or [中文操作步骤](RECOVERY.zh-CN.md).\n\n"
        "Open PowerShell in this extracted folder. Python 3.9+; the normal HTTP/manual-ID "
        "route needs only the standard library. You must obtain the correct official CIM "
        "and observe your own already-authorized phone's actual client ID. "
        "No firmware, personal ID/session, capture or runtime is included.\n\n"
        "先完整解压，在本目录打开 PowerShell，按教程确认条件、采集真实 ID、probe、上传并检查机身。"
        "HTTP 204 不是安装完成；结果不明时不要重复上传。\n\n"
        "[Case overview](OVERVIEW.md) · [Full case](CASE.md) · [Validation](VALIDATION.md)\n\n"
        "Socket-free checks: `py -3 -m unittest -v test_phone_id.py`\n\n"
        "Optional localhost-only simulation: `py -3 check_http_simulation.py -v`\n\n"
        "Operational sources preserve LICENSE.beta-original; new instructions/packaging "
        "follow LICENSE.toolkit. SHA256SUMS covers every other bundled file.\n"
    ).encode("utf-8")
    blobs["SHA256SUMS"] = "".join(
        hashlib.sha256(data).hexdigest() + "  " + name + "\n"
        for name, data in sorted(blobs.items())
    ).encode("ascii")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("xb") as stream:
        with zipfile.ZipFile(stream, "w", zipfile.ZIP_DEFLATED) as archive:
            for name, data in sorted(blobs.items()):
                archive.writestr("X2DII-WiFi-Upgrade/" + name, data)
    print(hashlib.sha256(args.output.read_bytes()).hexdigest(), args.output.name)


if __name__ == "__main__":
    main()
