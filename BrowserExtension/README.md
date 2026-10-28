# Meeting Busy browser integration

This optional extension supplies meeting and own-screen-sharing state from inactive tabs to the macOS app. It supports English controls in Google Meet, Teams, Webex, and Zoom web clients. Native desktop clients still use Accessibility. Safari continues to use Accessibility; there is no Safari extension in this package.

Spanish, French, and German call and sharing labels have limited best-effort coverage. Verify each client version with a live call.

## Direct browser distribution

Run `./scripts/package-browser-extensions.sh` from the repository root. It validates the extension versions against the app and creates a ZIP for each browser family under `dist/`, plus SHA-256 files. The Chromium ZIP can be extracted and loaded locally through Developer mode; the app's **Install/update bridge** action also copies the unpacked extension into Application Support. Chrome on macOS only supports self-hosted installed extensions through managed enterprise policies, so a normal direct download cannot silently install it.

For a Firefox extension that survives restart, submit the Firefox ZIP to Mozilla for **unlisted** signing, then distribute the resulting signed XPI directly. This uses Mozilla's signing service without a public add-on listing. The unsigned ZIP is only useful for temporary development loading. Keep the Chromium public key and Firefox add-on ID stable, and verify each installed extension ID against the native messaging allowlist. No public browser store listing is part of this workflow. [Chrome distribution rules](https://developer.chrome.com/docs/extensions/how-to/distribute) · [Firefox self-distribution](https://extensionworkshop.com/documentation/publish/install-self-distributed/)

## Install

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
