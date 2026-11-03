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

## Setup

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\install.ps1
```

This backs up `%APPDATA%\Deskflow\Deskflow.conf`, points Deskflow at the text config
(copied to `C:\ProgramData\Deskflow\switch-mac-win.conf`), creates the desktop shortcuts,
and starts the watcher (it also adds it to Startup). Re-run it after editing
`deskflow-server.conf`.

Mac:

```sh
./mac/install.sh
```

This installs `m1ddc` and creates **Go Windows!** in `~/Desktop` and `~/Applications`
(find it with Spotlight, or drag it to the Dock). From the Mac you can also just press
**Ctrl+Alt+Shift+F11**: the keyboard is plugged into Windows, so the Deskflow hotkey works anywhere.
