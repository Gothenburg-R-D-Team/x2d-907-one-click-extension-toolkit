#!/usr/bin/env python3
"""Experimental Phocus BLE session using an already observed phone client ID.

Protocol recovered from the official Android app and X2D II server. Physical
hardware acceptance, especially iOS identity reuse, has not been verified.
Requires Python 3.10+ and bleak for BLE operations; does not invent a new device ID.
"""
import argparse
import asyncio
import contextlib
import dataclasses
import datetime
import http.client
import json
from pathlib import Path
import struct
import sys
import threading
import time

import x2d2_wifi_upgrade as http_tool

SERVICE = '0000fff0-0000-1000-8000-00805f9b34fb'
NOTIFY = '0000fff4-0000-1000-8000-00805f9b34fb'
WRITE = '0000fff5-0000-1000-8000-00805f9b34fb'
MOBILE, NETWORK, PHOCUS = 0x02, 0x07, 0xD7


def crc8(data, value=0x77):
    for byte in data:
        value ^= byte
        for _ in range(8):
            value = (value >> 1) ^ (0x8C if value & 1 else 0)
    return value


def crc16(data, value=0x3692):
    for byte in data:
        value ^= byte
        for _ in range(8):
            value = (value >> 1) ^ (0x8408 if value & 1 else 0)
    return value


def packet(sender, receiver, sequence, flags, group, command, payload=b''):
    length = 13 + len(payload)
    if not 13 <= length <= 1023 or not 0 <= sequence <= 65535:
        raise http_tool.ToolError('Invalid BLE packet length/sequence.')
    header = b'\x55' + struct.pack('<H', length | 0x400)
    body = header + bytes([crc8(header), sender, receiver])
    body += struct.pack('<HBBB', sequence, flags, group, command) + payload
    return body + struct.pack('<H', crc16(body))


@dataclasses.dataclass(frozen=True)
class Frame:
    sender: int
    receiver: int
    sequence: int
    flags: int
    group: int
    command: int
    payload: bytes


class Decoder:
    def __init__(self):
        self.buffer = bytearray()

    def feed(self, data):
        self.buffer.extend(data)
        frames = []
        while len(self.buffer) >= 4:
            if self.buffer[0] != 0x55 or crc8(self.buffer[:3]) != self.buffer[3]:
                del self.buffer[0]
                continue
            word = struct.unpack_from('<H', self.buffer, 1)[0]
            length, version = word & 1023, word >> 10
            if version != 1 or length < 13:
                del self.buffer[0]
                continue
            if len(self.buffer) < length:
                break
            raw = bytes(self.buffer[:length])
            if crc16(raw[:-2]) != struct.unpack_from('<H', raw, length - 2)[0]:
                del self.buffer[0]
                continue
            del self.buffer[:length]
            seq, flags, group, cmd = struct.unpack_from('<HBBB', raw, 6)
            frames.append(Frame(raw[4], raw[5], seq, flags, group, cmd, raw[11:-2]))
        return frames


class BleSession:
    def __init__(self, client, identifier, name='Windows'):
        self.client = client
        self.identifier = http_tool.client_id(identifier)
        self.name = name.encode('utf-8')
        if not 1 <= len(self.name) <= 64:
            raise http_tool.ToolError('Client label must be 1..64 UTF-8 bytes.')
        self.decoder = Decoder()
        self.pending = {}
        self.sequence = 0
        self.lock = asyncio.Lock()
        self.tasks = set()
        self.background_error = None
        self.stopped = threading.Event()
        self.write_char = None

    def spawn(self, coro):
        task = asyncio.create_task(coro)
        self.tasks.add(task)
        def done(t):
            self.tasks.discard(t)
            if not t.cancelled() and t.exception() is not None:
                self.background_error = t.exception()
                self.stopped.set()
        task.add_done_callback(done)

    def notification(self, _sender, data):
        for frame in self.decoder.feed(data):
            key = (frame.sequence, frame.group, frame.command)
            pending = self.pending.get(key)
            if frame.flags & 0x80:
                if pending is not None:
                    expected_sender, future = pending
                    if frame.receiver == MOBILE and frame.sender == expected_sender and not future.done():
                        future.set_result(frame)
                continue
            # Native PhocusPingMessage sends cmdset=0/cmd=0. Ack only this
            # keepalive request. Never acknowledge an authorization decision.
            if (frame.receiver == MOBILE and frame.group == 0 and frame.command == 0
                    and frame.sender == PHOCUS and frame.flags & 0x60):
                self.spawn(self.send(packet(MOBILE, frame.sender, frame.sequence,
                                            0x80, frame.group, frame.command)))

    async def open(self):
        self.write_char = self.client.services.get_characteristic(WRITE)
        notify = self.client.services.get_characteristic(NOTIFY)
        if (self.write_char is None or notify is None
                or str(self.write_char.service_uuid).lower() != SERVICE
                or str(notify.service_uuid).lower() != SERVICE):
            raise http_tool.ToolError('Expected Phocus FFF0/FFF4/FFF5 BLE service is missing.')
        await self.client.start_notify(notify, self.notification)

    async def send(self, raw):
        if self.stopped.is_set() or not self.client.is_connected:
            raise http_tool.ToolError('BLE session disconnected/stopped.')
        props = self.write_char.properties
        if 'write-without-response' in props:
            response = False
            size = min(20, self.write_char.max_write_without_response_size)
        elif 'write' in props:
            response, size = True, 20
        else:
            raise http_tool.ToolError('Phocus BLE characteristic is not writable.')
        if size <= 0:
            raise http_tool.ToolError('Invalid BLE write size.')
        async with self.lock:
            for offset in range(0, len(raw), size):
                await self.client.write_gatt_char(self.write_char, raw[offset:offset+size], response=response)
                await asyncio.sleep(0.01)

    async def request(self, receiver, group, command, payload, flags, timeout):
        self.sequence = self.sequence % 65535 + 1
        key = self.sequence, group, command
        future = asyncio.get_running_loop().create_future()
        self.pending[key] = receiver, future
        try:
            await self.send(packet(MOBILE, receiver, self.sequence, flags, group, command, payload))
            return await asyncio.wait_for(future, timeout)
        finally:
            self.pending.pop(key, None)

    async def establish(self, timeout=20):
        # Android DeviceId is an 8-character hex string. The iOS ID's exact
        # stored text/case is unverified; this reuse candidate is tested live.
        device_id = format(self.identifier, '08X').encode('ascii')
        body = bytes([len(device_id)]) + device_id + bytes([len(self.name)]) + self.name
        reply = await self.request(NETWORK, 7, 69, body, 0x40, timeout)
        if len(reply.payload) < 2 or reply.payload[0] != 0:
            raise http_tool.ToolError('Camera did not accept the existing-ID authorization request.')
        status = reply.payload[1]
        if status == 2:
            raise http_tool.ToolError('Camera requests authorization on its screen. Existing ID reuse was not accepted; no firmware sent.')
        if status != 1:
            labels = {3: 'refused', 4: 'busy', 5: 'not accepted', 6: 'device conflict'}
            raise http_tool.ToolError('Existing-ID authorization failed: ' + labels.get(status, str(status)))
        # Exact App startup case LB6/a(u=3): version + ID_LE + inner seq +
        # UNKNOWN(0), no parameter body. The camera's V1 handler registers
        # this whitelisted ID before dispatch. HTTP probe remains mandatory.
        hello = b'\x01' + struct.pack('<IH', self.identifier, 0) + b'\x00'
        reply = await self.request(PHOCUS, 0, 254, hello, 0x20, timeout)
        if reply.payload and reply.payload[0] != 0:
            raise http_tool.ToolError('Camera rejected the V1 session hello. No firmware sent.')

    async def close(self):
        self.stopped.set()
        for task in list(self.tasks):
            task.cancel()
        if self.tasks:
            await asyncio.gather(*self.tasks, return_exceptions=True)
        for _, future in self.pending.values():
            if not future.done():
                future.cancel()
        if self.client.is_connected:
            with contextlib.suppress(Exception):
                await self.client.stop_notify(NOTIFY)


def load_identity(path):
    obj = json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(obj, dict):
        raise http_tool.ToolError('Identity JSON must be an object.')
    identifier = http_tool.client_id(obj['client_id'])
    host = http_tool.camera_address(obj.get('host', '192.168.2.1'))
    return host, identifier


def bleak_api():
    if sys.version_info < (3, 10):
        raise http_tool.ToolError('The BLE reuse test needs Python 3.10 or later; the offline ID collector supports Python 3.9.')
    try:
        from bleak import BleakClient, BleakScanner
        return BleakClient, BleakScanner
    except ImportError as exc:
        raise http_tool.ToolError('Install the BLE dependency on Windows: py -3 -m pip install bleak==3.0.1') from exc


async def run(a, result):
    client_type, scanner_type = bleak_api()
    if a.command == 'scan':
        devices = await scanner_type.discover(timeout=a.timeout, return_adv=True)
        candidates = []
        for device, advertisement in devices.values():
            if (SERVICE in [s.lower() for s in advertisement.service_uuids]
                    or any(k in (device.name or '').lower() for k in ['hasselblad', 'x2d'])):
                candidates.append({'address': device.address, 'name': device.name})
        print(json.dumps(candidates, ensure_ascii=False, indent=2))
        return
    host, identifier = load_identity(a.identity)
    result.update(host=host, client_id=identifier, state='connecting')
    device = await scanner_type.find_device_by_address(a.ble_address, timeout=a.timeout)
    if device is None:
        raise http_tool.ToolError('Specified camera BLE address is not advertising. Close the phone App/Bluetooth connection and scan again.')
    session = None
    def disconnected(_client):
        if session is not None:
            session.stopped.set()
    async with client_type(device, timeout=a.timeout, pair=False, disconnected_callback=disconnected) as client:
        session = BleSession(client, identifier, a.client_name)
        try:
            await session.open()
            await session.establish(a.timeout)
            result['state'] = 'ble_authorized'
            await asyncio.to_thread(http_tool.probe, host, 80, identifier, min(a.timeout, 15))
            result['state'] = 'session_accepted'
            print('Camera accepted the reused ID in BLE and HTTP /v1/parameters.', flush=True)
            if a.command == 'probe':
                print('No firmware uploaded. The BLE connection closes when this command exits.')
                return
            stamp = [0.0]
            def progress(sent, total):
                if session.stopped.is_set():
                    raise http_tool.OutcomeUnknown('BLE lost or operator stopped during upload. Check the camera before repeating.')
                now = time.monotonic()
                if sent == total or now - stamp[0] >= 1:
                    print('Sent %d / %d bytes (%.1f%%)' % (sent, total, sent*100/total), flush=True)
                    stamp[0] = now
            def worker():
                # The same worker hashes and uploads; file identity checks in
                # the HTTP uploader still apply. It always re-probes before POST.
                with a.firmware.open('rb') as stream:
                    firmware = http_tool.inspect_firmware(stream, a.firmware.name)
                    if a.expected_sha256 and firmware.sha256.lower() != a.expected_sha256.lower():
                        raise http_tool.ToolError('Firmware SHA256 does not match.')
                    result['firmware'] = {k:v for k,v in dataclasses.asdict(firmware).items() if k != 'fingerprint'}
                    if session.stopped.is_set():
                        raise http_tool.ToolError('BLE stopped before upload; no POST sent.')
                    return http_tool.upload(stream, firmware, host, 80, identifier,
                                            a.start_upgrade, a.http_timeout, progress)
            task = asyncio.create_task(asyncio.to_thread(worker))
            try:
                result.update(await asyncio.shield(task))
            except asyncio.CancelledError:
                session.stopped.set()
                # The worker checks this flag after each chunk. Await its exit
                # before closing BLE so an orphan worker cannot keep uploading.
                with contextlib.suppress(Exception):
                    await asyncio.shield(task)
                result.update(state='unknown', error='Stopped by operator during upload.')
                raise
            print('Camera returned HTTP 204: ' + result['state'] + '. Installation completion is not confirmed.')
        finally:
            await session.close()


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest='command', required=True)
    scan = sub.add_parser('scan')
    scan.add_argument('--timeout', type=float, default=8)
    for name in ['probe', 'upload']:
        item = sub.add_parser(name)
        item.add_argument('--identity', type=Path, required=True)
        item.add_argument('--ble-address', required=True, help='Camera BLE address returned by scan')
        item.add_argument('--client-name', default='Windows')
        item.add_argument('--timeout', type=float, default=20)
        item.add_argument('--result', type=Path)
        if name == 'upload':
            item.add_argument('firmware', type=Path)
            item.add_argument('--start-upgrade', action='store_true')
            item.add_argument('--expected-sha256')
            item.add_argument('--http-timeout', type=float, default=180)
    a = p.parse_args(argv)
    result = {'started_at': http_tool.utc_now(), 'state': 'not_started', 'installation_completed': False}
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    output = getattr(a, 'result', None) or Path('reuse-result-' + stamp + '.json')
    try:
        if not 0 < a.timeout <= 60 or (a.command == 'upload' and a.http_timeout <= 0):
            raise http_tool.ToolError('Invalid timeout.')
        asyncio.run(run(a, result))
        return 0
    except KeyboardInterrupt:
        result.update(state='unknown' if a.command == 'upload' else 'stopped', error='Stopped by operator.')
        print('Stopped. Inspect the camera before repeating an interrupted upload.', file=sys.stderr)
        return 3 if a.command == 'upload' else 2
    except Exception as exc:
        result.update(state='unknown' if isinstance(exc, http_tool.OutcomeUnknown) else 'failed', error=str(exc))
        print(str(exc), file=sys.stderr)
        return 3 if isinstance(exc, http_tool.OutcomeUnknown) else 2
    finally:
        if a.command != 'scan':
            result['finished_at'] = http_tool.utc_now()
            http_tool.write_json(output, result)
            print('Result: ' + str(output))


if __name__ == '__main__':
    raise SystemExit(main())
