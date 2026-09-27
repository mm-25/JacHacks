export PYTHONUNBUFFERED=1
#!/bin/bash
cd "$(dirname "$0")"

if [ -d "venv" ]; then
    source "venv/bin/activate"
elif [ -d "../venv" ]; then
    source "../venv/bin/activate"
fi

export SHERRY_URL="https://sherry.sherry-cloud.workers.dev"
export SHERRY_API_KEY="shr_CL4lSPqu1n78xIUpxooKU0YSqnYvZoudaWlK9OtsX-c"
export SHERRY_SYNC_FILE="$HOME/.sherry/scraped_data.json"

echo "Starting Sherry Sync daemon..."
jac run sherry_sync.jac
