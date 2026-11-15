#!/usr/bin/env bash
# Capture the genuine coy UI flows without erasing any simulator or sighting.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
COY_CAPTURE_DIR="${COY_CAPTURE_DIR:-$REPO_ROOT/data/app/coy-captures/$(date +%Y%m%d-%H%M%S)}"
COY_DERIVED_DATA="${COY_DERIVED_DATA:-$COY_CAPTURE_DIR/build}"
mkdir -p "$COY_CAPTURE_DIR"
curl --fail --silent http://127.0.0.1:8081/healthz >/dev/null || {
  echo 'Start the trained model and bridge first: bash scripts/run_coy.sh' >&2; exit 1;
}
# A new simulator gives Photos one known CC0 input and keeps all existing data intact.
if [[ -z "${DEMO_DEVICE:-}" ]]; then
  COY_RUNTIME="$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin)["runtimes"] if x.get("isAvailable") and x["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-") and int(x["version"].split(".")[0])>=18]; print(sorted(r,key=lambda x:tuple(map(int,x["version"].split("."))))[-1]["identifier"])')"
  DEMO_DEVICE="$(xcrun simctl create "coy capture $(date +%Y%m%d-%H%M%S)" 'iPhone 16' "$COY_RUNTIME")"
fi
echo "Simulator: $DEMO_DEVICE (kept after capture; never erased)"
xcrun simctl boot "$DEMO_DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEMO_DEVICE" -b >/dev/null
xcrun simctl status_bar "$DEMO_DEVICE" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --cellularMode notSupported --batteryState charged --batteryLevel 100
xcrun simctl addmedia "$DEMO_DEVICE" "$REPO_ROOT/docs/demo/sample_input.jpg"
PROJECT="$REPO_ROOT/ios/ucscdevfestapp/ucscdevfestapp.xcodeproj"
xcodebuild -project "$PROJECT" -scheme ucscdevfestapp -destination "platform=iOS Simulator,id=$DEMO_DEVICE" -derivedDataPath "$COY_DERIVED_DATA" CODE_SIGNING_ALLOWED=NO build-for-testing >"$COY_CAPTURE_DIR/build.log" 2>&1
recorder=''
cleanup() {
  if [[ -n "$recorder" ]]; then kill -INT "$recorder" 2>/dev/null || true; wait "$recorder" || true; fi
  xcrun simctl status_bar "$DEMO_DEVICE" clear
}
trap cleanup EXIT
capture() {
  local label="$1" test_name="$2" result=0
  xcrun simctl io "$DEMO_DEVICE" recordVideo --codec h264 "$COY_CAPTURE_DIR/$label.mov" >"$COY_CAPTURE_DIR/$label-recorder.log" 2>&1 &
  recorder=$!
  xcodebuild -project "$PROJECT" -scheme ucscdevfestapp -destination "platform=iOS Simulator,id=$DEMO_DEVICE" -derivedDataPath "$COY_DERIVED_DATA" CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:"ucscdevfestappUITests/$test_name" test-without-building >"$COY_CAPTURE_DIR/$label.log" 2>&1 || result=$?
  kill -INT "$recorder" 2>/dev/null || true
  wait "$recorder" || true
  recorder=''
  if [[ "$result" != 0 ]]; then echo "UI flow failed; inspect $COY_CAPTURE_DIR/$label.log. Recording is not validated." >&2; return "$result"; fi
}
capture named_flow CoyDemoTests/testNamedMapFlow
capture ranked_map CoyRankedDemoTests/testRankedAndMap
echo "Passed both flows. Raw recordings and logs: $COY_CAPTURE_DIR"
echo 'The named flow adds a local Goldie post and comment. It does not delete previous data.'
