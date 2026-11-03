# Runs at logon. Polls the monitor and moves the Deskflow cursor when the screen
# is switched from elsewhere (e.g. "Go Windows!" on the Mac, or the monitor's
# own buttons): fullscreen DP -> Windows, fullscreen Thunderbolt -> Mac.
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'DellDdc.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Deskflow.psm1') -Force

$log = Join-Path $env:LOCALAPPDATA 'switch-mac-win\watch.log'
New-Item -ItemType Directory -Force (Split-Path $log) | Out-Null
# Logging must never kill the watcher (e.g. if something else has the file open).
function Log($msg) { try { "$(Get-Date -Format s) $msg" | Add-Content $log -ErrorAction Stop } catch {} }

function Get-ScreenState {
    if ((Get-Vcp 0xE9 -TimeoutSec 3).Value -ne 0) { return 'Split' }
    switch ((Get-Vcp 0x60 -TimeoutSec 3).Value) { 0x19 { 'Mac' } 0x0F { 'Windows' } default { 'Other' } }
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
            Switch-DeskflowScreen $state
        } else {
            Log "screen changed $last -> $state"
        }
    }
    $last = $state
    Start-Sleep -Milliseconds 1000
}
