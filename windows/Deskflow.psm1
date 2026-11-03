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

# Wakes a sleeping Mac over ssh and waits for its Deskflow client to reconnect.
# A plain network packet only "dark wakes" the Mac (screen off, Deskflow stays
# disconnected); caffeinate -u declares user activity, which fully wakes it.
function Resume-Mac([int]$WaitSec = 15) {
    $start = Get-DeskflowLogLength
    & ssh.exe -o BatchMode=yes -o ConnectTimeout=8 $macHost 'caffeinate -u -t 2' 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { return $false }
    $connected = Wait-DeskflowLog 'accepted client connection' $start $WaitSec
    if ($connected) { Start-Sleep -Milliseconds 500 }   # let the handshake finish
    $connected
}

Export-ModuleMember -Function Switch-DeskflowScreen, Resume-Mac
