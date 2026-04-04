#!/usr/bin/env bash
set -euo pipefail

LOCK_FILE="/tmp/mpd_island_toggle.lock"
LYRICS_SCRIPT="${HOME}/.config/waybar/scripts/island/lycrics.sh"

if pgrep -f "$LYRICS_SCRIPT" >/dev/null 2>&1 && pgrep mpd >/dev/null 2>&1; then
  pkill -f "$LYRICS_SCRIPT" || true
  sleep 0.3
  killall mpd 2>/dev/null || true
  rm -f "$LOCK_FILE"
  exit 0
fi

mpd &
sleep 0.2
bash "$LYRICS_SCRIPT" &
echo $$ >"$LOCK_FILE"
