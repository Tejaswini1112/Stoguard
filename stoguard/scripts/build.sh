#!/usr/bin/env bash
# Cross-compile Stoguard for macOS, Windows, and Linux.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist"
mkdir -p "$OUT"
cd "$ROOT"

VERSION="${1:-1.0.0}"

build() {
  local goos="$1" goarch="$2" name="$3"
  local ext=""
  [[ "$goos" == "windows" ]] && ext=".exe"
  echo "==> $name ($goos/$goarch)"
  CGO_ENABLED=0 GOOS="$goos" GOARCH="$goarch" go build -ldflags "-s -w" -o "$OUT/$name$ext" .
}

build darwin arm64 "stoguard-darwin-arm64"
build darwin amd64 "stoguard-darwin-amd64"
build linux amd64 "stoguard-linux-amd64"
build linux arm64 "stoguard-linux-arm64"
build windows amd64 "stoguard-windows-amd64"

# Also build native for this machine
go build -ldflags "-s -w" -o "$OUT/stoguard" .

# Copy into website downloads
WEB_DL="$(cd "$ROOT/.." && pwd)/website/downloads"
mkdir -p "$WEB_DL"
cp -f "$OUT/stoguard-darwin-arm64" "$WEB_DL/stoguard-darwin-arm64" 2>/dev/null || true
cp -f "$OUT/stoguard-darwin-amd64" "$WEB_DL/stoguard-darwin-amd64" 2>/dev/null || true
cp -f "$OUT/stoguard-linux-amd64" "$WEB_DL/stoguard-linux-amd64" 2>/dev/null || true
cp -f "$OUT/stoguard-linux-arm64" "$WEB_DL/stoguard-linux-arm64" 2>/dev/null || true
cp -f "$OUT/stoguard-windows-amd64.exe" "$WEB_DL/stoguard-windows-amd64.exe" 2>/dev/null || true

echo "==> done ($VERSION)"
ls -lh "$OUT"
