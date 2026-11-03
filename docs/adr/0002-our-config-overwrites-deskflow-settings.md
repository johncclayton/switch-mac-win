# Our config is the source of truth and overwrites Deskflow's settings

The installers ask for the Deskflow screen names, hosts and IP addresses, and keep them in a config file on each machine. They then write those values into Deskflow's own settings on both machines (`computerName`, the server's screen list and per-screen section, and the Mac's `remoteHost`), after making a backup. We first considered the opposite, reading names from Deskflow's settings at runtime, so there would be one copy. We rejected it because the installer can't assume any existing setup, and with two copies a rename in one place silently breaks the hotkeys. One source that pushes into Deskflow keeps both machines consistent.

## Consequences

- Changes made by hand in the Deskflow app to the screen names or the server address are overwritten on the next install run. Change them in the config (or with the installer flags) instead.
- The installers stop Deskflow while they edit its settings, because the Deskflow app rewrites its settings file when it exits.
