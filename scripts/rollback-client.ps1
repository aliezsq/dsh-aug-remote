# dsh-aug-remote - Windows desktop client rollback
#
# Usage (quit the DSH desktop app first):
#   powershell -ExecutionPolicy Bypass -File .\rollback-client.ps1
#
# Restores the newest node_modules backup made by install-client.ps1 and the
# newest profile package.json backup next to it. Works for both the current
# dsh-aug-remote folder and a legacy dsh-aug-remote one.

param(
  [string]$Profile = ""
)

$ErrorActionPreference = 'Stop'

$profilesRoot = Join-Path $env:USERPROFILE '.dsh\profiles'
if ($Profile -ne "") {
  $profilesRoot = $Profile
}
if (-not (Test-Path -LiteralPath $profilesRoot)) { throw "Not found: $profilesRoot" }

$hits = @(
  Get-ChildItem -LiteralPath $profilesRoot -Directory |
    Where-Object {
      (Test-Path -LiteralPath (Join-Path $_.FullName 'node_modules\dsh-aug-remote')) -or
      (Test-Path -LiteralPath (Join-Path $_.FullName 'node_modules\dsh-aug-remote')) -or
      @(Get-ChildItem -LiteralPath (Join-Path $_.FullName 'node_modules') -Filter 'dsh-aug-remote.bak-*' -Directory -ErrorAction SilentlyContinue).Count -gt 0
    }
)
if ($hits.Count -eq 0) { throw "No profile with dsh-aug-remote found under $profilesRoot" }
$profileDir = $hits[0].FullName
$nm = Join-Path $profileDir 'node_modules'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

$running = Get-Process | Where-Object { $_.ProcessName -match 'deepseek|dsh' } | Select-Object -First 1
if ($running) { Write-Warning "DSH may still be running ($($running.ProcessName)); restart it after rollback." }

# Newest backup folder, preferring the current name.
$bak = Get-ChildItem -LiteralPath $nm -Filter 'dsh-aug-remote.bak-*' -Directory -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($null -eq $bak) {
  $bak = Get-ChildItem -LiteralPath $nm -Filter 'dsh-aug-remote.bak-*' -Directory -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
}
if ($null -eq $bak) { throw "No dsh-aug-remote.bak-* / dsh-aug-remote.bak-* folder to restore" }

$current = Join-Path $nm 'dsh-aug-remote'
if (Test-Path -LiteralPath $current) {
  Rename-Item -LiteralPath $current -NewName "dsh-aug-remote.bak-restore-$stamp"
}
Rename-Item -LiteralPath $bak.FullName -NewName 'dsh-aug-remote'
Write-Host ("restored: " + $bak.FullName + " -> dsh-aug-remote")

# Restore the newest profile package.json backup (the dependency migration).
$pkgJson = Join-Path $profileDir 'package.json'
$pkgBak = Get-ChildItem -LiteralPath $profileDir -Filter 'package.json.bak-*' -File -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($null -ne $pkgBak) {
  Copy-Item -LiteralPath $pkgJson -Destination "$pkgJson.bak-before-rollback-$stamp" -Force
  Copy-Item -LiteralPath $pkgBak.FullName -Destination $pkgJson -Force
  Write-Host ("restored profile package.json from " + $pkgBak.Name)
}

$installed = (Get-Content -LiteralPath (Join-Path $current 'package.json') -Raw | ConvertFrom-Json).version
Write-Host "dsh-aug-remote $installed restored. Restart the DSH desktop app." -ForegroundColor Green
