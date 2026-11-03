# switch-mac-win

One-click switching of a **Dell U4021QW** between a Mac (Thunderbolt) and a Windows
PC (DisplayPort), with [Deskflow](https://github.com/deskflow/deskflow) moving the
keyboard/mouse to match. Windows (`obsidian`) is the Deskflow server and the Mac
(`m6.local`) is the client.

| Shortcut | Where | Does |
|---|---|---|
| **Go Mac!** | Windows desktop | PBP off, input → Thunderbolt, Deskflow → Mac |
| **Go Windows!** | Mac desktop (and Windows) | PBP off, input → DisplayPort, Deskflow → Windows |
| **Go Split!** | Windows desktop | PBP 50/50: Windows left, Mac right |

## How it works

- **Monitor:** DDC/CI. On Windows that's `dxva2.dll` from PowerShell (`windows/DellDdc.psm1`,
  no extra tools). On the Mac it's [`m1ddc`](https://github.com/waydabber/m1ddc).
  U4021QW codes: input `0x60` (DP = `0x0F`, TB = `0x19`), PBP mode `0xE9`
  (`0x00` off, `0x24` split), PBP second input `0xE8`.
- **Deskflow:** `deskflow/deskflow-server.conf` has **no screen links**, so you
  switch explicitly. **Ctrl+Alt+Shift+F11** toggles between the two machines, on either
  machine. The scripts and the watcher use explicit hotkeys instead: **Ctrl+Alt+Shift+F10** (→ Mac)
  and **Ctrl+Alt+Shift+F12** (→ Windows).
- **Watcher:** `windows/watch-monitor.ps1` runs at logon and keeps the monitor and Deskflow
  in step, whichever one moves first. It logs to `%LOCALAPPDATA%\switch-mac-win\watch.log`.
  - *Monitor → Deskflow:* it polls the monitor once a second. When the monitor goes fullscreen
    on one input, it moves Deskflow to that machine. That is how the Mac's **Go Windows!**
    brings the keyboard and mouse back, since the Mac can't command the Deskflow server.
    It also works if you switch inputs with the monitor's buttons.
  - *Deskflow → monitor:* it reads Deskflow's log, and when the cursor changes machine (e.g. via
    the hotkeys) it switches the monitor to match. In split view it leaves the monitor alone,
    so the hotkeys just move the cursor. If Windows can't reach the monitor over DDC, it asks
    the Mac over `ssh m6` to run `mac/switch-to-windows.sh`.

## When the Mac isn't there

- **Asleep:** **Go Mac!** and **F11** wake it over `ssh m6 caffeinate -u` (a bare network
  packet only half-wakes it, with Deskflow still disconnected), wait for Deskflow to reconnect,
  then switch. It takes about 6 to 7 seconds.
- **Off, or Deskflow not running:** Go Mac! moves Deskflow first and only switches the
  monitor once Deskflow confirms the move, so it shows a warning and stays on Windows. F11 does nothing.
- If the Mac drops out while you're on it, Deskflow jumps the cursor back to Windows and the
  watcher switches the monitor back.

## Requirements

Everything below must be in place; the install scripts only cover the parts marked *(installer)*.

**Monitor**
- Dell U4021QW with **DDC/CI enabled** (on-screen menu → Others → DDC/CI → On).
- Windows on **DisplayPort**, Mac on **Thunderbolt/USB-C**. The keyboard and mouse are plugged into Windows.

**Deskflow** (tested with 1.27) on both machines
- Windows is the **server**, installed with its background service (the scripts read
  `C:\ProgramData\Deskflow\deskflow-daemon.log`). The Mac (`m6.local`) is added as a
  computer in the server's GUI. Per-screen options such as the Mac's Ctrl/Cmd remapping live
  there, not in the text config.
- Server config: `deskflow/deskflow-server.conf`, which defines the hotkeys *(installer)*:

  | Hotkey | Action | Used by |
  |---|---|---|
  | Ctrl+Alt+Shift+F11 | `switchToNextScreen` (toggle) | you, on either machine |
  | Ctrl+Alt+Shift+F10 | `switchToScreen(m6.local)` | Go Mac!, the watcher |
  | Ctrl+Alt+Shift+F12 | `switchToScreen(obsidian)` | Go Windows!, the watcher |

- The Mac is a **client** connecting to `obsidian`, with Deskflow set to start at login and
  granted **Accessibility** permission (System Settings → Privacy & Security).

**SSH from Windows to the Mac** (to wake it, and as a fallback for switching the monitor)
- On the Mac: **Remote Login** on (System Settings → General → Sharing).
- On Windows: the built-in OpenSSH client, and a host alias `m6` in `~/.ssh/config` that logs
  in **with a key and no password prompt**. The scripts use `ssh -o BatchMode=yes m6`. Example:

  ```
  Host m6
      HostName m6.local          # or the Mac's IP
      User your-mac-username
      IdentityFile ~/.ssh/id_ed25519
  ```

  Check it with `ssh -o BatchMode=yes m6 true`.

**Mac tools:** Homebrew on Apple silicon (`/opt/homebrew`), plus `m1ddc` *(installer)*.

**Names baked in.** If a machine is renamed, update these:
- `obsidian` and `m6.local` (Deskflow screen names): `deskflow/deskflow-server.conf`,
  `windows/Deskflow.psm1`, `windows/watch-monitor.ps1`.
- `m6` (SSH alias): `windows/Deskflow.psm1`, `windows/watch-monitor.ps1`.
- `~/src/switch-mac-win` (repo path on the Mac): `windows/watch-monitor.ps1`.

## Setup

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\install.ps1
```

This backs up `%APPDATA%\Deskflow\Deskflow.conf`, points Deskflow at the text config
(copied to `C:\ProgramData\Deskflow\switch-mac-win.conf`), creates the desktop shortcuts,
and starts the watcher (it also adds it to Startup). Re-run it after editing
`deskflow-server.conf`: it restarts the Deskflow app, because that is the only time Deskflow
re-reads the config.

Mac:

Clone the repo to `~/src/switch-mac-win` (the watcher's SSH fallback expects it there). Then:

```sh
./mac/install.sh
```

This installs `m1ddc` and creates **Go Windows!** in `~/Desktop` and `~/Applications`
(find it with Spotlight, or drag it to the Dock). From the Mac you can also just press
**Ctrl+Alt+Shift+F11**: the keyboard is plugged into Windows, so the Deskflow hotkey works anywhere.
