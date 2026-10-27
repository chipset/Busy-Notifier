# Meeting Busy

A native macOS menu bar app that shows a red **Busy** box at the upper left of the main display while a Webex, Microsoft Teams, Google Meet, or Zoom call is active. The box stays above ordinary windows, follows Spaces and full-screen apps, and does not intercept clicks or take keyboard focus. Requires macOS 13 or newer.

## Run

Open `dist/Meeting Busy.app`. On first launch, grant **Accessibility** access in System Settings → Privacy & Security → Accessibility. The app lives in the menu bar, with no Dock icon. If access is not picked up after enabling it, quit and reopen the app.

To rebuild with Xcode or the Swift command line tools:

```sh
./scripts/build-app.sh
open "dist/Meeting Busy.app"
```

The script builds for the current Mac's architecture and creates an ad hoc signed app. Keep it in a permanent location before enabling **Launch at login**. Rebuilds may require granting Accessibility access again. Distribution to other Macs requires a Developer ID signature and notarization.

The application icon is a white camera with a busy badge on a red gradient. `scripts/make-icon.swift` draws the vector artwork at standard macOS icon resolutions; the build script packages `AppIcon.icns` and exports `dist/AppIcon.png` for previewing. Changing the indicator color does not change the application icon or menu bar symbol.

## Behavior

- **Automatic:** polls every two seconds for active call controls, such as Leave call or End meeting. If the previous scan is still running, that tick is skipped, so detection can take longer with slow or numerous applications. Polling pauses during sleep. Merely opening Teams, Webex, a calendar invitation, or a meeting's prejoin page does not trigger the indicator.
- **Force Busy:** shows the indicator manually, including when a client does not expose its call controls.
- **I’m presenting — hide indicator:** hides immediately. Choose this before starting a presentation, then return to Automatic afterward.
- **Preview Busy for 5 seconds:** checks the indicator's appearance and placement. Presentation hiding takes precedence over previews and Force Busy.
- **Settings…:** changes the indicator text, color, size (50–250%), transparency (0–90%), display, and location. The color picker changes the box fill; text automatically uses black or white for contrast. Blank text uses “Busy”; longer messages automatically fit the box. Choose a corner or center preset, or use horizontal/vertical sliders for a custom position. Changes save automatically and survive relaunch, including appearance preferences from earlier versions. The preview is opt-in through **Show indicator preview**; opening Settings does not turn it on. Presentation hiding still takes precedence.

A preview is labeled **Preview** in the menu, including when Accessibility setup is needed. Stop it with **Stop preview**, by selecting a detection mode, by unchecking the preview in Settings, or by closing Settings (for the Settings preview). In Automatic mode, no permission and no explicit preview means no indicator; leaving a meeting clears the indicator on the next completed scan.

Stop sharing / Stop presenting controls automatically hide the indicator. Only your own sharing controls count; another participant presenting should not hide your Busy status. The app actually hides its window rather than relying on a window-capture exclusion flag.

## Detection coverage and limits

Native clients: Microsoft Teams (classic and current bundle IDs), Webex Meetings, Webex, and Zoom Workplace (`us.zoom.xos`). Browser meetings: Google Meet, Teams, Webex, and Zoom in Safari, Chrome, Edge, Firefox, Brave, and Arc, when the browser exposes meeting controls through macOS Accessibility. Zoom detection reads both enabled Meeting menu commands and host/participant call controls, including Stop Share. A recognized Zoom meeting window with multiple meeting toolbar controls also counts when the Leave button is hidden. A window title by itself does not count.

Detection currently recognizes **English control labels**. It inspects meeting application windows and web accessibility subtrees with a verified meeting-service URL, not arbitrary page text. It does not activate tabs or bring meeting windows to the front. Inactive browser tabs, minimized windows, hidden call toolbars, and client updates can prevent detection. Use Force Busy if needed.

Automatic presentation hiding is best effort. There may be a delay while the app reads sharing controls, and controls in an inactive tab or inaccessible toolbar can be missed. **For immediate hiding before sharing, choose I’m presenting.** This version cannot guarantee the indicator will never appear in captured frames when relying solely on automatic detection. Test your particular client before using it in a live presentation.

Accessibility reads happen in a background task with time and traversal limits. Attribute reads are batched, and breadth-first searches reach toolbars before deep chat history. A menu status reports incomplete scans. The app requests no microphone, camera, screen recording, or browser scripting permission; it records no meeting content and makes no network requests.

### Troubleshooting a missed meeting

Open **Settings… → Meeting detection → Detection details**. This shows the running app's version and path, Accessibility permission, application IDs, readable window/control counts, and scan failures. It does not include meeting titles or chat text. Zero controls or Accessibility errors indicate the app cannot inspect the client; zero meeting matches with readable controls indicates the client's UI does not match the current rules.

After rebuilding this locally signed app, macOS may invalidate its Accessibility authorization. Quit Meeting Busy, remove its old entry from System Settings → Privacy & Security → Accessibility, add the updated `dist/Meeting Busy.app`, enable it, and reopen that copy. Confirm **Automatic** is selected and **I’m presenting** is off. While troubleshooting, Force Busy provides a manual indicator.

A command-line diagnostic is also available (it reports the permissions of that invocation, which may differ in a restricted shell):

```sh
"dist/Meeting Busy.app/Contents/MacOS/MeetingBusy" --diagnose
```

## Verify

```sh
swift test
```

The unit tests cover call/prejoin distinctions, service URL validation, actionable controls versus page text, presentation controls, permission state, overrides, Zoom toolbar fallback, and indicator geometry/persistence. They do not simulate real conferencing clients.

Manual checks with Accessibility enabled:

1. Open each client without joining; no Busy box should appear.
2. Join a call, including one with camera and microphone off; the box should appear.
3. Switch apps and Spaces; the box should remain at the upper left on the main display.
4. Start and stop screen sharing; verify the box hides and returns. Repeat with the meeting browser tab in the background and check the manual presenting override.
5. Have another participant share; Busy should remain visible.
6. Leave the call; the box should disappear. Revoke Accessibility access and confirm the menu reports setup is needed.
7. Preview the box, change the main display, and test sleep/wake and Launch at login.
8. Change size, transparency, display, and position in Settings. Confirm changes apply immediately, stay on screen, and persist after quitting/reopening. Close Settings to end its preview.

## Implementation

`Sources/MeetingDetection` contains pure detection and display rules. `Sources/MeetingBusy` contains the AppKit menu, nonactivating overlay, and bounded Accessibility scanner. `scripts/build-app.sh` packages the executable and `Resources/Info.plist` into an app bundle. No external dependencies.

Apple references: [Accessibility API](https://developer.apple.com/documentation/applicationservices/1462085-axuielementcopyattributevalue), [window levels](https://developer.apple.com/documentation/appkit/nswindow/level-swift.property), and [window sharing behavior](https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum/none).

## License

Released under the [MIT License](LICENSE). Copyright © 2026 Thomas McQuitty.
