#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
notarize=false
case "${1:-}" in
  "") ;;
  --notarize) notarize=true ;;
  *) echo "Usage: $0 [--notarize]" >&2; exit 1 ;;
esac
if $notarize; then
  if [[ -z "${MEETING_BUSY_SIGNING_IDENTITY:-}" || "${MEETING_BUSY_SIGNING_IDENTITY:-}" == "-" || -z "${MEETING_BUSY_NOTARY_PROFILE:-}" ]]; then
    echo "Notarization requires MEETING_BUSY_SIGNING_IDENTITY and MEETING_BUSY_NOTARY_PROFILE. Use a Developer ID Application certificate and a stored notarytool Keychain profile." >&2
    exit 1
  fi
fi
./scripts/build-app.sh release universal
app="$PWD/dist/Meeting Busy.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
archive="$PWD/dist/MeetingBusy-$version-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
if $notarize; then
  xcrun notarytool submit "$archive" --keychain-profile "$MEETING_BUSY_NOTARY_PROFILE" --wait --output-format json > "$PWD/dist/notarization-result.json"
  status="$(plutil -extract status raw -o - "$PWD/dist/notarization-result.json")"
  if [[ "$status" != "Accepted" ]]; then
    echo "Apple did not accept this submission. Review dist/notarization-result.json and retrieve the submission log before distributing." >&2
    exit 1
  fi
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  spctl --assess --type execute --verbose "$app"
  ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
else
  echo "This archive has not been notarized. Default builds use an ad hoc signature."
fi
cd dist
shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256"
echo "Release archive: $archive"
