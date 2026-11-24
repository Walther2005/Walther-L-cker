#!/bin/bash
# Baut Pixelwisch.app im Ordner build/.  Voraussetzung: Xcode oder die Command Line Tools.
#   ./build-app.sh              – für diesen Mac
#   ./build-app.sh --universal  – für Apple Silicon und Intel
set -euo pipefail
cd "$(dirname "$0")"

ARCH_FLAGS=()
if [[ "${1:-}" == "--universal" ]]; then ARCH_FLAGS=(--arch arm64 --arch x86_64); fi

swift build -c release "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}"
BIN="$(swift build -c release "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}" --show-bin-path)/Pixelwisch"

APP=build/Pixelwisch.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Pixelwisch"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if swift Scripts/make-icon.swift build/AppIcon.iconset && iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"; then
  echo "Symbol erstellt."
else
  echo "Hinweis: Symbol konnte nicht erstellt werden – die App funktioniert trotzdem."
fi

codesign --force --sign - "$APP"
echo "Fertig: $APP"
