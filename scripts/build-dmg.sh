#!/usr/bin/env bash
# Build Stoguard.app and pack it into a compressed DMG for GitHub Releases.
# Usage: ./scripts/build-dmg.sh [version]   (default version: 0.3.1)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.3.1}"
STAGING="$ROOT/build/dmg-staging"
DMG="$ROOT/build/Stoguard-${VERSION}.dmg"

"$ROOT/scripts/build-app.sh"

echo "==> packaging DMG"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
if [ -d "$ROOT/build/Stoguard.app" ] && [ ! -L "$ROOT/build/Stoguard.app" ]; then
  cp -R "$ROOT/build/Stoguard.app" "$STAGING/"
elif [ -d "$ROOT/build/VACS.app" ]; then
  cp -R "$ROOT/build/VACS.app" "$STAGING/Stoguard.app"
else
  echo "error: build/Stoguard.app missing" >&2
  exit 1
fi
ln -sf /Applications "$STAGING/Applications"

hdiutil create \
  -volname "Stoguard ${VERSION}" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG"

rm -rf "$STAGING"
echo "==> done: $DMG"
