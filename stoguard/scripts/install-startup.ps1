# Install Stoguard to start with Windows (current user Startup folder).
# Run from an elevated or normal PowerShell after downloading the .exe:
#   .\scripts\install-startup.ps1 -ExePath "$env:USERPROFILE\Downloads\stoguard-windows-amd64.exe"
param(
  [Parameter(Mandatory = $true)]
  [string]$ExePath
)

$ErrorActionPreference = "Stop"
$ExePath = (Resolve-Path -LiteralPath $ExePath).Path
$startup = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startup "Stoguard.lnk"

$wscript = New-Object -ComObject WScript.Shell
$sc = $wscript.CreateShortcut($shortcutPath)
$sc.TargetPath = $ExePath
$sc.WorkingDirectory = Split-Path -Parent $ExePath
$sc.WindowStyle = 7  # minimized
$sc.Description = "Stoguard workstation mentor (local UI on 127.0.0.1:8787)"
$sc.Save()

Write-Host "Installed startup shortcut:"
Write-Host "  $shortcutPath"
Write-Host "Stoguard will launch at login. Open http://127.0.0.1:8787 in your browser."
Write-Host "To remove: delete the shortcut above."
