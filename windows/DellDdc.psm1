# DDC/CI helpers for talking to a monitor via Windows dxva2.dll (no external tools).
$src = @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class Ddc {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct PHYSICAL_MONITOR { public IntPtr h; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string desc; }
    public delegate bool EnumProc(IntPtr hMon, IntPtr hdc, IntPtr rect, IntPtr data);
    [DllImport("user32.dll")] public static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, EnumProc cb, IntPtr data);
    [DllImport("dxva2.dll")] public static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr hMon, out uint n);
    [DllImport("dxva2.dll")] public static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr hMon, uint n, [Out] PHYSICAL_MONITOR[] arr);
    [DllImport("dxva2.dll")] public static extern bool DestroyPhysicalMonitor(IntPtr h);
    [DllImport("dxva2.dll")] public static extern bool GetVCPFeatureAndVCPFeatureReply(IntPtr h, byte code, IntPtr type, out uint cur, out uint max);
    [DllImport("dxva2.dll")] public static extern bool SetVCPFeature(IntPtr h, byte code, uint val);
    [DllImport("dxva2.dll")] public static extern bool GetCapabilitiesStringLength(IntPtr h, out uint len);
    [DllImport("dxva2.dll", CharSet = CharSet.Ansi)] public static extern bool CapabilitiesRequestAndCapabilitiesReply(IntPtr h, StringBuilder s, uint len);

    public static PHYSICAL_MONITOR[] All() {
        var list = new System.Collections.Generic.List<PHYSICAL_MONITOR>();
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (hMon, hdc, r, d) => {
            uint n; if (GetNumberOfPhysicalMonitorsFromHMONITOR(hMon, out n) && n > 0) {
                var arr = new PHYSICAL_MONITOR[n];
                if (GetPhysicalMonitorsFromHMONITOR(hMon, n, arr)) list.AddRange(arr);
            }
            return true;
        }, IntPtr.Zero);
        return list.ToArray();
    }
    public static string Caps(IntPtr h) {
        uint len; if (!GetCapabilitiesStringLength(h, out len)) return null;
        var sb = new StringBuilder((int)len); return CapabilitiesRequestAndCapabilitiesReply(h, sb, len) ? sb.ToString() : null;
    }
}
'@
if (-not ('Ddc' -as [type])) { Add-Type -TypeDefinition $src }

# Returns the first physical monitor whose description matches (default: any).
function Get-DdcMonitor([string]$Match = '') {
    $mons = [Ddc]::All()
    $m = $mons | Where-Object { $_.desc -like "*$Match*" } | Select-Object -First 1
    if (-not $m) { throw "No DDC/CI monitor found matching '$Match'. Found: $($mons.desc -join ', ')" }
    $m
}

# Changing PBP/input makes Windows re-enumerate the display for a few seconds,
# during which no monitor (or a stale handle) is found. Retry until it settles.
function Invoke-WithRetry([scriptblock]$Action, [int]$TimeoutSec = 15) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ($true) {
        try { return & $Action }
        catch { if ((Get-Date) -gt $deadline) { throw }; Start-Sleep -Milliseconds 500 }
    }
}

function Get-Vcp([byte]$Code, [string]$Match = '', [int]$TimeoutSec = 15) {
    Invoke-WithRetry -TimeoutSec $TimeoutSec {
        $m = Get-DdcMonitor $Match
        $cur = 0; $max = 0
        $ok = [Ddc]::GetVCPFeatureAndVCPFeatureReply($m.h, $Code, [IntPtr]::Zero, [ref]$cur, [ref]$max)
        if (-not $ok) { throw ('Reading VCP 0x{0:X2} failed' -f $Code) }
        # Dell reports e.g. 0x0F0F for input 0x0F; the low byte is the value.
        [pscustomobject]@{ Code = ('0x{0:X2}' -f $Code); Value = ($cur -band 0xFF); Raw = $cur; Max = $max }
    }
}

function Set-Vcp([byte]$Code, [uint32]$Value, [string]$Match = '', [int]$TimeoutSec = 15) {
    Invoke-WithRetry -TimeoutSec $TimeoutSec {
        $m = Get-DdcMonitor $Match
        if (-not [Ddc]::SetVCPFeature($m.h, $Code, $Value)) { throw ('Setting VCP 0x{0:X2}={1} failed' -f $Code, $Value) }
    }
}

function Get-DdcCapabilities([string]$Match = '') { [Ddc]::Caps((Get-DdcMonitor $Match).h) }

Export-ModuleMember -Function Get-DdcMonitor, Get-Vcp, Set-Vcp, Get-DdcCapabilities
