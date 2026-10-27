# Meeting Busy 0.0.2

Development release for macOS 13 and newer, with one universal application for Apple Silicon and Intel Macs.

- Detect supported Zoom, Microsoft Teams, Webex, and Google Meet calls and show a floating status indicator.
- Pause automatic detection for 15 minutes, one hour, or until resumed, with independent service switches.
- Customize text, color, transparency, size, position, display selection, and saved appearance presets.
- Move the indicator by mouse or keyboard, including VoiceOver controls, and show it on every display.
- Use configurable global shortcuts, timed Busy modes, and optional presentation reminders.
- Review and save local reports for incorrect detections; diagnostic logs rotate locally and can be exported or cleared.
- Optionally check GitHub for updates and receive update notifications.

## Installation and security

Download `MeetingBusy-0.0.2-universal.zip`, extract it, and move `Meeting Busy.app` to Applications. Grant Accessibility permission for automatic detection. See [the user guide](https://github.com/chipset/Busy-Notifier/blob/v0.0.2/USER_GUIDE.md) for installation, per-app macOS security approval, usage, and troubleshooting.

This build is **ad hoc signed and not Apple-notarized**. It has no Apple Developer ID signature. Only approve a copy you trust. Notifications are optional; the app does not request microphone, camera, or screen-recording access.

## Validation and limitations

All 46 automated tests pass. Universal packaging, code-signature integrity, and the archive checksum have been checked. Live meeting-client, VoiceOver, multi-display, and notification checks still need manual validation. Cross-compilation does not substitute for testing on an Intel Mac.

Detection currently uses English controls and may miss hidden browser tabs or inaccessible meeting toolbars. Automatic screen-sharing hiding is best effort; choose Presenting before sharing when immediate hiding is needed. Pausing or disabling a service also stops its automatic sharing checks.

Logs and reports stay local unless you export and share them. Optional update checks contact GitHub. Updates require manual download and installation.
