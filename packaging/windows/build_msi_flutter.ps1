param(
  [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\\..')).Path,

  # Optional explicit WiX bin folder (where candle.exe/light.exe/heat.exe live).
  [string]$WixBinPath = ''
)

$ErrorActionPreference = 'Stop'

$outDir = Join-Path $PSScriptRoot 'output'
$pkgDir = Join-Path $PSScriptRoot 'package_flutter'
$releaseDir = Join-Path $Root 'flutter\\build\\windows\\x64\\runner\\Release'

if (!(Test-Path $releaseDir)) {
  throw "Flutter Release folder not found at: $releaseDir. Run: flutter build windows --release"
}

New-Item -ItemType Directory -Force -Path $outDir | Out-Null

if (Test-Path $pkgDir) {
  Remove-Item -Recurse -Force $pkgDir
}
New-Item -ItemType Directory -Force -Path $pkgDir | Out-Null

Copy-Item -Force -Recurse (Join-Path $releaseDir '*') $pkgDir

# Ensure installer has a stable icon for ARP + shortcuts.
$pkgIconIco = Join-Path $pkgDir 'icon.ico'
$icoCandidates = @(
  (Join-Path $Root 'flutter\\windows\\runner\\resources\\app_icon.ico'),
  (Join-Path $Root 'res\\icon.ico')
)
$icoResolved = $icoCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if ($icoResolved) {
  Copy-Item -Force $icoResolved $pkgIconIco
} else {
  Write-Warning "icon.ico not found; MSI will still build but ARP icon may be missing."
}

Push-Location $PSScriptRoot
try {
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

  $buildDate = ""
  $versionRs = Join-Path $Root 'src\\version.rs'
  if (Test-Path $versionRs) {
    $m = Select-String -LiteralPath $versionRs -Pattern 'BUILD_DATE: &str = \"([^\"]+)\"' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($m -and $m.Matches.Count -gt 0) {
      $buildDate = $m.Matches[0].Groups[1].Value
    }
  }
  if (-not $buildDate) {
    $buildDate = (Get-Date).ToString("yyyy-MM-dd HH:mm")
  }
  Write-Host "Using BuildDate: $buildDate"

  $wixCandidates = @()
  if ($WixBinPath) { $wixCandidates += $WixBinPath }
  $wixCandidates += @(
    (Join-Path ${env:ProgramFiles(x86)} 'WiX Toolset v3.14\\bin'),
    (Join-Path ${env:ProgramFiles(x86)} 'WiX Toolset v3.11\\bin'),
    (Join-Path ${env:ProgramFiles} 'WiX Toolset v3.14\\bin'),
    (Join-Path ${env:ProgramFiles} 'WiX Toolset v3.11\\bin')
  )
  foreach ($dir in $wixCandidates) {
    if ($dir -and (Test-Path (Join-Path $dir 'candle.exe')) -and (Test-Path (Join-Path $dir 'light.exe')) -and (Test-Path (Join-Path $dir 'heat.exe'))) {
      $env:PATH = "$dir;$env:PATH"
      break
    }
  }

  $candle = Get-Command candle.exe -ErrorAction SilentlyContinue
  $light = Get-Command light.exe -ErrorAction SilentlyContinue
  $heat = Get-Command heat.exe -ErrorAction SilentlyContinue
  if (-not $candle) { throw "candle.exe (WiX) not found in PATH" }
  if (-not $light) { throw "light.exe (WiX) not found in PATH" }
  if (-not $heat) { throw "heat.exe (WiX) not found in PATH" }

  $harvest = Join-Path $PSScriptRoot 'Harvest.wxs'
  if (Test-Path $harvest) { Remove-Item -Force $harvest }

  & heat.exe dir $pkgDir -cg AppFiles -dr INSTALLFOLDER -gg -srd -sfrag -var var.SourceDir -out $harvest | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "heat.exe failed with exit code $LASTEXITCODE" }

  # Remove rustdesk.exe from harvested component list to avoid duplicate component IDs.
  $harvestContent = Get-Content -LiteralPath $harvest -Raw
  $harvestContent = Get-Content -LiteralPath $harvest -Raw
  $pattern = '<Component[^>]*>\s*<File[^>]*rustdesk\.exe[^>]*/>\s*</Component>'
  $harvestContent = [System.Text.RegularExpressions.Regex]::Replace(
    $harvestContent,
    $pattern,
    '',
    [System.Text.RegularExpressions.RegexOptions]::Singleline
  )
  Set-Content -LiteralPath $harvest -Value $harvestContent
  $lines = Get-Content -LiteralPath $harvest
  $lines = $lines | Where-Object { $_ -notmatch 'ComponentRef Id=\"cmp71FD06D56A2F617FE91312838FA38B22\"' }
  Set-Content -LiteralPath $harvest -Value $lines
  if (Select-String -LiteralPath $harvest -Pattern 'rustdesk\.exe' -SimpleMatch) {
    throw "Failed to remove rustdesk.exe from Harvest.wxs. Clean the file or rerun."
  }

  & candle.exe -arch x64 Product_flutter.wxs Harvest.wxs "-dProductVersion=$productVersion" "-dBuildDate=$buildDate" "-dSourceDir=$pkgDir" -out ".\\" | Tee-Object -FilePath candle_output_flutter.txt | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "candle.exe failed with exit code $LASTEXITCODE. See: $(Join-Path $PSScriptRoot 'candle_output_flutter.txt')" }

  $msiFinal = (Join-Path $outDir 'DrSuportiRemote.msi')
  $msiTmp = (Join-Path $outDir 'DrSuportiRemote.tmp.msi')
  Remove-Item -Force -ErrorAction SilentlyContinue $msiTmp

  & light.exe Product_flutter.wixobj Harvest.wixobj -out $msiTmp | Tee-Object -FilePath light_output_flutter.txt | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "light.exe failed with exit code $LASTEXITCODE. See: $(Join-Path $PSScriptRoot 'light_output_flutter.txt')" }

  try {
    if (Test-Path $msiFinal) {
      Remove-Item -Force $msiFinal
    }
    Move-Item -Force $msiTmp $msiFinal
  } catch {
    $msiVersioned = (Join-Path $outDir ("DrSuportiRemote-{0}.msi" -f $productVersion))
    Move-Item -Force $msiTmp $msiVersioned
    throw "Failed to replace existing MSI at $msiFinal (it may be in use). A versioned MSI was written to: $msiVersioned"
  }
} finally {
  Pop-Location
}

Write-Host ("MSI generated: {0}" -f (Join-Path $outDir 'DrSuportiRemote.msi'))
