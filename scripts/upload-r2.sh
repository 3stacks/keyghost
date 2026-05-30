#!/usr/bin/env bash
# Uploads the signed/notarized DMG and the Sparkle appcast.xml to the keyghost
# Cloudflare R2 bucket. Reads VERSION + CLOUDFLARE_ACCOUNT_ID + CLOUDFLARE_API_TOKEN
# from the environment. CLOUDFLARE_API_TOKEN is the auth wrangler picks up; the
# account ID can be set as an env var or via the --remote flag's context.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="KeyGhost"
VERSION="${VERSION:?VERSION env var is required, e.g. VERSION=0.2.0}"
BUCKET="${R2_BUCKET:-keyghost}"
ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:?CLOUDFLARE_ACCOUNT_ID env var is required}"

DMG="$ROOT/build/${NAME}-${VERSION}.dmg"
APPCAST="$ROOT/build/appcast.xml"

if [ ! -f "$DMG" ]; then
    echo "✖ DMG not found at $DMG — run build-dmg.sh first" >&2
    exit 1
fi
if [ ! -f "$APPCAST" ]; then
    echo "✖ appcast.xml not found at $APPCAST — run build-dmg.sh with EdDSA key" >&2
    exit 1
fi

WRANGLER="$ROOT/node_modules/.bin/wrangler"
if [ ! -x "$WRANGLER" ]; then
    echo "✖ wrangler not found at $WRANGLER — run 'bun install' (or 'npm install') first" >&2
    exit 1
fi

# Upload the versioned DMG first so the appcast — which points at it — never
# references an object that doesn't exist yet.
echo "→ upload ${NAME}-${VERSION}.dmg → $BUCKET/"
CLOUDFLARE_ACCOUNT_ID="$ACCOUNT_ID" "$WRANGLER" r2 object put \
    "$BUCKET/${NAME}-${VERSION}.dmg" \
    --file="$DMG" \
    --remote 2>&1 | sed 's/^/    /'

echo "→ upload appcast.xml → $BUCKET/"
CLOUDFLARE_ACCOUNT_ID="$ACCOUNT_ID" "$WRANGLER" r2 object put \
    "$BUCKET/appcast.xml" \
    --file="$APPCAST" \
    --content-type="application/xml" \
    --remote 2>&1 | sed 's/^/    /'

echo "✓ uploaded ${NAME}-${VERSION}.dmg + appcast.xml to R2 bucket '$BUCKET'"
