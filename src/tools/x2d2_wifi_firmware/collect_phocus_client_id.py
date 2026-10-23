#!/usr/bin/env python3
"""Extract the actual Phocus HTTP client ID from an iPhone's exported HAR.

Runs offline on Windows/macOS with Python 3.9+. It reads App traffic evidence,
not a phone's UDID/MAC. It does not pair, contact a camera, or upload firmware.
"""
import argparse
from pathlib import Path
import json
import sys
from urllib.parse import urlsplit

from x2d2_wifi_upgrade import ToolError, camera_address, client_id, utc_now, write_json

HEADER = 'x-phocus-client-id'
MAX_FILE = 32 * 1024 * 1024


def accepted_har_ids(data, host):
    """Return IDs with a matching camera /v1/ request AND a recorded 2xx response.

    HAR has explicit request/response pairing. A raw dump cannot establish that
    pairing reliably, so it is deliberately not accepted as verified evidence.
    """
    try:
        har = json.loads(data.decode('utf-8-sig'))
    except (UnicodeError, ValueError) as exc:
        raise ToolError('Select an exported HAR JSON file, not a screenshot or packet binary.') from exc
    if not isinstance(har, dict) or not isinstance(har.get('log'), dict):
        raise ToolError('Missing HAR log object.')
    entries = har['log'].get('entries')
    if not isinstance(entries, list):
        raise ToolError('Missing HAR log.entries array.')
    found = {}
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        req, resp = entry.get('request'), entry.get('response')
        if not isinstance(req, dict) or not isinstance(resp, dict):
            continue
        try:
            url = urlsplit(req.get('url', ''))
            status = resp.get('status')
            port = url.port or (80 if url.scheme == 'http' else 443)
        except (ValueError, TypeError):
            continue
        if (url.scheme != 'http' or url.hostname != host or port != 80
                or not url.path.startswith('/v1/')
                or isinstance(status, bool) or not isinstance(status, int)
                or not 200 <= status < 300):
            continue
        headers = req.get('headers')
        if not isinstance(headers, list):
            continue
        values = set()
        invalid = False
        for header in headers:
            if not isinstance(header, dict) or str(header.get('name', '')).lower() != HEADER:
                continue
            try:
                values.add(client_id(header.get('value', '')))
            except ToolError:
                invalid = True
        if invalid or len(values) != 1:
            continue
        identifier = next(iter(values))
        # Store only request metadata. No account headers, cookies or response body.
        evidence = {'method': req.get('method', ''), 'path': url.path,
                    'http_status': status, 'recorded_at': entry.get('startedDateTime', '')}
        found.setdefault(identifier, []).append(evidence)
    return found


def collect(path, host, selected=None):
    if path.stat().st_size > MAX_FILE:
        raise ToolError('HAR exceeds 32 MiB. Export only the camera /v1/ requests, without image bodies.')
    found = accepted_har_ids(path.read_bytes(), host)
    if not found:
        raise ToolError('No camera-accepted X-Phocus-Client-Id found. Need HTTP port 80, /v1/ and a recorded 2xx response.')
    if selected is None:
        if len(found) != 1:
            raise ToolError('Several accepted IDs found: ' + ', '.join(map(str, sorted(found)))
                            + '. Use --client-id to select the intended phone ID.')
        selected = next(iter(found))
    selected = client_id(selected)
    if selected not in found:
        raise ToolError('Selected ID has no accepted camera request in this HAR.')
    return selected, found[selected]


def save_identity(identifier, host, evidence, session_path, identity_path, source, accepted=True):
    """Persist only the observed ID and camera request metadata."""
    identifier = client_id(identifier)
    now = utc_now()
    identity = {'client_id': identifier, 'client_id_hex': format(identifier, '08X'),
                'host': host, 'observed_camera_acceptance': accepted,
                'collected_at': now, 'evidence': evidence,
                'note': 'Observed App ID; does not establish that another device can recreate its session.'}
    session = {'host': host, 'port': 80, 'client_id': identifier,
               'captured_at': now, 'source': source,
               'note': 'Historical acceptance only. An active authorized session is still required; run probe before upload.'}
    write_json(identity_path, identity)
    write_json(session_path, session)


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('har', nargs='?', type=Path, help="HAR exported from the iPhone's own HTTP capture")
    p.add_argument('--observed-id', help='Decimal ID copied from the actual iPhone request header; acceptance is not independently verified')
    p.add_argument('--camera-host', default='192.168.2.1')
    p.add_argument('--client-id', help='Select one observed decimal ID if HAR contains several')
    p.add_argument('--output', type=Path, default=Path('session.json'))
    p.add_argument('--identity-output', type=Path, default=Path('phone-client-id.json'))
    a = p.parse_args(argv)
    try:
        host = camera_address(a.camera_host)
        # Refuse to overwrite the evidence or to alias the two different outputs.
        paths = [a.output.resolve(), a.identity_output.resolve()]
        if a.har is not None:
            paths.append(a.har.resolve())
        if len(set(paths)) != len(paths):
            raise ToolError('HAR, session output and identity output must be different files.')
        if (a.har is None) == (a.observed_id is None):
            raise ToolError('Supply either a HAR file or --observed-id copied from the actual request header.')
        if a.observed_id is not None:
            if a.client_id is not None:
                raise ToolError('--client-id selects a HAR record; use only --observed-id for a copied header.')
            identifier, evidence = client_id(a.observed_id), []
            accepted = False
            source = 'manually copied iPhone request header; acceptance unverified'
        else:
            identifier, evidence = collect(a.har, host, a.client_id)
            accepted = True
            source = 'iPhone HAR with matched camera 2xx response'
        save_identity(identifier, host, evidence, a.output, a.identity_output, source, accepted)
        print('Observed Phocus client ID (decimal): ' + str(identifier))
        print('Same numeric ID in hexadecimal: ' + format(identifier, '08X'))
        print('ID record: ' + str(a.identity_output))
        print('Existing uploader configuration: ' + str(a.output))
        print('Historical camera acceptance recorded.' if accepted else 'Manual ID entry; camera acceptance has not been verified.')
        print('This does not create a new session or install firmware.')
        return 0
    except (ToolError, OSError) as exc:
        print(str(exc), file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
