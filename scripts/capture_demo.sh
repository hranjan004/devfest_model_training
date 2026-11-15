#!/usr/bin/env bash
# Regenerate the screenshots and screen recording used in docs/DEMO.md.
#
# Needs: the API running on localhost:8080 (scripts/run_api.sh) with demo data
# (scripts/seed_demo_sightings.py), Xcode, and ffmpeg for the video and GIF.
# Uses a dedicated simulator ("DEVFEST Demo") that is erased on every run, and
# replaces the "Goldie" sighting posted by the previous run.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
DEVICE="${DEMO_DEVICE:-DEVFEST Demo}"
OUT="$ROOT/docs/demo"
SHOTS="$OUT/screenshots"
RAW="$(mktemp -d)"
DERIVED="${DERIVED_DATA:-/tmp/devfest_demo_dd}"
mkdir -p "$SHOTS"

curl -sf localhost:8080/v3/health > /dev/null || { echo "Start the API first: scripts/run_api.sh"; exit 1; }

# Remove the sighting the previous run posted.
PYTHONPATH=src:. .venv/bin/python - <<'PY'
import os
from pathlib import Path
from api.store import SightingStore
store = SightingStore(Path(os.environ.get("WILDLIFE_APP_DATA_DIR", "data/app")))
for row in store.list():
    if row["name"] == "Goldie" and not row["is_demo"]:
        store.delete(row["id"])
PY

# Fresh simulator: no leftover photos, permissions, or app data.
if ! xcrun simctl list devices | grep -q "$DEVICE ("; then
  RUNTIME="$(xcrun simctl list runtimes | grep -o 'com.apple.CoreSimulator.SimRuntime.iOS-18[-0-9]*' | tail -1)"
  xcrun simctl create "$DEVICE" "iPhone 16" "$RUNTIME" > /dev/null
fi
xcrun simctl shutdown "$DEVICE" 2>/dev/null || true
xcrun simctl erase "$DEVICE"
xcrun simctl boot "$DEVICE"
xcrun simctl bootstatus "$DEVICE" -b > /dev/null
open -a Simulator
xcrun simctl status_bar "$DEVICE" override --time "9:41" --dataNetwork wifi --wifiMode active \
  --wifiBars 3 --cellularMode notSupported --batteryState charged --batteryLevel 100
xcrun simctl location "$DEVICE" set 36.99795,-122.06030      # UCSC upper campus
xcrun simctl addmedia "$DEVICE" "$OUT/sample_input.jpg"

xcodebuild -project ios/ucscdevfestapp/ucscdevfestapp.xcodeproj -scheme ucscdevfestapp \
  -destination "platform=iOS Simulator,name=$DEVICE" -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO build-for-testing > /tmp/devfest_demo_build.log 2>&1 \
  || { tail -30 /tmp/devfest_demo_build.log; exit 1; }

run_test() {
  TEST_RUNNER_SHOTS_DIR="$RAW" xcodebuild -project ios/ucscdevfestapp/ucscdevfestapp.xcodeproj \
    -scheme ucscdevfestapp -destination "platform=iOS Simulator,name=$DEVICE" -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO \
    -only-testing:"ucscdevfestappUITests/DemoWalkthroughUITests/$1" test-without-building \
    > "/tmp/devfest_demo_$1.log" 2>&1 \
    || { tail -30 "/tmp/devfest_demo_$1.log"; exit 1; }
}

run_test test1BrowseTheApp

# Record the identify-and-post flow as a video.
xcrun simctl io "$DEVICE" recordVideo --codec h264 --force /tmp/devfest_demo.mov &
RECORDER=$!
trap 'kill -INT "$RECORDER" 2>/dev/null || true' EXIT
sleep 2
run_test test2IdentifyAndPost
kill -INT "$RECORDER"
wait "$RECORDER" || true
trap - EXIT
xcrun simctl status_bar "$DEVICE" clear

# Full-size PNGs are ~3 MB each. Store 590 x 1280 JPEGs in the repo.
rm -f "$SHOTS"/*.jpg
for png in "$RAW"/*.png; do
  sips -s format jpeg -s formatOptions 80 -Z 1280 "$png" --out "$SHOTS/$(basename "${png%.png}").jpg" > /dev/null
done
rm -rf "$RAW"

if command -v ffmpeg > /dev/null; then
  ffmpeg -y -loglevel error -i /tmp/devfest_demo.mov -vf "fps=30,scale=590:-2" \
    -c:v libx264 -preset veryfast -crf 30 -pix_fmt yuv420p -movflags +faststart -an "$OUT/identify_and_post.mp4"
  ffmpeg -y -loglevel error -i /tmp/devfest_demo.mov \
    -vf "setpts=PTS/2,fps=8,scale=240:-2:flags=lanczos,split[a][b];[a]palettegen=max_colors=96:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
    "$OUT/identify_and_post.gif"
fi
echo "Screenshots: $SHOTS"
ls -la "$SHOTS" "$OUT" | awk '{print $5, $9}'
