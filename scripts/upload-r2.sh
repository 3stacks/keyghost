#!/usr/bin/env bash
# Uploads the signed/notarized DMG and the Sparkle appcast.xml to the keyghost
# Cloudflare R2 bucket via R2's S3-compatible API. Reads VERSION,
# CLOUDFLARE_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY from the env
# (./.env is sourced automatically).
#
# Create the access keys at:
#   https://dash.cloudflare.com/<account>/r2/api-tokens
# with "Object Read & Write" scoped to the `keyghost` bucket.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ -f "$ROOT/.env" ]; then
    set -a; source "$ROOT/.env"; set +a
fi

NAME="KeyGhost"
VERSION="${VERSION:?VERSION env var is required, e.g. VERSION=0.2.0}"
BUCKET="${R2_BUCKET:-keyghost}"
ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:?CLOUDFLARE_ACCOUNT_ID env var is required}"
: "${R2_ACCESS_KEY_ID:?R2_ACCESS_KEY_ID env var is required (R2 token: Object Read & Write on bucket '$BUCKET')}"
: "${R2_SECRET_ACCESS_KEY:?R2_SECRET_ACCESS_KEY env var is required (paired with R2_ACCESS_KEY_ID)}"

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

if ! command -v aws >/dev/null 2>&1; then
    echo "✖ aws CLI not found — install with 'brew install awscli'" >&2
    exit 1
fi

ENDPOINT="https://${ACCOUNT_ID}.r2.cloudflarestorage.com"

# R2 ignores the region but aws CLI requires one; "auto" is the convention.
export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="auto"

# Upload the versioned DMG first so the appcast — which points at it — never
# references an object that doesn't exist yet.
echo "→ upload ${NAME}-${VERSION}.dmg → s3://${BUCKET}/"
aws s3 cp "$DMG" "s3://${BUCKET}/${NAME}-${VERSION}.dmg" \
    --endpoint-url "$ENDPOINT" \
    --content-type "application/x-apple-diskimage" \
    --checksum-algorithm CRC32 2>&1 | sed 's/^/    /'

echo "→ upload appcast.xml → s3://${BUCKET}/"
aws s3 cp "$APPCAST" "s3://${BUCKET}/appcast.xml" \
    --endpoint-url "$ENDPOINT" \
    --content-type "application/xml" \
    --cache-control "no-cache, max-age=0" \
    --checksum-algorithm CRC32 2>&1 | sed 's/^/    /'

echo "✓ uploaded ${NAME}-${VERSION}.dmg + appcast.xml to R2 bucket '$BUCKET'"
