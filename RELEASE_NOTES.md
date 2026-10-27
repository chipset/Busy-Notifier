# Meeting Busy 0.2.0

Version update from 0.0.3 to 0.2.0 (build 14). Functionality is unchanged. Supports macOS 13 and newer, with one universal application for Apple Silicon and Intel Macs.

- Includes **Available — hide indicator** and timed Available modes for 15, 30, or 60 minutes. Hide false positives without marking yourself Presenting; return to Automatic whenever you want. Detection continues, while Available also hides previews.
- Includes opt-in browser integration for Google Meet, Microsoft Teams, Webex, and Zoom web calls in background tabs. A bundled local native messaging helper connects the extension to the app, including when Accessibility access is unavailable.
- Includes bridge installation/removal and connection status in Settings. Pause and per-service choices apply to both detection paths; stale browser connections expire rather than keeping Busy indefinitely.
- Retain appearance customization, presets, mouse/keyboard positioning, multiple displays, global shortcuts, presentation reminders, local logging, reports, and optional update checks.

## Installation and security

Download `MeetingBusy-0.2.0-universal.zip`, extract it, and move `Meeting Busy.app` to Applications. Grant Accessibility permission for native-client and Safari detection. Browser integration requires separate setup: enable it in Settings, install the selected browser bridge, and load the provided extension folder. Chrome, Edge, Brave, and Chromium use developer-mode unpacked loading. Firefox uses a temporary unsigned add-on that must be loaded again after restarting the browser. Safari continues to use Accessibility.

See [the user guide](https://github.com/chipset/Busy-Notifier/blob/v0.2.0/USER_GUIDE.md) and [browser setup](https://github.com/chipset/Busy-Notifier/blob/v0.2.0/BrowserExtension/README.md).

This build is **ad hoc signed and not Apple-notarized**. It has no Apple Developer ID signature. Only approve a copy you trust. Browser extensions are not published to extension stores. The optional extension requests access to supported provider sites and native messaging, and transmits only local service/call/sharing flags and ephemeral numeric tab/frame IDs. URLs, titles, names, chat, and raw control labels are not sent to the native host. Notifications are optional; no microphone, camera, or screen-recording access is requested.

## Validation and limitations

All 56 Swift tests and 11 JavaScript tests pass. The packaged native host also passes a real stdio protocol test. An isolated Chromium smoke test passes native-host communication, inactive-tab heartbeats, leaving/sharing, pause/resume, and tab closure using synthetic meeting controls; it does not simulate renderer throttling or real provider sessions. Universal app/helper architectures and signature integrity are checked during packaging. Live meeting-client, Firefox, VoiceOver, multi-display, and notification checks still need manual validation. Cross-compilation does not substitute for testing on an Intel Mac.

Detection currently uses English controls. The extension improves inactive-tab coverage; frozen/discarded pages, inaccessible controls, and client changes can still prevent detection. Automatic screen-sharing hiding is best effort; choose Presenting before sharing for immediate hiding. Pausing or disabling a service also stops its automatic sharing checks. Logs and reports stay local unless exported and shared. Optional update checks contact GitHub; updates require manual installation.
