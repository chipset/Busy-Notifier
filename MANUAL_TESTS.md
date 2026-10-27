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

## Logging, updates, and distribution

Open the log folder and verify State changes mode records transitions, while Every scan includes scan results/errors. Verify exported entries have no meeting titles, chat, names, URLs, or custom indicator text. Check Clear logs and Off. Logs use `~/Library/Logs/MeetingBusy`, with four files bounded to 512 KiB each; exports are user-selected copies and are not cleared automatically.

Keep daily update checking off and verify no update check occurs. Run Check now; test no release (404), offline/error, current version, and a newer stable release. Only the project's HTTPS GitHub release page should open. If update notifications are enabled, verify a newer version triggers one notification per version and no automatic installation occurs.

Test the packaged app after ZIP extraction on an Apple Silicon Mac and an Intel Mac, each on a supported macOS release. For Developer ID releases, validate signing, notarization/stapling, and first launch on a separate Mac. For ad hoc builds, follow the documented per-app security exception. Confirm Accessibility and optional Notifications permission flows independently.
