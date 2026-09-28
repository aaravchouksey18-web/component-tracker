#!/bin/bash
# Removes every regenerable artifact so the project is source-only.
# build/ is disposable: ./build.sh, ./test.sh and ./render.sh recreate it.
# Assets/, Sources/, Tests/, Tools/ and Data/ are never touched.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

echo "==> Removing build/ …"
rm -rf build

echo "==> Removing stray app copies outside /Applications …"
# The app belongs in /Applications only. If an old duplicate is lying around,
# remove it so there is exactly one bundle and one source of truth.
for stray in "$HOME/Desktop/ComponentTracker.app" \
             "$HOME/Desktop/ComponentTracker alias" \
             "$HOME/Desktop/Open ComponentTracker" \
             "$HOME/Applications/ComponentTracker.app"; do
  if [ -e "$stray" ]; then
    rm -rf "$stray"
    echo "    removed: $stray"
  fi
done

echo "==> Finder cruft …"
find . -name '.DS_Store' -delete 2>/dev/null || true

echo "==> Done. Project is now source-only:"
du -sh . | awk '{print "    total: " $1}'
echo "    rebuild with:  ./build.sh && ./install.sh"
