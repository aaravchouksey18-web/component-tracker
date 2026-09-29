#!/bin/bash
# Headless logic tests for ComponentTracker.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/build/Tests"

mkdir -p "$HERE/build"

echo "==> Building tests…"
xcrun swiftc \
  -swift-version 5 \
  -target arm64-apple-macosx14.0 \
  -sdk "$(xcrun --show-sdk-path)" \
  -framework SwiftUI \
  -framework Combine \
  -framework AppKit \
  "$HERE/Sources/Model.swift" \
  "$HERE/Sources/Design.swift" \
  "$HERE/Sources/Store.swift" \
  "$HERE/Sources/PiSync.swift" \
  "$HERE/Sources/ExportService.swift" \
  "$HERE/Tests/Tests.swift" \
  -o "$OUT"

echo "==> Running…"
"$OUT"

# Layout/theme lint runs after the unit tests, not before, so a logic failure is
# still the thing you see first. It is cheap and it is the only automated check
# that can see the class of bug a unit test structurally cannot: a view that
# compiles, holds the right data, and lays out wrong.
echo ""
echo "==> Linting…"
./lint.sh
