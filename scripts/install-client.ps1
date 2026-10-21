# dsh-zen-remote 2.3.1 - Windows desktop client installer
#
# Usage (quit the DSH desktop app first):
#   powershell -ExecutionPolicy Bypass -File .\install-client.ps1 -Package .\dsh-zen-remote-2.3.1.tgz
#
# What it does: find the DSH profile that has dsh-zen-remote installed, rename
# that directory to dsh-zen-remote.bak-<timestamp>, then extract package/ from
# the tarball into place. On failure it restores the backup.
# Restart the DSH desktop app afterwards. Roll back with rollback-client.ps1.
#
# NOTE: this file is intentionally ASCII-only. Windows PowerShell 5.1 reads
# .ps1 files without a BOM using the system ANSI code page; non-ASCII text in
# the script gets mangled and breaks the parser.

param(
  [Parameter(Mandatory = $true)][string]$Package
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command tar -ErrorAction SilentlyContinue)) {
  throw "tar.exe not found. Windows 10 1803+ ships it; otherwise unpack the tgz manually (see INSTALL.md)."
}

if (-not (Test-Path -LiteralPath $Package)) { throw "Package not found: $Package" }
$Package = (Resolve-Path -LiteralPath $Package).Path

$profilesRoot = Join-Path $env:USERPROFILE '.dsh\profiles'
if (-not (Test-Path -LiteralPath $profilesRoot)) { throw "Not found: $profilesRoot" }

$hits = @(
  Get-ChildItem -LiteralPath $profilesRoot -Directory |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'node_modules\dsh-zen-remote\package.json') }
)
if ($hits.Count -eq 0) { throw "No profile under $profilesRoot has dsh-zen-remote installed" }
if ($hits.Count -gt 1) {
  $hits | ForEach-Object { Write-Host ("match: " + $_.FullName) }
  throw "More than one profile has dsh-zen-remote; handle it manually."
}

$profileDir = $hits[0].FullName
$dst = Join-Path $profileDir 'node_modules\dsh-zen-remote'
$bak = "$dst.bak-" + (Get-Date -Format 'yyyyMMdd-HHmmss')

Write-Host "profile : $profileDir"
Write-Host "backup  : $bak"

$running = Get-Process | Where-Object { $_.ProcessName -match 'deepseek|dsh' } | Select-Object -First 1
if ($running) { Write-Warning "DSH may still be running ($($running.ProcessName)); restart it after install." }

Rename-Item -LiteralPath $dst -NewName (Split-Path -Leaf $bak)
$tmp = Join-Path $env:TEMP ("zr-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
  tar -xzf $Package -C $tmp
  if (-not (Test-Path -LiteralPath (Join-Path $tmp 'package\package.json'))) {
    throw "Bad package layout (missing package/package.json)"
  }
  Move-Item -LiteralPath (Join-Path $tmp 'package') -Destination $dst
} catch {
  if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }
  if (Test-Path -LiteralPath $bak) { Rename-Item -LiteralPath $bak -NewName 'dsh-zen-remote' }
  throw
} finally {
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

$installed = (Get-Content -LiteralPath (Join-Path $dst 'package.json') -Raw | ConvertFrom-Json).version
Write-Host ""
Write-Host "dsh-zen-remote $installed installed." -ForegroundColor Green
Write-Host "Start DSH desktop app, open a session in the remote group, and look for the download button on artifact cards."
