# Split view when the Mac can't be reached, and a keeper for its Deskflow

Go Mac! and the toggle hotkey move Deskflow first and only then switch the monitor, so the monitor never shows a Mac that can't take the keyboard. When the Mac isn't connected to Deskflow, the wake listener wakes it. That covers a sleeping Mac, but not the other ways the Mac goes missing, and all of them need the Mac to have a display:

- The Mac was restarted. Nothing of ours runs until its FileVault password is typed, and nothing can be typed on a screen you can't see.
- Deskflow on the Mac was quit, or its client stopped. macOS ties the client's local network access to the app that launched it: a client that outlives the app is blocked from connecting ("No route to host"), and a client can't start at all without a display ("failed to initialize computer shape").

So when the wake doesn't bring Deskflow back, Go Mac! shows the Mac in **split view** (the Windows PC on the left, the Mac on the right) and waits for the Mac's Deskflow to connect. Split view keeps the Windows PC on screen with the keyboard, and gives the Mac a display and a face. Once Deskflow connects, Go Mac! finishes the switch; otherwise it stays in split view and says so.

On the Mac, a second LaunchAgent, the **keeper**, runs every 15 s and starts Deskflow if it isn't running, or restarts it when its client has stopped and a display is attached. It restarts the app rather than the client alone, so the client keeps its local network access. The wake listener nudges the keeper on every wake.

## Consequences

- The toggle hotkey can now change the monitor to split view. While Go Mac! is waiting (up to about a minute: the wake, then the split-view wait), the watcher does nothing else, and toggle presses made meanwhile are dropped.
- Quitting Deskflow on the Mac no longer sticks: the keeper reopens it within 15 s. To really stop it, unload the keeper: `launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.switch-mac-win.deskflow.plist`.
- A restarted Mac still needs its FileVault password typed on a keyboard of its own, since Deskflow isn't running yet. Turning FileVault off and automatic login on would make the Mac come back by itself; that's a security trade-off for the owner, not something the installer does. An authenticated restart (`sudo fdesetup authrestart`) skips the password once but still stops at the login window.
