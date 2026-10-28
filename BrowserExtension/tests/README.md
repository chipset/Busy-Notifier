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

## Safari native bridge

Run `swift test` on a Mac with loopback network access to verify authenticated HTTP state delivery, filtering, pause, and rejection. Run `python3 scripts/test-safari-handler.py` from the repository root to compile the actual Safari native handler into an ad hoc signed sandboxed test app and verify native-message forwarding and redirect refusal. `node --test BrowserExtension/tests/*.test.cjs` includes Safari request/reply transport and Manifest V2 tab injection. These checks do not enable Safari or simulate live meeting clients; follow the Safari checks in MANUAL_TESTS.md.
