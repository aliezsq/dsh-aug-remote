# dsh-aug-remote - Windows desktop client installer (pinned local build)
#
# Usage (quit the DSH desktop app first):
#   powershell -ExecutionPolicy Bypass -File .\install-client.ps1 -Package .\dsh-aug-remote-2.4.0.tgz
#
# What it does:
#   1. finds the DSH profile that has dsh-aug-remote OR the old dsh-aug-remote;
#   2. backs up both node_modules folders, installs the tarball as
#      node_modules\dsh-aug-remote;
#   3. migrates the profile: drops the old "dsh-aug-remote" dependency, pins
#      "dsh-aug-remote": "file:vendor/<tarball>", and renames the entry in
#      dsh.profile.bundles (so a later pnpm install cannot restore the npm
#      build, and the old package cannot load a second plugin row);
#   4. verifies the installed version.
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
$packageName = Split-Path -Leaf $Package

$profilesRoot = Join-Path $env:USERPROFILE '.dsh\profiles'
if (-not (Test-Path -LiteralPath $profilesRoot)) { throw "Not found: $profilesRoot" }

$hits = @(
  Get-ChildItem -LiteralPath $profilesRoot -Directory |
    Where-Object {
      (Test-Path -LiteralPath (Join-Path $_.FullName 'node_modules\dsh-aug-remote\package.json')) -or
      (Test-Path -LiteralPath (Join-Path $_.FullName 'node_modules\dsh-aug-remote\package.json'))
    }
)
if ($hits.Count -eq 0) { throw "No profile under $profilesRoot has dsh-aug-remote or dsh-aug-remote installed" }
if ($hits.Count -gt 1) {
  $hits | ForEach-Object { Write-Host ("match: " + $_.FullName) }
  throw "More than one profile matches; handle it manually."
}

$profileDir = $hits[0].FullName
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$dst = Join-Path $profileDir 'node_modules\dsh-aug-remote'
$old = Join-Path $profileDir 'node_modules\dsh-aug-remote'
$tmpRoot = Join-Path $env:TEMP ("zr-" + [guid]::NewGuid().ToString('N'))

Write-Host "profile : $profileDir"
$running = Get-Process | Where-Object { $_.ProcessName -match 'deepseek|dsh' } | Select-Object -First 1
if ($running) { Write-Warning "DSH may still be running ($($running.ProcessName)); restart it after install." }

# Back up both the new slot and the legacy folder, then extract the tarball.
if (Test-Path -LiteralPath $dst) {
  $bakNew = "$dst.bak-$stamp"
  Rename-Item -LiteralPath $dst -NewName (Split-Path -Leaf $bakNew)
  Write-Host "backup  : $bakNew"
}
New-Item -ItemType Directory -Path $tmpRoot | Out-Null
try {
  tar -xzf $Package -C $tmpRoot
  if (-not (Test-Path -LiteralPath (Join-Path $tmpRoot 'package\package.json'))) {
    throw "Bad package layout (missing package/package.json)"
  }
  Move-Item -LiteralPath (Join-Path $tmpRoot 'package') -Destination $dst
} finally {
  Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
}
if (Test-Path -LiteralPath $old) {
  $bakOld = "$old.bak-$stamp"
  Rename-Item -LiteralPath $old -NewName (Split-Path -Leaf $bakOld)
  Write-Host "removed : legacy dsh-aug-remote -> $bakOld"
}

# --- migrate the profile: dependency + bundles + pinned tarball --------------
$vendor = Join-Path $profileDir 'vendor'
New-Item -ItemType Directory -Force -Path $vendor | Out-Null
Copy-Item -LiteralPath $Package -Destination (Join-Path $vendor $packageName) -Force

$pkgJson = Join-Path $profileDir 'package.json'
if (-not (Test-Path -LiteralPath $pkgJson)) { throw "Missing profile package.json: $pkgJson" }
Copy-Item -LiteralPath $pkgJson -Destination "$pkgJson.bak-$stamp" -Force

$json = Get-Content -LiteralPath $pkgJson -Raw | ConvertFrom-Json
if ($null -eq $json.PSObject.Properties['dependencies']) {
  $json | Add-Member -MemberType NoteProperty -Name dependencies -Value (New-Object psobject)
}
$dep = "file:vendor/$packageName"
if ($json.dependencies.PSObject.Properties['dsh-aug-remote']) {
  $json.dependencies.PSObject.Properties.Remove('dsh-aug-remote')
}
if ($json.dependencies.PSObject.Properties['dsh-aug-remote']) {
  $json.dependencies.'dsh-aug-remote' = $dep
} else {
  $json.dependencies | Add-Member -MemberType NoteProperty -Name 'dsh-aug-remote' -Value $dep
}
if ($json.PSObject.Properties['dsh']) {
  $prof = $json.dsh.PSObject.Properties['profile']
  if ($null -ne $prof -and $null -ne $prof.Value.PSObject.Properties['bundles']) {
    $bundles = @($prof.Value.bundles | ForEach-Object { if ($_ -eq 'dsh-aug-remote') { 'dsh-aug-remote' } else { $_ } })
    if (-not ($bundles -contains 'dsh-aug-remote')) { $bundles += 'dsh-aug-remote' }
    $json.dsh.profile.bundles = @($bundles | Select-Object -Unique)
  }
}
# UTF-8 WITHOUT BOM: DSH parses package.json with JSON.parse, which rejects a BOM.
[System.IO.File]::WriteAllText($pkgJson, ($json | ConvertTo-Json -Depth 20), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "pinned  : dependencies.dsh-aug-remote = $dep"
Write-Host "bundles : dsh-aug-remote -> dsh-aug-remote"

$installed = (Get-Content -LiteralPath (Join-Path $dst 'package.json') -Raw | ConvertFrom-Json).version
Write-Host ""
Write-Host "dsh-aug-remote $installed installed." -ForegroundColor Green
Write-Host "Start DSH desktop app. If it reports a pnpm lockfile error after an"
Write-Host "app update, delete the profile's pnpm-lock.yaml once and let it reinstall."
