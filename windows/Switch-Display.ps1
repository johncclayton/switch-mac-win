# Switches the Dell U4021QW between the Mac (Thunderbolt), Windows (DisplayPort)
# and the side-by-side PBP split, and moves the Deskflow cursor to match.
param(
    [Parameter(Mandatory)][ValidateSet('Mac', 'Windows', 'Split')][string]$Target,
    [switch]$NoDeskflow,
    [int]$TimeoutSec = 15,    # how long to keep retrying DDC while the monitor re-enumerates
    [int]$WaitForMacSec = 45  # Mac: how long to wait for its Deskflow once it's shown in split view
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'DellDdc.psm1')
Import-Module (Join-Path $PSScriptRoot 'Deskflow.psm1')
$PSDefaultParameterValues = @{ 'Get-Vcp:TimeoutSec' = $TimeoutSec; 'Set-Vcp:TimeoutSec' = $TimeoutSec }

# U4021QW VCP values (from its DDC capabilities string)
$INPUT_DP = 0x0F   # Windows
$INPUT_TB = 0x19   # Mac (Thunderbolt / USB-C)
$VCP_INPUT = 0x60
$VCP_PBP_INPUT = 0xE8   # Dell: input of the second PBP window
$VCP_PBP_MODE = 0xE9    # Dell: 0x00 off, 0x24 50/50 split
$PBP_OFF = 0x00
$PBP_SPLIT = 0x24

function Set-Split {
    Set-Vcp $VCP_PBP_MODE $PBP_SPLIT
    Start-Sleep -Milliseconds 1500
    Set-Vcp $VCP_INPUT $INPUT_DP
    Set-Vcp $VCP_PBP_INPUT $INPUT_TB
}

function Set-Fullscreen([int]$InputCode) {
    if ((Get-Vcp $VCP_PBP_MODE).Value -ne $PBP_OFF) {
        Set-Vcp $VCP_PBP_MODE $PBP_OFF
        Start-Sleep -Milliseconds 1500   # let the monitor/Windows settle the mode change
    }
    Set-Vcp $VCP_INPUT $InputCode
}

switch ($Target) {
    'Mac' {
        # Move the keyboard/mouse first. If the Mac isn't connected to Deskflow (e.g.
        # asleep), wake it and try again. If it still isn't, show the Mac in split view
        # and wait for its Deskflow: a Mac with no display can't start Deskflow, and
        # after a restart it's waiting for a password (docs/adr/0003). The monitor only
        # goes fullscreen Mac once Deskflow has the cursor there.
        if (-not $NoDeskflow -and -not (Switch-DeskflowScreen Mac -WaitSec 2)) {
            Write-Host 'The Mac is not connected to Deskflow; waking it'
            if (-not ((Resume-Mac) -and (Switch-DeskflowScreen Mac -WaitSec 3))) {
                Write-Host "$(Get-LastWakeStatus); showing the Mac in split view and waiting for its Deskflow"
                $since = Get-DeskflowLogLength
                Set-Split
                if (-not ((Wait-MacConnected $since $WaitForMacSec) -and (Switch-DeskflowScreen Mac -WaitSec 3))) {
                    Write-Host "The Mac's Deskflow didn't connect within $WaitForMacSec s; staying in split view"
                    $msg = "The Mac's Deskflow hasn't connected. It's on the right half of the screen: log in to it if it asks, and once it's up press Go Mac! again."
                    (New-Object -ComObject WScript.Shell).Popup($msg, 10, 'Go Mac!', 0x30) | Out-Null
                    exit 1
                }
                Write-Host "The Mac's Deskflow connected"
            }
        }
        Set-Fullscreen $INPUT_TB
    }
    'Windows' {
        Set-Fullscreen $INPUT_DP
        if (-not $NoDeskflow) { Switch-DeskflowScreen Windows }
    }
    'Split' { Set-Split }
}
