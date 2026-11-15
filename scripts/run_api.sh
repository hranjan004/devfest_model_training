#!/usr/bin/env bash
# Start the UCSC Wildlife API (34-class BioCLIP inference + app feed) on port 8080.
# 0.0.0.0 lets a phone on the same Wi-Fi reach it at http://<this-mac-ip>:8080.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -x .venv/bin/uvicorn ]; then
  python3 -m venv .venv
  .venv/bin/pip install --upgrade pip
  .venv/bin/pip install -e ".[app]"
fi
export PYTHONPATH="src:."
exec .venv/bin/uvicorn api.main:app --host "${HOST:-0.0.0.0}" --port "${PORT:-8080}" --workers 1
