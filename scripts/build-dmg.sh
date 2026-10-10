#!/usr/bin/env bash
# Build Stoguard.app and pack it into a compressed DMG for GitHub Releases.
# Usage: ./scripts/build-dmg.sh [version]   (default version: 0.1.0)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.1.0}"
STAGING="$ROOT/build/dmg-staging"
DMG="$ROOT/build/Stoguard-${VERSION}.dmg"

"$ROOT/scripts/build-app.sh"

echo "==> packaging DMG"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$ROOT/build/Stoguard.app" "$STAGING/"
ln -sf /Applications "$STAGING/Applications"

hdiutil create \
  -volname "Stoguard ${VERSION}" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG"

rm -rf "$STAGING"
echo "==> done: $DMG"
