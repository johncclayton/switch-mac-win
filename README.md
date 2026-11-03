# switch-mac-win

One-click switching of a **Dell U4021QW** between a Mac (Thunderbolt) and a Windows
PC (DisplayPort), with [Deskflow](https://github.com/deskflow/deskflow) moving the
keyboard and mouse to match. The Windows PC is the Deskflow server and the Mac is the
client. Terms are defined in [GLOSSARY.md](GLOSSARY.md); decisions are recorded in [docs/adr](docs/adr).

| Shortcut | Where | Does |
|---|---|---|
| **Go Mac!** | Windows desktop | Wakes the Mac if needed, Deskflow → Mac, PBP off, input → Thunderbolt |
| **Go Windows!** | Mac (Desktop, `~/Applications`) and Windows desktop | PBP off, input → DisplayPort, Deskflow → Windows |
| **Go Split!** | Windows desktop | PBP 50/50: Windows left, Mac right |
| **Ctrl+Alt+Shift+F11** | either machine | Toggles between the two machines (the monitor follows) |

## Setup

You need:
- A Dell U4021QW with **DDC/CI enabled** (on-screen menu → Others → DDC/CI → On). The
  Windows PC is on **DisplayPort**, the Mac on **Thunderbolt/USB-C**, and the keyboard and
  mouse are plugged into the Windows PC.
- **[Deskflow](https://github.com/deskflow/deskflow)** (tested with 1.27) on both machines.
  On Windows, install it with its background service: the scripts read
  `C:\ProgramData\Deskflow\deskflow-daemon.log`. On the Mac, set it to start at login and
  give it **Accessibility** permission (System Settings → Privacy & Security). Deskflow's own
  settings can be left as they are: the installers set the screen names and the server address.
- **Homebrew** on the Mac (Apple silicon, `/opt/homebrew`).
- This repo cloned on both machines.

Then run the installer on either machine first. It asks for each machine's
**Deskflow screen name** and **host or IP address**, and finishes by printing the exact
command to run on the other machine, with the wake token and every value filled in.

Windows PC:

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\install.ps1 --server
```

Mac:

```sh
./mac/install.sh --client
```

The installers are safe to re-run: the current config is used as the defaults, and the
wake token is kept unless you pass `--new-token`. Each takes its values as options too
(`--server-name`, `--server-host`, `--client-name`, `--client-host`, `--token`,
`--wake-port`, and `--yes` to skip the questions); see the comments at the top of each
script. Then check that the Windows PC can wake the Mac:

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\test-wake.ps1
```

**Defaults.** Deskflow screen names default to the short hostnames (e.g. `my-pc`, `my-mac`)
and hosts to their Bonjour names (e.g. `my-pc.local`, `my-mac.local`), which resolve even
while the Mac sleeps. If you give an IP address instead, reserve it in your router's DHCP
settings.

**What the installers change.**
- **Windows PC:** `%LOCALAPPDATA%\switch-mac-win\config.json`; Deskflow's settings
  (`%APPDATA%\Deskflow\Deskflow.conf`, backed up first) and its server config
  `C:\ProgramData\Deskflow\switch-mac-win.conf`, generated from
  `deskflow/deskflow-server.conf.template`; the **Go Mac!**, **Go Windows!** and
  **Go Split!** desktop shortcuts; and the watcher, started now and from the Startup folder.
- **Mac:** `~/Library/Application Support/switch-mac-win/config`; Deskflow's settings
  (`~/Library/Deskflow/Deskflow.conf`, backed up first); `m1ddc`; the **Go Windows!** app; and
  the wake listener `~/Library/LaunchAgents/com.switch-mac-win.wake.plist`.

The config is the source of truth: the installers overwrite the screen names and the server
address in Deskflow's settings ([ADR 0002](docs/adr/0002-our-config-overwrites-deskflow-settings.md)).
To change them, re-run the installers, not the Deskflow app.

**Hotkeys** are in `config.json` on the Windows PC (`toggleKey`, `toMacKey`, `toWindowsKey`,
in Deskflow syntax, e.g. `Control+Alt+Shift+F11`). Edit them there, or pass `--toggle-key`,
`--to-mac-key` and `--to-windows-key`, then re-run `install.ps1`.

**Uninstalling.** There's no uninstaller. Delete the files listed above, unload the Mac's
LaunchAgent with `launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.switch-mac-win.wake.plist`,
and restore Deskflow's settings from the `Deskflow.conf.bak-*` backups if you want them back.

## How it works

- **Monitor:** DDC/CI. On Windows that's `dxva2.dll` from PowerShell (`windows/DellDdc.psm1`,
  no extra tools). On the Mac it's [`m1ddc`](https://github.com/waydabber/m1ddc).
  U4021QW codes: input `0x60` (DP = `0x0F`, TB = `0x19`), PBP mode `0xE9`
  (`0x00` off, `0x24` split), PBP second input `0xE8`.
- **Deskflow:** the server config has **no screen links**, so the cursor never wanders onto a
  machine the monitor isn't showing. Three hotkeys switch explicitly:

  | Default hotkey | Action | Used by |
  |---|---|---|
  | Ctrl+Alt+Shift+F11 | toggle | you, on either machine |
  | Ctrl+Alt+Shift+F10 | go to the Mac | Go Mac!, the watcher |
  | Ctrl+Alt+Shift+F12 | go to the Windows PC | Go Windows!, the watcher |

  The keyboard is plugged into the Windows PC, so the hotkeys work whichever machine you're on.
- **Watcher:** `windows/watch-monitor.ps1` runs at logon and keeps the monitor and Deskflow
  in step, whichever one moves first. It logs to `%LOCALAPPDATA%\switch-mac-win\watch.log`.
  - *Monitor → Deskflow:* it polls the monitor once a second. When the monitor goes fullscreen
    on one input, it moves Deskflow to that machine. That is how the Mac's **Go Windows!**
    brings the keyboard and mouse back, since the Mac can't command the Deskflow server.
    It also works if you switch inputs with the monitor's buttons.
  - *Deskflow → monitor:* it reads Deskflow's log, and when the cursor changes machine (e.g. via
    the hotkeys) it switches the monitor to match. In split view it leaves the monitor alone,
    so the hotkeys just move the cursor.
- **Wake listener:** a LaunchAgent on the Mac in which launchd listens on TCP port 47999,
  advertised over Bonjour. A connection wakes a sleeping Mac, but only partly (a "dark wake":
  screen off, Deskflow disconnected), so for each connection launchd runs `mac/wake.sh`. It
  reads the wake token the Windows PC sends, and if it matches runs `caffeinate -u`, which
  fully wakes the Mac. It allows at most one wake every 2 seconds and logs to
  `~/Library/Logs/switch-mac-win-wake.log`.
  There's no SSH anywhere ([ADR 0001](docs/adr/0001-no-ssh-wake-via-launchd.md)).

## When the Mac isn't there

- **Asleep:** **Go Mac!** and the toggle hotkey wake it through the wake listener, wait for
  Deskflow to reconnect (about 2 s), then switch.
- **Off, or Deskflow or the wake listener not running:** Go Mac! moves Deskflow first and only
  switches the monitor once Deskflow confirms the move, so it shows a warning and stays on
  Windows. The toggle hotkey does nothing.
- **The Mac drops out while you're on it:** Deskflow jumps the cursor back to the Windows PC,
  and the watcher switches the monitor back.
- **The Windows PC can't control the monitor while the Mac is on screen:** there's no
  automatic fallback; use the monitor's input button.

## When the Windows PC is asleep

Nothing wakes the Windows PC over the network. This is a known limitation of the design.

- **Why it's fine here:** the keyboard and mouse are plugged into the Windows PC, so a key
  press always wakes it over USB, whatever its network connection. Deskflow then restarts and
  the Mac reconnects. Keep the keyboard allowed to wake the PC; that's the Windows default
  (Device Manager → the keyboard → Power Management).
- **While it sleeps, the Mac has no shared keyboard or mouse,** because they go through the
  Windows PC. Press a key on the shared keyboard to bring it back. Clicking **Go Windows!**
  with the Mac's own trackpad switches the monitor, but the screen stays black until you
  press a key.
- **To avoid all this, don't let the Windows PC sleep** (Settings → System → Power → Sleep →
  Never). It hosts the keyboard and the Deskflow server, so it's best treated as always on.

**Why there's no Windows wake listener.** The Mac's wake listener works because of two Apple
features: the Mac hands its listener to a Bonjour Sleep Proxy on the network (an Apple TV or
HomePod) while it sleeps, and Macs can wake over Wi-Fi. Windows has neither:
- It doesn't use a Bonjour Sleep Proxy, and in sleep (S3) every process is frozen, so a
  listener can't hear anything.
- Waking over the network needs Wake-on-LAN, which works on wired Ethernet when the adapter
  and BIOS allow it. Over Wi-Fi it needs Wake-on-WLAN, which depends on the Wi-Fi card,
  its driver and the BIOS, and is often unreliable.

**So the Windows PC must be the Deskflow server.** The machine without the keyboard (the
Deskflow client) is the one that must be woken over the network, and only the Mac can do that
reliably, even on Wi-Fi. Running Windows as the client isn't supported.
