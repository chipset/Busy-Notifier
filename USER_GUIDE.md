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

The security exception above and Accessibility permission are separate approvals. Automatic meeting detection needs **Accessibility** permission to inspect other apps' user interfaces. This is a broad permission that can allow an app to read and control other apps, so grant it only to a copy you trust. Meeting Busy uses it to inspect supported meeting apps and browser controls. [Apple explains Accessibility access here](https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac).

1. In Meeting Busy's welcome dialog, select **Grant Accessibility access**. You can also choose **Grant Accessibility access…** from its menu bar menu.
2. In **System Settings → Privacy & Security → Accessibility**, turn on **Meeting Busy**.
3. If it is missing, click **+**, select `/Applications/Meeting Busy.app`, and click **Open**, then enable its switch.
4. Quit and reopen Meeting Busy if its menu still says **Setup needed: Accessibility access**.

This implementation does not request microphone, camera, screen recording, Full Disk Access, or browser scripting permission. It does not record meeting audio/video or send meeting information over the network. Optional update checks contact GitHub, and optional reminders request macOS Notifications permission. Appearance settings are saved locally. Detection details show application paths and scan statistics, so review that text before sharing it for troubleshooting.

You can revoke access at any time by turning off Meeting Busy in the same Accessibility settings. Automatic detection then stops; manual Force Busy and explicit previews can still show the indicator.

## Tell whether the app is running

Look for a **video camera symbol in the menu bar**, usually near the upper right of the screen. Meeting Busy does not have a Dock icon. The red camera application icon in Finder is the icon used to launch it.

Click the menu bar symbol and read the first line:

| Status | Meaning |
| --- | --- |
| In a meeting: Zoom, Teams, Webex, or Google Meet | A supported meeting was detected. |
| No active meeting detected | The app is running and currently has no meeting evidence. |
| Setup needed: Accessibility access | Automatic detection cannot run until permission is granted. |
| Busy — manual override | Force Busy is selected; the indicator can stay visible after a meeting ends. |
| Preview… | You explicitly enabled a preview; its visibility does not mean a meeting was detected. |
| Presenting / Screen sharing detected | The indicator is hidden. |
| Unable to inspect some meeting windows | A client could not be read or the scan reached a limit. |

The camera symbol is filled while the indicator is visible. A presentation symbol appears while presentation hiding is active. Read the menu status to distinguish an actual meeting from a manual indicator or preview.

## Use it during meetings

Select **Automatic** from the menu bar menu for normal use. It checks every two seconds while awake. If a previous scan is still running, that tick is skipped, so detection can take longer. Joining or leaving a meeting takes effect after a completed scan.

Opening a meeting app or its prejoin screen should not show the indicator. English meeting controls are currently supported. Hidden controls, inactive browser tabs, and changes to meeting clients can cause missed detections.

Use **Force Busy** to display your status manually. Return to **Automatic** when finished. Selecting a detection mode also stops any preview.

For a temporary indicator, choose **Busy for… → 15, 30, or 60 minutes**. The menu shows when it ends and then returns to Automatic, including after sleeping through the deadline. Changing modes cancels the timer. Manual modes and timers reset to Automatic when the app is relaunched.

The menu shows the last completed scan time and duration. Settings' detection details also identify the reason for a meeting match, such as active call controls or your stop-sharing control. A stale positive result expires if scans stop completing; closing or leaving a call clears its evidence on the next scan.

## Hide the indicator before presenting

Before sharing your screen, choose **I’m presenting — hide indicator** from the menu. The indicator hides immediately. After sharing ends, return to **Automatic**.

The app also tries to hide automatically when it finds your Stop sharing, Stop Share, or Stop presenting control. This can be delayed or missed, so use the manual presenting option before sharing when it matters that the box does not appear to your audience. Another participant presenting should not hide your status. Presentation hiding takes precedence over Force Busy and previews.

While manual Presenting is selected, the menu bar explicitly says **Presenting** and the menu shows how long it has been active. In Settings, optionally enable **Remind me to return to Automatic** and select a delay. Approve Notifications permission if requested. The reminder offers a Return to Automatic action; it never turns your indicator back on by itself. If notifications are denied or silenced, use the menu bar reminder and switch modes manually.

## Keyboard shortcuts

Enable **Settings… → Keyboard shortcuts → Enable global shortcuts**. These work while another app is active:

| Shortcut | Action |
| --- | --- |
| Control–Option–Command–1 | Automatic |
| Control–Option–Command–2 | Force Busy |
| Control–Option–Command–3 | Presenting |

The Settings status reports whether registration succeeded. If another app already uses a shortcut, disable the conflict or leave Meeting Busy's global shortcuts off. Shortcuts do not require Input Monitoring permission.

## Customize the indicator

Open the menu bar menu and choose **Settings…**.

| Setting | How to use it |
| --- | --- |
| Indicator text | Enter your message, such as “In a meeting.” Blank text falls back to “Busy.” Longer messages fit within the box. |
| Indicator color | Choose the box's background color. Text automatically switches between black and white for contrast. |
| Size | Choose 50–250% of the default size. |
| Transparency | 0% is solid; 90% is almost transparent. |
| Display | Choose the main display or a connected display. An unavailable display falls back to the main display. |
| Location | Use a corner/center button, the horizontal and vertical sliders, or the indicator's right-click Move option. |
| Restore default appearance | Reset the message, color, size, transparency, display choice, and location. |

Changes save automatically and survive quitting the app. Changing the indicator color does not change the application launch icon.

To move the box directly:

1. Right-click the visible indicator (or Control-click it).
2. Choose **Move indicator**. The pointer changes to a hand over the box.
3. Hold the left mouse button on the box and drag it to the desired position, including another display.
4. Release the button to save the new display and position automatically. The box stays within the chosen display's usable area.

To cancel before dragging, right-click again and choose **Cancel move**. When you are not in a meeting, enable the Settings preview below to make the indicator available for moving. The indicator receives mouse clicks within its box so that its Move menu is accessible; it does not take keyboard focus.

To see changes outside a meeting, enable **Show indicator preview**. This keeps a preview visible until you uncheck it, close Settings, select a detection mode, or choose **Stop preview** from the menu. Opening Settings alone does not enable a preview.

Alternatively, choose **Preview Busy for 5 seconds** from the menu. Both kinds of preview stay hidden while presenting.

## Launch at login and quit

After installing in Applications, select **Launch at login** from the menu. A checkmark indicates it is enabled. macOS may ask you to approve it in Login Items settings.

To stop the app, select **Quit Meeting Busy** from its menu bar menu. To stop it from returning at login, turn off **Launch at login** before quitting.

## Diagnostic logging

Under **Settings… → Diagnostic logging**, choose Off, State changes (the default), or Every scan. Logs stay in `~/Library/Logs/MeetingBusy`. The current log and three backups are each limited to 512 KiB. Old entries are discarded as files rotate.

Entries include event timestamps, detected services, detection reasons, permission state, numeric error codes, and scan durations. They exclude meeting titles, participant names, chat text, URLs, custom indicator text, and user paths. Meeting activity times can still be sensitive.

Use **Open log folder**, **Export…**, or **Clear logs**. Export creates a JSON Lines file at your chosen location; review it before sharing it with the maintainer. Nothing is uploaded automatically. Clearing the app's logs does not delete previously exported copies. Off stops new entries but leaves existing logs until you clear them.

## Check for updates

Choose **Check for updates…** from the menu, or **Check now** in Settings. Optional daily checks and update notifications are off until you enable them. Notifications require a separate macOS permission; daily checks contact GitHub even if notification permission is off.

Checks read the latest published stable release from `chipset/Busy-Notifier` on GitHub. No meeting information or diagnostic logs are sent. GitHub receives an ordinary API request and its usual connection metadata. The status distinguishes an available update, no published release, and a failed check. When available, use **View release** or the update menu item to open the GitHub page. Review the release's signing status, download its application ZIP, and install the new version yourself; the app does not download or replace itself.

## Update or repair permissions

Locally signed builds may need Accessibility permission granted again after an update or rebuild.

1. Quit Meeting Busy and replace the old application in Applications with the new copy.
2. Open **System Settings → Privacy & Security → Accessibility**.
3. Select the old **Meeting Busy** row, then click **−** below the list to remove it. Authenticate if requested.
4. Click **+**, select the new `/Applications/Meeting Busy.app`, and click **Open**.
5. Turn its switch on, reopen Meeting Busy, and select **Automatic**.

If you cannot find the app in the file picker, press **Command–Shift–G**, enter `/Applications`, and select it there. Check **Settings… → Meeting detection → Detection details** to confirm the running copy's path and version.

## Troubleshoot a missed or lingering indicator

**No indicator during a meeting:** select Automatic, check Accessibility permission, and bring the meeting tab or window into view. Open **Settings… → Meeting detection → Detection details** to see permission status, readable window/control counts, and scan failures. Force Busy is available while troubleshooting.

**Indicator remains after leaving:** read the menu status. Stop any preview and select Automatic to clear a manual override. If it says Setup needed, repair Accessibility permission; that status does not mean a meeting was detected. If it still reports **In a meeting: Zoom** after a completed scan, report the app version and detection details to the maintainer.

**No menu bar symbol:** reopen the installed app. If the app cannot start, revisit the first-launch security steps and check that the build supports your Mac's processor.

## Uninstall

Turn off Launch at login, quit Meeting Busy, remove its entry from Accessibility settings, then move the application from Applications to the Trash. Appearance preferences may remain saved locally.

If you want to remove diagnostic history, use Clear logs before quitting or delete `~/Library/Logs/MeetingBusy` afterward. Exported copies are separate files. You can also revoke optional notification permission in System Settings → Notifications.

## Build from source

Building requires Xcode or command line tools that provide Swift 6 or newer. In Terminal, change into your downloaded repository folder, then run:

```sh
./scripts/build-app.sh
```

The resulting application is `dist/Meeting Busy.app`. Copy it to Applications and follow the setup instructions above. If you prefer to check the source before building, the application code is in `Sources`, and the packaging and icon generation scripts are in `scripts`.
