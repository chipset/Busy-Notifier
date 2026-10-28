# Meeting Busy 0.4.0

Safari local test build for macOS 13 and newer. No paid Apple Developer membership is required for this ad hoc signed development workflow.

- Adds an embedded Safari web extension for Google Meet, Teams, Webex, and Zoom call and own-sharing detection in inactive tabs. The macOS Safari background page stays persistent so its heartbeat is independent of inactive tab timers.
- Adds Safari to Settings → Browser integration, with a button to open Safari extension settings and local-bridge status.
- Uses a sandboxed native handler and authenticated IPv4 loopback bridge. Only provider, ephemeral frame IDs, and call/sharing flags reach the app. No audio, video, URLs, titles, participants, or chat are transmitted.
- Pause, service switches, stale evidence expiry, Available, and Presenting work with Safari as with the other supported browsers. Native-client Accessibility detection remains available.

## Enable Safari

Move Meeting Busy.app to Applications, quit old copies, and open the app. Enable browser integration and select Safari in Settings. In Safari Settings → Advanced, enable Show features for web developers. In Settings → Developer, allow unsigned extensions. Then enable Meeting Busy under Extensions and allow its supported meeting sites. Open the extension popup and choose Connect open meeting tabs, or reload meeting tabs.

Safari resets Allow unsigned extensions when it quits. Repeat that approval after every Safari restart. The app cannot bypass this Safari requirement. Safari 16 uses Develop → Allow Unsigned Extensions instead.

## Build status

This preview is ad hoc signed and not notarized. It is for local testing outside the Mac App Store. It does not require Apple account credentials or a fee. Automated tests cover the shared detector, Safari message transport, real sandboxed native handler, authenticated loopback bridge, policy filtering, and universal packaging. Interactive Safari and real meeting-client acceptance checks remain necessary; this build is not presented as live-client verified. Choose Presenting before sharing when immediate hiding matters.
