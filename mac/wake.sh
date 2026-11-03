#!/bin/bash
# Run by launchd for each connection to the wake listener (stdin is the connection).
# Reads one line, the wake token, and fully wakes the Mac if it matches the config.
# At most one wake every 2 seconds.
config="$HOME/Library/Application Support/switch-mac-win/config"
stamp="$HOME/Library/Caches/switch-mac-win/last-wake"
say() { logger -t switch-mac-win "wake: $*"; }

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
if [ $((now - last)) -lt 2 ]; then exit 0; fi
echo "$now" > "$stamp"

say "waking"
exec /usr/bin/caffeinate -u -t 2
