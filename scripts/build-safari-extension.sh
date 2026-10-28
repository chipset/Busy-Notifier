#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="${1:?Pass the containing app path}"
configuration="${2:-release}"
architecture="${3:-universal}"
app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
app_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
project_root="$PWD/.build/SafariExtension"
if [[ "$architecture" == "universal" ]]; then safari_architectures="arm64 x86_64"
else safari_architectures="$(uname -m)"
fi
if [[ "$configuration" == "debug" ]]; then safari_configuration=Debug
else safari_configuration=Release
fi
mkdir -p "$PWD/.build" "$app/Contents/Resources" "$app/Contents/PlugIns"
xcrun safari-web-extension-converter "$app/Contents/Resources/BrowserExtension/safari" \
  --project-location "$project_root" --app-name MeetingBusySafari --bundle-identifier local.meetingbusy \
  --swift --macos-only --copy-resources --no-open --no-prompt --force > "$PWD/.build/safari-converter.log" 2>&1 || {
    cat "$PWD/.build/safari-converter.log"; exit 1;
  }
extension_source="$project_root/MeetingBusySafari/MeetingBusySafari Extension"
cp BrowserExtension/safari/SafariWebExtensionHandler.swift "$extension_source/SafariWebExtensionHandler.swift"
python3 - "$app" "$extension_source/Info.plist" <<'PY'
import json, pathlib, plistlib, secrets, sys
app = pathlib.Path(sys.argv[1])
config = {"port": 48157, "token": secrets.token_hex(32)}
(app / "Contents/Resources/SafariBridge.json").write_text(json.dumps(config))
path = pathlib.Path(sys.argv[2])
info = plistlib.loads(path.read_bytes())
info["MeetingBusySafariBridge"] = config
info["NSAppTransportSecurity"] = {"NSAllowsLocalNetworking": True}
info["CFBundleDisplayName"] = "Meeting Busy"
app_info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
for key in ("CFBundleShortVersionString", "CFBundleVersion"):
    info[key] = app_info[key]
path.write_bytes(plistlib.dumps(info))
PY
xcodebuild -project "$project_root/MeetingBusySafari/MeetingBusySafari.xcodeproj" \
  -target "MeetingBusySafari Extension" -configuration "$safari_configuration" \
  ARCHS="$safari_architectures" ONLY_ACTIVE_ARCH=NO MACOSX_DEPLOYMENT_TARGET=13.0 \
  CODE_SIGNING_ALLOWED=NO PRODUCT_BUNDLE_IDENTIFIER=local.meetingbusy.safari PRODUCT_NAME=MeetingBusySafari \
  MARKETING_VERSION="$app_version" CURRENT_PROJECT_VERSION="$app_build" \
  INFOPLIST_KEY_CFBundleDisplayName="Meeting Busy" \
  CONFIGURATION_BUILD_DIR="$PWD/.build/SafariProducts" build > "$PWD/.build/safari-build.log" 2>&1 || {
    tail -70 "$PWD/.build/safari-build.log"; exit 1;
  }
ditto "$PWD/.build/SafariProducts/MeetingBusySafari.appex" "$app/Contents/PlugIns/MeetingBusySafari.appex"
cat > "$PWD/.build/SafariEntitlements.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.network.client</key><true/>
</dict></plist>
PLIST
signing_identity="${MEETING_BUSY_SIGNING_IDENTITY:--}"
sign_options=(--force --sign "$signing_identity" --entitlements "$PWD/.build/SafariEntitlements.plist")
if [[ "$signing_identity" != "-" ]]; then sign_options+=(--options runtime --timestamp); fi
codesign "${sign_options[@]}" "$app/Contents/PlugIns/MeetingBusySafari.appex"
codesign --verify --strict "$app/Contents/PlugIns/MeetingBusySafari.appex"
