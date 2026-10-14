#!/bin/bash
# Records the footage Marketing/video (Remotion) cuts into the launch video: the screen
# around the notch, a plain gradient behind the panel, the demo key, and the short
# scenario `Recorder.swift --marketing` plays (hover, one code, search, lock, leave).
#
#   Scripts/Marketing/record-clips.sh                 # writes Marketing/video/public/take.mov
#   Scripts/Marketing/record-clips.sh --app <path>    # another NotchOTP.app
#
# Same requirements as Scripts/record-review-video.sh: a Mac with a notch, an unlocked
# session, the Accessibility permission for whatever runs this (the driver refuses to run
# without it) and the Screen Recording permission for the capture.
#
# Output, in Remotion's `public/` so the composition reads it with `staticFile()`:
#   take.mov        the region around the notch, 2x pixels
#   timeline.json   [{name, at}] — seconds into take.mov at which each step started
set -euo pipefail

cd "$(dirname "$0")/../.."

APP="build/NotchOTP.app"
[[ -d "$APP" ]] || APP="build/NotchOTP.xcarchive/Products/Applications/NotchOTP.app"
PUBLIC="Marketing/video/public"
OUT="$PUBLIC/take.mov"
TIMELINE="$PUBLIC/timeline.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) shift; APP="$1" ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
  shift
done

if [[ ! -d "$APP" ]]; then
  echo "no NotchOTP.app at $APP — run Scripts/build-app.sh first" >&2
  exit 1
fi

# The crop is derived from the panel the driver computes, never measured by hand:
# 110 pt either side of the 420 pt panel, 420 pt tall (notch + 340 pt panel + margin).
GEOMETRY="$(swift Scripts/Review/Recorder.swift --print-geometry)"
PANEL_X="$(echo "$GEOMETRY" | awk '/^panel/ { gsub(/[(),]/, "", $2); print int($2) }')"
if [[ -z "$PANEL_X" ]]; then
  echo "could not read the panel geometry:" >&2
  echo "$GEOMETRY" >&2
  exit 1
fi
REGION="$((PANEL_X - 110)),0,640,420"

pkill -f "NotchOTP.app/Contents/MacOS/NotchOTP" 2>/dev/null || true
mkdir -p "$PUBLIC"

# The backdrop compiles for a few seconds before its window exists; wait for "ready".
BACKDROP_LOG="$(mktemp -t notchotp-backdrop)"
swift Scripts/Marketing/Backdrop.swift > "$BACKDROP_LOG" 2>&1 &
BACKDROP=$!
for _ in $(seq 1 120); do
  grep -q ready "$BACKDROP_LOG" 2>/dev/null && break
  sleep 0.25
done
if ! grep -q ready "$BACKDROP_LOG"; then
  echo "the backdrop never came up:" >&2
  cat "$BACKDROP_LOG" >&2
  kill "$BACKDROP" 2>/dev/null || true
  exit 1
fi

cleanup() {
  kill "$BACKDROP" 2>/dev/null || true
  rm -f "$BACKDROP_LOG"
}
trap cleanup EXIT

# Written beside the destination and moved into place: `screencapture` refuses to write
# over an existing file, and a failed take should not destroy the previous one.
PARTIAL="${OUT%.mov}.partial.mov"
rm -f "$PARTIAL"
echo "recording $REGION to $OUT"
screencapture -v -C -R "$REGION" "$PARTIAL" &
CAPTURE=$!
CAPTURE_START="$(perl -MTime::HiRes=time -e 'printf "%.3f", time')"

# Give the recorder a beat to open its file, so the take starts on a clean first frame.
sleep 2

swift Scripts/Review/Recorder.swift --app "$APP" --demo --finger-wait 2 \
  --marketing --timeline "$TIMELINE" --capture-start "$CAPTURE_START"

sleep 1
kill -INT "$CAPTURE" 2>/dev/null || true
wait "$CAPTURE" 2>/dev/null || true
pkill -f "NotchOTP.app/Contents/MacOS/NotchOTP" 2>/dev/null || true

if [[ -s "$PARTIAL" ]]; then
  mv -f "$PARTIAL" "$OUT"
else
  echo "the capture produced nothing — check the Screen Recording permission" >&2
  exit 1
fi

echo
echo "footage:  $OUT ($(du -h "$OUT" | cut -f1))"
echo "timeline: $TIMELINE"
cat "$TIMELINE"
