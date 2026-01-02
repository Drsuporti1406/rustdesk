param(
  [ValidateSet('debug','release')]
  [string]$Configuration = 'release',

  # Optional explicit path to logo.png to be used in installed UI folder (ui/logo.png).
  [string]$UiLogoPath = '',

  # Optional explicit path to logo_preta.png to be used in installed UI folder (ui/logo_preta.png).
  [string]$UiLogoPretaPath = '',

  # Optional explicit path to an .ico file used by shortcuts/ARP (preferred over auto-generation).
  [string]$AppIconIcoPath = '',

  # Optional explicit path to sciter.dll.
  [string]$SciterDllPath = '',

  # Optional explicit WiX bin folder (where candle.exe/light.exe live).
  [string]$WixBinPath = '',

  # Skip `cargo build` and only package+build MSI (expects target/*/rustdesk.exe already built).
  [switch]$SkipBuild,

  [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\\..')).Path
)

$ErrorActionPreference = 'Stop'

$pkgDir = Join-Path $PSScriptRoot 'package'
$outDir = Join-Path $PSScriptRoot 'output'

New-Item -ItemType Directory -Force -Path $pkgDir | Out-Null
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$cargo = Get-Command cargo -ErrorAction SilentlyContinue
if (!$SkipBuild) {
  if (-not $cargo) { throw "cargo not found in PATH" }

  Push-Location $Root
  try {
    if ($Configuration -eq 'release') {
      & cargo build --release
    } else {
      & cargo build
    }
  } finally {
    Pop-Location
  }
}

$exeSrc = Join-Path $Root ("target\\{0}\\rustdesk.exe" -f $Configuration)
if (!(Test-Path $exeSrc)) {
  throw "rustdesk.exe not found at: $exeSrc"
}
Copy-Item -Force $exeSrc (Join-Path $pkgDir 'rustdesk.exe')

# Ensure installer can reference a stable icon file.
$pkgIconIco = Join-Path $pkgDir 'icon.ico'
$icoCandidates = @()
if ($AppIconIcoPath) { $icoCandidates += $AppIconIcoPath }
$icoCandidates += @(
  (Join-Path $Root 'res\\icon.ico')
)
$icoResolved = $icoCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if ($icoResolved) {
  Copy-Item -Force $icoResolved $pkgIconIco
} else {
  # Last resort: try to generate an .ico from src/logo.png into the package folder only.
  $logoForIco = Join-Path $Root 'src\\logo.png'
  if (Test-Path $logoForIco) {
    $py = Get-Command python -ErrorAction SilentlyContinue
    if ($py) {
      $env:RUSTDESK_ICON_SRC = $logoForIco
      $env:RUSTDESK_ICON_DST = $pkgIconIco
      try {
        & python -c "import os; from PIL import Image; src=os.environ.get('RUSTDESK_ICON_SRC'); dst=os.environ.get('RUSTDESK_ICON_DST'); img=Image.open(src).convert('RGBA'); img.save(dst, format='ICO', sizes=[(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)]); print('Generated:', dst)"
      } catch {
        Write-Warning "Failed to generate icon.ico from logo.png; provide -AppIconIcoPath or place res\\icon.ico"
      }
    } else {
      Write-Warning "python not found; provide -AppIconIcoPath or place res\\icon.ico"
    }
  }
}

# Sciter runtime is required for sciter UI builds.
$sciterCandidates = @()
if ($SciterDllPath) { $sciterCandidates += $SciterDllPath }
$sciterCandidates += @(
  (Join-Path $Root 'sciter.dll'),
  (Join-Path $PSScriptRoot 'sciter.dll'),
  (Join-Path $pkgDir 'sciter.dll')
)
$sciterResolved = $sciterCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $sciterResolved) {
  throw "sciter.dll not found. Provide -SciterDllPath, or place it at one of: $($sciterCandidates -join ', ')"
}
$sciterDst = (Join-Path $pkgDir 'sciter.dll')
if ((Resolve-Path $sciterResolved).Path -ne (Resolve-Path $sciterDst -ErrorAction SilentlyContinue).Path) {
  Copy-Item -Force $sciterResolved $sciterDst
}

# Copy Sciter UI files so non-inline builds can load them from [INSTALLFOLDER]\\ui\\*.*
$uiSrc = Join-Path $Root 'src\\ui'
$uiDst = Join-Path $pkgDir 'ui'
if (!(Test-Path $uiSrc)) {
  throw "UI folder not found at: $uiSrc"
}
New-Item -ItemType Directory -Force -Path $uiDst | Out-Null
Copy-Item -Force -Recurse (Join-Path $uiSrc '*') $uiDst

# Custom UI logos (optional overrides).
if (-not $UiLogoPath) { $UiLogoPath = (Join-Path $Root 'src\\logo.png') }
if (-not $UiLogoPretaPath) { $UiLogoPretaPath = (Join-Path $Root 'src\\logo_preta.png') }
if (Test-Path $UiLogoPath) {
  Copy-Item -Force $UiLogoPath (Join-Path $uiDst 'logo.png')
}
if (Test-Path $UiLogoPretaPath) {
  Copy-Item -Force $UiLogoPretaPath (Join-Path $uiDst 'logo_preta.png')
}

Push-Location $PSScriptRoot
try {
  # Generate a unique MSI ProductVersion for each build to ensure Windows Installer upgrades
  # overwrite files instead of keeping older binaries.
  $cargoToml = Join-Path $Root 'Cargo.toml'
  $baseVersion = "1.0.0"
  if (Test-Path $cargoToml) {
    $m = Select-String -LiteralPath $cargoToml -Pattern '^\s*version\s*=\s*\"([0-9]+)\.([0-9]+)\.([0-9]+)\"' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($m -and $m.Matches.Count -gt 0) {
      $baseVersion = "$($m.Matches[0].Groups[1].Value).$($m.Matches[0].Groups[2].Value).$($m.Matches[0].Groups[3].Value)"
    }
  }
  $parts = $baseVersion.Split('.')
  $major = [int]$parts[0]
  $minor = [int]$parts[1]
  $patch = [int]$parts[2]
  $epoch = Get-Date "2020-01-01T00:00:00Z"
  $minutes = [int]([Math]::Floor(((Get-Date).ToUniversalTime() - $epoch).TotalMinutes))
  $build = $minutes % 65535
  $productVersion = "$major.$minor.$patch.$build"
  Write-Host "Using MSI ProductVersion: $productVersion"

  $wixCandidates = @()
  if ($WixBinPath) { $wixCandidates += $WixBinPath }
  $wixCandidates += @(
    (Join-Path ${env:ProgramFiles(x86)} 'WiX Toolset v3.14\\bin'),
    (Join-Path ${env:ProgramFiles(x86)} 'WiX Toolset v3.11\\bin'),
    (Join-Path ${env:ProgramFiles} 'WiX Toolset v3.14\\bin'),
    (Join-Path ${env:ProgramFiles} 'WiX Toolset v3.11\\bin')
  )
  foreach ($dir in $wixCandidates) {
    if ($dir -and (Test-Path (Join-Path $dir 'candle.exe')) -and (Test-Path (Join-Path $dir 'light.exe'))) {
      $env:PATH = "$dir;$env:PATH"
      break
    }
  }

  $candle = Get-Command candle.exe -ErrorAction SilentlyContinue
  $light = Get-Command light.exe -ErrorAction SilentlyContinue
  if (-not $candle) { throw "candle.exe (WiX) not found in PATH" }
  if (-not $light) { throw "light.exe (WiX) not found in PATH" }
  # Force x64 MSI so ProgramFiles64Folder is honored on 64-bit Windows.
  & candle.exe -arch x64 Product.wxs "-dProductVersion=$productVersion" -out Product.wixobj | Tee-Object -FilePath candle_output.txt | Out-Null
  & light.exe Product.wixobj -out (Join-Path $outDir 'RustDesk.msi') | Tee-Object -FilePath light_output.txt | Out-Null
} finally {
  Pop-Location
}

Write-Host ("MSI generated: {0}" -f (Join-Path $outDir 'RustDesk.msi'))
