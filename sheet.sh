#!/bin/bash
# Compose render PNGs into one contact sheet for side-by-side comparison.
# Usage: ./sheet.sh <out.png> ["LABEL=path" ...]
# Bare paths are accepted too; the label defaults to the filename.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${1:?usage: sheet.sh <out.png> [label=path ...]}"
shift

if [ $# -eq 0 ]; then
  echo "usage: $0 <out.png> [label=path ...]" >&2
  exit 1
fi

xcrun swiftc \
  -swift-version 5 \
  -target arm64-apple-macosx14.0 \
  -sdk "$(xcrun --show-sdk-path)" \
  -framework AppKit \
  "$HERE/Tests/ContactSheet.swift" \
  -o "$HERE/build/ContactSheet"

"$HERE/build/ContactSheet" "$OUT" "$@"
