# Meeting Busy 0.4.3

Small preview update to 0.4.2. A real Safari meeting and own-sharing check is still outstanding (see MANUAL_TESTS.md).

- **Grant Accessibility access…** now shows either the macOS permission dialog or System Settings, not both. The first request shows the system dialog (which also lists the app under Accessibility); later requests open the Accessibility pane directly.

Everything in 0.4.2 is included: automatic Safari pairing with an Allow prompt, right-click hide options on the indicator, detection parity fixes, and the extension-stopped-reporting status. Safari removes temporary extensions on quit or after 24 hours; pair again with **Pair automatically** when needed.

This is an ad hoc signed preview, not notarized, and requires no paid Apple Developer account. After an update macOS may ask for Accessibility access again; only repair it if the app reports access denied. Intel Macs and older Safari versions have not been verified.
