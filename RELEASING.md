# Building and releasing Meeting Busy

Meeting Busy is distributed as a direct-download ZIP outside the Mac App Store. Developer ID signing and notarization are for that direct-download route; this workflow does not submit the app to the Mac App Store.

## Development release

Requires Xcode/Swift 6 or newer. Build a universal application and ZIP archive:

```sh
./scripts/package-release.sh
```

This produces `dist/Meeting Busy.app`, `dist/MeetingBusy-0.3.1-universal.zip`, and a `.sha256` checksum file alongside the archive. The default build contains both `arm64` and `x86_64` code and targets macOS 13 or newer. It is ad hoc signed and **not notarized**. Users may need the per-app macOS opening exception described in [USER_GUIDE.md](USER_GUIDE.md).

For a faster build for the current Mac only:

```sh
./scripts/build-app.sh debug native
```

## Developer ID signing and notarization

This checkout does not include a signing certificate, private key, or Apple credentials. An Apple Developer ID Application certificate with its private key must be installed in the releasing Mac's Keychain before making an identified-developer release. The release script enables hardened runtime and a secure timestamp for that signature, then submits the archive, staples Apple's accepted ticket, and verifies the app. See [Apple's notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

Use the same Developer ID Application identity, `local.meetingbusy` bundle identifier, and installation path for successive releases. A stable code-signing requirement lets macOS recognize the app across versions for privacy approvals such as Accessibility; the default ad hoc signature is tied to one build and may require reapproval after each update. Switching existing users from an ad hoc build to a Developer ID build may require one final approval. [Apple's code-signing explanation](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)

Use Xcode or the Apple Developer account tools to obtain and install the Developer ID Application certificate. Store notarization credentials interactively in Keychain:

```sh
xcrun notarytool store-credentials MeetingBusyNotary
```

Then provide the certificate's exact name and the stored profile's name:

```sh
MEETING_BUSY_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
MEETING_BUSY_NOTARY_PROFILE='MeetingBusyNotary' \
./scripts/package-release.sh --notarize
```

The script fails before building if the required configuration is missing. If Apple rejects the submission, inspect `dist/notarization-result.json` and retrieve its submission log with `notarytool log`. The final ZIP and checksum are regenerated after successful stapling. Keep keys and credentials out of Git; no certificate or password is needed by users to run a signed release.

## Validation before publishing

```sh
swift test
node --test BrowserExtension/tests/*.test.cjs
codesign --verify --deep --strict "dist/Meeting Busy.app"
lipo -archs "dist/Meeting Busy.app/Contents/MacOS/MeetingBusy"
cd dist
shasum -a 256 -c MeetingBusy-0.3.1-universal.zip.sha256
```

Complete the [manual acceptance checks](MANUAL_TESTS.md) on actual conferencing clients. Cross-compilation verifies the Intel slice builds, but does not substitute for running it on an Intel Mac. Notification delivery, global hotkeys, and screen-sharing behavior also need interactive testing.

## Publish to GitHub

Change `CFBundleShortVersionString` and increment `CFBundleVersion` in `Resources/Info.plist` for a release, then rebuild and validate. Commit the source and documentation, push them, and create a GitHub release in `chipset/Meeting-Busy` using the tag `v0.3.1` for this version. Attach the ZIP and its checksum, and state clearly whether it is ad hoc signed or Developer ID signed and notarized. Build outputs stay excluded from Git.

After committing the current source and `RELEASE_NOTES.md`, the publishing helper can perform these steps from a terminal with GitHub access:

```sh
./scripts/publish-release.sh
```

Its checks also require Node.js and Python 3. It requires the GitHub CLI (`gh`) to be installed and authenticated, a clean `main` branch, and the expected GitHub origin. It checks for existing tags/releases, fetches remote main, verifies the remote history is contained locally, runs tests, rebuilds the universal package, pushes main and an annotated version tag, then creates a regular GitHub release with the ZIP and checksum. It never force-pushes or replaces an existing release. Publishing is not automatic during normal builds. Use `gh auth login` first if the CLI is not authenticated.

The in-app updater reads GitHub's latest published stable release. Drafts and prereleases are not offered, and merely pushing a Git commit does not create an update. Users review the release page and install manually; the app never downloads or replaces its own executable. API behavior is documented in [GitHub's release API](https://docs.github.com/en/rest/releases/releases#get-the-latest-release).

No publishing or notarization is performed by simply running the application. The release script only uploads an archive to Apple when explicitly invoked with `--notarize`; publishing the resulting files to GitHub is a separate action.

The universal app also contains a universal native messaging host and both browser extension variants. Browser extensions remain local unpacked/temporary installs unless separately signed; app notarization does not sign them. Keep `BrowserExtension/identity.json` and the Chromium manifest key stable so existing native-host allowlists continue to match. Browser background tests require Node.js; optional end-to-end browser tests are documented in `BrowserExtension/tests/README.md`.

Run `./scripts/package-browser-extensions.sh` to create local browser extension ZIPs. Chromium can be loaded unpacked in Developer mode. For a Firefox extension that persists across restarts, request **unlisted** Mozilla signing and distribute the signed XPI yourself; no public browser store listing is needed. Check installed extension IDs against the app's native-host allowlists. The app and extension version numbers must match before packaging.
