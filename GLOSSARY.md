# switch-mac-win

Switching one monitor, plus the keyboard and mouse shared through Deskflow, between a Windows PC and a Mac.

## Machines

**Windows PC**:
The computer with the keyboard and mouse plugged in. It runs the Deskflow server.
_Avoid_: server, obsidian (a machine's name, not its role)

**Mac**:
The other computer, which gets its keyboard and mouse through Deskflow.
_Avoid_: client, m6 (a machine's name, not its role)

## Identities

**Deskflow screen name**:
The name Deskflow uses for a machine, e.g. in the hotkey actions and in its logs.
_Avoid_: computer name, hostname, screen

**Host or IP address**:
How one machine reaches the other over the network: a resolvable hostname or an IP address.
_Avoid_: address on its own, Mac address (reads as the hardware MAC address)

## Waking

**Wake listener**:
The service on the Mac that wakes it fully when the Windows PC connects to it.

**Wake token**:
The shared secret the Windows PC sends to the wake listener to prove the request is genuine.
_Avoid_: password, key
