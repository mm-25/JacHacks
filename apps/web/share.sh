#!/usr/bin/env bash
# Puts this Sherry server (web app + API + database) online for teammates:
# runs Sherry in normal mode on one port and opens a Cloudflare quick tunnel
# to it. Ctrl+C stops both. Only one Sherry server may use the database at a
# time, so stop `jac start --dev` first.
set -euo pipefail
cd "$(dirname "$0")"

PORT="${SHERRY_PORT:-8000}"
JAC=../../.venv/bin/jac
CLOUDFLARED=../mcp/.bin/cloudflared
mkdir -p .jac
SERVER_LOG=.jac/share-server.log
TUNNEL_LOG=.jac/share-tunnel.log

if [ ! -x "$CLOUDFLARED" ]; then
  echo "cloudflared not found at apps/mcp/.bin/cloudflared (see apps/mcp/README.md)." >&2
  exit 1
fi
if lsof -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Port $PORT is in use. Stop the running Sherry dev server (Ctrl+C in its terminal) first." >&2
  exit 1
fi
if CERTS=$(../../.venv/bin/python -m certifi 2>/dev/null); then
  export SSL_CERT_FILE="$CERTS"
fi

"$JAC" start main.jac --port "$PORT" >"$SERVER_LOG" 2>&1 < /dev/null &
SERVER_PID=$!
TUNNEL_PID=""
trap 'kill $SERVER_PID ${TUNNEL_PID} 2>/dev/null || true' EXIT

echo "Starting Sherry on port $PORT…"
for _ in $(seq 1 120); do
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "Sherry stopped while starting. Last lines of $SERVER_LOG:" >&2
    tail -20 "$SERVER_LOG" >&2
    exit 1
  fi
  curl -s -o /dev/null "http://localhost:$PORT/" && break
  sleep 1
done

"$CLOUDFLARED" tunnel --no-autoupdate --url "http://localhost:$PORT" >"$TUNNEL_LOG" 2>&1 &
TUNNEL_PID=$!

URL=""
for _ in $(seq 1 30); do
  URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$TUNNEL_LOG" | head -1 || true)
  [ -n "$URL" ] && break
  sleep 1
done
if [ -z "$URL" ]; then
  echo "The tunnel didn't start; see apps/web/$TUNNEL_LOG" >&2
  exit 1
fi

echo
echo "  Sherry is online:  $URL"
echo "  Teammates use it as the Sherry URL / API base (POST $URL/function/<name>)."
echo "  Local access still works at http://localhost:$PORT"
echo
echo "Press Ctrl+C to stop sharing."
wait "$SERVER_PID"
