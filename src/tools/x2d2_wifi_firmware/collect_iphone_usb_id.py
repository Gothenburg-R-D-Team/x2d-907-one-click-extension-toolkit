#!/usr/bin/env python3
"""Collect a camera-accepted Phocus client ID from iPhone USB network mirroring.

Windows requires Apple Mobile Device Support and pymobiledevice3==11.29.1.
The phone uses camera Wi-Fi; the PC does not need to join it during collection.
Only the ID and successful camera GET metadata are saved, never a full capture.
"""
import argparse
import asyncio
import collections
import ipaddress
from pathlib import Path
import re
import struct
import sys
import time

from collect_phocus_client_id import save_identity
from x2d2_wifi_upgrade import ToolError, camera_address, client_id, utc_now

LIMIT = 64 * 1024
MASK = 0xFFFFFFFF


class Prefix:
    """Bounded TCP prefix reassembly, starting at an observed SYN sequence."""
    def __init__(self, initial):
        self.initial = initial
        self.data = bytearray()
        self.pending = {}
        self.invalid = False
        self.complete = False

    def add(self, sequence, payload):
        if self.invalid or self.complete or not payload:
            return
        offset = (sequence - self.initial) & MASK
        if offset >= 0x80000000:
            return  # old retransmission from before SYN, never a new prefix
        if offset + len(payload) > LIMIT or len(self.pending) > 256:
            self.invalid = True
            self.pending.clear()
            return
        # Compare captured retransmissions/overlaps. Ambiguous streams fail.
        overlap = min(len(payload), max(0, len(self.data)-offset))
        if overlap and self.data[offset:offset+overlap] != payload[:overlap]:
            self.invalid = True
            return
        for start, old in self.pending.items():
            lo, hi = max(offset, start), min(offset+len(payload), start+len(old))
            if lo < hi and payload[lo-offset:hi-offset] != old[lo-start:hi-start]:
                self.invalid = True
                return
        if offset + len(payload) <= len(self.data):
            return
        self.pending[offset] = bytes(payload)
        while self.pending:
            usable = [o for o in self.pending if o <= len(self.data)]
            if not usable:
                break
            start = min(usable)
            value = self.pending.pop(start)
            already = len(self.data)-start
            if already < len(value):
                self.data.extend(value[already:])
        if b'\r\n\r\n' in self.data:
            self.complete = True
            self.pending.clear()
            # Drop body bytes from the same packet before keeping any prefix.
            end = self.data.index(b'\r\n\r\n')+4
            del self.data[end:]


def tcp_from_ethernet(raw):
    if len(raw) < 14:
        return None
    kind = struct.unpack_from('>H', raw, 12)[0]
    offset = 14
    for _ in range(2):
        if kind not in (0x8100, 0x88A8):
            break
        if len(raw) < offset+4:
            return None
        kind = struct.unpack_from('>H', raw, offset+2)[0]
        offset += 4
    if kind != 0x0800 or len(raw) < offset+20:
        return None
    ip = raw[offset:]
    size = (ip[0] & 15)*4
    total = struct.unpack_from('>H', ip, 2)[0]
    if ip[0] >> 4 != 4 or size < 20 or total < size+20 or len(ip) < total or ip[9] != 6:
        return None
    # IP fragments cannot prove complete HTTP headers without IP reassembly.
    if struct.unpack_from('>H', ip, 6)[0] & 0x3FFF:
        return None
    src, dst = str(ipaddress.IPv4Address(ip[12:16])), str(ipaddress.IPv4Address(ip[16:20]))
    tcp = ip[size:total]
    header_len = (tcp[12] >> 4)*4
    if header_len < 20 or header_len > len(tcp):
        return None
    sport, dport, sequence = struct.unpack_from('>HHI', tcp, 0)
    return src, dst, sport, dport, sequence, tcp[13], tcp[header_len:]


class CameraIdCollector:
    def __init__(self, host):
        self.host = host
        self.flows = collections.OrderedDict()
        self.camera_packets = 0

    def feed(self, raw):
        segment = tcp_from_ethernet(raw)
        if segment is None:
            return None
        src, dst, sport, dport, sequence, flags, payload = segment
        if dst == self.host and dport == 80:
            key, outgoing = (src, sport), True
        elif src == self.host and sport == 80:
            key, outgoing = (dst, dport), False
        else:
            return None
        self.camera_packets += 1
        syn, ack = bool(flags & 2), bool(flags & 16)
        if outgoing and syn and not ack:
            initial = (sequence+1) & MASK
            old = self.flows.get(key)
            if old is None or old['request'].initial != initial:
                self.flows[key] = {'request': Prefix(initial), 'response': None}
            if len(self.flows) > 32:
                self.flows.popitem(last=False)
        flow = self.flows.get(key)
        if flow is None:
            return None  # start capture before a new App HTTP connection
        self.flows.move_to_end(key)
        if not outgoing and syn and ack:
            initial = (sequence+1) & MASK
            old = flow['response']
            if old is None or old.initial != initial:
                flow['response'] = Prefix(initial)
        side = flow['request'] if outgoing else flow['response']
        if side is not None:
            side.add((sequence+int(syn)) & MASK, payload)
        req, resp = flow['request'], flow['response']
        result = None
        if (req.complete and resp is not None and resp.complete
                and not req.invalid and not resp.invalid):
            result = self.match(bytes(req.data), bytes(resp.data))
            # Inspect only the first request/response pair on each fresh stream.
            # Later pipelined/keepalive messages are intentionally not inferred.
            self.flows.pop(key, None)
        elif flags & 5:  # FIN or RST; incomplete evidence is discarded
            self.flows.pop(key, None)
        return result

    @staticmethod
    def match(request, response):
        lines = request.split(b'\r\n')
        first = re.fullmatch(rb'GET (/v1/[^ ]*) HTTP/1\.[01]', lines[0])
        status = re.match(rb'HTTP/1\.[01] ([0-9]{3})(?: |\r\n)', response)
        if first is None or status is None or not 200 <= int(status[1]) < 300:
            return None
        values = []
        for line in lines[1:]:
            if b':' not in line:
                continue
            name, value = line.split(b':', 1)
            if name.lower() == b'x-phocus-client-id':
                try:
                    values.append(client_id(value.strip().decode('ascii')))
                except (UnicodeError, ToolError):
                    return None
        if len(values) != 1:
            return None
        try:
            path = first[1].split(b'?', 1)[0].decode('ascii')
        except UnicodeError:
            return None
        return values[0], {'method': 'GET', 'path': path,
                           'http_status': int(status[1]), 'recorded_at': utc_now()}


async def capture(host, seconds):
    try:
        from pymobiledevice3.lockdown import create_using_usbmux
        from pymobiledevice3.usbmux import list_devices
        from pymobiledevice3.services.pcapd import PcapdService
    except ImportError as exc:
        raise ToolError('Install the iPhone dependency: py -3 -m pip install pymobiledevice3==11.29.1') from exc
    devices = [d for d in await list_devices() if d.is_usb]
    if len(devices) != 1:
        raise ToolError('Connect exactly one iPhone by USB and unlock it. If none is detected, check Apple Mobile Device Service.')
    print('Unlock the remote iPhone and accept Trust This Computer if prompted. No new camera authorization is requested.', flush=True)
    lockdown = await create_using_usbmux(serial=devices[0].serial, connection_type='USB', pair_timeout=30)
    collector = CameraIdCollector(host)
    try:
        async with PcapdService(lockdown) as service:
            print('READY: on iPhone, reopen Phocus, reconnect the already authorized camera and open its album/settings.', flush=True)
            print('Keep the iPhone on camera Wi-Fi. Windows does not need camera Wi-Fi during this capture.', flush=True)
            end = time.monotonic()+seconds
            packets = service.watch().__aiter__()
            while time.monotonic() < end:
                try:
                    packet = await asyncio.wait_for(packets.__anext__(), end-time.monotonic())
                except (asyncio.TimeoutError, StopAsyncIteration):
                    break
                result = collector.feed(bytes(packet.data))
                if result is not None:
                    return result
            raise ToolError('No accepted camera GET ID observed. Camera TCP packets: %d. Start again before reopening Phocus; confirm phone Wi-Fi and camera IP.' % collector.camera_packets)
    finally:
        await lockdown.close()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--camera-host', default='192.168.2.1')
    parser.add_argument('--seconds', type=float, default=60)
    parser.add_argument('--output', type=Path, default=Path('session.json'))
    parser.add_argument('--identity-output', type=Path, default=Path('phone-client-id.json'))
    args = parser.parse_args(argv)
    try:
        host = camera_address(args.camera_host)
        if not 1 <= args.seconds <= 300:
            raise ToolError('Capture duration must be 1..300 seconds.')
        if args.output.resolve() == args.identity_output.resolve():
            raise ToolError('The two output files must be different.')
        identifier, evidence = asyncio.run(capture(host, args.seconds))
        save_identity(identifier, host, [evidence], args.output, args.identity_output,
                      'iPhone USB mirror with TCP-reassembled camera GET/2xx response')
        print('Collected actual Phocus client ID: ' + str(identifier))
        print('Saved ' + str(args.identity_output) + ' and ' + str(args.output))
        print('No firmware uploaded. Historical ID acceptance does not establish Windows session reuse.')
        return 0
    except KeyboardInterrupt:
        print('Capture stopped. No new ID saved.', file=sys.stderr)
        return 2
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
