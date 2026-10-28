#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v gh >/dev/null || { echo "Install the GitHub CLI (gh) before publishing." >&2; exit 1; }
repository="chipset/Meeting-Busy"
origin="$(git remote get-url origin)"
case "$origin" in
  https://github.com/chipset/Meeting-Busy.git|https://github.com/chipset/Meeting-Busy|git@github.com:chipset/Meeting-Busy.git) ;;
  *) echo "Origin does not point to $repository; publishing stopped." >&2; exit 1 ;;
esac
if [[ "$(git branch --show-current)" != "main" || -n "$(git status --porcelain)" ]]; then
  echo "Publish from a clean main branch. Commit the source and release notes first." >&2
  exit 1
fi
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo "Expected a numeric major.minor.patch version." >&2; exit 1; fi
tag="v$version"
test -s RELEASE_NOTES.md || { echo "RELEASE_NOTES.md is missing or empty." >&2; exit 1; }
if [[ "$(head -n 1 RELEASE_NOTES.md)" != "# Meeting Busy $version" ]]; then
  echo "Release notes do not match the app version." >&2
  exit 1
fi
gh auth status >/dev/null
git fetch origin main --tags
if ! git merge-base --is-ancestor origin/main HEAD; then
  echo "Remote main contains commits not in this checkout. Integrate them before publishing." >&2
  exit 1
fi
if git show-ref --verify --quiet "refs/tags/$tag"; then
  if [[ "$(git rev-parse "$tag^{commit}")" != "$(git rev-parse HEAD)" ]]; then
    echo "Tag $tag points to different source. Choose a new version; existing tags are never replaced." >&2
    exit 1
  fi
fi
existing_releases="$(gh release list --repo "$repository" --limit 100 --json tagName --jq '.[].tagName')"
while IFS= read -r existing; do
  if [[ "$existing" == "$tag" ]]; then echo "Release $tag already exists; publishing stopped." >&2; exit 1; fi
done <<< "$existing_releases"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift test --disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security"
node --test BrowserExtension/tests/*.test.cjs
./scripts/package-release.sh
python3 scripts/test-browser-host.py
archive="dist/MeetingBusy-$version-universal.zip"
checksum="$archive.sha256"
git push -u origin main
if ! git show-ref --verify --quiet "refs/tags/$tag"; then git tag -a "$tag" -m "Meeting Busy $version"; fi
git push origin "refs/tags/$tag"
gh release create "$tag" "$archive" "$checksum" --repo "$repository" --verify-tag --title "Meeting Busy $version" --notes-file RELEASE_NOTES.md --latest
