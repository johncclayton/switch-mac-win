# Runs at logon. Polls the monitor and moves the Deskflow cursor when the screen
# is switched from elsewhere (e.g. "Go Windows!" on the Mac, or the monitor's
# own buttons): fullscreen DP -> Windows, fullscreen Thunderbolt -> Mac.
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'DellDdc.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Deskflow.psm1') -Force

$log = Join-Path $env:LOCALAPPDATA 'switch-mac-win\watch.log'
New-Item -ItemType Directory -Force (Split-Path $log) | Out-Null
function Log($msg) { "$(Get-Date -Format s) $msg" | Add-Content $log }

function Get-ScreenState {
    if ((Get-Vcp 0xE9 -TimeoutSec 3).Value -ne 0) { return 'Split' }
    switch ((Get-Vcp 0x60 -TimeoutSec 3).Value) { 0x19 { 'Mac' } 0x0F { 'Windows' } default { 'Other' } }
}

Log 'watcher started'
$last = $null
while ($true) {
    try {
        $state = Get-ScreenState
        if ($null -ne $last -and $state -ne $last -and $state -in 'Mac', 'Windows') {
            Log "screen changed $last -> $state; switching Deskflow"
            Switch-DeskflowScreen $state
        }
        $last = $state
    } catch {
        # Monitor briefly vanishes during mode changes; keep the last state and retry.
    }
    Start-Sleep -Milliseconds 1000
}
