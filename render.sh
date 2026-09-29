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

# The swatch probe. A unit test can assert `Skin.all.count == 3` and pass while
# the switcher is not on screen at all, because the data is right and the view
# is not. This asks the rendered pixels instead.
#
# It runs against a view that HAS the switcher and a view that does not. The
# negative case is the point: a probe that finds the swatches everywhere is
# matching something else, and would report PASS on a build where the section
# had been deleted.
xcrun swiftc \
  -swift-version 5 \
  -target arm64-apple-macosx14.0 \
  -sdk "$(xcrun --show-sdk-path)" \
  -framework AppKit \
  "$HERE/Tests/SwatchProbe.swift" \
  -o "$HERE/build/SwatchProbe"

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

echo ""
echo "== swatch probe =="
"$HERE/build/SwatchProbe" \
  "$HERE/build/renders/S-gd-sidebar.png" \
  "$HERE/build/renders/S-bd-cards.png"
PROBE_OK=$?

# Negative control. Expected to exit 1 (no swatches on a card grid). A 0 here
# means the probe matches indiscriminately and the check above is worthless.
if "$HERE/build/SwatchProbe" "$HERE/build/renders/S-gd-cards.png" >/dev/null 2>&1; then
  echo "PROBE IS VACUOUS — it found swatches in a view that has no switcher"
  exit 1
else
  echo "negative control ok — no swatches in a view without the switcher"
fi

exit $PROBE_OK
