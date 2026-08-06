#!/usr/bin/env bash
# Build universal Stoguard.app (Apple Silicon + Intel) with plain swiftc.
# Usage: ./scripts/build-app.sh          (produces ./build/Stoguard.app)
#        ./scripts/build-app.sh --run    (build, self-test, then open the app)
set -euo pipefail

APP="Stoguard"
DISPLAY_NAME="Stoguard"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP_DIR="$BUILD/$DISPLAY_NAME.app"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
SWIFT_FILES=($(find "$ROOT/Sources/Stoguard" -name '*.swift'))

mkdir -p "$BUILD"

if [ ! -f "$ROOT/Assets/AppIcon.icns" ]; then
  echo "==> generating AppIcon.icns"
  swift "$ROOT/scripts/generate-icon.swift"
fi

echo "==> compiling arm64 + x86_64 ($(swiftc --version | head -1))"
swiftc \
  -O -parse-as-library \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  "${SWIFT_FILES[@]}" \
  -o "$BUILD/${APP}-arm64"

swiftc \
  -O -parse-as-library \
  -sdk "$SDK" \
  -target x86_64-apple-macos14.0 \
  "${SWIFT_FILES[@]}" \
  -o "$BUILD/${APP}-x86_64"

echo "==> lipo universal binary"
lipo -create -output "$BUILD/$APP" "$BUILD/${APP}-arm64" "$BUILD/${APP}-x86_64"
rm -f "$BUILD/${APP}-arm64" "$BUILD/${APP}-x86_64"
lipo -info "$BUILD/$APP"

echo "==> assembling $DISPLAY_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD/$APP" "$APP_DIR/Contents/MacOS/$APP"
cp "$ROOT/Sources/Stoguard/Resources/rules.json" "$APP_DIR/Contents/Resources/rules.json"
if [ -f "$ROOT/Sources/Stoguard/Resources/rules.manifest.json" ]; then
  cp "$ROOT/Sources/Stoguard/Resources/rules.manifest.json" "$APP_DIR/Contents/Resources/rules.manifest.json"
fi
mkdir -p "$APP_DIR/Contents/Resources/PluginExamples"
for f in plugin-windows.example.json plugin-linux.example.json; do
  if [ -f "$ROOT/Sources/Stoguard/Resources/$f" ]; then
    cp "$ROOT/Sources/Stoguard/Resources/$f" "$APP_DIR/Contents/Resources/PluginExamples/$f"
  fi
done
cp "$ROOT/Assets/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key><string>$DISPLAY_NAME</string>
  <key>CFBundleIdentifier</key><string>app.stoguard.Stoguard</string>
  <key>CFBundleVersion</key><string>0.4.2</string>
  <key>CFBundleShortVersionString</key><string>0.4.2</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>$APP</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP_DIR"

echo "==> self-test"
"$APP_DIR/Contents/MacOS/$APP" --selftest

rm -rf "$BUILD/VACS.app"
ln -sfn "$DISPLAY_NAME.app" "$BUILD/VACS.app"

echo "==> done: $APP_DIR (universal)"
if [ "${1:-}" = "--run" ]; then
  open "$APP_DIR"
else
  echo "    open \"$APP_DIR\""
fi
