# Building and releasing Meeting Busy

## Development release

Requires Xcode/Swift 6 or newer. Build a universal application and ZIP archive:

```sh
./scripts/package-release.sh
```

This produces `dist/Meeting Busy.app`, `dist/MeetingBusy-0.0.1-universal.zip`, and a `.sha256` checksum file alongside the archive. The default build contains both `arm64` and `x86_64` code and targets macOS 13 or newer. It is ad hoc signed and **not notarized**. Users may need the per-app macOS opening exception described in [USER_GUIDE.md](USER_GUIDE.md).

For a faster build for the current Mac only:

```sh
./scripts/build-app.sh debug native
```

## Developer ID signing and notarization

This checkout does not include a signing certificate, private key, or Apple credentials. An Apple Developer ID Application certificate with its private key must be installed in the releasing Mac's Keychain before making an identified-developer release. The release script enables hardened runtime and a secure timestamp for that signature, then submits the archive, staples Apple's accepted ticket, and verifies the app. See [Apple's notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

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
codesign --verify --deep --strict "dist/Meeting Busy.app"
lipo -archs "dist/Meeting Busy.app/Contents/MacOS/MeetingBusy"
cd dist
shasum -a 256 -c MeetingBusy-0.0.1-universal.zip.sha256
```

Complete the [manual acceptance checks](MANUAL_TESTS.md) on actual conferencing clients. Cross-compilation verifies the Intel slice builds, but does not substitute for running it on an Intel Mac. Notification delivery, global hotkeys, and screen-sharing behavior also need interactive testing.

## Publish to GitHub

Change `CFBundleShortVersionString` and increment `CFBundleVersion` in `Resources/Info.plist` for a release, then rebuild and validate. Commit the source and documentation, push them, and create a GitHub release in `chipset/Busy-Notifier` using the tag `v0.0.1` for this version. Attach the ZIP and its checksum, and state clearly whether it is ad hoc signed or Developer ID signed and notarized. Build outputs stay excluded from Git.

The in-app updater reads GitHub's latest published stable release. Drafts and prereleases are not offered, and merely pushing a Git commit does not create an update. Users review the release page and install manually; the app never downloads or replaces its own executable. API behavior is documented in [GitHub's release API](https://docs.github.com/en/rest/releases/releases#get-the-latest-release).

No publishing or notarization is performed by simply running the application. The release script only uploads an archive to Apple when explicitly invoked with `--notarize`; publishing the resulting files to GitHub is a separate action.
