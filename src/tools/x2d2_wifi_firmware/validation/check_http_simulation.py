import contextlib
import hashlib
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
import json
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

import x2d2_wifi_upgrade as tool


@contextlib.contextmanager
def camera(status=200, post_status=204, drop=False):
    state = {"posts": [], "gets": 0}
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass
        def do_GET(self):
            state["gets"] += 1
            body = b'{"camera_model":"X2D II 100C"}'
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        def do_POST(self):
            body = self.rfile.read(int(self.headers["Content-Length"]))
            state["posts"].append((self.path, dict(self.headers), body))
            if drop:
                self.close_connection = True
                self.connection.shutdown(socket.SHUT_RDWR)
                return
            self.send_response(post_status)
            self.send_header("Content-Length", "0")
            self.end_headers()
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield server.server_address[1], state
    finally:
        server.shutdown()
        server.server_close()
        thread.join(2)


class UploadTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.file = Path(self.temp.name) / "X2DII_100C_v1_3_16_2(1).cim"
        self.body = b"VHABCIM\r\n" + bytes(range(256)) * 3000
        self.file.write_bytes(self.body)

    def test_exact_raw_post_and_start_flag(self):
        with self.file.open("rb") as stream, camera() as (port, state):
            fw = tool.inspect_firmware(stream, self.file.name)
            result = tool.upload(stream, fw, "127.0.0.1", port, 123456, start=True)
        self.assertEqual(len(state["posts"]), 1)
        path, headers, body = state["posts"][0]
        self.assertEqual(path, "/v1/upgrade/X2DII_100C_v1_3_16_2%281%29.cim")
        self.assertEqual(body, self.body)
        info = json.loads(headers[tool.UPLOAD_HEADER])
        self.assertIs(info["start_upgrade"], True)
        self.assertEqual(info["sha1"], hashlib.sha1(body).hexdigest())
        self.assertEqual(info["size"], len(body))
        self.assertEqual(headers["Content-Length"], str(len(body)))
        self.assertEqual(result["state"], "start_requested")
        self.assertFalse(result["installation_completed"])

    def test_upload_only_does_not_request_installation(self):
        with self.file.open("rb") as stream, camera() as (port, state):
            fw = tool.inspect_firmware(stream, self.file.name)
            result = tool.upload(stream, fw, "127.0.0.1", port, 123, start=False)
        self.assertIs(json.loads(state["posts"][0][1][tool.UPLOAD_HEADER])["start_upgrade"], False)
        self.assertEqual(result["state"], "uploaded")

    def test_expired_session_never_sends_post(self):
        with self.file.open("rb") as stream, camera(status=403) as (port, state):
            fw = tool.inspect_firmware(stream, self.file.name)
            with self.assertRaises(tool.ToolError):
                tool.upload(stream, fw, "127.0.0.1", port, 123, start=True)
        self.assertEqual(state["posts"], [])

    def test_lost_ack_is_unknown_and_no_automatic_retry(self):
        with self.file.open("rb") as stream, camera(drop=True) as (port, state):
            fw = tool.inspect_firmware(stream, self.file.name)
            with self.assertRaises(tool.OutcomeUnknown):
                tool.upload(stream, fw, "127.0.0.1", port, 123, start=True)
        self.assertEqual(len(state["posts"]), 1)

    def test_redirect_after_post_is_not_followed(self):
        with self.file.open("rb") as stream, camera(post_status=302) as (port, state):
            fw = tool.inspect_firmware(stream, self.file.name)
            with self.assertRaises(tool.OutcomeUnknown):
                tool.upload(stream, fw, "127.0.0.1", port, 123, start=True)
        self.assertEqual(len(state["posts"]), 1)

    def test_server_rejection_is_preserved(self):
        with self.file.open("rb") as stream, camera(post_status=409) as (port, state):
            fw = tool.inspect_firmware(stream, self.file.name)
            with self.assertRaisesRegex(tool.ToolError, "HTTP 409"):
                tool.upload(stream, fw, "127.0.0.1", port, 123, start=True)
        self.assertEqual(len(state["posts"]), 1)

    def test_file_change_before_upload_stops_before_post(self):
        with self.file.open("rb") as stream, camera() as (port, state):
            fw = tool.inspect_firmware(stream, self.file.name)
            self.file.write_bytes(self.body + b"changed")
            with self.assertRaisesRegex(tool.ToolError, "changed"):
                tool.upload(stream, fw, "127.0.0.1", port, 123)
        self.assertEqual(state["posts"], [])

    def test_inspect_is_offline_and_validates_magic(self):
        with patch.object(tool.http.client, "HTTPConnection", side_effect=AssertionError("network")):
            with contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(tool.main(["inspect", str(self.file)]), 0)
            self.assertEqual(json.loads(output.getvalue())["upload_info"]["sha1"], hashlib.sha1(self.body).hexdigest())
        self.file.write_bytes(b"not a CIM" * 100)
        with self.file.open("rb") as stream:
            with self.assertRaises(tool.ToolError):
                tool.inspect_firmware(stream, self.file.name)

    def test_session_import_handles_text_and_har(self):
        self.assertEqual(tool.extract_ids(b"x-phocus-client-id: 12345\r\n"), {12345})
        har = {"log": {"entries": [{"request": {"headers": [{"name": "X-Phocus-Client-Id", "value": "12345"}]}}]}}
        self.assertEqual(tool.extract_ids(json.dumps(har).encode()), {12345})
        for value in (0, -1, 2**32, True, "123\r\nInjected: x"):
            with self.assertRaises(tool.ToolError):
                tool.client_id(value)

    def test_capture_proxy_observes_get_and_blocks_writes(self):
        session = Path(self.temp.name) / "session.json"
        with camera() as (port, state):
            process = subprocess.Popen([sys.executable, str(Path(tool.__file__)), "capture-session",
                "--bind", "127.0.0.1", "--listen-port", "0", "--camera-host", "127.0.0.1",
                "--camera-port", str(port), "--output", str(session)],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                line = process.stdout.readline()
                proxy_port = int(line.split("127.0.0.1:")[1].split(";")[0])
                proxy = http.client.HTTPConnection("127.0.0.1", proxy_port, timeout=3)
                proxy.request("GET", "http://127.0.0.1:%d/v1/parameters" % port,
                              headers={tool.CLIENT_HEADER: "67890"})
                response = proxy.getresponse()
                self.assertEqual(response.status, 200)
                response.read()
                proxy.close()
                self.assertEqual(tool.load_session(session), ("127.0.0.1", port, 67890))
                proxy = http.client.HTTPConnection("127.0.0.1", proxy_port, timeout=3)
                proxy.request("POST", "http://127.0.0.1:%d/v1/upgrade/a.cim" % port, body=b"bad")
                response = proxy.getresponse()
                self.assertEqual(response.status, 405)
                response.read()
                proxy.close()
                self.assertEqual(state["posts"], [])
                proxy = http.client.HTTPConnection("127.0.0.1", proxy_port, timeout=3)
                proxy.request("GET", "http://example.com/v1/parameters")
                response = proxy.getresponse()
                self.assertEqual(response.status, 403)
                response.read()
                proxy.close()
            finally:
                process.terminate()
                process.communicate(timeout=5)


if __name__ == "__main__":
    unittest.main()
