#!/bin/bash
# Run by launchd for each connection to the wake listener (stdin is the connection).
# Reads one line, the wake token, and fully wakes the Mac if it matches the config.
# At most one wake every 2 seconds.
config="$HOME/Library/Application Support/switch-mac-win/config"
stamp="$HOME/Library/Caches/switch-mac-win/last-wake"
log="$HOME/Library/Logs/switch-mac-win-wake.log"
say() { echo "$(date '+%Y-%m-%dT%H:%M:%S') $*" >> "$log"; }

[ -r "$config" ] || { say "no config at $config"; exit 0; }
# shellcheck source=/dev/null
. "$config"

IFS= read -r -t 5 token || true
token="${token%$'\r'}"
if [ -z "$WAKE_TOKEN" ] || [ "$token" != "$WAKE_TOKEN" ]; then
    say "rejected a connection with a wrong or missing token"
    exit 0
fi

mkdir -p "$(dirname "$stamp")"
now=$(date +%s)
last=$(cat "$stamp" 2>/dev/null || echo 0)
if [ $((now - last)) -lt 2 ]; then say "ignored: less than 2 s since the last wake"; exit 0; fi
echo "$now" > "$stamp"

say "waking"
# Also give the keeper a nudge, so Deskflow starts now if it isn't running.
launchctl kickstart "gui/$(id -u)/com.switch-mac-win.deskflow" 2>/dev/null || true
exec /usr/bin/caffeinate -u -t 2
