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

# With -WaitSec, waits for Deskflow to log the move and returns whether it happened
# (it doesn't when the Mac's Deskflow isn't connected).
function Switch-DeskflowScreen([ValidateSet('Mac', 'Windows')][string]$Screen, [int]$WaitSec = 0) {
    $start = try { (Get-Item $deskflowLog).Length } catch { 0 }
    $fkey = if ($Screen -eq 'Mac') { $VK_F10 } else { $VK_F12 }
    [DfKeys]::Chord([byte[]]@($VK_CONTROL, $VK_MENU, $VK_SHIFT, $fkey))
    if (-not $WaitSec) { return }
    $pattern = '(?:switch|jump) from "[^"]+" to "' + [regex]::Escape($screenName[$Screen]) + '"'
    $deadline = (Get-Date).AddSeconds($WaitSec)
    do {
        Start-Sleep -Milliseconds 200
        try {
            $fs = [IO.File]::Open($deskflowLog, 'Open', 'Read', 'ReadWrite,Delete')
            try {
                if ($fs.Length -lt $start) { $start = 0 }
                $fs.Position = $start
                if ((New-Object IO.StreamReader($fs)).ReadToEnd() -match $pattern) { return $true }
            } finally { $fs.Close() }
        } catch {}
    } while ((Get-Date) -lt $deadline)
    $false
}

Export-ModuleMember -Function Switch-DeskflowScreen
