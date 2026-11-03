# Checks that this PC can reach the Mac's wake listener with the configured token.
# Put the Mac to sleep first to see a real wake: the Mac's Deskflow should reconnect.
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Config.psm1')
Import-Module (Join-Path $PSScriptRoot 'Deskflow.psm1')
$cfg = Read-SmwConfig
$ip = Get-MacIPv4
if (-not $ip) { Write-Host "Can't resolve $($cfg.clientHost) to an IPv4 address, and there's no earlier answer to fall back on. Try again while the Mac is awake." -ForegroundColor Red; exit 1 }
Write-Host "$($cfg.clientHost) -> $ip"
if (-not (Send-MacWake)) { Write-Host "Couldn't connect to the wake listener on $($ip):$($cfg.wakePort). Is mac/install.sh done?" -ForegroundColor Red; exit 1 }
Write-Host "Sent the wake token to $($ip):$($cfg.wakePort)."
if (Resume-Mac -WaitSec 10) { Write-Host 'The Mac connected to Deskflow.' -ForegroundColor Green }
else { Write-Host "No new Deskflow connection. That's expected if the Mac was already awake; otherwise check ~/Library/Logs/switch-mac-win-wake.log on the Mac." -ForegroundColor Yellow }
