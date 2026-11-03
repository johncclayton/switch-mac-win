# Sets up the Windows PC (the Deskflow server). Safe to re-run.
#
#   powershell -ExecutionPolicy Bypass -File .\windows\install.ps1 --server [options]
#
# Asks for anything it doesn't know (existing config values are the defaults), then:
#  - saves %LOCALAPPDATA%\switch-mac-win\config.json
#  - writes Deskflow's settings: this machine's name, the Mac's screen, and the server
#    config with the hotkeys (backs up Deskflow.conf first; see docs/adr/0002)
#  - creates the "Go Mac!", "Go Windows!", "Go Split!" desktop shortcuts
#  - starts watch-monitor.ps1 now and at every logon
#  - prints the command to run on the Mac
#
# Options (all optional except --server):
#   --server-name NAME   Deskflow screen name of this Windows PC
#   --server-host HOST   host or IP address of this Windows PC (the Mac connects to it)
#   --client-name NAME   Deskflow screen name of the Mac
#   --client-host HOST   host or IP address of the Mac (to wake it)
#   --token TOKEN        wake token (default: keep the existing one, or generate one)
#   --new-token          generate a new wake token
#   --wake-port PORT     wake listener port (default 47999)
#   --toggle-key KEYS / --to-mac-key KEYS / --to-windows-key KEYS
#                        hotkeys in Deskflow syntax, e.g. Control+Alt+Shift+F11
#   --yes                don't ask; use the options and defaults
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$repo = Split-Path $here
Import-Module (Join-Path $here 'Config.psm1') -Force

# --- Options ------------------------------------------------------------------
$valueFlags = @{
    '--server-name' = 'serverName'; '--server-host' = 'serverHost'
    '--client-name' = 'clientName'; '--client-host' = 'clientHost'
    '--token' = 'wakeToken'; '--wake-port' = 'wakePort'
    '--toggle-key' = 'toggleKey'; '--to-mac-key' = 'toMacKey'; '--to-windows-key' = 'toWindowsKey'
}
$given = @{}; $role = $null; $newToken = $false; $yes = $false
for ($i = 0; $i -lt $args.Count; $i++) {
    $a = $args[$i]
    if ($a -eq '--server') { $role = 'server' }
    elseif ($a -eq '--client') { throw 'This is the Windows installer, which sets up the Deskflow server. Run mac/install.sh --client on the Mac.' }
    elseif ($a -eq '--new-token') { $newToken = $true }
    elseif ($a -eq '--yes') { $yes = $true }
    elseif ($valueFlags.ContainsKey($a) -and $i + 1 -lt $args.Count) { $given[$valueFlags[$a]] = $args[++$i] }
    else { throw "Unknown or incomplete option '$a'. See the comments at the top of install.ps1." }
}
if ($role -ne 'server') { throw 'Say which role this machine has: install.ps1 --server' }

$old = Read-SmwConfig -AllowMissing
$cfg = Copy-SmwConfig $old

function Ask($key, $label, $default) {
    if ($given.ContainsKey($key)) { return $given[$key] }
    if ($yes) {
        if (-not $default) { throw "No value for $label; pass it as an option." }
        return $default
    }
    $prompt = if ($default) { "$label [$default]" } else { $label }
    do { $answer = Read-Host $prompt; if (-not $answer) { $answer = $default } } while (-not $answer)
    $answer
}
function Test-IsIp($s) { $ip = $null; [Net.IPAddress]::TryParse($s, [ref]$ip) }

$thisHost = $env:COMPUTERNAME.ToLower()
Write-Host 'Windows PC (this machine)'
$cfg.serverName = Ask 'serverName' '  Deskflow screen name' ($(if ($old.serverName) { $old.serverName } else { $thisHost }))
$cfg.serverHost = Ask 'serverHost' '  Host or IP address' ($(if ($old.serverHost) { $old.serverHost } else { "$thisHost.local" }))
Write-Host 'Mac'
$cfg.clientName = Ask 'clientName' '  Deskflow screen name' $old.clientName
$cfg.clientHost = Ask 'clientHost' '  Host or IP address' ($(if ($old.clientHost) { $old.clientHost } else { "$($cfg.clientName).local" }))
foreach ($k in 'wakePort', 'toggleKey', 'toMacKey', 'toWindowsKey') { if ($given.ContainsKey($k)) { $cfg[$k] = $given[$k] } }
$cfg.wakePort = [int]$cfg.wakePort
foreach ($k in 'toggleKey', 'toMacKey', 'toWindowsKey') { [void](ConvertTo-VirtualKeys $cfg[$k]) }   # validate
if ($cfg.serverName -eq $cfg.clientName) { throw 'The two Deskflow screen names must differ.' }

if ($given.ContainsKey('wakeToken')) { $cfg.wakeToken = $given.wakeToken }
elseif ($newToken -or -not $old.wakeToken) {
    $bytes = New-Object byte[] 16
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $cfg.wakeToken = -join ($bytes | ForEach-Object { $_.ToString('x2') })
    Write-Host 'Generated a new wake token.'
}

# Hosts: warn early about the things that break later.
foreach ($h in @($cfg.serverHost, $cfg.clientHost)) {
    if (Test-IsIp $h) { Write-Warning "$h is an IP address: reserve it in your router's DHCP settings so it doesn't change." }
}
$macIp = Resolve-IPv4 $cfg.clientHost
if (-not $macIp) {
    Write-Warning "Can't resolve $($cfg.clientHost) to an IPv4 address right now. Waking the Mac needs it; check the name, or use the Mac's IP address."
}

Save-SmwConfig $cfg
# Seed the fallback address used when the name doesn't resolve while the Mac sleeps.
if ($macIp) { Set-Content (Join-Path (Split-Path $ConfigPath) 'mac-ipv4.txt') $macIp }
Write-Host "Saved $ConfigPath"

# --- Deskflow -----------------------------------------------------------------
$serverConf = 'C:\ProgramData\Deskflow\switch-mac-win.conf'
$template = Get-Content (Join-Path $repo 'deskflow\deskflow-server.conf.template') -Raw
$rendered = $template.Replace('{{SERVER_NAME}}', $cfg.serverName).Replace('{{CLIENT_NAME}}', $cfg.clientName).
    Replace('{{TOGGLE_KEY}}', $cfg.toggleKey).Replace('{{TO_MAC_KEY}}', $cfg.toMacKey).Replace('{{TO_WINDOWS_KEY}}', $cfg.toWindowsKey)
New-Item -ItemType Directory -Force (Split-Path $serverConf) | Out-Null
Set-Content $serverConf $rendered -NoNewline
Write-Host "Wrote $serverConf"

# Deskflow.conf is an INI file the Deskflow app rewrites when it exits, so stop it first.
$gui = 'C:\Program Files\Deskflow\deskflow.exe'
$guiConf = Join-Path $env:APPDATA 'Deskflow\Deskflow.conf'
Get-Process deskflow -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 2
$lines = [Collections.Generic.List[string]]::new()
if (Test-Path $guiConf) {
    Copy-Item $guiConf "$guiConf.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
    $lines.AddRange([string[]](Get-Content $guiConf))
}

function Find-Section($name) { $lines.IndexOf("[$name]") }
function Get-SectionEnd($start) {
    $j = $start + 1
    while ($j -lt $lines.Count -and $lines[$j] -notmatch '^\[') { $j++ }
    $j
}
function Set-Ini($section, $key, $value) {
    $s = Find-Section $section
    if ($s -lt 0) { if ($lines.Count -and $lines[-1] -ne '') { $lines.Add('') }; $lines.Add("[$section]"); $s = $lines.Count - 1 }
    $end = Get-SectionEnd $s
    for ($j = $s + 1; $j -lt $end; $j++) {
        if ($lines[$j].StartsWith("$key=")) { $lines[$j] = "$key=$value"; return }
    }
    $insert = $end
    while ($insert -gt $s + 1 -and $lines[$insert - 1] -eq '') { $insert-- }
    $lines.Insert($insert, "$key=$value")
}
function Get-ComputerSections { $lines | Where-Object { $_ -match '^\[computer_(.+)\]$' } | ForEach-Object { $_ -replace '^\[computer_(.+)\]$', '$1' } }
# Renames a screen's [computer_*] section, keeping its options (e.g. the Mac's modifier remapping).
function Rename-Screen($from, $to) {
    if (-not $from -or $from -eq $to -or (Find-Section "computer_$to") -ge 0) { return }
    $s = Find-Section "computer_$from"
    if ($s -lt 0) { return }
    $lines[$s] = "[computer_$to]"
    Write-Host "Renamed Deskflow screen $from -> $to"
}
function Set-ScreenGridName($from, $to, [int]$slot) {
    $pattern = '^screens\\(\d+)\\name=(.*)$'
    $names = @{}
    foreach ($l in $lines) { if ($l -match $pattern) { $names[[int]$Matches[1]] = $Matches[2] } }
    $hit = $names.Keys | Where-Object { $names[$_] -eq $to -or ($from -and $names[$_] -eq $from) } | Select-Object -First 1
    if ($null -eq $hit) { $hit = $slot }
    Set-Ini 'internalConfig' "screens\$hit\name" $to
}

$oldServer = if ($old.serverName) { $old.serverName } else { (Get-ComputerSections | Where-Object { $_ -ieq $env:COMPUTERNAME } | Select-Object -First 1) }
$oldClient = if ($old.clientName) { $old.clientName } else { (Get-ComputerSections | Where-Object { $_ -ne $oldServer -and $_ -ine $env:COMPUTERNAME } | Select-Object -First 1) }
Rename-Screen $oldServer $cfg.serverName
Rename-Screen $oldClient $cfg.clientName
Set-Ini "computer_$($cfg.serverName)" 'name' $cfg.serverName
Set-Ini "computer_$($cfg.clientName)" 'name' $cfg.clientName
# The GUI's 5x3 screen grid: the Windows PC in the middle (8), the Mac to its right (9).
if (-not ($lines -match '^screens\\size=')) { Set-Ini 'internalConfig' 'screens\size' '15' }
Set-ScreenGridName $oldServer $cfg.serverName 8
Set-ScreenGridName $oldClient $cfg.clientName 9
Set-Ini 'core' 'computerName' $cfg.serverName
Set-Ini 'core' 'coreMode' '2'   # server
Set-Ini 'server' 'externalConfig' 'true'
Set-Ini 'server' 'externalConfigFile' ($serverConf -replace '\\', '/')
New-Item -ItemType Directory -Force (Split-Path $guiConf) | Out-Null
Set-Content $guiConf $lines
Write-Host "Updated $guiConf (backup next to it)"
Start-Process $gui
Write-Host 'Started Deskflow'

# --- Shortcuts ----------------------------------------------------------------
$shell = New-Object -ComObject WScript.Shell
$ps = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
function New-Shortcut($lnkPath, $script, $icon) {
    $s = $shell.CreateShortcut($lnkPath)
    # conhost --headless runs PowerShell with no console window flashing up
    $s.TargetPath = "$env:WINDIR\System32\conhost.exe"
    $s.Arguments = "--headless `"$ps`" -NoProfile -ExecutionPolicy Bypass -File `"$script`""
    $s.WorkingDirectory = $here
    $s.IconLocation = $icon
    $s.Save()
}
$desktop = [Environment]::GetFolderPath('Desktop')
New-Shortcut (Join-Path $desktop 'Go Mac!.lnk')     (Join-Path $here 'switch-to-mac.ps1')     "$env:WINDIR\System32\imageres.dll,109"
New-Shortcut (Join-Path $desktop 'Go Windows!.lnk') (Join-Path $here 'switch-to-windows.ps1') "$env:WINDIR\System32\imageres.dll,111"
New-Shortcut (Join-Path $desktop 'Go Split!.lnk')   (Join-Path $here 'switch-to-split.ps1')   "$env:WINDIR\System32\imageres.dll,174"
Write-Host "Shortcuts created on $desktop"

# --- Watcher ------------------------------------------------------------------
$watcher = Join-Path $here 'watch-monitor.ps1'
$startup = [Environment]::GetFolderPath('Startup')
New-Shortcut (Join-Path $startup 'switch-mac-win watcher.lnk') $watcher "$env:WINDIR\System32\imageres.dll,109"
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object CommandLine -like '*watch-monitor.ps1*' |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Process "$env:WINDIR\System32\conhost.exe" "--headless `"$ps`" -NoProfile -ExecutionPolicy Bypass -File `"$watcher`""
Write-Host 'Watcher started (and added to Startup)'

# --- The Mac --------------------------------------------------------------------
Write-Host ''
Write-Host 'Now run this on the Mac, in its copy of the repo:' -ForegroundColor Cyan
Write-Host ("  ./mac/install.sh --client --server-name '{0}' --server-host '{1}' --client-name '{2}' --client-host '{3}' --wake-port {4} --token '{5}'" -f
    $cfg.serverName, $cfg.serverHost, $cfg.clientName, $cfg.clientHost, $cfg.wakePort, $cfg.wakeToken)
Write-Host ''
Write-Host 'Then test waking the Mac from here with:  powershell -ExecutionPolicy Bypass -File .\windows\test-wake.ps1'
