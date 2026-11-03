#!/bin/sh
# One-time setup on the Mac: installs m1ddc and puts a "Go Windows!" app on the Desktop.
set -e
here="$(cd "$(dirname "$0")" && pwd)"
command -v m1ddc >/dev/null || /opt/homebrew/bin/brew install m1ddc
chmod +x "$here/switch-to-windows.sh"
app="$HOME/Desktop/Go Windows!.app"
rm -rf "$app"
osacompile -o "$app" -e "do shell script quoted form of \"$here/switch-to-windows.sh\""
echo "Created $app"
