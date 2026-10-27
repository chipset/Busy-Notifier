# Browser integration validation

Run the dependency-free classifier and background-worker tests with Node.js:

```sh
node --test BrowserExtension/tests/*.test.cjs
```

Build the packaged app first, then test the actual helper with Python 3 (standard library only):

```sh
./scripts/build-app.sh
python3 scripts/test-browser-host.py
```

The optional browser smoke test requires Python Playwright and its full Chromium browser:

```sh
python3 -m venv .build/browser-test-env
.build/browser-test-env/bin/pip install playwright
.build/browser-test-env/bin/python -m playwright install chromium
.build/browser-test-env/bin/python BrowserExtension/tests/browser-smoke.py
```

This uses an isolated headless Chromium profile, synthetic HTTPS provider pages intercepted locally, a temporary extension copy, an isolated cache, and a uniquely named temporary native-host registration inside the isolated profile's NativeMessagingHosts directory. Its own registration is removed on completion. It does not open a real provider session or modify the user's Chrome profile or production bridge registration. It checks actual extension loading, native-host communication, inactive-tab heartbeats, leaving/sharing while inactive, pause/resume, and tab closure. It is a transport/DOM integration test; real provider controls, Firefox, browser policies, macOS Accessibility, overlay behavior, and captured presentation frames still need the checks in MANUAL_TESTS.md.

The smoke test verifies inactivity through the browser tabs API. Playwright keeps page rendering visible even when a tab is inactive, so this does not simulate browser timer throttling, freezing, or discarding. The worker heartbeat test and live browser acceptance checks cover those separately.
