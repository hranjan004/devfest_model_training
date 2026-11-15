#!/usr/bin/env bash
# Start the real BioCLIP-v4 API and coy's native response adapter. No installs,
# resets, seeds, or termination of services started by another process.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
export DEVFEST_MODEL_ROOT="${DEVFEST_MODEL_ROOT:-$REPO_ROOT}"
export WILDLIFE_UCSC34_RUN_DIR="${WILDLIFE_UCSC34_RUN_DIR:-$DEVFEST_MODEL_ROOT/runs/ucsc34_bioclip_v4}"
export PYTHONPATH="$REPO_ROOT/src:$REPO_ROOT${PYTHONPATH:+:$PYTHONPATH}"
COY_PYTHON="${COY_PYTHON:-$REPO_ROOT/.venv/bin/python}"
COY_HOST="${COY_HOST:-0.0.0.0}"
COY_PORT="${COY_PORT:-8081}"
COY_API_PORT="${COY_API_PORT:-8080}"
COY_LOG_DIR="${COY_LOG_DIR:-$REPO_ROOT/data/app/coy-logs}"
API_DEFAULT="http://127.0.0.1:$COY_API_PORT"
export WILDLIFE_V4_URL="${WILDLIFE_V4_URL:-$API_DEFAULT}"
WILDLIFE_V4_URL="${WILDLIFE_V4_URL%/}"
api_pid=""
bridge_pid=""

if [[ ! -x "$COY_PYTHON" ]]; then
  echo "Python environment missing: $COY_PYTHON" >&2
  echo "From the repository: python3 -m venv .venv && .venv/bin/python -m pip install -e '.[app]'" >&2
  exit 1
fi
if ! "$COY_PYTHON" - <<'PY'
import importlib.util
import sys
missing = [name for name in ("uvicorn", "fastapi", "requests", "numpy", "PIL", "multipart", "torch", "open_clip") if importlib.util.find_spec(name) is None]
if missing:
    print("Missing dependencies: " + ", ".join(missing), file=sys.stderr)
    print("Install with: .venv/bin/python -m pip install -e '.[app]'", file=sys.stderr)
    sys.exit(1)
PY
then
  exit 1
fi
if [[ ! -f "$WILDLIFE_UCSC34_RUN_DIR/classes.json" ]]; then
  echo "Missing trained catalog: $WILDLIFE_UCSC34_RUN_DIR/classes.json" >&2
  echo "Restore your trained ucsc34_bioclip_v4 run (see docs/IPHONE_SETUP.md). Model artifacts are not bundled in git." >&2
  exit 1
fi

health() {
  "$COY_PYTHON" - "$1" "$2" <<'PY'
import json
import sys
import urllib.request
try:
    with urllib.request.urlopen(sys.argv[1], timeout=2) as response:
        result = json.load(response)
    ok = result.get("num_classes") == 34 and result.get("model_version") == "ucsc34-bioclip2-v4"
    ok = ok and (result.get("ready") is True if sys.argv[2] == "bridge" else result.get("status") == "ok" and result.get("weights_present") is True)
    sys.exit(0 if ok else 1)
except Exception:
    sys.exit(1)
PY
}

cleanup() {
  trap - EXIT INT TERM
  # These PIDs belong to children of this launcher. Reused APIs are untouched.
  for owned_pid in "$bridge_pid" "$api_pid"; do
    if [[ -n "$owned_pid" ]]; then
      kill "$owned_pid" 2>/dev/null || true
      wait "$owned_pid" 2>/dev/null || true
    fi
  done
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

check_host="$COY_HOST"
if [[ "$check_host" == "0.0.0.0" || "$check_host" == "::" ]]; then check_host="127.0.0.1"; fi
bridge_url="http://$check_host:$COY_PORT"
if health "$bridge_url/healthz" bridge; then
  echo "coy is already ready at $bridge_url (existing services left running)."
  exit 0
fi
mkdir -p "$COY_LOG_DIR"
if health "$WILDLIFE_V4_URL/v3/health" api; then
  echo "Using existing BioCLIP-v4 API at $WILDLIFE_V4_URL"
else
  if [[ "$WILDLIFE_V4_URL" != "$API_DEFAULT" ]]; then
    echo "Configured external BioCLIP-v4 API is not healthy: $WILDLIFE_V4_URL/v3/health" >&2
    exit 1
  fi
  if [[ ! -f "$WILDLIFE_UCSC34_RUN_DIR/model_adapter.pt" ]]; then
    echo "Missing trained weights: $WILDLIFE_UCSC34_RUN_DIR/model_adapter.pt" >&2
    echo "Restore your trained run; the launcher never substitutes another model." >&2
    exit 1
  fi
  "$COY_PYTHON" -m uvicorn api.main:app --host 127.0.0.1 --port "$COY_API_PORT" --workers 1 >>"$COY_LOG_DIR/bioclip.log" 2>&1 &
  api_pid=$!
  api_ready=false
  for attempt in {1..45}; do
    if ! kill -0 "$api_pid" 2>/dev/null; then break; fi
    if health "$WILDLIFE_V4_URL/v3/health" api; then api_ready=true; break; fi
    sleep 1
  done
  if [[ "$api_ready" != true ]]; then
    echo "BioCLIP-v4 did not become ready. Check $COY_LOG_DIR/bioclip.log (including any occupied port)." >&2
    exit 1
  fi
fi

"$COY_PYTHON" -m uvicorn api.coy_bridge:app --host "$COY_HOST" --port "$COY_PORT" --workers 1 >>"$COY_LOG_DIR/coy.log" 2>&1 &
bridge_pid=$!
bridge_ready=false
for attempt in {1..30}; do
  if ! kill -0 "$bridge_pid" 2>/dev/null; then break; fi
  if health "$bridge_url/healthz" bridge; then bridge_ready=true; break; fi
  sleep 1
done
if [[ "$bridge_ready" != true ]]; then
  echo "coy did not become ready. Check $COY_LOG_DIR/coy.log (including any occupied port)." >&2
  exit 1
fi
echo "coy is ready: $bridge_url/healthz"
echo "iPhone on the same LAN: http://<this-Mac-LAN-IP>:$COY_PORT"
echo "Logs: $COY_LOG_DIR. First inference may download the pinned BioCLIP base weights."
echo "Press Ctrl-C to stop only the services this launcher started."
wait "$bridge_pid"
