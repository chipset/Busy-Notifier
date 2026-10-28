#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
for browser in chromium firefox safari safari-temporary; do
  manifest_version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "BrowserExtension/$browser/manifest.json")"
  if [[ "$manifest_version" != "$version" ]]; then
    echo "$browser manifest version $manifest_version does not match app version $version" >&2
    exit 1
  fi
done

./scripts/build-browser-extension.sh
for browser in chromium firefox safari-temporary; do
  archive="$PWD/dist/MeetingBusy-$version-$browser-extension.zip"
  (cd "dist/BrowserExtension/$browser" && zip -q -X -r "$archive" .)
  (cd dist && shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256")
  echo "Prepared $archive"
done
echo "Firefox package requires Mozilla signing before users can install it permanently."
echo "Safari temporary extension: add the folder or ZIP in Safari Developer settings and paste a pairing code from the app."
