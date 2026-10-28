#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output="${1:-$PWD/dist/BrowserExtension}"
for browser in chromium firefox safari safari-temporary; do
  mkdir -p "$output/$browser"
  cp BrowserExtension/shared/* "$output/$browser/"
  cp "BrowserExtension/$browser/manifest.json" "$output/$browser/manifest.json"
done
cp BrowserExtension/safari/safari-transport.js "$output/safari/"
cp BrowserExtension/safari-temporary/safari-transport.js BrowserExtension/safari-temporary/safari-pairing.js BrowserExtension/safari-temporary/popup.html BrowserExtension/safari-temporary/popup.js "$output/safari-temporary/"
cp BrowserExtension/identity.json "$output/identity.json"
if [[ -f BrowserExtension/README.md ]]; then cp BrowserExtension/README.md "$output/README.md"; fi
