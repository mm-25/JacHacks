#!/bin/bash
# Sends the desktop scraper's chats to Sherry, continuously (sherry_sync.jac).
#
# Your API key is personal: never commit it. Put it in ~/.sherry/sync.env:
#     SHERRY_API_KEY=shr_...
# (Sherry web -> account menu -> Connect apps and assistants -> Create key),
# or export SHERRY_API_KEY before running this script.
export PYTHONUNBUFFERED=1
cd "$(dirname "$0")"

if [ -d "venv" ]; then
    source "venv/bin/activate"
elif [ -d "../venv" ]; then
    source "../venv/bin/activate"
fi

if [ -f "$HOME/.sherry/sync.env" ]; then
    set -a
    source "$HOME/.sherry/sync.env"
    set +a
fi

export SHERRY_URL="${SHERRY_URL:-https://sherry.sherry-cloud.workers.dev}"
export SHERRY_SYNC_FILE="${SHERRY_SYNC_FILE:-$HOME/.sherry/scraped_data.json}"

if [ -z "$SHERRY_API_KEY" ]; then
    echo "Set SHERRY_API_KEY (or put SHERRY_API_KEY=shr_... in ~/.sherry/sync.env)." >&2
    exit 1
fi

echo "Starting Sherry Sync daemon..."
jac run sherry_sync.jac
