# Meeting Busy 0.3.1

This maintenance release moves the project's GitHub home to `chipset/Meeting-Busy` and updates the in-app release checker to use and trust the new repository URL. Meeting detection and indicator behavior are unchanged from 0.3.0.

Version 0.3.0 may not announce this update automatically because its release-link validation expects the old repository path. Download 0.3.1 directly from this release page, then future update checks will use the new location.

## Installation and security

Download `MeetingBusy-0.3.1-universal.zip`, extract it, and move `Meeting Busy.app` to Applications. Grant Accessibility permission for native clients and Safari. Optional browser detection requires separate bridge and extension installation. The browser extension ZIPs are included for direct distribution; the unsigned Firefox ZIP is temporary until Mozilla signs an unlisted XPI.

This direct-download build is ad hoc signed and is not notarized. The release script supports Developer ID signing and notarization when a signing identity and notary profile are available. No Mac App Store submission is involved.

## Validation and limits

Automated Swift and JavaScript tests, native-host protocol checks, and universal packaging are required before publication. Live meeting-client, Firefox, VoiceOver, multi-display, and screen-sharing checks remain manual. Detection is best effort; choose Presenting before sharing when immediate hiding matters.
