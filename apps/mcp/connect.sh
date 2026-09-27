#!/usr/bin/env bash
# Opens a Cloudflare quick tunnel to the Sherry MCP server and starts the server
# with that public URL. Ctrl+C stops both. Sherry itself (apps/web) must be running.
set -euo pipefail
cd "$(dirname "$0")"

PORT="${SHERRY_MCP_PORT:-8100}"
LOG=.data/tunnel.log
mkdir -p .data

if [ ! -x .bin/cloudflared ]; then
  echo "cloudflared not found in apps/mcp/.bin (see README: Connect claude.ai or ChatGPT)." >&2
  exit 1
fi

.bin/cloudflared tunnel --no-autoupdate --url "http://localhost:$PORT" >"$LOG" 2>&1 &
TUNNEL_PID=$!
trap 'kill $TUNNEL_PID 2>/dev/null || true' EXIT

URL=""
for _ in $(seq 1 30); do
  URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$LOG" | head -1 || true)
  [ -n "$URL" ] && break
  sleep 1
done
if [ -z "$URL" ]; then
  echo "The tunnel didn't start; see apps/mcp/$LOG" >&2
  exit 1
fi

echo
echo "  Connector URL (paste into claude.ai):  $URL/mcp"
echo

SHERRY_MCP_PUBLIC_URL="$URL" ../../.venv/bin/jac run main.jac
