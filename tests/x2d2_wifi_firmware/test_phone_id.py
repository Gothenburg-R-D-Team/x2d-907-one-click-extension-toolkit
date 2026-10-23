import asyncio
import contextlib
import io
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src/tools/x2d2_wifi_firmware"))

import collect_phocus_client_id as har_tool
import collect_iphone_usb_id as usb
import x2d2_reuse_session as ble
import x2d2_wifi_upgrade as http_tool


def har_entry(identifier='123456', status=200, url='http://192.168.2.1/v1/parameters'):
    return {'startedDateTime':'2026-10-14T08:00:00Z',
            'request':{'url':url,'method':'GET','headers':[
                {'name':'X-Phocus-Client-Id','value':identifier},
                {'name':'Cookie','value':'must-not-be-saved'}]},
            'response':{'status':status,'content':{'text':'must-not-be-saved'}}}


def ethernet(src, dst, sport, dport, seq, flags, payload=b''):
    import ipaddress
    tcp = struct.pack('>HHIIBBHHH', sport, dport, seq, 0, 0x50, flags, 65535, 0, 0)+payload
    ip = struct.pack('>BBHHHBBH4s4s', 0x45, 0, 20+len(tcp), 1, 0x4000, 64, 6, 0,
                     ipaddress.IPv4Address(src).packed, ipaddress.IPv4Address(dst).packed)
    return b'\0'*12+b'\x08\x00'+ip+tcp


class PhoneIdTests(unittest.TestCase):
    def test_har_filters_wrong_camera_failed_and_invalid_ids(self):
        entries=[har_entry(),har_entry('999',403),har_entry('888',200,'http://example.com/v1/parameters'),
                 har_entry('777',200,'https://192.168.2.1/v1/parameters'),har_entry('0'),har_entry('123\r\nx: y')]
        found=har_tool.accepted_har_ids(json.dumps({'log':{'entries':entries}}).encode(),'192.168.2.1')
        self.assertEqual(set(found),{123456})
        self.assertNotIn('must-not-be-saved',json.dumps(found))

    def test_har_refuses_ambiguous_duplicate_header(self):
        row=har_entry();row['request']['headers'].append({'name':'x-phocus-client-id','value':'654321'})
        self.assertEqual(har_tool.accepted_har_ids(json.dumps({'log':{'entries':[row]}}).encode(),'192.168.2.1'),{})

    def test_actual_har_makes_existing_uploader_config_offline(self):
        with tempfile.TemporaryDirectory() as root:
            root=Path(root);src=root/'phone.har';session=root/'session.json';identity=root/'phone-client-id.json'
            src.write_text(json.dumps({'log':{'entries':[har_entry()]}}))
            with patch.object(http_tool.http.client,'HTTPConnection',side_effect=AssertionError('network')):
                with contextlib.redirect_stdout(io.StringIO()):
                    code=har_tool.main([str(src),'--output',str(session),'--identity-output',str(identity)])
            self.assertEqual(code,0);self.assertEqual(http_tool.load_session(session),('192.168.2.1',80,123456))
            self.assertTrue(json.loads(identity.read_text())['observed_camera_acceptance'])
            self.assertNotIn('must-not-be-saved',identity.read_text())
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(har_tool.main([str(src),'--output',str(src),'--identity-output',str(identity)]),2)

    def test_manual_id_is_explicitly_unverified(self):
        with tempfile.TemporaryDirectory() as root:
            root=Path(root);identity=root/'id.json';session=root/'session.json'
            with contextlib.redirect_stdout(io.StringIO()):
                code=har_tool.main(['--observed-id','123456','--output',str(session),'--identity-output',str(identity)])
            self.assertEqual(code,0)
            self.assertFalse(json.loads(identity.read_text())['observed_camera_acceptance'])
            self.assertEqual(http_tool.load_session(session)[2],123456)

    def start_flow(self, collector):
        collector.feed(ethernet('192.168.2.218','192.168.2.1',52000,80,100,2))
        collector.feed(ethernet('192.168.2.1','192.168.2.218',80,52000,500,18))

    def test_usb_reassembly_out_of_order_duplicate_and_paired_response(self):
        c=usb.CameraIdCollector('192.168.2.1');self.start_flow(c)
        req=b'GET /v1/parameters?x=private HTTP/1.1\r\nX-Phocus-Client-Id: 123456\r\n\r\n'
        self.assertIsNone(c.feed(ethernet('192.168.2.218','192.168.2.1',52000,80,121,24,req[20:])))
        self.assertIsNone(c.feed(ethernet('192.168.2.218','192.168.2.1',52000,80,121,24,req[20:])))
        self.assertIsNone(c.feed(ethernet('192.168.2.218','192.168.2.1',52000,80,101,24,req[:20])))
        rsp=b'HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}'
        result=c.feed(ethernet('192.168.2.1','192.168.2.218',80,52000,501,24,rsp))
        self.assertEqual(result[0],123456);self.assertEqual(result[1]['path'],'/v1/parameters')
        self.assertNotIn('private',json.dumps(result))

    def test_usb_rejects_missing_syn_failed_response_other_port(self):
        req=b'GET /v1/parameters HTTP/1.1\r\nX-Phocus-Client-Id: 123456\r\n\r\n'
        c=usb.CameraIdCollector('192.168.2.1')
        self.assertIsNone(c.feed(ethernet('192.168.2.218','192.168.2.1',52000,80,101,24,req)))
        self.start_flow(c)
        c.feed(ethernet('192.168.2.218','192.168.2.1',52000,80,101,24,req))
        self.assertIsNone(c.feed(ethernet('192.168.2.1','192.168.2.218',80,52000,501,24,b'HTTP/1.1 403 Forbidden\r\n\r\n')))
        self.assertIsNone(c.feed(ethernet('192.168.2.1','192.168.2.218',443,52000,501,24,b'HTTP/1.1 200 OK\r\n\r\n')))

    def test_tcp_conflicting_retransmissions_fail_and_sequence_wrap(self):
        p=usb.Prefix(0xFFFFFFFC);p.add(2,b'cd\r\n\r\n');p.add(0xFFFFFFFC,b'abcd12')
        self.assertTrue(p.complete);self.assertEqual(bytes(p.data),b'abcd12cd\r\n\r\n')
        p=usb.Prefix(100);p.add(110,b'abcd');p.add(112,b'XX')
        self.assertTrue(p.invalid)

    def test_parser_bounds_invalid_ip_and_large_flow(self):
        self.assertIsNone(usb.tcp_from_ethernet(b'bad'))
        p=usb.Prefix(1);p.add(usb.LIMIT,b'a'*2);self.assertTrue(p.invalid)
        c=usb.CameraIdCollector('192.168.2.1')
        for port in range(100,150):
            c.feed(ethernet('192.168.2.218','192.168.2.1',port,80,10,2))
        self.assertEqual(len(c.flows),32)

    def test_ble_decoder_resync_fragmentation_and_corruption(self):
        # Independent CRC-table witnesses from the App's LD6/a static arrays.
        self.assertEqual(ble.crc8(b'\0',0),0)
        self.assertEqual(ble.crc8(b'\x01',0),0x5e)
        self.assertEqual(ble.crc16(b'\x01',0),0x1189)
        raw=ble.packet(2,7,1,0x40,7,69,b'\x08ABCDEF00\x07Windows')
        self.assertEqual(raw[4:11],b'\x02\x07\x01\x00\x40\x07\x45')
        d=ble.Decoder();self.assertEqual(d.feed(b'garbage'+raw[:6]),[])
        frames=d.feed(raw[6:]);self.assertEqual(len(frames),1);self.assertEqual(frames[0].payload,b'\x08ABCDEF00\x07Windows')
        bad=raw[:-1]+bytes([raw[-1]^1]);self.assertEqual(ble.Decoder().feed(bad),[])


class FakeCharacteristic:
    service_uuid=ble.SERVICE
    properties=['write']


class FakeServices:
    def get_characteristic(self,_):return FakeCharacteristic()


class FakeBle:
    is_connected=True
    services=FakeServices()
    def __init__(self,status=1):
        self.status=status;self.sent=[];self.decoder=ble.Decoder();self.notify=None
    async def start_notify(self,_,callback):self.notify=callback
    async def stop_notify(self,_):pass
    async def write_gatt_char(self,_,data,response):
        for f in self.decoder.feed(data):
            self.sent.append(f)
            if f.command==69:payload=bytes([0,self.status])
            else:payload=b'\0'
            reply=ble.packet(f.receiver,f.sender,f.sequence,0x80,f.group,f.command,payload)
            self.notify(None,bytearray(reply))


class BleSessionTests(unittest.IsolatedAsyncioTestCase):
    async def test_existing_id_is_used_in_auth_and_v1_hello(self):
        client=FakeBle();s=ble.BleSession(client,0x00ABCDEF)
        await s.open()
        try:await s.establish(0.5)
        finally:await s.close()
        self.assertEqual(len(client.sent),2)
        self.assertEqual(client.sent[0].payload,b'\x0800ABCDEF\x07Windows')
        self.assertEqual(client.sent[1].payload,b'\x01\xef\xcd\xab\0\0\0\0')
        self.assertEqual(client.sent[1].receiver,0xD7)

    async def test_screen_authorization_requirement_stops_before_hello(self):
        client=FakeBle(status=2);s=ble.BleSession(client,123456);await s.open()
        try:
            with self.assertRaisesRegex(http_tool.ToolError,'screen'):
                await s.establish(0.5)
        finally:await s.close()
        self.assertEqual(len(client.sent),1)

    async def test_refused_id_stops_and_pending_requests_are_cleared(self):
        client=FakeBle(status=3);s=ble.BleSession(client,123456);await s.open()
        try:
            with self.assertRaisesRegex(http_tool.ToolError,'refused'):
                await s.establish(0.5)
        finally:await s.close()
        self.assertEqual(s.pending,{})


if __name__=='__main__':unittest.main()
