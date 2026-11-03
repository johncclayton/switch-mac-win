# One-time setup on Windows. Safe to re-run.
#  - points Deskflow at deskflow/deskflow-server.conf (backs up Deskflow.conf first)
#  - creates "Go Mac!", "Go Windows!", "Go Split!" desktop shortcuts
#  - starts watch-monitor.ps1 now and at every logon
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$repo = Split-Path $here

# --- Deskflow -----------------------------------------------------------------
$serverConf = 'C:\ProgramData\Deskflow\switch-mac-win.conf'
Copy-Item (Join-Path $repo 'deskflow\deskflow-server.conf') $serverConf -Force

$guiConf = Join-Path $env:APPDATA 'Deskflow\Deskflow.conf'
$text = Get-Content $guiConf -Raw
$new = $text -replace '(?m)^externalConfig=.*$', 'externalConfig=true' `
             -replace '(?m)^externalConfigFile=.*$', ('externalConfigFile=' + ($serverConf -replace '\\', '/'))
if ($new -ne $text) {
    Copy-Item $guiConf "$guiConf.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Set-Content $guiConf $new -NoNewline   # the Deskflow daemon notices and restarts the server
    Write-Host "Deskflow now uses $serverConf"
}

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
