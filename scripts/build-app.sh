#!/usr/bin/env bash
# Builds build/OpenRecord.app (menu bar app + bundled openrecord-mcp server).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product OpenRecord
swift build -c release --product openrecord-mcp
BIN="$(swift build -c release --show-bin-path)"

APP=build/OpenRecord.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/OpenRecord" "$BIN/openrecord-mcp" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns scripts/setup-whisper.sh "$APP/Contents/Resources/"

# macOS ties Screen Recording/Microphone grants to the code signature. An ad-hoc signature changes on
# every build, so prefer a real identity when one exists to keep permissions across rebuilds.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application|Apple Development/ { print $2; exit }')}"
IDENTITY="${IDENTITY:--}"
SIGN=(codesign --force --options runtime --sign "$IDENTITY")
# Secure timestamps are required for notarization but unavailable for ad-hoc signatures.
[[ "$IDENTITY" != "-" ]] && SIGN+=(--timestamp)

# Hardened runtime blocks the microphone unless the audio-input entitlement is present.
"${SIGN[@]}" "$APP/Contents/MacOS/openrecord-mcp"
"${SIGN[@]}" --entitlements Resources/OpenRecord.entitlements "$APP"
codesign --verify --strict "$APP"
echo "Built $APP (signed: $IDENTITY)"
