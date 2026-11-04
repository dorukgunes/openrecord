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
cp scripts/setup-whisper.sh "$APP/Contents/Resources/"

# macOS ties Screen Recording/Microphone grants to the code signature. An ad-hoc signature changes on
# every build, so prefer a real identity when one exists to keep permissions across rebuilds.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ { print $2; exit }')}"
IDENTITY="${IDENTITY:--}"
codesign --force --sign "$IDENTITY" "$APP/Contents/MacOS/openrecord-mcp"
codesign --force --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP (signed: $IDENTITY)"
