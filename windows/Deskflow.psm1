# Moves the Deskflow cursor by "pressing" the hotkeys defined in
# deskflow/deskflow-server.conf. The Deskflow server hooks the keyboard globally,
# so synthesized keys reach it even when the cursor is on the Mac.
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

$VK_CONTROL = 0x11; $VK_MENU = 0x12; $VK_SHIFT = 0x10; $VK_F10 = 0x79; $VK_F12 = 0x7B

# Mac = Ctrl+Alt+Shift+F10 -> switchToScreen(m6.local)
# (F11 is the toggle for people; scripts need an explicit target)
# Windows = Ctrl+Alt+Shift+F12 -> switchToScreen(obsidian)
$deskflowLog = 'C:\ProgramData\Deskflow\deskflow-daemon.log'
$screenName = @{ Mac = 'm6.local'; Windows = 'obsidian' }
$macHost = 'm6'   # ssh host used to wake the Mac

function Get-DeskflowLogLength { try { (Get-Item $deskflowLog).Length } catch { 0 } }

# Waits until Deskflow logs a line matching $Pattern after byte offset $From.
function Wait-DeskflowLog([string]$Pattern, [long]$From, [int]$WaitSec) {
    $deadline = (Get-Date).AddSeconds($WaitSec)
    do {
        Start-Sleep -Milliseconds 200
        try {
            $fs = [IO.File]::Open($deskflowLog, 'Open', 'Read', 'ReadWrite,Delete')
            try {
                if ($fs.Length -lt $From) { $From = 0 }   # log was rotated
                $fs.Position = $From
                if ((New-Object IO.StreamReader($fs)).ReadToEnd() -match $Pattern) { return $true }
            } finally { $fs.Close() }
        } catch {}
    } while ((Get-Date) -lt $deadline)
    $false
}

# With -WaitSec, waits for Deskflow to log the move and returns whether it happened
# (it doesn't when the Mac's Deskflow isn't connected).
function Switch-DeskflowScreen([ValidateSet('Mac', 'Windows')][string]$Screen, [int]$WaitSec = 0) {
    $start = Get-DeskflowLogLength
    $fkey = if ($Screen -eq 'Mac') { $VK_F10 } else { $VK_F12 }
    [DfKeys]::Chord([byte[]]@($VK_CONTROL, $VK_MENU, $VK_SHIFT, $fkey))
    if (-not $WaitSec) { return }
    Wait-DeskflowLog ('(?:switch|jump) from "[^"]+" to "' + [regex]::Escape($screenName[$Screen]) + '"') $start $WaitSec
}

$macWakePort = 47999   # mac/wake-listener.plist

# Windows often can't resolve m6.local, so fall back to the HostName in ~/.ssh/config.
function Get-MacAddress {
    try { return ([Net.Dns]::GetHostAddresses('m6.local') | Where-Object AddressFamily -eq 'InterNetwork' | Select-Object -First 1).IPAddressToString } catch {}
    $cfg = Join-Path $env:USERPROFILE '.ssh\config'
    if (Test-Path $cfg) {
        $inHost = $false
        foreach ($line in Get-Content $cfg) {
            if ($line -match '^\s*Host\s+(.+)$') { $inHost = ($Matches[1] -split '\s+') -contains $macHost }
            elseif ($inHost -and $line -match '^\s*HostName\s+(\S+)') { return $Matches[1] }
        }
    }
    'm6.local'
}

# Pokes the Mac's wake listener (mac/wake-listener.plist): connecting is all it takes.
function Send-MacWakeConnection([int]$TimeoutMs = 3000) {
    $c = New-Object Net.Sockets.TcpClient
    try { $c.ConnectAsync((Get-MacAddress), $macWakePort).Wait($TimeoutMs) } catch { $false } finally { $c.Close() }
}

# Wakes a sleeping Mac and waits for its Deskflow client to reconnect. Returns how it
# woke ('listener' or 'ssh'), or $null. A plain network packet only "dark wakes" the
# Mac (screen off, Deskflow stays disconnected); caffeinate -u, run either by the wake
# listener or over ssh, declares user activity, which fully wakes it.
function Resume-Mac([int]$WaitSec = 15, [ValidateSet('Auto', 'Listener', 'Ssh')][string]$Method = 'Auto') {
    if ($Method -in 'Auto', 'Listener') {
        $start = Get-DeskflowLogLength
        # The first connection may only wake the Mac; retry so one lands once it's up.
        $deadline = (Get-Date).AddSeconds($WaitSec)
        do {
            [void](Send-MacWakeConnection)
            if (Wait-DeskflowLog 'accepted client connection' $start 2) { Start-Sleep -Milliseconds 500; return 'listener' }
        } while ((Get-Date) -lt $deadline)
        if ($Method -eq 'Listener') { return $null }
    }
    $start = Get-DeskflowLogLength
    & ssh.exe -o BatchMode=yes -o ConnectTimeout=8 $macHost 'caffeinate -u -t 2' 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { return $null }
    if (Wait-DeskflowLog 'accepted client connection' $start $WaitSec) { Start-Sleep -Milliseconds 500; return 'ssh' }
    $null
}

Export-ModuleMember -Function Switch-DeskflowScreen, Resume-Mac
