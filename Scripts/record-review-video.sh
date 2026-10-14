#!/bin/bash
# Records the screen recording App Review asks for, driving NotchOTP with synthetic input.
#
#   Scripts/record-review-video.sh --demo                     # whole take, unattended
#   Scripts/record-review-video.sh --key --finger-wait 60     # real YubiKey: touch the
#                                                             # sensor when the sheet shows
#   Scripts/record-review-video.sh --demo --print-geometry    # where each target lands
#   Scripts/record-review-video.sh --demo --dry-run           # events only, no recording
#
# What it needs, and why:
#
#   * a Mac with a notch — the panel exists nowhere else;
#   * an unlocked session, an empty clipboard and no NotchOTP already running;
#   * the **Accessibility** permission for whatever runs this: the driver posts synthetic
#     pointer and keyboard events, and without the permission the kernel drops them
#     silently — the recording would be a minute of nothing happening;
#   * the **Screen Recording** permission for the capture;
#   * the archive, because the app under test has to be the one that was submitted. The
#     store-signed payload cannot be launched outside the store path (launchd spawn
#     failure 163), so this uses the archived build the archive step produced.
#
# `--demo` is what a reviewer without a YubiKey runs: four accounts, rotating codes, a
# simulated sensor. `--key` runs the real path and waits `--finger-wait` seconds for the
# finger; it is the stronger recording, and the only one that needs a human at the keyboard.
set -euo pipefail

cd "$(dirname "$0")/.."

ARCHIVE="build/NotchOTP.xcarchive/Products/Applications/NotchOTP.app"
OUT="$HOME/Desktop/NotchOTP-2.1-review.mov"
MODE=""
DRY=0
MIC=0
FINGER=""
DRIVER_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --demo) MODE=demo ;;
    --key) MODE=key ;;
    --out) shift; OUT="$1" ;;
    --mic) MIC=1 ;;
    --dry-run) DRY=1 ;;
    --print-geometry) DRY=1; DRIVER_ARGS+=(--print-geometry) ;;
    --no-paste) DRIVER_ARGS+=(--no-paste) ;;
    --finger-wait) shift; FINGER="$1" ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
  shift
done

if [[ -z "$MODE" ]]; then
  echo "pick a mode: --demo (no hardware) or --key (real YubiKey)" >&2
  exit 2
fi

if [[ ! -d "$ARCHIVE" ]]; then
  cat >&2 <<EOF
No archive at $ARCHIVE.

The recording has to show the build that was submitted. Make one first:

    TEAM_ID=2MJF39L8VY Scripts/archive-app.sh
EOF
  exit 1
fi

DRIVER_ARGS+=(--app "$ARCHIVE")

if [[ "$MODE" == "demo" ]]; then
  DRIVER_ARGS+=(--demo)
  # The simulated sensor answers ~900 ms after the sheet appears, so the wait is short.
  DRIVER_ARGS+=(--finger-wait "${FINGER:-2}")
else
  # A real finger: long enough to notice the sheet and reach the sensor.
  DRIVER_ARGS+=(--finger-wait "${FINGER:-30}")
fi

# A stale instance would answer the pointer instead of the one this take launches.
pkill -f "NotchOTP.app/Contents/MacOS/NotchOTP" 2>/dev/null || true
sleep 1

if [[ "$DRY" == 1 ]]; then
  echo "dry run: events only, nothing recorded"
  swift Scripts/Review/Recorder.swift ${DRIVER_ARGS[@]+"${DRIVER_ARGS[@]}"}
  exit 0
fi

mkdir -p build/review
LOG="build/review/log-$(date +%H%M%S).txt"

echo "recording to $OUT"
# Written beside the destination and moved into place: `screencapture` fails to save when
# the final path already holds a file ("Failed to save to final location"), and a take that
# dies half way should not destroy the previous one.
PARTIAL="${OUT%.mov}.partial.mov"
rm -f "$PARTIAL"
CAPTURE_ARGS=(-v -C -k)
[[ "$MIC" == 1 ]] && CAPTURE_ARGS+=(-g)
screencapture "${CAPTURE_ARGS[@]}" "$PARTIAL" &
CAPTURE=$!

# Give the recorder a beat to open its file, so the take starts on a clean first frame.
sleep 2

swift Scripts/Review/Recorder.swift ${DRIVER_ARGS[@]+"${DRIVER_ARGS[@]}"} | tee "$LOG"

sleep 1
kill -INT "$CAPTURE" 2>/dev/null || true
wait "$CAPTURE" 2>/dev/null || true

if [[ -s "$PARTIAL" ]]; then
  mv -f "$PARTIAL" "$OUT"
else
  echo "the capture produced nothing — check the Screen Recording permission" >&2
  exit 1
fi

echo
echo "video:    $OUT ($(du -h "$OUT" | cut -f1))"
echo "timeline: $LOG"
echo
echo "What the app logged during the take:"
log show --last 3m --predicate 'subsystem == "app.notchotp"' --style compact 2>/dev/null \
  | grep -E "panel |code handed|evaluatePolicy|accounts listed|locked by user" || true
