#!/bin/bash
# Run by launchd every 15 s: keeps Deskflow running on the Mac (docs/adr/0003).
#  - The Deskflow app isn't running (quit by hand, or crashed): start it.
#  - The app is running but its client isn't: it couldn't start without a display
#    ("failed to initialize computer shape"), or it was stopped from the app. Once a
#    display is attached, restart the app so the client starts with it.
# Starting the client from the app matters: macOS ties the client's local network
# access to the app that launched it, and blocks the client once that app is gone.
# A client that outlived the app is killed first: while it runs, LaunchServices
# thinks the app is already running and "open -a Deskflow" does nothing.
# At most one start every 60 s, so a client that keeps failing can't be restarted in a loop.
log="$HOME/Library/Logs/switch-mac-win-keeper.log"
stamp="$HOME/Library/Caches/switch-mac-win/last-deskflow-start"
say() { echo "$(date '+%Y-%m-%dT%H:%M:%S') $*" >> "$log"; }

has_display() { system_profiler SPDisplaysDataType 2>/dev/null | grep -q 'Resolution:'; }
app_running() { pgrep -xq Deskflow; }
client_running() { pgrep -fq 'deskflow-core client'; }
start_app() {
    mkdir -p "$(dirname "$stamp")"
    now=$(date +%s); last=$(cat "$stamp" 2>/dev/null || echo 0)
    if [ $((now - last)) -lt 60 ]; then return 0; fi
    echo "$now" > "$stamp"
    say "$1; starting Deskflow"
    pkill -x Deskflow 2>/dev/null || true
    pkill -x deskflow-core 2>/dev/null || true
    sleep 1
    open -a Deskflow 2>> "$log"
}

if ! app_running; then
    start_app "the Deskflow app isn't running"
elif ! client_running && has_display; then
    start_app "Deskflow's client isn't running and a display is attached"
fi
exit 0
