# Manual acceptance checks

Automated tests cover detection rules, stale evidence, timer expiry, appearance persistence and placement, release versions/URLs, and diagnostic log rotation. The live-client checks below require a person with Accessibility permission and actual meeting clients. They have not been completed by the restricted development tool session.

For each run, record the app version, macOS version, processor, browser/client version, and pass/fail result. Start in Automatic with previews off. Use Every scan logging temporarily if investigating a failure, then return to State changes or Off.

## Meeting lifecycle

Repeat with native Zoom, native Teams, native Webex, and browser Google Meet. Also test supported browser clients for Zoom, Teams, and Webex where used.

| Check | Expected result |
| --- | --- |
| Launch the client without joining | No meeting indicator. |
| Open a prejoin page or wait for a host | No indicator unless active meeting controls are exposed. |
| Join with audio and camera enabled | Indicator appears after a completed scan; service and signal are identified. |
| Mute audio, turn off camera, or disconnect computer audio | Meeting remains detected while call controls are available. |
| Change apps or Spaces | The indicator remains above ordinary windows. |
| Minimize the meeting or switch browser tabs | Record whether controls remain readable; report any missed detection with scan statistics. |
| Have someone else present | Your Busy indicator remains visible. |
| Share your own screen | Indicator hides when your stop-sharing control is detected; use manual Presenting before sharing for immediate hiding. |
| Stop sharing | Indicator returns if the call remains active. |
| Leave the meeting while the client stays open | Indicator clears on the next completed scan. Zoom's menu commands alone must not keep it busy. |
| Quit the meeting client | Indicator clears after the next scan. |

For a hang/read-error scenario, the last positive result must expire rather than keeping Busy visible indefinitely. A new successful result may show the indicator again. Revoking Accessibility must clear detected evidence and report Setup needed.

## Manual modes and reminders

Select Busy for 15, 30, and 60 minutes; verify the menu shows the end time and returns to Automatic after the deadline. Sleep across a deadline and confirm expiry on wake. Switching modes must cancel the old timer. An indefinite Force Busy must remain until changed.

Select Presenting and verify the menu bar visibly says Presenting while the indicator is hidden. Enable reminder notifications and approve them in macOS, then use the five-minute setting for a check. A reminder must not automatically restore the indicator. Use its Return to Automatic action and verify the mode changes. Switching modes before the reminder is due must cancel it. Denying notifications must leave manual mode usable.

## Shortcuts and appearance

Enable global shortcuts and test Control–Option–Command–1/2/3 from another app. Verify Automatic/Busy/Presenting respectively, with no keyboard focus taken by the indicator. Check the reported registration error if a shortcut is already in use, and verify disabling shortcuts unregisters all three.

Change text, color, size, transparency, location, and display; restart and verify persistence. Right-click → Move indicator, drag between displays, and verify the saved position does not snap back during scans. Test preview start/stop, no preview on opening Settings, and presentation hiding during a preview. Disconnect the chosen display and confirm fallback to the main display. In the Setup and live test section, check permission/bridge status, Check now, Preview Busy, Test Presenting, and Return to Automatic.

## Pausing, service switches, reports, and presets

Pause for 15 minutes, one hour, and until resumed. Verify scans stop and pending results cannot restore Busy. Test deadline expiry across sleep and relaunch, manual Resume, Force Busy while paused, and Presenting while paused. Automatic must not silently cancel a pause. Pausing also stops automatic sharing detection, so test the manual presenting override.

Disable each service in the menu and Settings and verify it is ignored in both native and browser clients. Switch a service off during an in-flight scan; the old result must be discarded. Disable all services and verify the status is explicit, even without Accessibility permission. Reenable a service and verify detection restarts. Relaunch and verify preferences persist.

Customize each shortcut, test valid alternate keys/modifiers from another app, duplicates, missing modifiers, conflicts with other apps, reset, disable, and persistence. An invalid/conflicting configuration must leave all global shortcuts unregistered and explain the failure.

Save, update by name, apply, and delete appearance presets. Verify text/color/size/transparency/location/display choices round-trip and that existing appearance preferences survive upgrade. A preset must not change detection mode or begin recording.

Enable Show on every display, connect/disconnect a monitor, and verify one indicator per connected screen. Give two displays different positions; move one and confirm the other does not move. Hide one display's indicator and confirm the other stays visible. Restart and verify both positions and visibility persist. Then test returning to one selected display and fallback after disconnection. Enter Presenting and verify every visible copy hides.

With Return to Automatic after sharing stops enabled, choose Presenting before sharing. Confirm it stays selected until own sharing is detected. Stop sharing while the call continues; it should return to Automatic after three complete checks. Verify it stays in Presenting when the meeting disappears, a different call remains, or scans are incomplete.

Repeat a live call and own screen share with Spanish, French, and German client UI where available. Confirm prejoin screens and another participant's presentation do not count as your active call or own sharing.

Use only the keyboard to open Move indicator using the keyboard. Test arrows, Shift+arrows, Option+arrows, Return/Escape, directional buttons, and preview ownership when another preview already exists. Check VoiceOver's custom Move action and each directional button label. The ordinary indicator must remain nonactivating; only the explicitly opened movement window takes focus.

Open This detection is incorrect in each state. Check generated reports contain no meeting content, paths, custom appearance text, or logs. Edit Expected behavior, save locally, and inspect the file. Nothing should be uploaded, and report contents must not enter diagnostic logs. Reopening an already visible report must preserve edits; closing/reopening should provide a new snapshot.

## Logging, updates, and distribution

Open the log folder and verify State changes mode records transitions, while Every scan includes scan results/errors. Verify exported entries have no meeting titles, chat, names, URLs, or custom indicator text. Check Clear logs and Off. Logs use `~/Library/Logs/MeetingBusy`, with four files bounded to 512 KiB each; exports are user-selected copies and are not cleared automatically.

Keep daily update checking off and verify no update check occurs. Run Check now; test no release (404), offline/error, current version, and a newer stable release. Only the project's HTTPS GitHub release page should open. If update notifications are enabled, verify a newer version triggers one notification per version and no automatic installation occurs.

Test the packaged app after ZIP extraction on an Apple Silicon Mac and an Intel Mac, each on a supported macOS release. For Developer ID releases, validate signing, notarization/stapling, and first launch on a separate Mac. For ad hoc builds, follow the documented per-app security exception. Confirm Accessibility and optional Notifications permission flows independently.

## Browser integration and Available (0.0.3)

- Install each browser bridge from the packaged app in Applications, load the corresponding extension, and confirm connection status. Repeat after app relocation/update, using Install/update bridge and extension reload. Confirm bridge removal affects only the selected browser registration and removes its host manifest.
- In real Meet, Teams, Webex, and Zoom web calls, join with microphone/camera off, switch to another tab/app for over a minute, leave while the tab is inactive, and close/navigate the meeting tab. Busy should track actual call controls without activating the meeting tab. Test sharing and another participant sharing. Repeat with Accessibility denied to isolate extension evidence.
- Test multiple browser profiles, simultaneous providers, pause/resume, service switches, extension disable/reload, browser crash, and app sleep/wake. Disconnected evidence must expire after 20 seconds plus the next app poll; other active connections should remain effective. Firefox temporary installs disappear on browser restart; Safari supports the embedded extension or Accessibility fallback.
- Select Available during a detected call, detected sharing, Force Busy, and a preview: all indicators should hide and the menu should say Available. Verify 15/30/60-minute expiry, Return to Automatic, relaunch reset, and sleep past expiry. Available must not cancel an existing detection pause or start a Presenting reminder.
- Inspect bridge JSON/logs and verify no URLs, titles, participant names, chat, or raw button text are saved. Verify host manifests allow only the packaged extension ID and point to the installed helper. Test on Intel as well as Apple Silicon.

## Safari local extension

- With no paid certificate installed, build the universal app and verify the embedded appex has both architectures and sandbox/network-client entitlements. Open the packaged app from Applications, enable unsigned extensions in Safari, enable Meeting Busy, and permit only the supported meeting sites.
- Confirm the popup connects with browser integration on, detects a call in an inactive tab, hides for your own share, stays visible for another participant's share, clears on leave/navigation/tab closure, and expires stale evidence after a Safari crash or frozen page.
- Check pause/resume and each service switch. Disable integration and confirm the loopback listener stops; reenable and reconnect. Test two Safari profiles simultaneously, multiple providers, and browser/app sleep and wake.
- Restart Safari and verify the documented requirement to allow unsigned extensions again. Disable the Safari extension and confirm Accessibility fallback works when permission is granted.
- Quit the app and verify the popup reports a disconnect. Launch duplicate app copies and verify a port conflict is reported without connecting to the wrong build.
- Test on Safari 16/macOS 13 and a current Safari release. Unit and native-loopback tests do not replace this live Safari check.

## Safari temporary-extension pairing

- On a Safari version offering Add Temporary Extension, load the safari-temporary folder or ZIP and verify Meeting Busy (Temporary) appears even if the embedded native extension does not. Enable website and loopback permissions.
- Copy the code from the current running app and pair in the popup. Confirm a connected popup, live call and own-sharing state, inactive tabs, pause, service switches, tab closure, app quit, and stale-evidence expiry.
- Check an invalid pairing code cannot connect, re-pair after replacing the app, and verify ordinary HTTP(S) origins cannot send authenticated state. A Safari-origin preflight must not write a state snapshot.
- Quit Safari and verify the extension is removed. Reload it and pair again when needed. Record Safari version and actual UI results separately from the native-handler tests.

Observed on 2026-10-28, Safari 27: user confirmed Meeting Busy (Temporary) appears after Add Temporary Extension. The app received a fresh browser heartbeat with integration enabled. Live meeting and own-sharing detection are not yet verified in this session.
