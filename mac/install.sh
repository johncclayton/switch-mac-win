#!/bin/bash
# Sets up the Mac (the Deskflow client). Safe to re-run.
#
#   ./mac/install.sh --client [options]
#
# Asks for anything it doesn't know (existing config values are the defaults), then:
#  - saves ~/Library/Application Support/switch-mac-win/config
#  - writes Deskflow's settings: this Mac's name and the Windows PC to connect to
#    (backs up Deskflow.conf first; see docs/adr/0002)
#  - installs m1ddc, the "Go Windows!" app (Desktop and ~/Applications), the
#    wake listener and the Deskflow keeper (both LaunchAgents)
#  - prints the command to run on the Windows PC
#
# Options (all optional except --client):
#   --server-name NAME   Deskflow screen name of the Windows PC
#   --server-host HOST   host or IP address of the Windows PC (Deskflow connects to it)
#   --client-name NAME   Deskflow screen name of this Mac
#   --client-host HOST   host or IP address of this Mac (the Windows PC wakes it)
#   --token TOKEN        wake token (default: keep the existing one, or generate one)
#   --new-token          generate a new wake token
#   --wake-port PORT     wake listener port (default 47999)
#   --yes                don't ask; use the options and defaults
set -e
here="$(cd "$(dirname "$0")" && pwd)"
config_dir="$HOME/Library/Application Support/switch-mac-win"
config="$config_dir/config"

die() { echo "error: $*" >&2; exit 1; }

# --- Options ------------------------------------------------------------------
role= new_token= yes=
g_server_name= g_server_host= g_client_name= g_client_host= g_token= g_port=
while [ $# -gt 0 ]; do
    case "$1" in
        --client) role=client ;;
        --server) die "this is the Mac installer, which sets up the Deskflow client. Run windows\\install.ps1 --server on the Windows PC." ;;
        --new-token) new_token=1 ;;
        --yes) yes=1 ;;
        --server-name) g_server_name="$2"; shift ;;
        --server-host) g_server_host="$2"; shift ;;
        --client-name) g_client_name="$2"; shift ;;
        --client-host) g_client_host="$2"; shift ;;
        --token) g_token="$2"; shift ;;
        --wake-port) g_port="$2"; shift ;;
        *) die "unknown option '$1'. See the comments at the top of install.sh." ;;
    esac
    shift
done
[ "$role" = client ] || die "say which role this machine has: ./mac/install.sh --client"

SERVER_NAME= SERVER_HOST= CLIENT_NAME= CLIENT_HOST= WAKE_PORT=47999 WAKE_TOKEN=
# shellcheck source=/dev/null
if [ -r "$config" ]; then . "$config"; fi

# ask VAR LABEL GIVEN DEFAULT
ask() {
    local var=$1 label=$2 given=$3 default=$4 answer=
    if [ -n "$given" ]; then answer=$given
    elif [ -n "$yes" ]; then
        [ -n "$default" ] || die "no value for $label; pass it as an option"
        answer=$default
    else
        while [ -z "$answer" ]; do
            if [ -n "$default" ]; then read -r -p "$label [$default]: " answer; answer=${answer:-$default}
            else read -r -p "$label: " answer; fi
        done
    fi
    case "$answer" in *"'"*|*" "*) die "$label can't contain quotes or spaces" ;; esac
    printf -v "$var" '%s' "$answer"
}
is_ip() { [[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; }
resolve_ipv4() { if is_ip "$1"; then echo "$1"; else dscacheutil -q host -a name "$1" | awk '/^ip_address:/{print $2; exit}'; fi; }

local_host=$(scutil --get LocalHostName)
echo "Windows PC"
ask SERVER_NAME "  Deskflow screen name" "$g_server_name" "$SERVER_NAME"
ask SERVER_HOST "  Host or IP address" "$g_server_host" "${SERVER_HOST:-$SERVER_NAME.local}"
echo "Mac (this machine)"
ask CLIENT_NAME "  Deskflow screen name" "$g_client_name" "${CLIENT_NAME:-$(echo "$local_host" | tr '[:upper:]' '[:lower:]')}"
ask CLIENT_HOST "  Host or IP address" "$g_client_host" "${CLIENT_HOST:-$local_host.local}"
if [ -n "$g_port" ]; then WAKE_PORT=$g_port; fi
[[ $WAKE_PORT =~ ^[0-9]+$ ]] || die "wake port must be a number"
[ "$SERVER_NAME" != "$CLIENT_NAME" ] || die "the two Deskflow screen names must differ"

if [ -n "$g_token" ]; then WAKE_TOKEN=$g_token
elif [ -n "$new_token" ] || [ -z "$WAKE_TOKEN" ]; then
    WAKE_TOKEN=$(openssl rand -hex 16)
    echo "Generated a new wake token."
fi
case "$WAKE_TOKEN" in *"'"*|*" "*) die "the wake token can't contain quotes or spaces" ;; esac

for h in "$SERVER_HOST" "$CLIENT_HOST"; do
    if is_ip "$h"; then echo "warning: $h is an IP address: reserve it in your router's DHCP settings so it doesn't change." >&2; fi
done
if [ -z "$(resolve_ipv4 "$SERVER_HOST")" ]; then
    echo "warning: can't resolve $SERVER_HOST to an IPv4 address right now. Deskflow needs it; check the name, or use the Windows PC's IP address." >&2
fi

mkdir -p "$config_dir"
( umask 077; cat > "$config" <<EOF
# switch-mac-win config, written by mac/install.sh. Shell syntax (it's sourced).
SERVER_NAME='$SERVER_NAME'
SERVER_HOST='$SERVER_HOST'
CLIENT_NAME='$CLIENT_NAME'
CLIENT_HOST='$CLIENT_HOST'
WAKE_PORT='$WAKE_PORT'
WAKE_TOKEN='$WAKE_TOKEN'
EOF
)
echo "Saved $config"

# --- Deskflow -----------------------------------------------------------------
# set_ini FILE SECTION KEY VALUE
set_ini() {
    awk -v s="[$2]" -v k="$3" -v v="$4" '
        /^\[/ { if (insec && !done) { print k "=" v; done = 1 }
                insec = ($0 == s); if (insec) found = 1; print; next }
        insec && index($0, k "=") == 1 { if (!done) { print k "=" v; done = 1 }; next }
        { print }
        END { if (!found) { print ""; print s; print k "=" v } else if (insec && !done) print k "=" v }
    ' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}
df_conf="$HOME/Library/Deskflow/Deskflow.conf"
# The Deskflow app rewrites its settings when it quits, so quit it first.
osascript -e 'quit app "Deskflow"' 2>/dev/null || true
sleep 2
pkill -x Deskflow 2>/dev/null || true
pkill -x deskflow-core 2>/dev/null || true   # the core can outlive the app, with the old settings
mkdir -p "$(dirname "$df_conf")"
if [ -f "$df_conf" ]; then cp "$df_conf" "$df_conf.bak-$(date +%Y%m%d-%H%M%S)"; else : > "$df_conf"; fi
set_ini "$df_conf" core computerName "$CLIENT_NAME"
set_ini "$df_conf" core coreMode 1   # client
set_ini "$df_conf" client remoteHost "$SERVER_HOST"
echo "Updated $df_conf (backup next to it)"
open -a Deskflow && echo "Started Deskflow"

# --- Tools and the Go Windows! app --------------------------------------------
command -v m1ddc >/dev/null || /opt/homebrew/bin/brew install m1ddc
chmod +x "$here/switch-to-windows.sh" "$here/wake.sh" "$here/keep-deskflow.sh"
mkdir -p "$HOME/Applications"
for app in "$HOME/Desktop/Go Windows!.app" "$HOME/Applications/Go Windows!.app"; do
    rm -rf "$app"
    osacompile -o "$app" -e "do shell script quoted form of \"$here/switch-to-windows.sh\""
    echo "Created $app"
done

# --- Wake listener and Deskflow keeper (LaunchAgents) ---------------------------
mkdir -p "$HOME/Library/LaunchAgents"
# install_agent PLIST TEMPLATE SED-EXPRESSIONS...
install_agent() {
    local agent="$HOME/Library/LaunchAgents/$1" template=$2; shift 2
    launchctl bootout "gui/$(id -u)" "$agent" 2>/dev/null || true
    sed "$@" "$here/$template" > "$agent"
    launchctl bootstrap "gui/$(id -u)" "$agent"
}
install_agent com.switch-mac-win.wake.plist wake-listener.plist.template \
    -e "s|{{WAKE_SCRIPT}}|$here/wake.sh|" -e "s|{{WAKE_PORT}}|$WAKE_PORT|"
echo "Wake listener on port $WAKE_PORT (~/Library/LaunchAgents/com.switch-mac-win.wake.plist)"
install_agent com.switch-mac-win.deskflow.plist keep-deskflow.plist.template \
    -e "s|{{KEEP_SCRIPT}}|$here/keep-deskflow.sh|" -e "s|{{HOME}}|$HOME|"
echo "Deskflow keeper installed (~/Library/LaunchAgents/com.switch-mac-win.deskflow.plist)"

# --- The Windows PC -----------------------------------------------------------
echo
echo "Now run this on the Windows PC, in its copy of the repo (skip it if you already did):"
echo "  powershell -ExecutionPolicy Bypass -File .\\windows\\install.ps1 --server --server-name $SERVER_NAME --server-host $SERVER_HOST --client-name $CLIENT_NAME --client-host $CLIENT_HOST --wake-port $WAKE_PORT --token $WAKE_TOKEN"
