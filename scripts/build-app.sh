#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
if [[ "$configuration" != "release" && "$configuration" != "debug" ]]; then
  echo "Usage: $0 [release|debug]" >&2
  exit 1
fi
build_options=(--disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security" -c "$configuration")
if [[ "$configuration" == "release" ]]; then
  build_options+=(-debug-info-format none)
fi
swift build "${build_options[@]}"
binary_dir="$(swift build "${build_options[@]}" --show-bin-path)"
app="$PWD/dist/Meeting Busy.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
staged_binary="$(mktemp "$app/Contents/MacOS/.MeetingBusy.XXXXXX")"
trap 'rm -f "$staged_binary"' EXIT
cp "$binary_dir/MeetingBusy" "$staged_binary"
chmod +x "$staged_binary"
mv -f "$staged_binary" "$app/Contents/MacOS/MeetingBusy"
cp Resources/Info.plist "$app/Contents/Info.plist"
swift scripts/make-icon.swift "$PWD/.build/AppIcon.iconset" "$app/Contents/Resources/AppIcon.icns"
cp "$PWD/.build/AppIcon.iconset/icon_512x512@2x.png" "$PWD/dist/AppIcon.png"
codesign --force --sign - --identifier local.meetingbusy "$app"
touch "$app"
echo "Built $app"
