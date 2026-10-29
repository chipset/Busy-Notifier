# Meeting Busy 0.4.2

Preview release building on 0.4.1's Safari temporary extension. Automated tests pass; a real Safari meeting and own-sharing check is still outstanding (see MANUAL_TESTS.md).

- Right-clicking the indicator can now hide it (15 minutes, 1 hour, or until Automatic) in addition to moving it.
- Safari temporary extension pairs automatically after an Allow prompt in the app; pairing uses a per-install secret instead of the build-wide token. Manual codes still work.
- Detection: Teams and Meet no longer treat a mid-call "New meeting"/"Join a meeting" button as the call ending; Webex combined leave/end labels now work in browsers. A parity test keeps the Swift and JavaScript phrase lists identical.
- The page scanner is throttled; Safari updates reach the indicator immediately; stale snapshot files are pruned; the Accessibility fallback scan slows down while the extension is reporting and nothing is active.
- The menu reports when the browser extension stops reporting. A second launch now hands over to the running copy instead of fighting over the Safari bridge port.
- Adds GitHub Actions CI for the Swift and JavaScript tests.

Safari: open the new Mac app, add the temporary extension folder or ZIP as before, then choose **Pair automatically** in its popup and click **Allow** in Meeting Busy. A pairing made with 0.4.1 will not carry over. Safari removes temporary extensions on quit or after 24 hours.

This is an ad hoc signed preview, not notarized, and requires no paid Apple Developer account. After an update macOS may ask for Accessibility access again; only repair it if the app reports access denied. Intel Macs and older Safari versions have not been verified.
