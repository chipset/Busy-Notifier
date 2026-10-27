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

Change text, color, size, transparency, location, and display; restart and verify persistence. Right-click → Move indicator, drag between displays, and verify the saved position does not snap back during scans. Test preview start/stop, no preview on opening Settings, and presentation hiding during a preview. Disconnect the chosen display and confirm fallback to the main display.

## Pausing, service switches, reports, and presets

Pause for 15 minutes, one hour, and until resumed. Verify scans stop and pending results cannot restore Busy. Test deadline expiry across sleep and relaunch, manual Resume, Force Busy while paused, and Presenting while paused. Automatic must not silently cancel a pause. Pausing also stops automatic sharing detection, so test the manual presenting override.

Disable each service in the menu and Settings and verify it is ignored in both native and browser clients. Switch a service off during an in-flight scan; the old result must be discarded. Disable all services and verify the status is explicit, even without Accessibility permission. Reenable a service and verify detection restarts. Relaunch and verify preferences persist.

Customize each shortcut, test valid alternate keys/modifiers from another app, duplicates, missing modifiers, conflicts with other apps, reset, disable, and persistence. An invalid/conflicting configuration must leave all global shortcuts unregistered and explain the failure.

Save, update by name, apply, and delete appearance presets. Verify text/color/size/transparency/location/display choices round-trip and that existing appearance preferences survive upgrade. A preset must not change detection mode or begin recording.

Enable Show on every display, connect/disconnect a monitor, and verify one indicator per connected screen. Move one and confirm shared relative placement, then test returning to one selected display and fallback after disconnection. Enter Presenting and verify every copy hides.

Use only the keyboard to open Move indicator using the keyboard. Test arrows, Shift+arrows, Option+arrows, Return/Escape, directional buttons, and preview ownership when another preview already exists. Check VoiceOver's custom Move action and each directional button label. The ordinary indicator must remain nonactivating; only the explicitly opened movement window takes focus.

Open This detection is incorrect in each state. Check generated reports contain no meeting content, paths, custom appearance text, or logs. Edit Expected behavior, save locally, and inspect the file. Nothing should be uploaded, and report contents must not enter diagnostic logs. Reopening an already visible report must preserve edits; closing/reopening should provide a new snapshot.

## Logging, updates, and distribution

Open the log folder and verify State changes mode records transitions, while Every scan includes scan results/errors. Verify exported entries have no meeting titles, chat, names, URLs, or custom indicator text. Check Clear logs and Off. Logs use `~/Library/Logs/MeetingBusy`, with four files bounded to 512 KiB each; exports are user-selected copies and are not cleared automatically.

Keep daily update checking off and verify no update check occurs. Run Check now; test no release (404), offline/error, current version, and a newer stable release. Only the project's HTTPS GitHub release page should open. If update notifications are enabled, verify a newer version triggers one notification per version and no automatic installation occurs.

Test the packaged app after ZIP extraction on an Apple Silicon Mac and an Intel Mac, each on a supported macOS release. For Developer ID releases, validate signing, notarization/stapling, and first launch on a separate Mac. For ad hoc builds, follow the documented per-app security exception. Confirm Accessibility and optional Notifications permission flows independently.
