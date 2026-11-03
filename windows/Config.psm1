# Reads this machine's switch-mac-win config, written by install.ps1.
# Example: windows/config.example.json
$ConfigPath = Join-Path $env:LOCALAPPDATA 'switch-mac-win\config.json'

$Defaults = [ordered]@{
    serverName   = ''                         # Deskflow screen name of the Windows PC
    serverHost   = ''                         # host or IP address of the Windows PC
    clientName   = ''                         # Deskflow screen name of the Mac
    clientHost   = ''                         # host or IP address of the Mac
    wakePort     = 47999
    wakeToken    = ''
    toggleKey    = 'Control+Alt+Shift+F11'    # Deskflow keystroke syntax
    toMacKey     = 'Control+Alt+Shift+F10'
    toWindowsKey = 'Control+Alt+Shift+F12'
}

# Returns the saved config merged over the defaults (an ordered hashtable).
function Read-SmwConfig([switch]$AllowMissing) {
    $cfg = Copy-SmwConfig $Defaults
    if (Test-Path $ConfigPath) {
        $saved = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        foreach ($p in $saved.PSObject.Properties) { $cfg[$p.Name] = $p.Value }
    } elseif (-not $AllowMissing) {
        throw "No config at $ConfigPath. Run windows\install.ps1 --server first."
    }
    $cfg
}

function Copy-SmwConfig($Config) {
    $copy = [ordered]@{}
    foreach ($k in $Config.Keys) { $copy[$k] = $Config[$k] }
    $copy
}

function Save-SmwConfig($Config) {
    New-Item -ItemType Directory -Force (Split-Path $ConfigPath) | Out-Null
    [pscustomobject]$Config | ConvertTo-Json | Set-Content $ConfigPath -Encoding UTF8
}

# 'Control+Alt+Shift+F10' -> virtual-key codes for keybd_event.
function ConvertTo-VirtualKeys([string]$Keystroke) {
    foreach ($part in $Keystroke -split '\+') {
        switch -Regex ($part.Trim()) {
            '^(Control|Ctrl)$' { 0x11; continue }
            '^Alt$'            { 0x12; continue }
            '^Shift$'          { 0x10; continue }
            '^(Super|Meta|Win)$' { 0x5B; continue }
            '^F([1-9]|1[0-9]|2[0-4])$' { 0x6F + [int]$Matches[1]; continue }
            '^[A-Za-z0-9]$'    { [int][char]$part.Trim().ToUpper(); continue }
            default { throw "Unsupported key '$part' in hotkey '$Keystroke'" }
        }
    }
}

# Resolves a host or IP address to an IPv4 address (Bonjour .local names included).
# Asks for IPv4 explicitly: the IPv6 lookup of a .local name can fail.
function Resolve-IPv4([string]$HostOrIp) {
    $ip = $null
    if ([Net.IPAddress]::TryParse($HostOrIp, [ref]$ip)) { return $HostOrIp }
    try {
        (Resolve-DnsName $HostOrIp -Type A -ErrorAction Stop | Where-Object { $_.Type -eq 'A' } | Select-Object -First 1).IPAddress
    } catch { $null }
}

Export-ModuleMember -Function Read-SmwConfig, Save-SmwConfig, Copy-SmwConfig, ConvertTo-VirtualKeys, Resolve-IPv4 -Variable ConfigPath, Defaults
