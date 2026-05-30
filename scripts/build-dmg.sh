#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="KeyGhost"
VERSION="${VERSION:-0.1.0}"
TEAM_ID="${TEAM_ID:-}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-notarytool-profile}"

SKIP_NOTARIZE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-notarize) SKIP_NOTARIZE=true; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# Build the .app (inherits VERSION, BUILD_NUMBER, SIGNING_IDENTITY, TEAM_ID).
VERSION="$VERSION" "$ROOT/scripts/build-app.sh"

APP="$ROOT/build/${NAME}.app"
STAGING="$ROOT/build/dmg-staging"
DMG="$ROOT/build/${NAME}-${VERSION}.dmg"

echo "→ stage dmg contents"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "→ create dmg"
rm -f "$DMG"
hdiutil create \
    -volname "$NAME $VERSION" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG" >/dev/null

rm -rf "$STAGING"

if [ "$SIGNING_IDENTITY" = "-" ]; then
    echo "→ codesign DMG (ad-hoc)"
    codesign --force --sign - "$DMG" 2>&1 | sed 's/^/    /'
else
    echo "→ codesign DMG ($SIGNING_IDENTITY)"
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG" 2>&1 | sed 's/^/    /'
fi

if [ "$SKIP_NOTARIZE" = false ] && [ "$SIGNING_IDENTITY" != "-" ]; then
    echo "→ notarize via $NOTARY_PROFILE (this can take a few minutes)"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "→ staple notarization ticket"
    xcrun stapler staple "$DMG"
else
    echo "→ skipping notarization"
fi

echo "→ gatekeeper assessment"
if spctl --assess --type open --context context:primary-signature "$DMG" 2>/dev/null; then
    echo "    Gatekeeper: OK"
else
    echo "    Gatekeeper: WARN (notarization may still be propagating, or this is an ad-hoc build)"
fi

# Generate Sparkle appcast.xml so the auto-update feed picks up this build. We
# need the private EdDSA key — passed via the SPARKLE_ED_PRIVATE_KEY env var in
# CI, looked up in the keychain locally. If neither is available we skip (e.g.
# unsigned developer builds don't ship via Sparkle anyway).
APPCAST="$ROOT/build/appcast.xml"
GENERATE_APPCAST="$ROOT/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
DOWNLOAD_URL_PREFIX="${SPARKLE_DOWNLOAD_URL_PREFIX:-https://keyghost.lukeboyle.com/}"

if [ ! -x "$GENERATE_APPCAST" ]; then
    echo "→ skip appcast (generate_appcast missing — run 'swift build' once to fetch Sparkle artifacts)"
elif [ "$SIGNING_IDENTITY" = "-" ]; then
    echo "→ skip appcast (ad-hoc builds aren't shipped via Sparkle)"
else
    echo "→ generate appcast.xml (download URL prefix: $DOWNLOAD_URL_PREFIX)"
    rm -f "$APPCAST"
    # generate_appcast scans the build dir; remove any old DMGs so only the
    # current one is published in the feed.
    find "$ROOT/build" -maxdepth 1 -name "*.dmg" -not -name "$(basename "$DMG")" -delete

    if [ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]; then
        echo "$SPARKLE_ED_PRIVATE_KEY" | "$GENERATE_APPCAST" \
            --ed-key-file - \
            --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
            "$ROOT/build" 2>&1 | sed 's/^/    /'
    else
        echo "    (using EdDSA key from keychain — pass SPARKLE_ED_PRIVATE_KEY to override)"
        "$GENERATE_APPCAST" \
            --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
            "$ROOT/build" 2>&1 | sed 's/^/    /'
    fi

    if [ -f "$APPCAST" ]; then
        echo "    appcast.xml: $(wc -l < "$APPCAST") lines"
    else
        echo "✖ appcast.xml was not generated" >&2
        exit 1
    fi
fi

echo "✓ built $DMG ($(du -h "$DMG" | cut -f1))"
