#!/usr/bin/env python3
"""Exercise the packaged native helper over real stdio pipes, isolated from user state."""
import json
import os
from pathlib import Path
import select
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
HOST = ROOT / 'dist/Meeting Busy.app/Contents/MacOS/MeetingBusyBrowserHost'


def receive(process):
    assert select.select([process.stdout], [], [], 5)[0], 'native host reply timed out'
    size = struct.unpack('<I', process.stdout.read(4))[0]
    assert 0 < size <= 65536
    return json.loads(process.stdout.read(size))


def send(process, value):
    payload = json.dumps(value).encode()
    process.stdin.write(struct.pack('<I', len(payload)) + payload)
    process.stdin.flush()
    return receive(process)


def main():
    with tempfile.TemporaryDirectory(prefix='meeting-busy-host-') as directory:
        root = Path(directory)
        def policy(enabled=True, paused=False):
            (root / 'policy.json').write_text(json.dumps(dict(enabled=enabled, paused=paused, services=['Zoom'])))
        policy()
        process = subprocess.Popen([str(HOST)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   env={**os.environ, 'MEETING_BUSY_BRIDGE_TEST_DIRECTORY': directory})
        try:
            assert receive(process)['policy']['enabled']
            states = [dict(id='1:0', service='Zoom', inMeeting=True, presenting=False),
                      dict(id='2:0', service='Google Meet', inMeeting=True, presenting=False)]
            assert send(process, dict(protocolVersion=1, states=states))['accepted']
            snapshots = list(root.glob('session-*.json'))
            assert len(snapshots) == 1
            assert json.loads(snapshots[0].read_text())['states'] == states[:1], 'disabled services leaked'
            assert snapshots[0].stat().st_mode & 0o777 == 0o600
            states[0]['id'] = 'https://private.invalid/meeting'
            assert not send(process, dict(protocolVersion=1, states=states))['accepted']
            assert not list(root.glob('session-*.json')), 'invalid payload retained Busy'
            states[0]['id'] = '1:0'
            policy(paused=True)
            assert send(process, dict(protocolVersion=1, states=states))['policy']['paused']
            assert not list(root.glob('session-*.json'))
            policy()
            assert send(process, dict(protocolVersion=1, states=states))['accepted']
            assert list(root.glob('session-*.json'))
            process.stdin.close()
            assert process.wait(timeout=5) == 0
            assert not list(root.glob('session-*.json')), 'EOF left a live session'
            assert not process.stderr.read()
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
    print('PASS: real native host framing, filtering, rejection, pause, permissions, and EOF cleanup')


if __name__ == '__main__':
    main()
