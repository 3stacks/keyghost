#!/usr/bin/env bash
# Build and run a debug KeyGhost whose TCC grants survive rebuilds.
#
# Xcode/SPM debug builds are ad-hoc signed with a content-hash identifier, so
# macOS ties an Input Monitoring grant to one exact build and silently denies
# the next one. This script re-signs the debug binary with the Developer ID
# from .env and a fixed identifier. The binary path and designated requirement
# then stay stable, so you grant Input Monitoring + Accessibility once and
# every later dev build reuses the grant.
#
# Note: this launches outside the Xcode debugger. To debug, use
# Xcode > Debug > Attach to Process > KeyGhost after launch.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ -f "$ROOT/.env" ]; then
    set -a; source "$ROOT/.env"; set +a
fi

# CommandLineTools' SDK cannot compile the Liquid Glass views.
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

SIGNING_IDENTITY="${SIGNING_IDENTITY:?SIGNING_IDENTITY missing from .env — a stable cert is the whole point}"

echo "→ swift build (debug)"
swift build --package-path "$ROOT"

BIN="$ROOT/.build/debug/KeyGhost"

echo "→ re-sign with stable identity (com.lukeboyle.keyghost.dev)"
codesign --force --sign "$SIGNING_IDENTITY" \
    --identifier com.lukeboyle.keyghost.dev \
    "$BIN" 2>&1 | sed 's/^/    /'

echo "→ launch $BIN"
echo "  (grant Input Monitoring + Accessibility for this binary once; it sticks)"
exec "$BIN"
