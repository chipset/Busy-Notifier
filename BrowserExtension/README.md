# Meeting Busy browser integration

This optional extension supplies meeting and own-screen-sharing state from inactive tabs to the macOS app. It supports English controls in Google Meet, Teams, Webex, and Zoom web clients. Native desktop clients still use Accessibility. Safari has an embedded local extension; its free unsigned setup is described below.

Spanish, French, and German call and sharing labels have limited best-effort coverage. Verify each client version with a live call.

## Safari: use the temporary extension when the bundled one is missing

Safari can reject an ad hoc signed native bundle even with **Allow unsigned extensions** enabled. This occurred on Safari 27 with the 0.4.0 preview: PlugInKit registered the extension, but Safari logged a code-signing-dictionary failure and did not list it. Signature and native-handler tests alone do not establish Safari visibility.

The temporary version uses Safari's **Add Temporary Extension** feature and pairs directly with the local Mac app. It needs no paid account or native extension certificate.

1. Quit old copies, update to Meeting Busy 0.4.1 or later, and open the installed copy.
2. In Meeting Busy **Settings → Browser integration**, choose **Safari**, turn integration on, and select **Open Safari extension folder**. This copies the `safari-temporary` folder into Application Support and opens it in Finder.
3. In Safari **Settings → Advanced**, enable **Show features for web developers**. In **Settings → Developer**, choose **Add Temporary Extension…**, approve Safari's prompt, and select the opened folder. You may instead select `MeetingBusy-0.4.1-safari-temporary-extension.zip` from the release.
4. Enable **Meeting Busy (Temporary)** under Safari Extensions and allow its supported meeting sites and `127.0.0.1` local-bridge access. Enable it in the Safari profile where you attend calls.
5. Open the temporary extension popup in Safari and choose **Pair automatically**. Meeting Busy asks you to **Allow** the extension; click Allow in the Mac app. (Fallback: choose **Copy pairing code (manual)** in the app and paste it under **Pair with a code instead**.) Then choose **Connect open meeting tabs**, or reload meeting tabs. The popup should say **Connected to Meeting Busy**.
6. Join and leave a call, switch tabs, and start and stop your own screen share to verify live detection.

Safari removes temporary extensions after 24 hours or when it quits. Add the folder or ZIP again and pair when needed. Pairing uses a per-install secret stored in `~/Library/Application Support/MeetingBusy/BrowserBridge`, so updating the Mac app does not break an existing pairing; a re-added extension just needs Pair automatically again. If the extension stops reporting, the menu says so. If Safari has no Add Temporary Extension option, this route is unavailable there; use Accessibility fallback or a locally development-signed embedded extension. [Apple's temporary-extension instructions](https://developer.apple.com/documentation/safariservices/running-your-safari-web-extension)

The temporary extension stores its pairing token in extension-local storage, never in meeting-page scripts. It sends only provider, ephemeral frame IDs, and call/sharing state to an authenticated IPv4 loopback listener. Requests from ordinary website origins are rejected even with a valid token; only native requests and Safari extension origins can use the bridge. Integration off stops the listener, and pauses, service switches, and stale-evidence expiry apply normally. No external service is contacted. Its persistent macOS background page supplies the five-second heartbeat independently of inactive-tab timers. Quit duplicate app copies if the bridge reports a port conflict.

The original embedded native extension is still built for development testing, but ad hoc Safari discovery is not assumed to work. A free Apple Development identity may be used for local development signing; a paid Developer ID identity is not required for the temporary route.

## Direct browser distribution

Run `./scripts/package-browser-extensions.sh` from the repository root. It validates the extension versions against the app and creates a ZIP for each browser family under `dist/`, plus SHA-256 files. The Chromium ZIP can be extracted and loaded locally through Developer mode; the app's **Install/update bridge** action also copies the unpacked extension into Application Support. Chrome on macOS only supports self-hosted installed extensions through managed enterprise policies, so a normal direct download cannot silently install it.

For a Firefox extension that survives restart, submit the Firefox ZIP to Mozilla for **unlisted** signing, then distribute the resulting signed XPI directly. This uses Mozilla's signing service without a public add-on listing. The unsigned ZIP is only useful for temporary development loading. Keep the Chromium public key and Firefox add-on ID stable, and verify each installed extension ID against the native messaging allowlist. No public browser store listing is part of this workflow. [Chrome distribution rules](https://developer.chrome.com/docs/extensions/how-to/distribute) · [Firefox self-distribution](https://extensionworkshop.com/documentation/publish/install-self-distributed/)

## Install Chromium or Firefox

1. Put `Meeting Busy.app` in its permanent location, open it, and go to **Settings → Browser integration**.
2. Enable **Use browser extension meeting detection**, choose your browser, and click **Install/update bridge**. This registers a native messaging host for your macOS user and copies the extension into Application Support. It does not install an extension into the browser automatically.
3. Click **Open extension folder**.
4. In Chrome, open `chrome://extensions`; Edge: `edge://extensions`; Brave: `brave://extensions`; Chromium: `chrome://extensions`. Enable **Developer mode**, choose **Load unpacked**, and select the opened `chromium` folder. If browser policy disallows developer extensions, ask your administrator.
5. Firefox: for the unsigned development copy, open `about:debugging#/runtime/this-firefox`, choose **Load Temporary Add-on**, and select `manifest.json` in the opened `firefox` folder. Reload it after every browser restart. If you have an unlisted signed XPI, open **Add-ons and themes → Settings → Install Add-on From File** and select it instead.
6. Open the extension popup and choose **Connect open meeting tabs**. Existing tabs can also be reloaded. Check the app's Browser integration section for a browser connection, then test joining, leaving, and sharing in your client.

Repeat bridge installation for each browser you use, and load the extension into each browser profile containing meeting tabs. No private/incognito access is enabled by default. After app updates, click Install/update bridge and reload the extension in the browser. After moving the app, reinstall the bridge so its executable path is current. The app's copied folder is the recommended installation location.

## Operation and privacy

Controls are checked when the document changes and periodically. The extension's background process sends a heartbeat every five seconds independently of inactive-tab timers. The app reads it on its two-second polling cycle. Closing/navigating a tab clears its contribution; a disconnected or crashed connection expires within 20 seconds plus the next app poll. Sleeping, discarded, or frozen documents can still hide changes, and client UI changes can break recognition. Use **Available** to hide a false positive and **Presenting** before sharing when immediate hiding matters.

The extension requests native messaging, script injection, and access only to the supported providers listed in its manifest. Such site access is broad: install only a copy you trust. Code reads actionable button labels locally to classify state. It transmits only an ephemeral numeric tab/frame ID, provider, in-meeting flag, and presenting flag to a local native host. It does not transmit URLs, titles, participant names, chat, or button text. It does not request camera/microphone or record calls. There is no extension network endpoint or telemetry.

The host stores user-private JSON state under `~/Library/Application Support/MeetingBusy/BrowserBridge`. State is transient, and stale files are ignored. Pause, service switches, and the app's integration switch also apply to the extension. Changes reach the extension on the next heartbeat. Available hides the indicator while detection continues. The native host accepts only the packaged extension ID through the browser's origin allowlist. Chromium identity uses a committed **public** key, with no signing private key in the repository.

## Remove

In the app, select each registered browser and click **Remove selected bridge and turn integration off**. Remove Meeting Busy from each browser's extension manager as well. This removes the selected native-host registration; copied extension files remain so another browser using the same folder is not broken. After removing all copies you may delete `~/Library/Application Support/MeetingBusy/BrowserExtension` and `BrowserBridge` while the app and browsers are closed.

## Development

Run `./scripts/build-browser-extension.sh` from the repository root to assemble browser folders under `dist/BrowserExtension`. Run `node --test BrowserExtension/tests/*.test.cjs` for classifier/background-worker tests. The app build embeds both variants and the universal native host.

References: [Chrome native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging), [Firefox native messaging](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Native_messaging), [Firefox temporary installation](https://extensionworkshop.com/documentation/develop/temporary-installation-in-firefox/).
