#!/bin/bash
# Generates the app icon into Assets/AppIcon.icns (a source asset, not a build
# artifact) and, if a built app bundle is lying around, installs it there too.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

mkdir -p Assets build

xcrun swiftc \
  -swift-version 5 \
  -parse-as-library \
  -target arm64-apple-macosx14.0 \
  -sdk "$(xcrun --show-sdk-path)" \
  -framework AppKit \
  -framework CoreGraphics \
  Tools/IconGen.swift \
  -o build/IconGen

./build/IconGen

rm -f Assets/AppIcon.icns
iconutil -c icns build/AppIcon.iconset -o Assets/AppIcon.icns
echo "==> Assets/AppIcon.icns created"

APP="build/ComponentTracker.app"
if [ -d "$APP" ]; then
  cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  # Refresh the resource seal, then re-sign so the bundle stays valid.
  codesign --force --sign - --timestamp=none "$APP" 2>/dev/null \
    || codesign --force --deep --sign - "$APP"
  echo "==> icon installed in $APP"
fi
