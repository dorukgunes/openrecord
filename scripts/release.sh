#!/usr/bin/env bash
# Builds a Developer ID signed release zip plus SHA256SUMS.txt in dist/.
# Set NOTARY_PROFILE (see CONTRIBUTING.md) to notarize and staple it too.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
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

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple build/OpenRecord.app
  # Re-zip so the download carries the stapled ticket and opens offline.
  rm "$ZIP"
  ditto -c -k --keepParent build/OpenRecord.app "$ZIP"
  spctl --assess --type exec -vv build/OpenRecord.app
else
  echo "NOTARY_PROFILE not set: $ZIP is signed but not notarized, so Gatekeeper will block it on other Macs." >&2
fi

(cd dist && shasum -a 256 ./*.zip > SHA256SUMS.txt)
echo "Release $VERSION:"
ls -l dist
