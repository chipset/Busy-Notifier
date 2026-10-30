# Project progress and resume notes

Last updated: 2026-10-30. Repo: https://github.com/chipset/Meeting-Busy (local: `~/source/meeting-busy`).

## Current state

- **Latest release: 0.4.3 (build 21)**, published as a GitHub *prerelease* (not marked latest): https://github.com/chipset/Meeting-Busy/releases/tag/v0.4.3. Tags `v0.4.2` and `v0.4.3` are pushed.
- `/Applications/Meeting Busy.app` is the 0.4.3 build taken from the published ZIP. `~/Applications/Meeting Busy.app` was removed.
- `main` is pushed and is the source of truth. CI is defined in `.github/workflows/ci.yml` (macOS runner: `swift test` plus `node --test BrowserExtension/tests/*.test.cjs`) but **has never run on GitHub**; check the Actions tab after the first push.

## Branches

| Branch | Commit | Status |
| --- | --- | --- |
| `main` | 37852ad (Release 0.4.3) | Pushed. Work here. |
| `feature/usb-indicator-light` | ce9351c | **Unmerged.** Optional USB indicator light (RP2040 + WS2812). Pushed as a backup branch only. |
| `improvements/reliability-and-pairing` | 7e2c80a | Fully merged into `main`. Redundant; safe to delete (`git branch -d`). Not pushed. |

The feature branch forks from 7e2c80a, is 1 commit ahead and 4 behind `main`. Merging it **conflicts in `RELEASE_NOTES.md`** (`App.swift` auto-merges). To resume: `git checkout feature/usb-indicator-light && git rebase main` (or merge main), resolve `RELEASE_NOTES.md`, run `swift test` and the firmware tests, then merge.

## What 0.4.x delivered

- Detection: phrase lists live in one place per language and are mirrored in `BrowserExtension/shared/detector.js`; `parity.test.cjs` fails if Swift and JS drift. "New meeting" / "Join a meeting" only end Zoom calls.
- Browser extension: throttled content-script scan (300 ms).
- Safari: approval-based pairing (`SafariPairingCoordinator`, one prompt at a time, 5 per 10 minutes, single-use). Per-install pairing token (`0600`) for extension origins; the build-wide token only authenticates requests with no Origin (needed by the native appex path). Popup has "Pair automatically" plus a manual fallback. Loopback bridge: 127.0.0.1:48157.
- Reliability: snapshot pruning (300 s), in-process notification on Safari updates, adaptive Accessibility scan interval (6 s when idle and bridge connected), single-instance handoff (second launch opens Settings in the running one).
- UI: right-click on the indicator offers Hide for 15 minutes / 1 hour / until Automatic (plus VoiceOver action).
- 0.4.3 fix: "Grant Accessibility access…" shows the system dialog the first time only, then opens System Settings.

## USB indicator light (feature branch)

- Hardware plan: RP2040 board + 10-LED WS2812 strip on GP0, CircuitPython, USB serial (`/dev/cu.usbmodem*`). The user is **still getting the hardware** and wants to test it together.
- Protocol: app sends `HELLO` (reply `MEETINGBUSY 1`), then `STATE <busy|presenting|free|attention|off>` lines, with a 3 s heartbeat; firmware turns off after 10 s of silence.
- Patterns: busy = solid red, presenting = solid yellow, free = off, attention = amber flash (2 s period). Brightness is capped to the USB current budget (~400 mA).
- `boot.py` disables the USB mass-storage drive, HID and MIDI (corporate policy). Maintenance mode: hold GP15 to ground to get the drive back.
- Code: `Sources/MeetingDetection/IndicatorLight.swift`, `Sources/MeetingBusy/UsbLight.swift`, `Firmware/UsbLight/` (with tests in `tests/test_protocol.py`), settings toggle in Settings. Swift tests: `IndicatorLightTests.swift` (includes a pty-based handshake test).
- **Never run on real hardware.** Expect to tune pin, LED count, brightness and the serial-port match when the device arrives.

## Open items / not yet done

1. Real-world acceptance tests per `MANUAL_TESTS.md`: live Safari meeting, own-sharing detection, and the Safari pairing flow have only been verified by automated tests.
2. Fresh-install Accessibility behaviour (0.4.3 fix) is untested. To test: `tccutil reset Accessibility local.meetingbusy` and `defaults delete local.meetingbusy didRequestAccessibilityPrompt`, then choose Grant Accessibility twice (expect dialog only, then Settings only).
3. The embedded Safari native extension (appex) is never listed by Safari; the temporary-extension route is the workaround. Root cause is unsolved (likely signing: ad hoc build).
4. Stable signing: a self-signed certificate (so Accessibility consent survives updates) needs a decision on key handling; free Apple ID dev signing is unproven. No notarization.
5. Decide whether to promote 0.4.3 from prerelease to stable (`gh release edit v0.4.3 --prerelease=false --latest`).
6. Delete the redundant `improvements/reliability-and-pairing` branch.
7. `dist/AGENT_HANDOFF.txt` (gitignored) is stale; it describes 0.4.1.

## Release procedure (short)

See `RELEASING.md`. In outline: bump `Resources/Info.plist` and the four extension manifests (`chromium`, `firefox`, `safari`, `safari-temporary`), update `RELEASE_NOTES.md`, run `scripts/package-release.sh`, commit, push `main`, create an annotated tag, push it, then `gh release create --verify-tag --prerelease --latest=false --notes-file ...` with the ZIPs and `.sha256` files. Run the push, tag and release as separate commands.

## Verifying

- `swift test` and `node --test BrowserExtension/tests/*.test.cjs` (on the feature branch also `python3 -m unittest discover -s Firmware/UsbLight/tests`).
- `/Applications/Meeting\ Busy.app/Contents/MacOS/MeetingBusy --diagnose` prints version and Accessibility status.
