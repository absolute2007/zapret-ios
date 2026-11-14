#!/bin/bash
# Packs the built .app into an IPA for AltStore.
#
# The app is built with CODE_SIGNING_ALLOWED=NO and then ad-hoc signed here
# WITH entitlements: AltStore reads them from the binary to know which
# capabilities (Network Extension, App Groups) to register when re-signing.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/build/Build/Products/Release-iphoneos/Zapret.app}"
OUT="${2:-$ROOT/build/Zapret.ipa}"
APPEX="$APP/PlugIns/ZapretTunnel.appex"

[ -d "$APP" ] || { echo "app not found: $APP" >&2; exit 1; }
[ -d "$APPEX" ] || { echo "extension not found: $APPEX" >&2; exit 1; }

# Strip leftovers of the (disabled) Xcode signing.
find "$APP" -name "_CodeSignature" -type d -prune -exec rm -rf {} +
find "$APP" -name "embedded.mobileprovision" -delete

codesign --force --sign - --timestamp=none \
    --entitlements "$ROOT/Tunnel/ZapretTunnel.entitlements" "$APPEX"
codesign --force --sign - --timestamp=none \
    --entitlements "$ROOT/App/Zapret.entitlements" "$APP"

echo "==> Entitlements (app):"
codesign -d --entitlements - "$APP" 2>/dev/null || true
echo "==> Entitlements (extension):"
codesign -d --entitlements - "$APPEX" 2>/dev/null || true

WORK="$(mktemp -d)"
mkdir -p "$WORK/Payload"
cp -R "$APP" "$WORK/Payload/"
rm -f "$OUT"
(cd "$WORK" && zip -qry "$OUT" Payload)
rm -rf "$WORK"
echo "==> $OUT ($(du -h "$OUT" | cut -f1))"
