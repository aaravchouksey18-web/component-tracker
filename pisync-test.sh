#!/bin/bash
# End-to-end test for the Pi push: drives the real PiSyncController against the
# real Raspberry Pi and verifies the bytes that land there. Needs the Pi
# reachable and key-based SSH auth working — it is not a headless unit test.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/build/PiSyncE2E"

mkdir -p "$HERE/build"

echo "==> Building Pi sync E2E harness…"
xcrun swiftc \
  -swift-version 5 \
  -target arm64-apple-macosx14.0 \
  -sdk "$(xcrun --show-sdk-path)" \
  -framework SwiftUI \
  -framework Combine \
  "$HERE/Sources/Model.swift" \
  "$HERE/Sources/Design.swift" \
  "$HERE/Sources/Store.swift" \
  "$HERE/Sources/ExportService.swift" \
  "$HERE/Sources/PiSync.swift" \
  "$HERE/Tests/PiSyncE2E.swift" \
  -o "$OUT"

echo "==> Running against the Pi…"
echo "    (endpoint from PI_TEST_HOST/PI_TEST_PORT/PI_TEST_USER/PI_TEST_REMOTE_DIR,"
echo "     defaults pi.local:22 as user pi into ~/component-tracker-e2e — a sandbox,"
echo "     never your real backup folder)"
# Only pass variables that are actually set: `${VAR:-}` would export an *empty
# string* to the harness, and Swift's `?? default` falls back on unset, not on
# "" — a bare `./pisync-test.sh` would then try to ssh to host "".
ENV_ARGS=()
[[ -n "${PI_TEST_HOST:-}" ]] && ENV_ARGS+=(PI_TEST_HOST="$PI_TEST_HOST")
[[ -n "${PI_TEST_PORT:-}" ]] && ENV_ARGS+=(PI_TEST_PORT="$PI_TEST_PORT")
[[ -n "${PI_TEST_USER:-}" ]] && ENV_ARGS+=(PI_TEST_USER="$PI_TEST_USER")
[[ -n "${PI_TEST_REMOTE_DIR:-}" ]] && ENV_ARGS+=(PI_TEST_REMOTE_DIR="$PI_TEST_REMOTE_DIR")
env "${ENV_ARGS[@]}" "$OUT"
