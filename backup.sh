#!/bin/bash
# Copies your live inventory into the project at Data/inventory.json, so the
# whole project folder — code, docs and data — is self-contained and can be
# zipped, moved to another Mac, or committed to git as one unit.
#
#   ./backup.sh          copy live data into Data/
#   ./backup.sh restore  copy Data/inventory.json back over the live data
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIVE="$HOME/Library/Application Support/ComponentTracker/inventory.json"
COPY="$HERE/Data/inventory.json"
MODE="${1:-save}"

summarise() {
  python3 - "$1" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
c = d["components"]
print("    %d components, %d units total" % (len(c), sum(x.get("quantity", 0) for x in c)))
PY
}

case "$MODE" in
  save)
    mkdir -p "$HERE/Data"
    # Never clobber a good backup with a truncated or corrupt file.
    python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$LIVE" 2>/dev/null \
      || { echo "Live data is unreadable/corrupt — refusing to overwrite the backup."; exit 1; }
    cp "$LIVE" "$COPY"
    echo "==> Backed up live data to Data/inventory.json"
    summarise "$COPY"
    ;;
  restore)
    [ -f "$COPY" ] || { echo "No Data/inventory.json to restore from. Run './backup.sh' on the machine that has the data."; exit 1; }
    osascript -e 'tell application "ComponentTracker" to quit' >/dev/null 2>&1 || true
    pkill -f 'ComponentTracker.app/Contents/MacOS' >/dev/null 2>&1 || true
    sleep 1
    mkdir -p "$(dirname "$LIVE")"
    [ -f "$LIVE" ] && cp "$LIVE" "$LIVE.bak"   # keep the outgoing file, just in case
    cp "$COPY" "$LIVE"
    echo "==> Restored Data/inventory.json into the live data location"
    summarise "$LIVE"
    [ -f "$LIVE.bak" ] && echo "    previous live data kept at: $LIVE.bak"
    ;;
  *)
    echo "usage: ./backup.sh [save|restore]"; exit 1
    ;;
esac
