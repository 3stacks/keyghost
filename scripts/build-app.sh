#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Source ./.env if present so SIGNING_IDENTITY, TEAM_ID, etc. can live there
# instead of the shell. The file is gitignored. A stable Developer ID
# signature is what makes TCC remember Accessibility + Input Monitoring
# grants across rebuilds — ad-hoc signing gives a fresh cdhash every time.
if [ -f "$ROOT/.env" ]; then
    set -a; source "$ROOT/.env"; set +a
fi

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
FRAMEWORKS="$APP/Contents/Frameworks"

echo "→ clean"
rm -rf "$ROOT/build"
mkdir -p "$MACOS" "$RES" "$FRAMEWORKS"

echo "→ swift build (release)"
swift build -c release --package-path "$ROOT"

BIN_SRC="$ROOT/.build/release/$NAME"
if [ ! -x "$BIN_SRC" ]; then
    echo "✖ release binary not found at $BIN_SRC" >&2
    exit 1
fi

echo "→ stage binary"
cp "$BIN_SRC" "$MACOS/$NAME"

# Embed Sparkle.framework alongside the main binary. SPM produces an xcframework
# under .build/artifacts/sparkle; pick the macos slice.
SPARKLE_SRC="$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ ! -d "$SPARKLE_SRC" ]; then
    echo "✖ Sparkle.framework not found at $SPARKLE_SRC (expected after 'swift build')" >&2
    exit 1
fi
echo "→ stage Sparkle.framework"
cp -R "$SPARKLE_SRC" "$FRAMEWORKS/"

# The release binary embeds @rpath/Sparkle.framework/...; add a runtime path so
# that resolves to the framework we just embedded.
echo "→ add rpath @executable_path/../Frameworks"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS/$NAME" 2>/dev/null || true

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

# Sparkle ships several nested bundles (XPC services, the Autoupdate helper,
# Updater.app) that must be signed deep-first or codesign refuses to seal the
# outer .app. This mirrors what ko-nav does for its Xcode-embedded Sparkle.
SPARKLE_FW="$FRAMEWORKS/Sparkle.framework"

# XPC services (Installer + Downloader, used at runtime to talk between the
# sandboxed updater and the main app).
find "$SPARKLE_FW" -name "*.xpc" -type d | while read -r xpc; do
    echo "    sparkle xpc: $(basename "$xpc")"
    codesign "${SIGN_ARGS[@]}" "$xpc" 2>&1 | sed 's/^/      /' || true
done

# Sparkle's Autoupdate helper and Updater.app live under Versions/B.
SPARKLE_VB="$SPARKLE_FW/Versions/B"
if [ -x "$SPARKLE_VB/Autoupdate" ]; then
    echo "    sparkle: Autoupdate"
    codesign "${SIGN_ARGS[@]}" "$SPARKLE_VB/Autoupdate" 2>&1 | sed 's/^/      /' || true
fi
if [ -d "$SPARKLE_VB/Updater.app" ]; then
    echo "    sparkle: Updater.app"
    codesign "${SIGN_ARGS[@]}" "$SPARKLE_VB/Updater.app" 2>&1 | sed 's/^/      /' || true
fi

# The framework itself, after its internals are sealed.
echo "    sparkle: Sparkle.framework"
codesign "${SIGN_ARGS[@]}" "$SPARKLE_FW" 2>&1 | sed 's/^/      /' || true

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
