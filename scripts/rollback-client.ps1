# dsh-zen-remote - Windows desktop client rollback
#
# Usage (quit the DSH desktop app first):
#   powershell -ExecutionPolicy Bypass -File .\rollback-client.ps1
#
# Finds the newest dsh-zen-remote.bak-<timestamp> directory and swaps it back.
#
# NOTE: ASCII-only on purpose (Windows PowerShell 5.1 ANSI code page issue).

$ErrorActionPreference = 'Stop'

$profilesRoot = Join-Path $env:USERPROFILE '.dsh\profiles'
if (-not (Test-Path -LiteralPath $profilesRoot)) { throw "Not found: $profilesRoot" }

$hits = @()
Get-ChildItem -LiteralPath $profilesRoot -Directory | ForEach-Object {
  $nodeModules = Join-Path $_.FullName 'node_modules'
  if (Test-Path -LiteralPath $nodeModules) {
    Get-ChildItem -LiteralPath $nodeModules -Directory -Filter 'dsh-zen-remote.bak-*' | ForEach-Object {
      $hits += [pscustomobject]@{
        Profile = $_.Parent.Parent.FullName
        Backup  = $_.FullName
        Time    = $_.LastWriteTime
      }
    }
  }
}
if ($hits.Count -eq 0) { throw "No dsh-zen-remote.bak-* backup found" }

$latest = $hits | Sort-Object Time -Descending | Select-Object -First 1
$dst = Join-Path $latest.Profile 'node_modules\dsh-zen-remote'

Write-Host "profile: $($latest.Profile)"
Write-Host "restore: $($latest.Backup)"

$running = Get-Process | Where-Object { $_.ProcessName -match 'deepseek|dsh' } | Select-Object -First 1
if ($running) { Write-Warning "DSH may still be running ($($running.ProcessName)); restart it after rollback." }

if (Test-Path -LiteralPath $dst) {
  Rename-Item -LiteralPath $dst -NewName ("dsh-zen-remote.rolledback-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
Rename-Item -LiteralPath $latest.Backup -NewName 'dsh-zen-remote'
Write-Host "Rolled back. Restart the DSH desktop app." -ForegroundColor Green
