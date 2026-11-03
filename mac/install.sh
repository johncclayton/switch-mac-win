#!/bin/sh
# One-time setup on the Mac: installs m1ddc and creates a "Go Windows!" app on the
# Desktop and in ~/Applications (so Spotlight/Launchpad find it and it can go in the Dock).
set -e
here="$(cd "$(dirname "$0")" && pwd)"
command -v m1ddc >/dev/null || /opt/homebrew/bin/brew install m1ddc
chmod +x "$here/switch-to-windows.sh"
mkdir -p "$HOME/Applications"
for app in "$HOME/Desktop/Go Windows!.app" "$HOME/Applications/Go Windows!.app"; do
    rm -rf "$app"
    osacompile -o "$app" -e "do shell script quoted form of \"$here/switch-to-windows.sh\""
    echo "Created $app"
done

# Wake listener: lets Windows wake this Mac by connecting to TCP port 47999 (no SSH needed).
agent="$HOME/Library/LaunchAgents/com.switch-mac-win.wake.plist"
mkdir -p "$HOME/Library/LaunchAgents"
launchctl bootout "gui/$(id -u)" "$agent" 2>/dev/null || true
cp "$here/wake-listener.plist" "$agent"
launchctl bootstrap "gui/$(id -u)" "$agent"
echo "Wake listener on port 47999 ($agent)"
