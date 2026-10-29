# Unreleased

- Right-clicking the indicator can now hide it (15 minutes, 1 hour, or until Automatic) in addition to moving it.
- Safari temporary extension pairs automatically after an Allow prompt in the app; pairing uses a per-install secret instead of the build-wide token. Manual codes still work.
- Detection: Teams and Meet no longer treat a mid-call "New meeting"/"Join a meeting" button as the call ending; Webex combined leave/end labels now work in browsers. A parity test keeps the Swift and JavaScript phrase lists identical.
- The page scanner is throttled; Safari updates reach the indicator immediately; stale snapshot files are pruned; the Accessibility fallback scan slows down while the extension is reporting and nothing is active.
- The menu reports when the browser extension stops reporting. A second launch now hands over to the running copy instead of fighting over the Safari bridge port.
- Adds GitHub Actions CI for the Swift and JavaScript tests.

# Meeting Busy 0.4.1

Safari setup preview addressing the 0.4.0 extension not appearing in Safari Settings even when unsigned extensions are allowed. Safari can reject the embedded ad hoc native bundle with a code-signing-dictionary error; registering it in PlugInKit does not prove Safari accepts it.

- Adds Meeting Busy (Temporary), loaded through Safari Settings → Developer → Add Temporary Extension. It does not use the bundled native handler or require a certificate.
- Adds Open Safari extension folder and Copy Safari pairing code to the Mac app. Pair in the temporary extension popup, then connect open meeting tabs.
- Uses authenticated loopback requests with a token stored only in extension-local storage. Ordinary webpage origins remain blocked; Safari-extension CORS preflights never write state.
- Keeps the existing call classifier, background heartbeat, service filtering, pause, sharing hiding, and stale-evidence expiry.

Update and open the new Mac app, load the temporary Safari folder or ZIP, allow supported sites and local-bridge access, then paste the app's pairing code into the popup. Safari removes temporary extensions after 24 hours or when it quits. Pair again after app updates. This route requires Safari's Add Temporary Extension option.

This is an ad hoc signed local preview, not notarized. It requires no paid Apple Developer account. Automated tests cover pairing, authentication, origin validation, preflight behavior, state filtering, native handling, and packaging; Safari 27 temporary-extension visibility has been confirmed by the user, and the app has received a fresh browser heartbeat. A real meeting check remains interactive.
