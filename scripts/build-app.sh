#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
architecture="${2:-universal}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
if [[ "$configuration" != "release" && "$configuration" != "debug" ]]; then
  echo "Usage: $0 [release|debug] [universal|native]" >&2
  exit 1
fi
case "$architecture" in
  universal) architectures=(arm64 x86_64) ;;
  native) architectures=("$(uname -m)") ;;
  *) echo "Architecture must be universal or native." >&2; exit 1 ;;
esac
binaries=()
browser_hosts=()
for target_architecture in "${architectures[@]}"; do
  build_options=(--disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security" --scratch-path "$PWD/.build/architectures/$target_architecture" --triple "$target_architecture-apple-macosx13.0" -c "$configuration")
  if [[ "$configuration" == "release" ]]; then build_options+=(-debug-info-format none); fi
  swift build "${build_options[@]}"
  binary_dir="$(swift build "${build_options[@]}" --show-bin-path)"
  binaries+=("$binary_dir/MeetingBusy")
  browser_hosts+=("$binary_dir/MeetingBusyBrowserHost")
done
app="$PWD/dist/Meeting Busy.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
staged_binary="$(mktemp "$app/Contents/MacOS/.MeetingBusy.XXXXXX")"
cleanup_staged_binary() {
  if [[ -f "$staged_binary" ]]; then unlink "$staged_binary"; fi
}
trap cleanup_staged_binary EXIT
if [[ "$architecture" == "universal" ]]; then
  lipo -create "${binaries[@]}" -output "$staged_binary"
else
  cp "${binaries[0]}" "$staged_binary"
fi
chmod 755 "$staged_binary"
mv -f "$staged_binary" "$app/Contents/MacOS/MeetingBusy"
staged_host="$(mktemp "$app/Contents/MacOS/.BrowserHost.XXXXXX")"
if [[ "$architecture" == "universal" ]]; then
  lipo -create "${browser_hosts[@]}" -output "$staged_host"
else
  cp "${browser_hosts[0]}" "$staged_host"
fi
chmod 755 "$staged_host"
mv -f "$staged_host" "$app/Contents/MacOS/MeetingBusyBrowserHost"
cp Resources/Info.plist "$app/Contents/Info.plist"
./scripts/build-browser-extension.sh "$app/Contents/Resources/BrowserExtension"
swift scripts/make-icon.swift "$PWD/.build/AppIcon.iconset" "$app/Contents/Resources/AppIcon.icns"
cp "$PWD/.build/AppIcon.iconset/icon_512x512@2x.png" "$PWD/dist/AppIcon.png"
signing_identity="${MEETING_BUSY_SIGNING_IDENTITY:--}"
if [[ "$signing_identity" == "-" ]]; then
  codesign --force --sign - --identifier local.meetingbusy.browser "$app/Contents/MacOS/MeetingBusyBrowserHost"
  codesign --force --sign - --identifier local.meetingbusy "$app"
else
  codesign --force --options runtime --timestamp --sign "$signing_identity" --identifier local.meetingbusy.browser "$app/Contents/MacOS/MeetingBusyBrowserHost"
  codesign --force --options runtime --timestamp --sign "$signing_identity" --identifier local.meetingbusy "$app"
fi
codesign --verify --deep --strict "$app"
if [[ "$architecture" == "universal" ]]; then
  binary_architectures="$(lipo -archs "$app/Contents/MacOS/MeetingBusy")"
  host_architectures="$(lipo -archs "$app/Contents/MacOS/MeetingBusyBrowserHost")"
  if [[ " $binary_architectures " != *" arm64 "* || " $binary_architectures " != *" x86_64 "* ]]; then
    echo "Universal build is missing a required architecture: $binary_architectures" >&2
    exit 1
  fi
  if [[ " $host_architectures " != *" arm64 "* || " $host_architectures " != *" x86_64 "* ]]; then echo "Browser host is missing a required architecture." >&2; exit 1; fi
fi
touch "$app"
echo "Built $app"
