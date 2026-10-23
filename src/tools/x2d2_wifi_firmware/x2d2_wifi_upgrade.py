#!/usr/bin/env python3
"""X2D II HTTP CIM uploader, based on Phocus Mobile/server static analysis.

Python 3.9+, standard library only. An active, authorized Phocus session is
required. No pairing bypass, firmware modification, or automatic upload retry.
"""
import argparse
import dataclasses
import datetime
import hashlib
import http.client
import ipaddress
import json
import os
from pathlib import Path
import re
import sys
import tempfile
import time
from urllib.parse import quote, urlsplit

CHUNK = 256 * 1024
CLIENT_HEADER = "X-Phocus-Client-Id"
UPLOAD_HEADER = "X-Phocus-Upload-Info"
MAX_RESPONSE = 1024 * 1024


class ToolError(Exception):
    pass


class OutcomeUnknown(ToolError):
    """A POST may have reached the camera; do not automatically repeat it."""


def camera_address(value):
    try:
        addr = ipaddress.IPv4Address(value)
    except ipaddress.AddressValueError as exc:
        raise ToolError("Camera/bind address must be an IPv4 address.") from exc
    if not (addr.is_private or addr.is_loopback) or addr.is_unspecified or addr.is_multicast:
        raise ToolError("Use the camera's local IPv4 address, not a public/wildcard address.")
    return str(addr)


def client_id(value):
    if isinstance(value, bool) or not re.fullmatch(r"[0-9]+", str(value)):
        raise ToolError("Client ID must be a nonzero decimal uint32 from a valid App session.")
    number = int(value)
    if not 1 <= number <= 0xFFFFFFFF:
        raise ToolError("Client ID is outside the camera's uint32 range.")
    return number


def utc_now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                     prefix=path.name + ".", suffix=".tmp", delete=False) as stream:
        temporary = Path(stream.name)
        stream.write(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    try:
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def save_session(path, host, identifier, port=80, source="capture"):
    write_json(path, {"host": camera_address(host), "port": port,
                      "client_id": client_id(identifier), "captured_at": utc_now(),
                      "source": source,
                      "note": "Valid only while this authorized App session remains active."})


def load_session(path):
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        host = camera_address(data["host"])
        identifier = client_id(data["client_id"])
        port = int(data.get("port", 80))
        if not 1 <= port <= 65535:
            raise ToolError("Invalid camera port.")
        return host, port, identifier
    except (KeyError, ValueError, OSError) as exc:
        raise ToolError("Cannot read session JSON: " + str(exc)) from exc


def extract_ids(data):
    """HTTP text/complete headers in packet captures; also supports HAR JSON.

    This is not a TCP reassembler and cannot decrypt encrypted captures.
    """
    found = set()
    for match in re.finditer(rb"X-Phocus-Client-Id\s*:\s*([0-9]+)", data, re.I):
        found.add(client_id(match.group(1).decode("ascii")))
    try:
        obj = json.loads(data.decode("utf-8-sig"))
    except (UnicodeError, ValueError):
        return found

    def walk(value):
        if isinstance(value, dict):
            if str(value.get("name", "")).lower() == CLIENT_HEADER.lower():
                found.add(client_id(value.get("value", "")))
            for item in value.values():
                walk(item)
        elif isinstance(value, list):
            for item in value:
                walk(item)
    walk(obj)
    return found


@dataclasses.dataclass(frozen=True)
class Firmware:
    filename: str
    size: int
    sha1: str
    sha256: str
    fingerprint: tuple


def fingerprint(stream):
    stat = os.fstat(stream.fileno())
    return (stat.st_dev, stat.st_ino, stat.st_size, stat.st_mtime_ns)


def inspect_firmware(stream, filename):
    if Path(filename).suffix.lower() != ".cim":
        raise ToolError("Select the complete official .cim firmware package.")
    before = fingerprint(stream)
    if not 128 <= before[2] <= 0x7FFFFFFF:
        raise ToolError("CIM size is invalid or exceeds the server's signed 32-bit size field.")
    stream.seek(0)
    if stream.read(9) != b"VHABCIM\r\n":
        raise ToolError("Missing the VHABCIM header; this is not a complete CIM package.")
    stream.seek(0)
    sha1, sha256 = hashlib.sha1(), hashlib.sha256()
    while True:
        block = stream.read(CHUNK)
        if not block:
            break
        sha1.update(block)
        sha256.update(block)
    if fingerprint(stream) != before:
        raise ToolError("Firmware changed during hashing; nothing was uploaded.")
    stream.seek(0)
    return Firmware(Path(filename).name, before[2], sha1.hexdigest(), sha256.hexdigest(), before)


def upload_info(firmware, start):
    # These three fields are consumed by Httpd::upgradeCim in X2D II 1.3.16.2.
    # model/version/count/index are accepted optional tags, not required here.
    return {"size": firmware.size, "sha1": firmware.sha1, "start_upgrade": bool(start)}


def upload_path(firmware):
    return "/v1/upgrade/" + quote(firmware.filename, safe="")


def read_response(response):
    data = response.read(MAX_RESPONSE + 1)
    if len(data) > MAX_RESPONSE:
        raise ToolError("Camera response exceeds the expected control-response size.")
    return data.decode("utf-8", errors="replace")


def probe(host, port, identifier, timeout=15):
    connection = http.client.HTTPConnection(host, port, timeout=timeout)
    try:
        connection.request("GET", "/v1/parameters", headers={CLIENT_HEADER: str(identifier),
                            "Connection": "close"})
        response = connection.getresponse()
        body = read_response(response)
        if response.status != 200:
            raise ToolError("Session probe rejected: HTTP %s %s. %s" %
                            (response.status, response.reason, body[:2000]))
        # A real JSON response separates the Phocus API from an unrelated web server.
        try:
            parameters = json.loads(body)
        except ValueError as exc:
            raise ToolError("The parameters endpoint did not return JSON; no upload attempted.") from exc
        if not isinstance(parameters, (dict, list)):
            raise ToolError("Unexpected parameters response; no upload attempted.")
        return parameters
    finally:
        connection.close()


def upload(stream, firmware, host, port, identifier, start=False, timeout=180, progress=None):
    # Preflight is a read-only GET. A failed/expired session never gets a POST.
    probe(host, port, identifier, min(timeout, 15))
    if fingerprint(stream) != firmware.fingerprint:
        raise ToolError("Firmware changed since hashing; no upload attempted.")
    headers = {CLIENT_HEADER: str(identifier),
               UPLOAD_HEADER: json.dumps(upload_info(firmware, start), separators=(",", ":")),
               "Content-Type": "application/octet-stream",
               "Content-Length": str(firmware.size), "Connection": "close"}
    connection = http.client.HTTPConnection(host, port, timeout=timeout)
    posted = False
    try:
        connection.connect()
        posted = True
        connection.putrequest("POST", upload_path(firmware))
        for name, value in headers.items():
            connection.putheader(name, value)
        connection.endheaders()
        stream.seek(0)
        sent = 0
        digest = hashlib.sha1()
        while sent < firmware.size:
            block = stream.read(min(CHUNK, firmware.size - sent))
            if not block:
                raise OutcomeUnknown("Firmware became shorter during transmission.")
            connection.send(block)
            digest.update(block)
            sent += len(block)
            if progress:
                progress(sent, firmware.size)
        if fingerprint(stream) != firmware.fingerprint or digest.hexdigest() != firmware.sha1:
            raise OutcomeUnknown("Firmware changed during transmission; check the camera before continuing.")
        response = connection.getresponse()
        body = read_response(response)
        if response.status == 204:
            return {"state": "start_requested" if start else "uploaded",
                    "http_status": 204, "response": body,
                    "installation_completed": False}
        if 200 <= response.status < 300 or 300 <= response.status < 400:
            raise OutcomeUnknown("Unexpected HTTP %d after upload. Inspect the camera; do not repeat automatically." % response.status)
        raise ToolError("Camera rejected the request: HTTP %d %s. %s" %
                        (response.status, response.reason, body[:4000]))
    except OutcomeUnknown:
        raise
    except (OSError, http.client.HTTPException, ToolError) as exc:
        if posted and not isinstance(exc, ToolError):
            raise OutcomeUnknown("Connection interrupted after POST began. The camera may have received the firmware/start request. " + str(exc)) from exc
        if posted and isinstance(exc, ToolError) and str(exc).startswith("Camera rejected"):
            raise
        if posted:
            raise OutcomeUnknown(str(exc)) from exc
        raise ToolError(str(exc)) from exc
    finally:
        connection.close()


def capture_proxy(bind, listen_port, host, camera_port, session_path):
    """Optional read-only HTTP proxy to observe an authorized App's client ID.

    Only works if the App honors the iPhone Wi-Fi HTTP-proxy setting. No TLS,
    CONNECT, arbitrary forwarding, or firmware/deletion requests are supported.
    """
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
    host, bind = camera_address(host), camera_address(bind)

    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.0"

        def log_message(self, format, *args):
            pass

        def do_GET(self):
            target = urlsplit(self.path)
            if target.scheme not in ("", "http") or (target.hostname and target.hostname != host):
                self.send_error(403, "Only the configured camera is allowed")
                return
            try:
                requested_port = target.port or 80
            except ValueError:
                self.send_error(403, "Invalid camera port")
                return
            if target.netloc and requested_port != camera_port:
                self.send_error(403, "Camera port mismatch")
                return
            if not target.path.startswith("/v1/") or target.path.startswith(("/v1/upgrade", "/v1/delete", "/v1/userdata/delete")):
                self.send_error(403, "Only read-only Phocus API requests are forwarded")
                return
            path = target.path + ("?" + target.query if target.query else "")
            connection = http.client.HTTPConnection(host, camera_port, timeout=20)
            try:
                excluded = {"host", "connection", "proxy-connection", "proxy-authorization",
                            "transfer-encoding", "content-length"}
                headers = {k: v for k, v in self.headers.items() if k.lower() not in excluded}
                headers["Connection"] = "close"
                connection.request("GET", path, headers=headers)
                response = connection.getresponse()
                identifier = self.headers.get(CLIENT_HEADER)
                if identifier and 200 <= response.status < 300:
                    save_session(session_path, host, identifier, camera_port, "authorized App GET observed through local proxy")
                    print("Saved an accepted App session to " + str(session_path), flush=True)
                self.send_response(response.status, response.reason)
                for name, value in response.getheaders():
                    if name.lower() not in {"transfer-encoding", "connection"}:
                        self.send_header(name, value)
                self.send_header("Connection", "close")
                self.end_headers()
                while True:
                    block = response.read(CHUNK)
                    if not block:
                        break
                    self.wfile.write(block)
            except (OSError, http.client.HTTPException, ToolError) as exc:
                print("Capture/forward error: " + str(exc), file=sys.stderr, flush=True)
                self.close_connection = True
            finally:
                connection.close()

        def reject_write(self):
            self.send_error(405, "Capture mode forwards GET only")
        do_POST = do_PUT = do_DELETE = do_PATCH = do_CONNECT = reject_write

    server = ThreadingHTTPServer((bind, listen_port), Handler)
    print("Read-only capture proxy listening on %s:%d; camera %s:%d" %
          (bind, server.server_address[1], host, camera_port), flush=True)
    print("If the App bypasses the system proxy, use import-session with an HTTP/HAR capture instead.", flush=True)
    try:
        server.serve_forever()
    finally:
        server.server_close()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("inspect", "upload"):
        item = sub.add_parser(name)
        item.add_argument("firmware", type=Path)
        item.add_argument("--start-upgrade", action="store_true", help="Upload with start_upgrade=true; this requests installation")
        item.add_argument("--expected-sha256", help="Optional trusted SHA256 for the exact official package")
        if name == "upload":
            item.add_argument("--session", type=Path, required=True)
            item.add_argument("--timeout", type=float, default=180)
            item.add_argument("--result", type=Path)
    item = sub.add_parser("probe")
    item.add_argument("--session", type=Path, required=True)
    item = sub.add_parser("import-session")
    item.add_argument("capture", type=Path, help="HTTP header text, HAR, or packet capture containing complete plaintext headers")
    item.add_argument("--camera-host", default="192.168.2.1")
    item.add_argument("--output", type=Path, default=Path("session.json"))
    item.add_argument("--client-id", help="Select a specific observed ID if capture includes several")
    item = sub.add_parser("capture-session")
    item.add_argument("--bind", required=True, help="Windows computer's IPv4 on the camera Wi-Fi network")
    item.add_argument("--listen-port", type=int, default=8888)
    item.add_argument("--camera-host", default="192.168.2.1")
    item.add_argument("--camera-port", type=int, default=80)
    item.add_argument("--output", type=Path, default=Path("session.json"))
    args = parser.parse_args(argv)
    try:
        if args.command == "capture-session":
            capture_proxy(args.bind, args.listen_port, args.camera_host, args.camera_port, args.output)
        elif args.command == "import-session":
            found = extract_ids(args.capture.read_bytes())
            identifier = client_id(args.client_id) if args.client_id else next(iter(found)) if len(found) == 1 else None
            if identifier is None or identifier not in found:
                raise ToolError("Need exactly one observed client ID, or --client-id selecting an ID in this capture. Found: " + str(sorted(found)))
            save_session(args.output, args.camera_host, identifier, source="imported local HTTP capture; validate with probe")
            print("Saved session to " + str(args.output))
        elif args.command == "probe":
            host, port, identifier = load_session(args.session)
            probe(host, port, identifier)
            print("Session accepted by /v1/parameters. No firmware was uploaded.")
        else:
            with args.firmware.open("rb") as stream:
                firmware = inspect_firmware(stream, args.firmware.name)
                if args.expected_sha256 and firmware.sha256.lower() != args.expected_sha256.lower():
                    raise ToolError("Firmware SHA256 does not match the supplied trusted hash.")
                plan = {"firmware": dataclasses.asdict(firmware), "path": upload_path(firmware),
                        "method": "POST", "upload_info": upload_info(firmware, args.start_upgrade)}
                del plan["firmware"]["fingerprint"]
                if args.command == "inspect":
                    print(json.dumps(plan, indent=2, ensure_ascii=False))
                    return 0
                if args.timeout <= 0:
                    raise ToolError("Timeout must be positive.")
                host, port, identifier = load_session(args.session)
                stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
                result_path = args.result or Path("upload-result-" + stamp + ".json")
                result = {"started_at": utc_now(), "host": host, "plan": plan,
                          "state": "not_started", "installation_completed": False}
                write_json(result_path, result)
                last_print = [0.0]
                def progress(sent, total):
                    now = time.monotonic()
                    if sent == total or now-last_print[0] >= 1:
                        print("Sent %d / %d bytes (%.1f%%)" % (sent, total, sent*100/total), flush=True)
                        last_print[0] = now
                try:
                    result.update(upload(stream, firmware, host, port, identifier,
                                         args.start_upgrade, args.timeout, progress))
                except KeyboardInterrupt:
                    result.update(state="unknown", error="Interrupted by operator; inspect camera before repeating.")
                    raise
                except (ToolError, OSError, http.client.HTTPException) as exc:
                    result.update(state="unknown" if isinstance(exc, OutcomeUnknown) else "failed", error=str(exc))
                    raise
                finally:
                    result["finished_at"] = utc_now()
                    write_json(result_path, result)
                print("Camera returned HTTP 204: " + result["state"] + ".")
                print("Installation completion is NOT confirmed. Check the camera/App before another upload.")
                print("Result: " + str(result_path))
        return 0
    except KeyboardInterrupt:
        print("Stopped. If interrupted during upload, its outcome may be unknown; inspect the camera before repeating.", file=sys.stderr)
        return 3
    except (ToolError, OSError, http.client.HTTPException) as exc:
        print(str(exc), file=sys.stderr)
        return 3 if isinstance(exc, OutcomeUnknown) else 2


if __name__ == "__main__":
    raise SystemExit(main())
