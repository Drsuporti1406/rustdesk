<#
.SYNOPSIS
  Remove RustDesk completely from Windows (files, service, registry, shortcuts).

.DESCRIPTION
  Best-effort cleanup for typical RustDesk installs (MSI/EXE portable/service).
  Supports -WhatIf via ShouldProcess; use -Force to skip confirmation.

.PARAMETER Force
  Skip interactive confirmations.

.PARAMETER IncludeLogs
  Also remove RustDesk log folders (if present).

.PARAMETER IncludeUserProfiles
  Also remove per-user RustDesk folders for ALL local user profiles (requires admin).
  If not set, only removes for the current user.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\windows\purge_rustdesk.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\windows\purge_rustdesk.ps1 -Force -IncludeLogs -IncludeUserProfiles
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
  [switch]$Force,
  [switch]$IncludeLogs,
  [switch]$IncludeUserProfiles,
  [switch]$FailIfLeftovers = $true
)

$ErrorActionPreference = 'Stop'

function Test-IsAdmin {
  $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Section([string]$Title) {
  Write-Host ""
  Write-Host "== $Title ==" -ForegroundColor Cyan
}

function Stop-ProcessByName([string[]]$Names) {
  foreach ($name in $Names) {
    Get-Process -Name $name -ErrorAction SilentlyContinue | ForEach-Object {
      if ($PSCmdlet.ShouldProcess("process $($_.ProcessName) (PID $($_.Id))", "Stop")) {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
      }
    }
  }
}

function Remove-PathSafe([string]$Path) {
  if (-not $Path) { return }
  if (-not (Test-Path -LiteralPath $Path)) { return }
  if ($PSCmdlet.ShouldProcess($Path, "Remove")) {
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Remove-PathWithRetry([string]$Path, [int]$Retries = 4, [int]$DelayMs = 750) {
  if (-not $Path) { return }
  for ($i = 0; $i -le $Retries; $i++) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Remove-PathSafe $Path
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if ($i -lt $Retries) {
      Start-Sleep -Milliseconds $DelayMs
    }
  }
}

function Remove-RegistryKeySafe([string]$KeyPath) {
  if (-not $KeyPath) { return }
  if (-not (Test-Path -LiteralPath $KeyPath)) { return }
  if ($PSCmdlet.ShouldProcess($KeyPath, "Remove registry key")) {
    Remove-Item -LiteralPath $KeyPath -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Remove-RegistryValuesContaining([string]$KeyPath, [string[]]$Needles) {
  if (-not (Test-Path -LiteralPath $KeyPath)) { return }
  $props = Get-ItemProperty -LiteralPath $KeyPath -ErrorAction SilentlyContinue
  if (-not $props) { return }
  foreach ($prop in ($props.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' })) {
    $value = [string]$prop.Value
    if ([string]::IsNullOrWhiteSpace($value)) { continue }
    $match = $false
    foreach ($n in $Needles) {
      if ($value -like "*$n*") { $match = $true; break }
    }
    if ($match) {
      $target = "$KeyPath -> $($prop.Name)"
      if ($PSCmdlet.ShouldProcess($target, "Remove registry value")) {
        Remove-ItemProperty -LiteralPath $KeyPath -Name $prop.Name -Force -ErrorAction SilentlyContinue
      }
    }
  }
}

function Remove-AnyUninstallEntries {
  $roots = @(
    "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall",
    "HKLM:\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall",
    "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall"
  )
  foreach ($root in $roots) {
    if (-not (Test-Path $root)) { continue }
    Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | ForEach-Object {
      $k = $_.PSPath
      $p = Get-ItemProperty -LiteralPath $k -ErrorAction SilentlyContinue
      $name = [string]$p.DisplayName
      if ($name -and $name -like "*RustDesk*") {
        # Try to run uninstall first (best-effort).
        $uninstall = [string]$p.UninstallString
        if ($uninstall) {
          if ($PSCmdlet.ShouldProcess($name, "Attempt uninstall: $uninstall")) {
            try {
              Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $uninstall -Wait -WindowStyle Hidden
            } catch {
              Write-Warning "Uninstall command failed for '$name': $($_.Exception.Message)"
            }
          }
        }
        # Remove leftover uninstall entry.
        Remove-RegistryKeySafe $k
      }
    }
  }
}

function Remove-ServiceByName([string]$Name) {
  $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
  if (-not $svc) { return }
  if ($svc.Status -ne 'Stopped') {
    if ($PSCmdlet.ShouldProcess("service $Name", "Stop")) {
      try { Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue } catch {}
    }
  }
  if ($PSCmdlet.ShouldProcess("service $Name", "Delete")) {
    try { sc.exe delete $Name | Out-Null } catch {}
  }
}

function Remove-FirewallRulesLike([string]$Pattern) {
  $cmd = Get-Command netsh.exe -ErrorAction SilentlyContinue
  if (-not $cmd) { return }
  # Intentionally unused: kept as placeholder for environments without NetSecurity module.
  # Do NOT add broad netsh deletions here.
}

function Remove-FirewallRulesRustDesk {
  # Safer: enumerate with Get-NetFirewallRule when available.
  $getRule = Get-Command Get-NetFirewallRule -ErrorAction SilentlyContinue
  if ($getRule) {
    $rules = Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object {
      $_.DisplayName -like "*RustDesk*" -or $_.Group -like "*RustDesk*"
    }
    foreach ($r in $rules) {
      if ($PSCmdlet.ShouldProcess("Firewall rule '$($r.DisplayName)'", "Remove")) {
        try { Remove-NetFirewallRule -Name $r.Name -ErrorAction SilentlyContinue } catch {}
      }
    }
  }
}

function Get-UserProfileDirs {
  $dirs = @()
  if ($IncludeUserProfiles) {
    $roots = @(
      "C:\\Users"
    )
    foreach ($root in $roots) {
      if (-not (Test-Path -LiteralPath $root)) { continue }
      $dirs += Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin @('Default', 'Default User', 'All Users', 'Public') } |
        Select-Object -ExpandProperty FullName
    }
  } else {
    if ($env:USERPROFILE) { $dirs += $env:USERPROFILE }
  }
  return ($dirs | Sort-Object -Unique)
}

function Get-RustDeskLeftovers {
  $leftovers = New-Object System.Collections.Generic.List[string]

  # Processes
  $procs = Get-Process -Name "rustdesk" -ErrorAction SilentlyContinue
  foreach ($p in $procs) {
    $path = $null
    try { $path = $p.Path } catch {}
    if ($path) {
      $leftovers.Add("Process rustdesk.exe still running (PID $($p.Id)) at '$path'")
    } else {
      $leftovers.Add("Process rustdesk.exe still running (PID $($p.Id))")
    }
  }

  # Services
  foreach ($svcName in @("rustdesk", "RustDesk")) {
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($svc) {
      $leftovers.Add("Service '$svcName' still present (Status: $($svc.Status))")
    }
  }

  # Files/folders
  foreach ($p in @(
    "C:\\Program Files\\RustDesk",
    "C:\\Program Files (x86)\\RustDesk",
    "C:\\ProgramData\\RustDesk"
  )) {
    if (Test-Path -LiteralPath $p) {
      $leftovers.Add("Folder still present: $p")
    }
  }
  foreach ($p in @(
    "C:\\Program Files\\RustDesk\\rustdesk.exe",
    "C:\\Program Files (x86)\\RustDesk\\rustdesk.exe"
  )) {
    if (Test-Path -LiteralPath $p) {
      $leftovers.Add("Executable still present: $p")
    }
  }

  # Registry keys (common)
  foreach ($k in @(
    "HKLM:\\SOFTWARE\\RustDesk",
    "HKLM:\\SOFTWARE\\WOW6432Node\\RustDesk",
    "HKCU:\\SOFTWARE\\RustDesk"
  )) {
    if (Test-Path -LiteralPath $k) {
      $leftovers.Add("Registry key still present: $k")
    }
  }

  # Uninstall entries mentioning RustDesk
  $uninstallRoots = @(
    "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall",
    "HKLM:\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall",
    "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall"
  )
  foreach ($root in $uninstallRoots) {
    if (-not (Test-Path $root)) { continue }
    Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | ForEach-Object {
      $p = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
      $name = [string]$p.DisplayName
      if ($name -and $name -like "*RustDesk*") {
        $leftovers.Add("Uninstall entry still present: $name ($($_.Name))")
      }
    }
  }

  return $leftovers
}

Write-Section "Pre-flight"
if (-not (Test-IsAdmin)) {
  throw "Run this script as Administrator (required to remove service and ProgramData)."
}

if (-not $Force) {
  Write-Host "This will remove RustDesk program files, service, and configuration from this PC." -ForegroundColor Yellow
  $resp = Read-Host "Type YES to continue"
  if ($resp -ne "YES") {
    Write-Host "Canceled."
    exit 1
  }
}

Write-Section "Stop RustDesk processes"
Stop-ProcessByName @("rustdesk", "RustDesk", "rustdesk_service", "RustDeskService")

Write-Section "Attempt uninstall + remove uninstall entries"
Remove-AnyUninstallEntries

# Uninstallers may spawn/keep processes briefly; stop once more.
Stop-ProcessByName @("rustdesk", "RustDesk", "rustdesk_service", "RustDeskService")

Write-Section "Remove services"
Remove-ServiceByName "rustdesk"
Remove-ServiceByName "RustDesk"

Write-Section "Remove scheduled tasks (best-effort)"
$schtasks = Get-Command schtasks.exe -ErrorAction SilentlyContinue
if ($schtasks) {
  $tasks = & schtasks.exe /Query /FO LIST /V 2>$null | Select-String -Pattern "^TaskName:\s+" -ErrorAction SilentlyContinue
  foreach ($t in $tasks) {
    $name = ($t.ToString() -replace "^TaskName:\\s+", "").Trim()
    if ($name -and $name -like "*RustDesk*") {
      if ($PSCmdlet.ShouldProcess("Scheduled task $name", "Delete")) {
        try { & schtasks.exe /Delete /TN $name /F | Out-Null } catch {}
      }
    }
  }
}

Write-Section "Remove firewall rules"
Remove-FirewallRulesRustDesk

Write-Section "Remove files"
# Install locations
Remove-PathWithRetry "C:\\Program Files\\RustDesk"
Remove-PathWithRetry "C:\\Program Files (x86)\\RustDesk"

# Common data
Remove-PathWithRetry "C:\\ProgramData\\RustDesk"
Remove-PathWithRetry "C:\\ProgramData\\RustDesk\\shared_memory_portable_service"

# Per-user data
$profiles = Get-UserProfileDirs
foreach ($profile in $profiles) {
  Remove-PathSafe (Join-Path $profile "AppData\\Roaming\\RustDesk")
  Remove-PathSafe (Join-Path $profile "AppData\\Local\\RustDesk")
  if ($IncludeLogs) {
    Remove-PathSafe (Join-Path $profile "AppData\\Roaming\\RustDesk\\logs")
    Remove-PathSafe (Join-Path $profile "AppData\\Local\\RustDesk\\logs")
  }
}

# Shortcuts
Remove-PathSafe "$env:ProgramData\\Microsoft\\Windows\\Start Menu\\Programs\\RustDesk.lnk"
Remove-PathSafe "$env:APPDATA\\Microsoft\\Windows\\Start Menu\\Programs\\RustDesk.lnk"
Remove-PathSafe "$env:PUBLIC\\Desktop\\RustDesk.lnk"
Remove-PathSafe "$env:USERPROFILE\\Desktop\\RustDesk.lnk"

Write-Section "Remove registry leftovers"
# App-specific keys (best effort)
Remove-RegistryKeySafe "HKLM:\\SOFTWARE\\RustDesk"
Remove-RegistryKeySafe "HKCU:\\SOFTWARE\\RustDesk"
Remove-RegistryKeySafe "HKLM:\\SOFTWARE\\WOW6432Node\\RustDesk"

# Some installs store settings under vendor keys; remove values containing RustDesk path/name.
$needles = @("RustDesk", "rustdesk.exe", "\\RustDesk\\")
Remove-RegistryValuesContaining "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run" $needles
Remove-RegistryValuesContaining "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run" $needles
Remove-RegistryValuesContaining "HKLM:\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Run" $needles

Write-Section "Done"
Write-Host "RustDesk purge completed (best-effort)." -ForegroundColor Green

if ($FailIfLeftovers -and -not $WhatIfPreference) {
  $left = Get-RustDeskLeftovers
  if ($left.Count -gt 0) {
    Write-Host ""
    Write-Host "Leftovers detected (purge is NOT complete):" -ForegroundColor Yellow
    $left | ForEach-Object { Write-Host " - $_" }
    throw "RustDesk purge incomplete: remove leftovers (or reboot) and re-run. Use -FailIfLeftovers:$false to skip failing."
  }
}

Write-Host "No leftovers detected by this script." -ForegroundColor Green
Write-Host "Recommendation: reboot Windows to ensure everything is fully unloaded."
