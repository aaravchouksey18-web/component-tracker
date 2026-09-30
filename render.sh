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

# The type-scale probe. Built against the app sources, not standalone: it needs
# `Skin`, `Type` and the real font constructors to measure anything true.
xcrun swiftc \
  -swift-version 5 \
  -target arm64-apple-macosx14.0 \
  -sdk "$(xcrun --show-sdk-path)" \
  -framework SwiftUI \
  -framework Charts \
  -framework AppKit \
  -framework Combine \
  $SOURCES \
  "$HERE/Tests/InkBands.swift" \
  -o "$HERE/build/InkBands"

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
# The status is captured on the same line as the command, via `||`.
# `PROBE_OK=$?` on the following line reads the exit of whatever ran last, and
# when the 90s watchdog above is still alive that is `kill $WATCH` — so a
# passing probe was recorded as exit 143 and the whole script failed. The probe
# was never wrong; the arithmetic was.
PROBE_OK=0
"$HERE/build/SwatchProbe" \
  "$HERE/build/renders/S-gd-sidebar.png" \
  "$HERE/build/renders/S-bd-cards.png" || PROBE_OK=$?

# Negative control. Expected to exit 1 (no swatches on a card grid). A 0 here
# means the probe matches indiscriminately and the check above is worthless.
if "$HERE/build/SwatchProbe" "$HERE/build/renders/S-gd-cards.png" >/dev/null 2>&1; then
  echo "PROBE IS VACUOUS — it found swatches in a view that has no switcher"
  exit 1
else
  echo "negative control ok — no swatches in a view without the switcher"
fi

# The type-scale probe. `Skin.figureSize` was declared, described in a commit
# message as the thing that gives Swiss its character, asserted in a test
# against another `Skin` field — and read by nothing. Every one of the 117 font
# call sites passed a literal, so the app rendered in 8–14pt with one 20pt
# figure in all three skins, and the whole suite stayed green.
#
# This is the check that would have caught it: it measures ink coverage per role
# in each skin and compares against point sizes pinned as literals, so
# collapsing the scale makes the measurement diverge from the expectation. Its
# first two versions both passed with the scale destroyed — one because it
# measured card fill instead of glyphs, the next because it derived the
# expectation from `Type.size` and so compared a value with itself.
echo ""
echo "== type scale probe =="
INK_OK=0
"$HERE/build/InkBands" || INK_OK=$?

# Negative control, same reasoning as the swatch probe: break the ladder on
# purpose and require the probe to notice. A probe never seen failing is not
# evidence, and this one had two false passes before this line existed.
cp "$HERE/Sources/Design.swift" "$HERE/build/Design.probe.bak"
# The trap restores the file if this script is interrupted between breaking the
# scale and putting it back, so a Ctrl-C cannot leave a sabotaged Design.swift
# on disk. It is cleared once the restore is done, and that matters more than it
# looks: a trap on EXIT runs *after* the explicit `exit`, and `exit` does not
# protect `$?` from the trap's own commands. With the backup already removed,
# the trap's `cp` failed and its status became the script's — so a run that
# passed every check still exited 1. `trap - EXIT` before the verdict, so the
# cleanup can never be what decides whether the render passed.
trap 'cp "$HERE/build/Design.probe.bak" "$HERE/Sources/Design.swift" 2>/dev/null || true' EXIT
python3 - "$HERE/Sources/Design.swift" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace("        case .display: return k.figureSize",
              "        case .display: return k.bodySize")
s = s.replace("        case .figure:  return k.figureSize - 3",
              "        case .figure:  return k.bodySize")
open(p, "w").write(s)
PY
xcrun swiftc \
  -swift-version 5 \
  -target arm64-apple-macosx14.0 \
  -sdk "$(xcrun --show-sdk-path)" \
  -framework SwiftUI \
  -framework Charts \
  -framework AppKit \
  -framework Combine \
  $SOURCES \
  "$HERE/Tests/InkBands.swift" \
  -o "$HERE/build/InkBands.broken" 2>/dev/null
if [ ! -x "$HERE/build/InkBands.broken" ]; then
  echo "TYPE PROBE COULD NOT BE BUILT — the negative control never ran, so the"
  echo "  probe above is untested. Treating that as a failure, not a pass."
  INK_OK=1
elif "$HERE/build/InkBands.broken" >/dev/null 2>&1; then
  echo "TYPE PROBE IS VACUOUS — it passed with the type scale destroyed"
  INK_OK=1
else
  echo "negative control ok — the probe fails when the scale is flattened"
fi
cp "$HERE/build/Design.probe.bak" "$HERE/Sources/Design.swift"
rm -f "$HERE/build/Design.probe.bak" "$HERE/build/InkBands.broken"

# Disarm the restore trap now that the file is back. Leaving it armed means it
# runs after the `exit` below, when the backup it copies from no longer exists,
# and the `cp`'s failure becomes the script's exit status — a run that passed
# every check reported failure. Disarming here means the cleanup is a fact that
# already happened, not a step that runs last and gets the last word.
trap - EXIT

# And if the restore itself failed, that is not a pass. A sabotaged Design.swift
# left on disk would be found by the next build, but a script that says "clean"
# while the source is broken is worse than one that stops.
if ! grep -q "case .display: return k.figureSize" "$HERE/Sources/Design.swift"; then
  echo "RESTORE FAILED — Sources/Design.swift did not come back intact."
  echo "  Restore it from git: git checkout -- Sources/Design.swift"
  exit 1
fi

if [ $PROBE_OK -eq 0 ] && [ $INK_OK -eq 0 ]; then exit 0; else exit 1; fi
