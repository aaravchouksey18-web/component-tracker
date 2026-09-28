#!/bin/bash
# Installs ComponentTracker.app to /Applications — the single, only install location.
# There is deliberately no Desktop copy: duplicate bundles of the same app invite
# accidental double-launch, and the app self-guards against that anyway.
# Set INSTALL_PREFIX to install somewhere else (e.g. ~/Applications).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/build/ComponentTracker.app"
PREFIX="${INSTALL_PREFIX:-/Applications}"
DEST="$PREFIX/ComponentTracker.app"

[ -d "$SRC" ] || { echo "Build first: ./build.sh"; exit 1; }
mkdir -p "$PREFIX"

# Quit any running copy so the bundle can be replaced cleanly.
osascript -e 'tell application "ComponentTracker" to quit' >/dev/null 2>&1 || true
pkill -f 'ComponentTracker.app/Contents/MacOS' >/dev/null 2>&1 || true
sleep 1

# Note: ${PREFIX} must stay braced. An unbraced $PREFIX followed by the
# multibyte "…" makes bash treat "PREFIX…" as the variable name.
echo "==> Installing to ${PREFIX}…"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"
touch "$DEST"

# The app is ad-hoc signed, so the signature is invalidated by the copy.
# Re-sign in place so Gatekeeper accepts the installed bundle.
codesign --force --sign - --timestamp=none "$DEST" 2>/dev/null \
  || codesign --force --deep --sign - "$DEST"

echo "==> Done"
echo "    $DEST"
echo "    data: $HOME/Library/Application Support/ComponentTracker/inventory.json"
echo "    (run ./backup.sh to copy your data into Data/ in this project)"
