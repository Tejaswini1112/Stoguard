# Run Stoguard on Windows (PowerShell)
# Usage: from the stoguard/ folder — .\scripts\run.ps1
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
  Write-Host "Go is not installed. Install from https://go.dev/dl/ or run a prebuilt .exe from website\downloads\"
  exit 1
}

Write-Host "Starting Stoguard on http://127.0.0.1:8787 ..."
go run .
