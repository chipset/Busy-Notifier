# Meeting Busy

A native macOS menu bar app that shows a **Busy** box while a Webex, Microsoft Teams, Google Meet, or Zoom call is active. Its default is red at the upper left of the main display; text, color, size, transparency, and display placement are customizable. The box stays above ordinary windows, follows Spaces and full-screen apps, and can be repositioned without taking keyboard focus. Requires macOS 13 or newer.

Start with the [user guide](USER_GUIDE.md) for installation, macOS security prompts, Accessibility permission, settings, and troubleshooting.

## Run

Open `dist/Meeting Busy.app`. Grant **Accessibility** access in System Settings → Privacy & Security → Accessibility for native-client and Safari detection. The optional Chromium/Firefox browser extension can detect supported browser meetings without that permission. The app lives in the menu bar, with no Dock icon. If access is not picked up after enabling it, quit and reopen the app.

To rebuild with Xcode or the Swift command line tools:

```sh
./scripts/build-app.sh
open "dist/Meeting Busy.app"
```

The script builds a universal app for Apple Silicon and Intel by default; `./scripts/build-app.sh debug native` builds only for the current Mac. Default builds are ad hoc signed. Keep the app in a permanent location before enabling **Launch at login**. Rebuilds may require granting Accessibility access again. A Developer ID certificate and notarization credentials are not included; see [releasing instructions](RELEASING.md) for identified-developer builds and the [first-launch security instructions](USER_GUIDE.md#open-a-build-that-macos-blocks) for development builds.

Ad hoc signatures identify a particular build, so macOS may treat each changed build as a new app for Accessibility permission. The app can open the permission prompt but cannot silently approve itself. To avoid repeated approval on ordinary direct-download updates, sign releases with the same **Developer ID Application** identity and keep the bundle identifier and installed path stable. Switching from an ad hoc build to a Developer ID build may require one more approval. See [permission repair](USER_GUIDE.md#update-or-repair-permissions) if access is lost. [Apple: code identity across versions](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)

The application icon is a white camera with a busy badge on a red gradient. `scripts/make-icon.swift` draws the vector artwork at standard macOS icon resolutions; the build script packages `AppIcon.icns` and exports `dist/AppIcon.png` for previewing. Changing the indicator color does not change the application icon or menu bar symbol.

## Behavior

- **Automatic:** polls every two seconds for active call controls, such as Leave call or End meeting. If the previous scan is still running, that tick is skipped, so detection can take longer with slow or numerous applications. Polling pauses during sleep. Merely opening Teams, Webex, a calendar invitation, or a meeting's prejoin page does not trigger the indicator.
- **Available — hide indicator:** hides a false-positive indicator without marking you Presenting. **Available for…** offers 15, 30, or 60 minutes, then returns to Automatic. Detection continues; Available also suppresses previews. Select Automatic to end it early. Manual overrides reset on app relaunch.
- **Force Busy:** shows the indicator manually, including when a client does not expose its call controls.
- **Busy for…:** shows Busy for 15, 30, or 60 minutes, then returns to Automatic. The menu shows the end time; sleep does not extend the deadline.
- **Pause detection:** stops automatic scans for 15 minutes, one hour, or until resumed. Pauses survive relaunch and expire across sleep. Force Busy, manual Presenting, and explicit previews remain available. Pausing also stops automatic sharing detection, so use manual Presenting before sharing.
- **Meeting services:** independently enables Zoom, Teams, Webex, and Google Meet for native/browser detection. Turning a service off clears old evidence and discards pending results from the previous configuration. With all services off, the app explicitly reports that state.
- **I’m presenting — hide indicator:** hides immediately. Choose this before starting a presentation, then return to Automatic afterward.
- **Preview Busy for 5 seconds:** checks the indicator's appearance and placement. Presentation hiding takes precedence over previews and Force Busy.
- **Settings…:** changes the indicator text, color, size (50–250%), transparency (0–90%), display, and location. The color picker changes the box fill; text automatically uses black or white for contrast. Blank text uses “Busy”; longer messages automatically fit the box. Choose a corner or center preset, or use horizontal/vertical sliders for a custom position. Changes save automatically and survive relaunch, including appearance preferences from earlier versions. The preview is opt-in through **Show indicator preview**; opening Settings does not turn it on. Presentation hiding still takes precedence.

A preview is labeled **Preview** in the menu, including when Accessibility setup is needed. Stop it with **Stop preview**, by selecting a detection mode, by unchecking the preview in Settings, or by closing Settings (for the Settings preview). In Automatic mode, no permission and no explicit preview means no indicator; leaving a meeting clears the indicator on the next completed scan.

Settings also includes configurable global shortcuts (defaults: Control–Option–Command–1 Automatic, –2 Busy, –3 Presenting), presentation reminders, local diagnostic logging, and daily GitHub update checks. Choose each shortcut's key and modifiers; duplicate/unmodified combinations are rejected, and registration conflicts are identified. Presenting is explicitly shown in the menu bar until you change modes. The menu and Settings show the last check time/duration; detection details explain the signal used.

The top of Settings shows setup and live-test status: Accessibility permission, browser connection, enabled services, the latest detection result, and controls to check now, preview Busy, test Presenting, and return to Automatic. Optional **Return to Automatic after sharing stops** only acts after the app observed your own sharing control and then receives three complete checks of the same continuing call without sharing. If checks are incomplete or the call disappears, manual Presenting stays active.

To move the visible box, **right-click → Move indicator**, then drag it with the left mouse button and release. Control-click also opens this menu. The new position and display save automatically and appear in Settings. Dropping near an edge keeps the entire indicator within the display's usable area. Right-click again and choose **Cancel move** to leave move mode without dragging. When outside a meeting, enable the Settings preview to position it.

**Move indicator using the keyboard…** is available in the menu, Settings, context menu, and the indicator's accessibility custom action. Arrows move 10 points, Shift+arrows 50, and Option+arrows 1. Directional buttons are also provided. Return/Escape finishes. A temporary preview starts if needed and ends with the movement session; Presenting still hides the indicator. Every move saves immediately.

**Show on every display** can render an indicator on each connected display. Otherwise the selected display is used, with fallback to the main display. Each display can have its own position and visibility; displays without an override use the global location. Dragging an indicator saves that display's position. Disconnected/unused indicator windows are closed.

**Appearance presets** save full text/color/size/transparency/location/display settings locally. Meeting, Recording, and Do not disturb are supplied initially. Save with an existing name to update a preset, apply it from Settings or the menu, or delete it. Presets do not change detection mode or start recording. Existing appearance settings are preserved on upgrade.

**This detection is incorrect…** opens an editable report with version/build, macOS version, detection state, enabled services, signals, last scan time, and error codes. Review and save it locally before sharing yourself. It excludes meeting content, custom text, user paths, and logs. No report is uploaded automatically, and its contents are not written to diagnostic logs.

Stop sharing / Stop presenting controls automatically hide the indicator. Only your own sharing controls count; another participant presenting should not hide your Busy status. The app actually hides its window rather than relying on a window-capture exclusion flag.

## Detection coverage and limits

Optional **Settings → Browser integration** adds a local native-messaging extension for Chrome, Edge, Brave, Chromium, and Firefox. Its purpose is to detect calls and your own screen sharing in inactive meeting tabs, which Accessibility can miss. Native clients and Safari still need Accessibility; **there is no Safari extension**. Follow the [browser setup instructions](BrowserExtension/README.md); enabling the setting alone does not install the extension. Firefox currently uses temporary unsigned add-on loading and must be reloaded after browser restart. This is a developer extension, not a store-published extension.

The extension sends only provider and call/sharing flags with an ephemeral tab/frame ID to the bundled local host. Background heartbeats run every five seconds; the app reads them every two seconds. On disconnect, stale browser evidence expires after 20 seconds. Pause and service switches apply to both detection paths. No meeting content or URLs are written to the bridge. Frozen/discarded pages and changed controls can still prevent detection; live-client testing is necessary.

Native clients: Microsoft Teams (classic and current bundle IDs), Webex Meetings, Webex, and Zoom Workplace (`us.zoom.xos`). Browser meetings: Google Meet, Teams, Webex, and Zoom in Safari, Chrome, Edge, Firefox, Brave, and Arc, when the browser exposes meeting controls through macOS Accessibility. Zoom detection reads host/participant call controls, including Stop Share. Enabled Meeting menu commands only corroborate an actual meeting window and its controls; they cannot keep Busy active on their own after a call ends. A recognized Zoom meeting window with multiple meeting toolbar controls also counts when the Leave button is hidden. A window title by itself does not count.

Detection recognizes **English controls and a limited set of Spanish, French, and German leave/share controls**. It inspects meeting application windows and web accessibility subtrees with a verified meeting-service URL, not arbitrary page text. It does not activate tabs or bring meeting windows to the front. Without the extension, inactive browser tabs can be missed. Minimized windows, frozen pages, hidden call toolbars, and client updates can prevent detection. Use Force Busy if needed.

Automatic presentation hiding is best effort. There may be a delay while the app reads sharing controls, and controls in an inactive tab or inaccessible toolbar can be missed. **For immediate hiding before sharing, choose I’m presenting.** This version cannot guarantee the indicator will never appear in captured frames when relying solely on automatic detection. Test your particular client before using it in a live presentation.

Accessibility reads happen concurrently across apps in background tasks with time and traversal limits. Attribute reads are batched, and breadth-first searches reach toolbars before deep chat history. A menu status reports incomplete scans. Old positive results expire after 12 seconds if no new scan result arrives. The app requests no microphone, camera, or screen recording permission. The optional browser extension requests access to supported meeting sites and script injection there. It records no meeting content. Only optional/manual update checks contact GitHub; notifications are separately opt-in.

Diagnostic logging defaults to state changes. Settings can disable it or enable every-scan details, open the folder, export, or clear logs. Logs are structured local JSON Lines under `~/Library/Logs/MeetingBusy`, limited to a current file plus three backups at 512 KiB each. They contain event times, services, detection signals, permission state, error codes, and scan durations. No titles, participant names, chats, URLs, indicator text, or user paths are logged. Meeting activity times may still be sensitive; exports are only saved where the user chooses and are never uploaded automatically.

Update checks read the latest stable release in `chipset/Meeting-Busy` on GitHub, at most daily when enabled, or when Check for updates is selected. The app validates versions and release URLs and opens the release page for manual download/installation. With no published GitHub release it reports that none is available. Source commits alone do not create app updates.

### Troubleshooting a missed meeting

Open **Settings… → Meeting detection → Detection details**. This shows the running app's version and path, Accessibility permission, application IDs, readable window/control counts, and scan failures. It does not include meeting titles or chat text. Zero controls or Accessibility errors indicate the app cannot inspect the client; zero meeting matches with readable controls indicates the client's UI does not match the current rules.

After updating an ad hoc signed build, first reopen Meeting Busy and check Accessibility status in Settings. If access is denied, quit, remove its old entry from System Settings → Privacy & Security → Accessibility, add the updated `dist/Meeting Busy.app`, enable it, and reopen that copy. Confirm **Automatic** is selected and **I’m presenting** is off. While troubleshooting, Force Busy provides a manual indicator.

A command-line diagnostic is also available (it reports the permissions of that invocation, which may differ in a restricted shell):

```sh
"dist/Meeting Busy.app/Contents/MacOS/MeetingBusy" --diagnose
```

## Verify

```sh
swift test
node --test BrowserExtension/tests/*.test.cjs
```

The unit tests cover call/prejoin distinctions, service URL validation, actionable controls versus page text, presentation controls and guarded auto-return, permission state, overrides, Zoom post-call/menu behavior, stale evidence, timers, release versions/URLs, log rotation and schemas, and per-display placement/persistence. They do not simulate real conferencing clients. See [manual acceptance checks](MANUAL_TESTS.md) for the live-client and interactive release checks that remain necessary.

Manual checks with Accessibility enabled:

1. Open each client without joining; no Busy box should appear.
2. Join a call, including one with camera and microphone off; the box should appear.
3. Switch apps and Spaces; the box should remain at its configured position on the selected displays.
4. Start and stop screen sharing; verify automatic hiding and return. Repeat with the meeting browser tab in the background and check manual Presenting and its optional auto-return setting.
5. Have another participant share; Busy should remain visible.
6. Leave the call; the box should disappear. Revoke Accessibility access and confirm the menu reports setup is needed.
7. Preview the box, change the main display, and test sleep/wake and Launch at login.
8. Change size, transparency, display, per-display visibility, and position in Settings. Confirm changes apply immediately, stay on screen, and persist after quitting/reopening. Close Settings to end its preview.
9. Right-click the indicator, choose Move indicator, and drag it within and between displays. Confirm it does not snap back during a scan, retains its position after relaunch, and still hides when presenting. Check Control-click and Cancel move as well.

## Implementation

`Sources/MeetingDetection` contains detection/display rules, manual mode/timer state, release validation, and structured logging. `Sources/MeetingBusy` contains the AppKit menu, overlay, Accessibility scanner, settings, hotkeys, notifications, and update checks. `scripts/build-app.sh` packages a universal executable and `Resources/Info.plist` into an app bundle. `scripts/package-release.sh` creates ZIP/checksum artifacts and optionally notarizes them. No external package dependencies.

Apple references: [Accessibility API](https://developer.apple.com/documentation/applicationservices/1462085-axuielementcopyattributevalue), [window levels](https://developer.apple.com/documentation/appkit/nswindow/level-swift.property), and [window sharing behavior](https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum/none).

## License

Released under the [MIT License](LICENSE). Copyright © 2026 Thomas McQuitty.
