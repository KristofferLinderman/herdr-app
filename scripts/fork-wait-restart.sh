#!/usr/bin/env bash
# Waits until every running Herdr was started after the installed build, so the fork update agent
# (scripts/fork-update.md) carries on by itself once Kristoffer restarts. Run it in the background.
#
#   scripts/fork-wait-restart.sh [max seconds, default 86400]
#
# Exit codes: 0 restarted (prints the running version), 1 gave up waiting.
set -euo pipefail

app=/Applications/Herdr.app
bin="$app/Contents/MacOS/Herdr"
max="${1:-86400}"
installed="$(stat -f %m "$bin")"
waited=0

# 0 when at least one Herdr runs and none started before the install.
restarted() {
  local pids pid started any=1
  pids="$(pgrep -f "$bin" || true)"
  for pid in $pids; do
    started="$(date -j -f '%a %b %d %T %Y' "$(ps -o lstart= -p "$pid" | sed 's/ *$//')" +%s 2>/dev/null)" || continue
    [[ $started -ge $installed ]] || return 1
    any=0
  done
  return $any
}

until restarted; do
  if [[ $waited -ge $max ]]; then
    echo "Herdr wasn't restarted within ${max}s." >&2
    exit 1
  fi
  sleep 5
  waited=$((waited + 5))
done
echo "Herdr restarted: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist") (Build $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist"))."
