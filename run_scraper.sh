#!/bin/bash

# Navigate to the workspace directory
cd "$(dirname "$0")"

# Activate Python virtual environment
if [ -d "venv" ]; then
    source "venv/bin/activate"
elif [ -d "../venv" ]; then
    source "../venv/bin/activate"
else
    echo "Virtual environment not found. Please create one (python -m venv venv) and pip install jaclang."
    exit 1
fi

# Run the jaclang scraper
echo "Starting JacHacks Scraper daemon..."
jac run scraper.jac
