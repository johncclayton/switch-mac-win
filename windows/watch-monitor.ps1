# Runs at logon and keeps the monitor and Deskflow in step, whichever one moves first:
#  - monitor -> Deskflow: polls the monitor; when it goes fullscreen DP/Thunderbolt
#    (e.g. "Go Windows!" on the Mac, or the monitor's buttons) it moves the cursor.
#  - Deskflow -> monitor: reads Deskflow's log; when the cursor changes machine
#    (e.g. the toggle hotkey) it switches the monitor to match. In split view the
#    monitor is left alone, so the hotkeys just move the cursor.
#  - toggle hotkey while the Mac sleeps: wakes the Mac, then moves there.
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'DellDdc.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Deskflow.psm1') -Force

$switchDisplay = Join-Path $PSScriptRoot 'Switch-Display.ps1'
$deskflowLog = 'C:\ProgramData\Deskflow\deskflow-daemon.log'

$log = Join-Path $env:LOCALAPPDATA 'switch-mac-win\watch.log'
New-Item -ItemType Directory -Force (Split-Path $log) | Out-Null
# Logging must never kill the watcher (e.g. if something else has the file open).
function Log($msg) { try { "$(Get-Date -Format s) $msg" | Add-Content $log -ErrorAction Stop } catch {} }

function Get-ScreenState {
    if ((Get-Vcp 0xE9 -TimeoutSec 3).Value -ne 0) { return 'Split' }
    switch ((Get-Vcp 0x60 -TimeoutSec 3).Value) { 0x19 { 'Mac' } 0x0F { 'Windows' } default { 'Other' } }
}

# Returns the Deskflow screen names Deskflow switched to since the last call, in
# order, plus 'wake-mac' when the toggle hotkey failed because the Mac wasn't connected.
$logPos = try { (Get-Item $deskflowLog).Length } catch { 0 }
function Read-DeskflowSwitches {
    $fs = [IO.File]::Open($deskflowLog, 'Open', 'Read', 'ReadWrite,Delete')
    try {
        if ($fs.Length -lt $script:logPos) { $script:logPos = 0 }   # log was rotated
        if ($fs.Length -eq $script:logPos) { return }
        $fs.Position = $script:logPos
        $text = (New-Object IO.StreamReader($fs)).ReadToEnd()
        $script:logPos = $fs.Length
    } finally { $fs.Close() }
    foreach ($m in [regex]::Matches($text, '(?:switch|jump) from "([^"]+)" to "([^"]+)"|not enough computers to toggle')) {
        if (-not $m.Groups[1].Success) { 'wake-mac' }
        elseif ($m.Groups[1].Value -ne $m.Groups[2].Value) { $m.Groups[2].Value }
    }
}

# Deskflow moved the cursor to $target ('Mac'/'Windows'): make the monitor follow.
function Sync-MonitorTo($target) {
    try { $now = Get-ScreenState } catch { $now = 'Unreachable' }
    if ($now -eq $target) { return $now }
    if ($now -eq 'Split') { Log "deskflow -> $target; split view, monitor left alone"; return $now }
    # Unreachable from Windows almost always means the Mac is fullscreen.
    if ($now -eq 'Unreachable' -and $target -eq 'Mac') { return $now }
    Log "deskflow -> $target; switching monitor (was $now)"
    try {
        & $switchDisplay -Target $target -NoDeskflow -TimeoutSec 4
    } catch {
        # No fallback (see docs/adr/0001): use the monitor's input button.
        Log "monitor switch failed: $($_.Exception.Message)"; return $now
    }
    return $target
}

# While the Mac is on screen, Windows often loses its DDC link to the monitor,
# so "unreachable" is a state of its own. Unreachable -> Windows is the
# Mac's "Go Windows!" and must move Deskflow back.
Log 'watcher started'
$last = $null
$fails = 0
while ($true) {
    try {
        $state = Get-ScreenState
        $fails = 0
    } catch {
        $fails++
        # Ignore short blips during mode changes; after ~5s call it unreachable.
        $state = if ($fails -ge 2) { 'Unreachable' } else { $last }
        if ($fails -eq 2) { Log "monitor unreachable: $($_.Exception.Message)" }
    }
    if ($null -ne $last -and $state -ne $last) {
        if ($state -in 'Mac', 'Windows') {
            Log "screen changed $last -> $state; switching Deskflow"
            Switch-DeskflowScreen $state | Out-Null
        } else {
            Log "screen changed $last -> $state"
        }
    }
    $last = $state

    try {
        $moves = @(Read-DeskflowSwitches)
        if ($moves -contains 'wake-mac') {
            # Toggle pressed while the Mac was asleep: wake it, then go there. The
            # resulting Deskflow switch is picked up next time round and moves the monitor.
            Log 'toggle hotkey but the Mac is not connected; waking it'
            if ((Resume-Mac) -and (Switch-DeskflowScreen Mac -WaitSec 3)) { Log 'Mac woke up' }
            else { Log 'Mac did not wake up / reconnect; staying on Windows' }
            $moves = @()
        }
        if ($moves.Count) {
            $target = Get-ScreenRole $moves[-1]
            if ($target) { $last = Sync-MonitorTo $target }
        }
    } catch { Log "deskflow log check failed: $($_.Exception.Message)" }

    Start-Sleep -Milliseconds 1000
}
