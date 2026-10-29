# Meeting Busy user guide

Meeting Busy shows a small status box while you are in a Zoom, Webex, Microsoft Teams, or Google Meet meeting. It runs in the macOS menu bar and lets you change the box's text, color, size, location, and transparency.

This is a development application. Automatic meeting and presentation detection is best effort, and some client versions or hidden browser tabs may not expose the controls it needs.

## Install the application

You need macOS 13 or newer. The default universal build supports both Apple Silicon and Intel Macs. A build specifically marked native only supports the processor used to build it.

1. Obtain `Meeting Busy.app` from a source you trust. If it arrives in a ZIP archive, double-click the ZIP to extract it.
2. Drag `Meeting Busy.app` into your **Applications** folder.
3. Open the copy in Applications. Keep this copy in the same location, especially if you plan to enable launch at login.

If you downloaded the repository's source code, it does not contain a ready-to-run app: generated applications are excluded from Git. Follow [Build from source](#build-from-source), then copy the resulting app to Applications.

## Open a build that macOS blocks

The supplied build script applies an **ad hoc signature**, which is a local signature without an Apple-verified developer identity. The application is **not signed with an Apple Developer ID and is not notarized by Apple**. A valid local signature does not establish who published the app or mean Apple has checked it for malware.

If you trust the source and macOS blocks the first launch because the developer cannot be verified or Apple cannot check it:

1. Attempt to open `Meeting Busy.app` in Finder, then dismiss the warning.
2. Open **System Settings → Privacy & Security**.
3. Scroll to **Security** and find the message about Meeting Busy.
4. Click **Open Anyway**, authenticate if requested, then confirm **Open**.

This creates an exception for that app. Do not disable Gatekeeper system-wide or remove quarantine flags to install it. If macOS reports known malware or says the app is damaged, stop and obtain a fresh copy from the maintainer. On a managed work Mac, contact IT if these options are restricted. See [Apple's guidance on safely opening apps](https://support.apple.com/en-us/102445).

## Grant Accessibility access

The security exception above and Accessibility permission are separate approvals. Automatic native-client and browser detection without an extension needs **Accessibility** permission to inspect other apps' user interfaces. This is a broad permission that can allow an app to read and control other apps, so grant it only to a copy you trust. Meeting Busy uses it to inspect supported meeting apps and browser controls. [Apple explains Accessibility access here](https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac).

1. In Meeting Busy's welcome dialog, select **Grant Accessibility access**. You can also choose **Grant Accessibility access…** from its menu bar menu. The first time, macOS shows its own permission dialog (use its **Open System Settings** button); after that the command opens System Settings directly.
2. In **System Settings → Privacy & Security → Accessibility**, turn on **Meeting Busy**.
3. If it is missing, click **+**, select `/Applications/Meeting Busy.app`, and click **Open**, then enable its switch.
4. Quit and reopen Meeting Busy if its menu still says **Setup needed: Accessibility access**.

This implementation does not request microphone, camera, screen recording, or Full Disk Access permission. The optional browser extension separately requests access to supported meeting sites and script injection there. It does not record meeting audio/video or send meeting information over the network. Optional update checks contact GitHub, and optional reminders request macOS Notifications permission. Appearance settings are saved locally. Detection details show application paths and scan statistics, so review that text before sharing it for troubleshooting.

You can revoke access at any time by turning off Meeting Busy in the same Accessibility settings. Accessibility detection then stops; a connected browser extension can still detect browser meetings; manual Force Busy and explicit previews can still show the indicator.

Settings starts with **Setup and live test**. Check Accessibility there, then optionally install the browser bridge and extension below. Join a call and choose **Check now**; the result should change to **In a meeting**. Use **Preview Busy for 5 seconds** to check appearance and **Test Presenting** to check hiding. Choose **Return to Automatic** when finished.

## Tell whether the app is running

Choose **About & setup…** from the menu bar menu to see the application version and build number. Quit and reopen after updating to run the newly installed version.

Look for a **video camera symbol in the menu bar**, usually near the upper right of the screen. Meeting Busy does not have a Dock icon. The red camera application icon in Finder is the icon used to launch it.

Click the menu bar symbol and read the first line:

| Status | Meaning |
| --- | --- |
| In a meeting: Zoom, Teams, Webex, or Google Meet | A supported meeting was detected. |
| No active meeting detected | The app is running and currently has no meeting evidence. |
| Setup needed: Accessibility access | Automatic detection cannot run until permission is granted. |
| Available — hide indicator | You have temporarily hidden the indicator; detection continues. |
| Busy — manual override | Force Busy is selected; the indicator can stay visible after a meeting ends. |
| Preview… | You explicitly enabled a preview; its visibility does not mean a meeting was detected. |
| Presenting / Screen sharing detected | The indicator is hidden. |
| Unable to inspect some meeting windows | A client could not be read or the scan reached a limit. |
| Detection paused… | Automatic scans are stopped until the deadline or until you resume. |
| All meeting services are disabled | Enable at least one service to use automatic detection. |

The camera symbol is filled while the indicator is visible. A presentation symbol appears while presentation hiding is active. Read the menu status to distinguish an actual meeting from a manual indicator or preview.

## Use it during meetings

Select **Automatic** from the menu bar menu for normal use. It checks every two seconds while awake. If a previous scan is still running, that tick is skipped, so detection can take longer. Joining or leaving a meeting takes effect after a completed scan.

Opening a meeting app or its prejoin screen should not show the indicator. English controls and a limited set of Spanish, French, and German leave/share controls are supported. Hidden controls and changes to meeting clients can cause missed detections. The optional browser extension improves inactive-tab detection.

Use **Force Busy** to display your status manually. Return to **Automatic** when finished. Selecting a detection mode also stops any preview.

For a temporary indicator, choose **Busy for… → 15, 30, or 60 minutes**. The menu shows when it ends and then returns to Automatic, including after sleeping through the deadline. Changing modes cancels the timer. Manual modes and timers reset to Automatic when the app is relaunched.

The menu shows the last completed scan time and duration. Settings' detection details also identify the reason for a meeting match, such as active call controls or your stop-sharing control. A stale positive result expires if scans stop completing; closing or leaving a call clears its evidence on the next scan.

## Hide a false-positive indicator with Available

Choose **Available — hide indicator** to hide the box immediately without marking yourself Presenting. Choose **Available for… → 15, 30, or 60 minutes** for automatic expiry. The menu bar shows Available and the menu shows its end time. Detection continues in the background, and previews are hidden too. Return to **Automatic** to end the override early. At expiry, the current meeting state determines visibility. Overrides reset to Automatic after relaunch.

## Detect meetings in background browser tabs

Open **Settings → Browser integration**, enable the extension setting, select your browser, and click **Install/update bridge**. Then click **Open extension folder** and load that folder through your browser's extension manager. Follow the [complete browser installation and privacy instructions](BrowserExtension/README.md).

Chrome, Edge, Brave, and Chromium use an unpacked developer extension. Firefox uses a temporary unsigned add-on that must be reloaded after each browser restart. Safari: in the app choose Open Safari extension folder, then use Safari Settings → Developer → Add Temporary Extension to load it. Open the temporary extension popup, choose Pair automatically, and click Allow when Meeting Busy asks (a manual pairing code is also available in the app). Allow supported sites and the local bridge. Safari removes temporary extensions on quit or after 24 hours. No paid developer account is needed for this workflow. The bundled ad hoc native extension can fail to appear in Safari, so use the temporary version if it is missing. Safari Accessibility detection remains available as a fallback. Place the app in Applications before bridge installation. After an update or move, reinstall the bridge and reload the extension. Managed browsers may restrict developer extensions.

The extension can detect supported browser controls without Accessibility; native clients still need it. It sends only local provider/call/sharing flags with an ephemeral tab/frame ID. Its five-second background heartbeat is independent of inactive-tab timers; the app reads state every two seconds. Tab close/navigation clears its contribution. Crashed/disconnected state expires after 20 seconds plus the next app poll. Frozen or discarded pages and changed controls may still cause misses. Test your client, and choose Presenting before sharing for immediate hiding.

## Pause detection or choose meeting services

Choose **Pause detection → 15 minutes, 1 hour, or Until resumed** from the menu. Resume early with **Resume detection**. Pauses survive quitting/reopening, and timed pauses resume after their deadline, including after sleep. The menu bar says Paused while a pause is active.

Pause stops automatic meeting and screen-sharing checks. It hides the automatic indicator and discards in-progress detection results. Force Busy, Presenting, and explicit previews remain available. Selecting Automatic does not cancel a pause; choose Resume detection to restart checks. Use manual Presenting before sharing while scans are paused.

Under **Meeting services** in the menu, or **Settings… → Automatic detection**, turn Zoom, Teams, Webex, and Google Meet on or off individually. This applies to native clients and browser meetings. Disabled services are ignored, including their sharing controls. Turning services off clears previous evidence. With all services off, automatic detection stays disabled until you turn one on. Choices save automatically.

## Hide the indicator before presenting

Before sharing your screen, choose **I’m presenting — hide indicator** from the menu. The indicator hides immediately. After sharing ends, return to **Automatic**.

The app also tries to hide automatically when it finds your Stop sharing, Stop Share, or Stop presenting control. This can be delayed or missed, so use the manual presenting option before sharing when it matters that the box does not appear to your audience. Another participant presenting should not hide your status. Presentation hiding takes precedence over Force Busy and previews.

While manual Presenting is selected, the menu bar explicitly says **Presenting** and the menu shows how long it has been active. In Settings, optionally enable **Remind me to return to Automatic** and select a delay. Approve Notifications permission if requested. The reminder offers a Return to Automatic action; it never turns your indicator back on by itself. If notifications are denied or silenced, use the menu bar reminder and switch modes manually.

You can also enable **Return to Automatic after sharing stops**. This only acts if Meeting Busy first detects your own sharing control, then sees the same call still active without sharing on three complete checks. If the call disappears or checks are incomplete, Presenting remains selected. Leave this option off if you prefer to switch back manually.

## Keyboard shortcuts

Enable **Settings… → Keyboard shortcuts → Enable global shortcuts**. These work while another app is active:

| Shortcut | Action |
| --- | --- |
| Control–Option–Command–1 | Automatic |
| Control–Option–Command–2 | Force Busy |
| Control–Option–Command–3 | Presenting |

These are the defaults. In Settings, choose each action's key and Command/Option/Control/Shift modifiers. Each shortcut needs Command, Option, or Control, and a different combination from the other actions. Letter/number choices use standard ANSI key positions. **Reset shortcuts** restores the defaults. Changes save automatically and apply immediately when shortcuts are enabled.

The Settings status identifies registration failures. Invalid or conflicting configurations leave all global shortcuts unregistered until corrected; the menu remains usable. Choose another combination, disable the conflicting shortcut in the other app, or leave global shortcuts off. Shortcuts do not require Input Monitoring permission.

## Customize the indicator

Open the menu bar menu and choose **Settings…**.

| Setting | How to use it |
| --- | --- |
| Indicator text | Enter your message, such as “In a meeting.” Blank text falls back to “Busy.” Longer messages fit within the box. |
| Indicator color | Choose the box's background color. Text automatically switches between black and white for contrast. |
| Size | Choose 50–250% of the default size. |
| Transparency | 0% is solid; 90% is almost transparent. |
| Display | Choose the main display or a connected display. An unavailable display falls back to the main display. |
| Show on every display | Show one indicator on each connected display; set each display's position and visibility separately below. |
| Location | Use a corner/center button, the horizontal and vertical sliders, or the indicator's right-click Move option. |
| Restore default appearance | Reset the message, color, size, transparency, display choice, and location. |

Changes save automatically and survive quitting the app. Changing the indicator color does not change the application launch icon.

Choose an **Appearance preset**, then click Apply preset. Starter presets are Meeting, Recording, and Do not disturb. To save your own, enter a name under **Save current appearance as** and click Save preset. An existing name updates that preset. Delete preset removes the selected preset. The menu's **Appearance presets** submenu applies saved styles quickly.

Presets include text, color, size, transparency, position, display selection, and the every-display setting. They do not change detection mode, enable recording, or change macOS Focus. To use a Recording style outside a meeting, apply it and select Force Busy. Restore default appearance resets the current indicator but keeps saved presets.

To move the box directly:

1. Right-click the visible indicator (or Control-click it).
2. Choose **Move indicator**. The pointer changes to a hand over the box.
3. Hold the left mouse button on the box and drag it to the desired position, including another display.
4. Release the button to save the new display and position automatically. The box stays within the chosen display's usable area.

To cancel before dragging, right-click again and choose **Cancel move**. When you are not in a meeting, enable the Settings preview below to make the indicator available for moving. The indicator receives mouse clicks within its box so that its Move menu is accessible; it does not take keyboard focus.

To hide the indicator, right-click it (or Control-click) and choose **Hide for 15 minutes**, **Hide for 1 hour**, or **Hide until I choose Automatic**. This sets the Available mode, so it also keeps any USB light off. Choose **Automatic** in the menu bar to bring detection back early; VoiceOver users have a "Hide indicator until Automatic" custom action.

For keyboard-only movement, choose **Move indicator using the keyboard…** in the menu or Settings, or **Move using keyboard…** from the box's context menu. VoiceOver users can invoke its Move indicator using keyboard custom action. Arrows move 10 points, Shift+arrows 50, and Option+arrows one point. Directional buttons are also available. Return, Escape, or Done finishes; changes save immediately. A temporary preview starts if needed and ends with the movement window. Presenting always keeps the indicator hidden.

Choose a display in Settings before keyboard movement. With Show on every display enabled, moving one indicator updates that display's position. All copies hide together while presenting. Disconnecting a display removes its indicator.

To see changes outside a meeting, enable **Show indicator preview**. This keeps a preview visible until you uncheck it, close Settings, select a detection mode, or choose **Stop preview** from the menu. Opening Settings alone does not enable a preview.

Alternatively, choose **Preview Busy for 5 seconds** from the menu. Both kinds of preview stay hidden while presenting.

## Launch at login and quit

After installing in Applications, select **Launch at login** from the menu. A checkmark indicates it is enabled. macOS may ask you to approve it in Login Items settings.

To stop the app, select **Quit Meeting Busy** from its menu bar menu. To stop it from returning at login, turn off **Launch at login** before quitting.

## Diagnostic logging

Under **Settings… → Diagnostic logging**, choose Off, State changes (the default), or Every scan. Logs stay in `~/Library/Logs/MeetingBusy`. The current log and three backups are each limited to 512 KiB. Old entries are discarded as files rotate.

Entries include event timestamps, detected services, detection reasons, permission state, numeric error codes, and scan durations. They exclude meeting titles, participant names, chat text, URLs, custom indicator text, and user paths. Meeting activity times can still be sensitive.

Use **Open log folder**, **Export…**, or **Clear logs**. Export creates a JSON Lines file at your chosen location; review it before sharing it with the maintainer. Nothing is uploaded automatically. Clearing the app's logs does not delete previously exported copies. Off stops new entries but leaves existing logs until you clear them.

## Report an incorrect detection

Choose **This detection is incorrect…** from the menu or the Automatic detection section of Settings. An editable report opens with app version/build, macOS version, mode, pause/permission status, enabled services, detected signals, last scan time, and numeric error codes.

Describe the expected behavior and steps to reproduce, then review and edit the report before clicking **Save reviewed report…**. It is saved as a local text file wherever you choose. Share that file with the maintainer yourself if you want help; nothing is uploaded or submitted automatically.

The generated report excludes meeting titles/content, participant names, custom indicator text, user paths, and log contents. Anything you type into it is included when you save, so remove private information first. Logs can be exported separately from Settings if requested. Preparing a report does not put its contents or your notes in the app's logs. An open report keeps your edits when you invoke the command again; close it and reopen the command for a fresh snapshot.

## Check for updates

Choose **Check for updates…** from the menu, or **Check now** in Settings. Optional daily checks and update notifications are off until you enable them. Notifications require a separate macOS permission; daily checks contact GitHub even if notification permission is off.

Checks read the latest published stable release from `chipset/Meeting-Busy` on GitHub. No meeting information or diagnostic logs are sent. GitHub receives an ordinary API request and its usual connection metadata. The status distinguishes an available update, no published release, and a failed check. When available, use **View release** or the update menu item to open the GitHub page. Review the release's signing status, download its application ZIP, and install the new version yourself; the app does not download or replace itself.

## Update or repair permissions

The supplied ad hoc signed builds use a code identity tied to the exact build. When the app changes, macOS may no longer match its saved Accessibility approval. This is why rebuilding or installing a new ZIP can require another approval. The app's **Grant Accessibility access** button can prompt or open System Settings, but cannot grant itself permission. [Apple explains the code identity behavior](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements) and [the Accessibility prompt API](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions).

For future direct-download releases, signing every version with the same Developer ID Application identity and retaining the bundle identifier and installation path should preserve the app's identity across ordinary updates. Moving from an ad hoc build to a Developer ID build may require one more approval. A managed Mac can instead receive an Accessibility policy from IT through Apple's [Privacy Preferences Policy Control payload](https://support.apple.com/guide/deployment/privacy-preferences-policy-control-payload-dep38df53c2a/web).

Only repair the permission if the updated app reports that Accessibility access is denied:

1. Quit Meeting Busy, replace the old application in Applications with the new copy, and reopen it. Check the status in Settings.
2. If access is denied, quit the app and open **System Settings → Privacy & Security → Accessibility**.
3. Select the old **Meeting Busy** row, then click **−** below the list to remove it. Authenticate if requested.
4. Click **+**, select the new `/Applications/Meeting Busy.app`, and click **Open**.
5. Turn its switch on, reopen Meeting Busy, and select **Automatic**.

If you cannot find the app in the file picker, press **Command–Shift–G**, enter `/Applications`, and select it there. Check **Settings… → Meeting detection → Detection details** to confirm the running copy's path and version.

## Troubleshoot a missed or lingering indicator

**No indicator during a meeting:** select Automatic, check Accessibility permission, and bring the meeting tab or window into view. Open **Settings… → Meeting detection → Detection details** to see permission status, readable window/control counts, and scan failures. Force Busy is available while troubleshooting.

**Indicator remains after leaving:** choose **Available** or **Available for…** to hide it while troubleshooting. Read the menu status. Stop any preview and select Automatic to clear a manual override. If it says Setup needed, repair Accessibility permission; that status does not mean a meeting was detected. If it still reports **In a meeting: Zoom** after a completed scan, report the app version and detection details to the maintainer.

**No menu bar symbol:** reopen the installed app. If the app cannot start, revisit the first-launch security steps and check that the build supports your Mac's processor.

## Uninstall

Remove each browser bridge in Settings and remove the extension from each browser (see the browser guide). Turn off Launch at login, quit Meeting Busy, remove its entry from Accessibility settings, then move the application from Applications to the Trash. Appearance preferences may remain saved locally.

If you want to remove diagnostic history, use Clear logs before quitting or delete `~/Library/Logs/MeetingBusy` afterward. Exported copies are separate files. You can also revoke optional notification permission in System Settings → Notifications.

## Build from source

Building requires Xcode or command line tools that provide Swift 6 or newer. In Terminal, change into your downloaded repository folder, then run:

```sh
./scripts/build-app.sh
```

The resulting application is `dist/Meeting Busy.app`. Copy it to Applications and follow the setup instructions above. If you prefer to check the source before building, the application code is in `Sources`, and the packaging and icon generation scripts are in `scripts`.
