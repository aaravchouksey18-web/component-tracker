#!/bin/bash
# Offscreen UI renders -> build/renders/*.png
# MainView.swift is excluded because it declares the app's @main entry point.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$HERE/build"

SOURCES=$(ls "$HERE"/Sources/*.swift | grep -v 'MainView.swift')

xcrun swiftc \
  -swift-version 5 \
  -target arm64-apple-macosx14.0 \
  -sdk "$(xcrun --show-sdk-path)" \
  -framework SwiftUI \
  -framework Charts \
  -framework AppKit \
  -framework Combine \
  $SOURCES \
  "$HERE/Tests/RenderTests.swift" \
  -o "$HERE/build/RenderTests"

# Guard against a renderer that cannot exit, so this never blocks a build.
if command -v gtimeout >/dev/null 2>&1; then
  gtimeout 90 "$HERE/build/RenderTests"
else
  "$HERE/build/RenderTests" &
  RT=$!
  ( sleep 90; kill -9 $RT 2>/dev/null ) &
  WATCH=$!
  wait $RT 2>/dev/null || true
  kill $WATCH 2>/dev/null || true
fi
