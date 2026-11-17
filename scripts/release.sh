#!/usr/bin/env bash
# Builds, signs, notarizes, and generates a Sparkle appcast for a release.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
if [[ -z "${NOTARY_PROFILE:-}" ]]; then
  echo "Set NOTARY_PROFILE to a stored notarytool Keychain profile (see RELEASING.md)." >&2
  exit 1
fi
./scripts/build-app.sh

SIGNATURE="$(codesign -dvv build/OpenRecord.app 2>&1)"
if [[ "$SIGNATURE" != *"Authority=Developer ID Application"* ]]; then
  echo "Release builds must be signed with a Developer ID Application identity (set CODESIGN_IDENTITY)." >&2
  exit 1
fi

rm -rf dist
mkdir -p dist
ZIP="dist/OpenRecord-$VERSION.zip"
ditto -c -k --keepParent build/OpenRecord.app "$ZIP"

xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple build/OpenRecord.app
# Re-zip so the download carries the stapled ticket and opens offline.
rm "$ZIP"
ditto -c -k --keepParent build/OpenRecord.app "$ZIP"
spctl --assess --type exec -vv build/OpenRecord.app

(cd dist && shasum -a 256 ./*.zip > SHA256SUMS.txt)

SPARKLE_BIN="$(find .build/artifacts/sparkle/Sparkle/bin -name generate_appcast -type f -print -quit)"
if [[ -z "$SPARKLE_BIN" ]]; then
  echo "Sparkle generate_appcast was not found. Resolve the Swift package dependency first." >&2
  exit 1
fi
"$SPARKLE_BIN" --download-url-prefix "https://github.com/dorukgunes/openrecord/releases/download/v$VERSION/" \
  -o dist/appcast.xml dist

echo "Release $VERSION:"
ls -l dist
