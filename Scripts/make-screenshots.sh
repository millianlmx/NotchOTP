#!/bin/bash
# Produces the App Store screenshots and the README previews.
#
#   Scripts/make-screenshots.sh                 # capture, then compose both languages
#   Scripts/make-screenshots.sh --capture-only   # just the raw captures
#   Scripts/make-screenshots.sh --compose-only   # just the compositions, from the captures
#   Scripts/make-screenshots.sh --all-sizes      # also 1440×900 and 2880×1800
#
# What it needs, and why:
#
#   * a Mac with a notch — the panel only exists on a notched screen, on an external
#     display the app is the menu bar icon and nothing else;
#   * an unlocked session: `screencapture -l` cannot read another process's window while
#     the screen is locked, and the lock also makes the app wipe its own codes;
#   * the Screen Recording permission for whatever runs this.
#
# Debug build on purpose: the `-panel`, `-confirm` and `-settings` launch arguments the
# captures drive live behind `#if DEBUG`, next to the `-confirm` harness the README
# documents for exercising the real key.
set -euo pipefail

cd "$(dirname "$0")/.."

RAW="build/screenshots/raw"
OUT="docs/app-store/screenshots"
STATES=(list confirm settings)
LANGUAGES=(en fr)

compose=1
capture=1
options=()
for argument in "$@"; do
  case "$argument" in
    --capture-only) compose=0 ;;
    --compose-only) capture=0 ;;
    *) options+=("$argument") ;;
  esac
done

if [[ "$capture" == 1 ]]; then
  ./Scripts/build-app.sh --debug

  mkdir -p "$RAW"
  for state in "${STATES[@]}"; do
    for language in "${LANGUAGES[@]}"; do
      swift Scripts/Screenshots/Capture.swift "$state" "$language" "$RAW"
    done
  done
fi

if [[ "$compose" == 1 ]]; then
  swift Scripts/Screenshots/Compose.swift "$RAW" "$OUT" ${options[@]+"${options[@]}"}

  # The README shows the panel itself, at the size it is drawn: the frame it hangs from
  # belongs to the store screenshots, not to the documentation. The two it keeps are the
  # ones its text describes — one confirmed code among the masks, and the sheet that asked
  # for the gesture.
  cp "$RAW/confirm-en-20.png" docs/panel-list.png
  cp "$RAW/confirm-en-05.png" docs/panel-confirmation.png

  echo
  echo "Store screenshots: $OUT/<language>/<size>/"
  echo "README previews:   docs/panel-list.png, docs/panel-confirmation.png"
fi
