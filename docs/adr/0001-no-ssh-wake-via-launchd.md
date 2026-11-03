# No SSH: wake the Mac with a launchd listener

The Windows PC needs to fully wake a sleeping Mac. A network packet only "dark wakes" it (screen off, Deskflow disconnected), so something on the Mac must also run `caffeinate -u`. We first did this over SSH, and later used SSH as a fallback for switching the monitor back. We removed SSH entirely: setting up a passwordless key pair, plus Remote Login, was the biggest setup burden for a new user. A launchd socket listener (port advertised over Bonjour) both wakes the Mac and runs `caffeinate -u`, needs no keys, and woke a sleeping Mac in about 2 s against 6 to 7 s over SSH.

## Consequences

- There's no longer a fallback for switching the monitor back to the Windows PC when the Windows PC can't control the monitor over DDC/CI while the Mac is on screen. The fallback is the monitor's input button. It could come back as a second command on the wake listener once the listener checks the wake token.
- Anything on the local network can connect to the wake listener. Until the wake token exists, the only thing such a connection can do is wake the Mac.
