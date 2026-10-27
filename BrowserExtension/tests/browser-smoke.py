#!/usr/bin/env python3
"""Optional Playwright/Chromium smoke test. Uses synthetic provider pages, no real calls."""
import json
import os
from pathlib import Path
import shutil
import tempfile
import time
import uuid
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[2]
HOST = ROOT / 'dist/Meeting Busy.app/Contents/MacOS/MeetingBusyBrowserHost'
SOURCE = ROOT / 'dist/Meeting Busy.app/Contents/Resources/BrowserExtension/chromium'


def main():
    name = 'local.meetingbusy.test.' + uuid.uuid4().hex
    with tempfile.TemporaryDirectory(prefix='meeting-busy-browser-') as directory:
        root = Path(directory)
        hosts = root / 'profile/NativeMessagingHosts'
        hosts.mkdir(parents=True)
        registration = hosts / (name + '.json')
        extension = root / 'extension'
        shutil.copytree(SOURCE, extension)
        background = extension / 'background.js'
        background.write_text(background.read_text().replace('local.meetingbusy.browser', name).replace('void api.runtime.lastError; disconnectNative();', 'globalThis.testNativeError = api.runtime.lastError?.message; disconnectNative();'))
        identity = json.loads((ROOT / 'BrowserExtension/identity.json').read_text())['chromiumID']
        registration.write_text(json.dumps(dict(name=name, description='Isolated Meeting Busy test',
            path=str(HOST), type='stdio', allowed_origins=['chrome-extension://' + identity + '/'])))
        registration.chmod(0o600)
        cache = root / 'cache'
        cache.mkdir()
        def policy(paused=False):
            staged = cache / 'policy.tmp'
            staged.write_text(json.dumps(dict(enabled=True, paused=paused, services=['Google Meet'])))
            staged.replace(cache / 'policy.json')
        policy()
        def states():
            return [state for file in cache.glob('session-*.json') for state in json.loads(file.read_text())['states']]
        def wait_for(context, predicate, label, timeout=15):
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                if predicate():
                    print('PASS:', label, flush=True)
                    return
                context.pages[0].wait_for_timeout(100)
            for worker in context.service_workers:
                print('Worker:', worker.url, worker.evaluate('api.tabs.query({}).then(tabs => ({bridgeStatus, policy, documents: documents.size, error: globalThis.testNativeError, tabs: tabs.map(t => ({id:t.id, active:t.active, windowId:t.windowId}))}))'))
            raise AssertionError(label + ': ' + repr(states()))
        try:
            with sync_playwright() as playwright:
                context = playwright.chromium.launch_persistent_context(str(root / 'profile'),
                    executable_path=playwright.chromium.executable_path, headless=True, timeout=30000,
                    args=['--disable-extensions-except=' + str(extension), '--load-extension=' + str(extension)],
                    env={**os.environ, 'MEETING_BUSY_BRIDGE_TEST_DIRECTORY': str(cache)})
                try:
                    context.on('serviceworker', lambda worker: worker.on('console', lambda message: print('Worker console:', message.text)))
                    context.route('https://meet.google.com/**', lambda route: route.fulfill(content_type='text/html',
                        body='<html><body><button aria-label="Leave call">Leave call</button><button>Unmute</button></body></html>'))
                    meeting = context.new_page()
                    meeting.goto('https://meet.google.com/abc-defg-hij')
                    wait_for(context, lambda: any(s['inMeeting'] for s in states()), 'browser reaches real native helper')
                    other = context.new_page()
                    other.goto('about:blank')
                    other.bring_to_front()
                    tab_id = int(next(s['id'] for s in states() if s['inMeeting']).split(':')[0])
                    worker = context.service_workers[0]
                    wait_for(context, lambda: worker.evaluate('(id) => chrome.tabs.get(id).then(tab => !tab.active)', tab_id),
                             'browser confirms meeting tab is inactive')
                    first = max(json.loads(f.read_text())['receivedAt'] for f in cache.glob('session-*.json'))
                    wait_for(context, lambda: any(json.loads(f.read_text())['receivedAt'] > first + 4000 for f in cache.glob('session-*.json')),
                             'background heartbeat refreshes inactive meeting')
                    meeting.evaluate('document.body.innerHTML = "<button>Rejoin</button>"')
                    wait_for(context, lambda: not any(s['inMeeting'] for s in states()), 'leaving inactive tab clears Busy')
                    meeting.evaluate('document.body.innerHTML = "<button>Stop presenting</button>"')
                    wait_for(context, lambda: any(s['presenting'] for s in states()), 'own sharing in inactive tab is detected')
                    policy(paused=True)
                    wait_for(context, lambda: not list(cache.glob('session-*.json')), 'pause removes bridge evidence')
                    policy()
                    wait_for(context, lambda: any(s['presenting'] for s in states()), 'resume rescans inactive tab')
                    meeting.close()
                    wait_for(context, lambda: not any(s['inMeeting'] for s in states()), 'tab close clears contribution')
                finally:
                    context.close()
                assert not list(cache.glob('session-*.json')), 'browser shutdown left a session'
        finally:
            registration.unlink(missing_ok=True)
    print('PASS: isolated browser integration complete; no real provider session used')


if __name__ == '__main__':
    main()
