#!/bin/bash
# Run by launchd every 15 s: keeps Deskflow running on the Mac (docs/adr/0003).
#  - Deskflow isn't running (quit by hand, or crashed): start it.
#  - Deskflow is running but its client isn't: it couldn't start without a display
#    ("failed to initialize computer shape"), or it was quit from the app. Once a
#    display is attached, restart Deskflow so the client starts with it.
# Starting the client from the app matters: macOS ties the client's local network
# access to the app that launched it, and blocks the client once that app is gone.
log="$HOME/Library/Logs/switch-mac-win-keeper.log"
say() { echo "$(date '+%Y-%m-%dT%H:%M:%S') $*" >> "$log"; }

has_display() { system_profiler SPDisplaysDataType 2>/dev/null | grep -q 'Resolution:'; }

if ! pgrep -xq Deskflow; then
    say "Deskflow isn't running; starting it"
    open -a Deskflow
elif ! pgrep -fq 'deskflow-core client' && has_display; then
    say "Deskflow's client isn't running and a display is attached; restarting Deskflow"
    osascript -e 'quit app "Deskflow"' 2>/dev/null || true
    sleep 2
    pkill -x Deskflow 2>/dev/null || true
    open -a Deskflow
fi
exit 0
