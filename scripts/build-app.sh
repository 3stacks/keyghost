#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="KeyGhost"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
TEAM_ID="${TEAM_ID:-}"
# Default: ad-hoc sign. Override with SIGNING_IDENTITY="Developer ID Application: Your Org (TEAMID)"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
ENTITLEMENTS="$ROOT/Bundle/Entitlements.plist"

# Pass SIGNING_IDENTITY=- for ad-hoc (skips --timestamp + Developer ID metadata).
if [ "$SIGNING_IDENTITY" = "-" ]; then
    SIGN_ARGS=(--force --sign -)
    DMG_SIGN_ARGS=(--force --sign -)
else
    SIGN_ARGS=(--force --sign "$SIGNING_IDENTITY" --timestamp --options runtime)
    DMG_SIGN_ARGS=(--force --sign "$SIGNING_IDENTITY" --timestamp)
fi

APP="$ROOT/build/${NAME}.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"

echo "→ clean"
rm -rf "$ROOT/build"
mkdir -p "$MACOS" "$RES"

echo "→ swift build (release)"
swift build -c release --package-path "$ROOT"

BIN_SRC="$ROOT/.build/release/$NAME"
if [ ! -x "$BIN_SRC" ]; then
    echo "✖ release binary not found at $BIN_SRC" >&2
    exit 1
fi

echo "→ stage binary"
cp "$BIN_SRC" "$MACOS/$NAME"

# Swift Package resources live in a sibling .bundle next to the executable.
# Bundle.module also probes Bundle.main.resourceURL, so Contents/Resources/ works
# inside an .app. .build/release is a symlink so use a glob instead of find.
shopt -s nullglob
for b in "$ROOT"/.build/release/*.bundle; do
    if [ -d "$b" ]; then
        echo "→ stage resource bundle ($(basename "$b"))"
        cp -R "$b" "$RES/"
    fi
done
shopt -u nullglob

echo "→ write Info.plist (v$VERSION build $BUILD_NUMBER)"
sed \
    -e "s/__VERSION__/$VERSION/" \
    -e "s/__BUILD__/$BUILD_NUMBER/" \
    "$ROOT/Bundle/Info.plist" > "$APP/Contents/Info.plist"

echo "→ codesign ($SIGNING_IDENTITY)"
# Note: SPM's resource bundle is a flat dir with the .bundle suffix and no
# Info.plist, which codesign won't accept as a sub-bundle. We sign only the
# main app — the .app signature seals the resource files by hash.
if [ "$SIGNING_IDENTITY" = "-" ]; then
    codesign "${SIGN_ARGS[@]}" "$APP" 2>&1 | sed 's/^/    /'
else
    codesign "${SIGN_ARGS[@]}" --entitlements "$ENTITLEMENTS" "$APP" 2>&1 | sed 's/^/    /'
fi

echo "→ verify signature"
codesign --verify --deep --strict "$APP" && echo "    signature OK"
if [ "$SIGNING_IDENTITY" != "-" ]; then
    codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "Authority|TeamIdentifier|Signature" | sed 's/^/    /'
fi

echo "✓ built $APP"
