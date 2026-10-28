#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output="${1:-$PWD/dist/BrowserExtension}"
for browser in chromium firefox safari; do
  mkdir -p "$output/$browser"
  cp BrowserExtension/shared/* "$output/$browser/"
  cp "BrowserExtension/$browser/manifest.json" "$output/$browser/manifest.json"
done
cp BrowserExtension/safari/safari-transport.js "$output/safari/"
cp BrowserExtension/identity.json "$output/identity.json"
if [[ -f BrowserExtension/README.md ]]; then cp BrowserExtension/README.md "$output/README.md"; fi
