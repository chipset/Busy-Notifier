# Meeting Busy 0.3.0

This release adds setup checks, safer presentation recovery, per-display placement, and broader control-label coverage for macOS 13 and newer.

- Settings now shows Accessibility and browser connection status, enabled services, the current detection result, and a live-test workflow. You can check immediately, preview Busy, test Presenting, and return to Automatic.
- Optional automatic return from manual Presenting requires an observed own-sharing control followed by three complete checks confirming the same call continues without sharing. Uncertain checks leave Presenting selected.
- When showing on every display, each display can have its own position and visibility. Existing appearance settings and presets remain compatible.
- Native and browser detection recognize a limited set of Spanish, French, and German leave and own-sharing controls in addition to English. Live-client verification remains necessary because providers can change labels.
- Browser extension ZIPs can be produced with `./scripts/package-browser-extensions.sh` for local installation. Firefox requires unlisted Mozilla signing for an extension that survives restart; no public listing is planned.

## Installation and security

Download `MeetingBusy-0.3.0-universal.zip`, extract it, and move `Meeting Busy.app` to Applications. Grant Accessibility permission for native clients and Safari. Optional browser detection requires a separate bridge and extension installation. The app asks for no microphone, camera, or screen-recording permission; it records no meeting content.

This direct-download development archive is ad hoc signed and is not notarized. The release script can create a Developer ID signed and notarized archive when the publisher supplies a valid signing identity and Keychain notary profile. No Mac App Store submission is involved.

## Validation and limits

Automated Swift and JavaScript tests and a universal package build pass. Live meeting-client, Firefox, VoiceOver, multi-display, and screen-sharing checks still need manual validation. Detection is best effort; choose Presenting before sharing when immediate hiding matters. New clients such as FaceTime and Slack huddles are not enabled without verified live control fixtures.
