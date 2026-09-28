#!/bin/bash
# Build ComponentTracker.app — native SwiftUI, no Xcode required.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="ComponentTracker"
BUNDLE_ID="com.componenttracker.ComponentTracker"
VERSION="1.0.0"
BUILD_DIR="$HERE/build"
APP="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP/Contents"

SDK="$(xcrun --show-sdk-path)"
ARCH="$(uname -m)"
TARGET="arm64-apple-macosx14.0"

echo "==> SDK      : $SDK"
echo "==> Arch     : $ARCH ($TARGET)"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

echo "==> Compiling…"
xcrun swiftc \
  -O \
  -parse-as-library \
  -swift-version 5 \
  -target "$TARGET" \
  -sdk "$SDK" \
  -framework SwiftUI \
  -framework AppKit \
  -framework Charts \
  -framework Combine \
  "$HERE"/Sources/*.swift \
  -o "$CONTENTS/MacOS/$APP_NAME"

echo "==> Writing Info.plist…"
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSSupportsAutomaticTermination</key><true/>
  <key>NSSupportsSuddenTermination</key><true/>
  <key>NSHumanReadableCopyright</key><string>Local inventory tracker</string>
</dict>
</plist>
PLIST

echo "==> Installing icon…"
if [ ! -f "$HERE/Assets/AppIcon.icns" ]; then
  "$HERE/make-icon.sh" >/dev/null 2>&1 || echo "    (icon generation failed — app will use the default icon)"
fi
cp "$HERE/Assets/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns" 2>/dev/null \
  || echo "    (no icon found — app will use the default icon)"

echo "==> Signing (ad-hoc)…"
codesign --force --sign - --timestamp=none "$APP" 2>/dev/null \
  || codesign --force --deep --sign - "$APP"

echo "==> Done: $APP"
du -sh "$APP" | awk '{print "    size: " $1}'
