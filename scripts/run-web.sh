#!/usr/bin/env bash
# Keep the Stoguard local web UI running on http://127.0.0.1:8787
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/stoguard"
mkdir -p dist
if [[ ! -x dist/stoguard ]]; then
  echo "==> building stoguard"
  go build -o dist/stoguard .
fi
# Free the port if a stale process is stuck
if lsof -tiTCP:8787 -sTCP:LISTEN >/dev/null 2>&1; then
  echo "==> stopping existing listener on :8787"
  lsof -tiTCP:8787 -sTCP:LISTEN | xargs kill 2>/dev/null || true
  sleep 0.3
fi
echo "==> Stoguard web UI → http://127.0.0.1:8787"
exec ./dist/stoguard -port 8787 "$@"
