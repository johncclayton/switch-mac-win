# Moves the Deskflow cursor by "pressing" the hotkeys from the config (written into
# Deskflow's server config by install.ps1), and wakes a sleeping Mac.
# The Deskflow server hooks the keyboard globally, so synthesized keys reach it even
# when the cursor is on the Mac.
Import-Module (Join-Path $PSScriptRoot 'Config.psm1')

$src = @'
using System; using System.Runtime.InteropServices;
public static class DfKeys {
    [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll")] static extern uint MapVirtualKey(uint code, uint mapType);
    const uint KEYUP = 2;
    static void Key(byte vk, bool up) { keybd_event(vk, (byte)MapVirtualKey(vk, 0), up ? KEYUP : 0, UIntPtr.Zero); }
    public static void Chord(byte[] keys) {
        foreach (var k in keys) Key(k, false);
        System.Threading.Thread.Sleep(60);
        for (int i = keys.Length - 1; i >= 0; i--) Key(keys[i], true);
    }
}
'@
if (-not ('DfKeys' -as [type])) { Add-Type -TypeDefinition $src }

$DeskflowLog = 'C:\ProgramData\Deskflow\deskflow-daemon.log'
$Config = Read-SmwConfig

# Deskflow screen name -> 'Mac' / 'Windows'
function Get-ScreenRole([string]$ScreenName) {
    if ($ScreenName -eq $Config.clientName) { 'Mac' } elseif ($ScreenName -eq $Config.serverName) { 'Windows' }
}

function Get-DeskflowLogLength { try { (Get-Item $DeskflowLog).Length } catch { 0 } }

# Waits until Deskflow logs a line matching $Pattern after byte offset $From.
function Wait-DeskflowLog([string]$Pattern, [long]$From, [int]$WaitSec) {
    $deadline = (Get-Date).AddSeconds($WaitSec)
    do {
        Start-Sleep -Milliseconds 200
        try {
            $fs = [IO.File]::Open($DeskflowLog, 'Open', 'Read', 'ReadWrite,Delete')
            try {
                if ($fs.Length -lt $From) { $From = 0 }   # log was rotated
                $fs.Position = $From
                if ((New-Object IO.StreamReader($fs)).ReadToEnd() -match $Pattern) { return $true }
            } finally { $fs.Close() }
        } catch {}
    } while ((Get-Date) -lt $deadline)
    $false
}

# Presses the "go to Mac" / "go to Windows" hotkey. With -WaitSec, waits for Deskflow
# to log the move and returns whether it happened (it doesn't when the Mac's Deskflow
# isn't connected).
function Switch-DeskflowScreen([ValidateSet('Mac', 'Windows')][string]$Screen, [int]$WaitSec = 0) {
    $start = Get-DeskflowLogLength
    $keystroke = if ($Screen -eq 'Mac') { $Config.toMacKey } else { $Config.toWindowsKey }
    [DfKeys]::Chord([byte[]]@(ConvertTo-VirtualKeys $keystroke))
    if (-not $WaitSec) { return }
    $name = if ($Screen -eq 'Mac') { $Config.clientName } else { $Config.serverName }
    Wait-DeskflowLog ('(?:switch|jump) from "[^"]+" to "' + [regex]::Escape($name) + '"') $start $WaitSec
}

# The Mac's IPv4 address. Resolving a .local name while the Mac sleeps works only
# some of the time, so remember the last good answer and fall back to it.
function Get-MacIPv4 {
    $cache = Join-Path (Split-Path $ConfigPath) 'mac-ipv4.txt'
    $ip = Resolve-IPv4 $Config.clientHost
    if ($ip) {
        try { if ((Get-Content $cache -ErrorAction SilentlyContinue) -ne $ip) { Set-Content $cache $ip } } catch {}
        return $ip
    }
    try { (Get-Content $cache -ErrorAction Stop | Select-Object -First 1) } catch { $null }
}

# Connects to the Mac's wake listener and sends the wake token.
function Send-MacWake([int]$TimeoutMs = 3000) {
    $ip = Get-MacIPv4
    if (-not $ip) { return $false }
    $c = New-Object Net.Sockets.TcpClient
    try {
        if (-not $c.ConnectAsync([Net.IPAddress]::Parse($ip), [int]$Config.wakePort).Wait($TimeoutMs)) { return $false }
        $w = New-Object IO.StreamWriter($c.GetStream())
        $w.Write("$($Config.wakeToken)`n"); $w.Flush()
        $true
    } catch { $false } finally { $c.Close() }
}

# Wakes a sleeping Mac and waits for its Deskflow client to reconnect. A network
# packet alone only "dark wakes" the Mac (screen off, Deskflow disconnected); the wake
# listener runs caffeinate -u, which fully wakes it. Returns whether Deskflow reconnected.
function Resume-Mac([int]$WaitSec = 15) {
    $start = Get-DeskflowLogLength
    $deadline = (Get-Date).AddSeconds($WaitSec)
    do {
        # The first connection may only wake the Mac; retry so one lands once it's up.
        [void](Send-MacWake)
        if (Wait-DeskflowLog 'accepted client connection' $start 2) {
            Start-Sleep -Milliseconds 500   # let the handshake finish
            return $true
        }
    } while ((Get-Date) -lt $deadline)
    $false
}

Export-ModuleMember -Function Switch-DeskflowScreen, Resume-Mac, Get-ScreenRole, Send-MacWake, Get-MacIPv4
