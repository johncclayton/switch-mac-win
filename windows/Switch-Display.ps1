# Switches the Dell U4021QW between the Mac (Thunderbolt), Windows (DisplayPort)
# and the side-by-side PBP split, and moves the Deskflow cursor to match.
param(
    [Parameter(Mandatory)][ValidateSet('Mac', 'Windows', 'Split')][string]$Target,
    [switch]$NoDeskflow,
    [int]$TimeoutSec = 15   # how long to keep retrying DDC while the monitor re-enumerates
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

function Set-Fullscreen([int]$InputCode) {
    if ((Get-Vcp $VCP_PBP_MODE).Value -ne $PBP_OFF) {
        Set-Vcp $VCP_PBP_MODE $PBP_OFF
        Start-Sleep -Milliseconds 1500   # let the monitor/Windows settle the mode change
    }
    Set-Vcp $VCP_INPUT $InputCode
}

switch ($Target) {
    'Mac' {
        # Move the keyboard/mouse first: if the Mac isn't there (off, asleep, Deskflow
        # not running) Deskflow won't move, and we leave the monitor on Windows rather
        # than switching to a blank screen.
        if (-not $NoDeskflow -and -not (Switch-DeskflowScreen Mac -WaitSec 3)) {
            $msg = 'The Mac is not connected to Deskflow (off, asleep, or Deskflow not running). Staying on Windows.'
            (New-Object -ComObject WScript.Shell).Popup($msg, 8, 'Go Mac!', 0x30) | Out-Null
            exit 1
        }
        Set-Fullscreen $INPUT_TB
    }
    'Windows' {
        Set-Fullscreen $INPUT_DP
        if (-not $NoDeskflow) { Switch-DeskflowScreen Windows }
    }
    'Split' {
        Set-Vcp $VCP_PBP_MODE $PBP_SPLIT
        Start-Sleep -Milliseconds 1500
        Set-Vcp $VCP_INPUT $INPUT_DP
        Set-Vcp $VCP_PBP_INPUT $INPUT_TB
    }
}
