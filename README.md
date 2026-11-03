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
  switch explicitly. Use the hotkeys **Ctrl+Alt+Shift+F11** (→ Mac) and **Ctrl+Alt+Shift+F12**
  (→ Windows); the scripts press them for you.
- **Mac → Windows:** the Mac can't send commands to the Deskflow server, so
  `windows/watch-monitor.ps1` runs at logon. It polls the monitor once a second, and when the
  input becomes fullscreen DP it moves Deskflow to Windows. It works the same way if you
  switch inputs with the monitor's buttons. It logs to `%LOCALAPPDATA%\switch-mac-win\watch.log`.

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

This installs `m1ddc` and creates `~/Desktop/Go Windows!.app`.
