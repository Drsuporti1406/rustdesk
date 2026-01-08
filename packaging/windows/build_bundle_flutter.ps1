param(
  [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\\..')).Path,

  # Optional explicit WiX bin folder (where candle.exe/light.exe live).
  [string]$WixBinPath = '',
  [string]$MsiPath = '',
  [string]$BundleName = 'DrSuporti Remote Tecnico',
  [string]$OutputBaseName = 'DrSuportiRemoteTecnico'
)

$ErrorActionPreference = 'Stop'

$outDir = Join-Path $PSScriptRoot 'output'
if (-not $MsiPath) {
  $MsiPath = Join-Path $outDir ("{0}.msi" -f $OutputBaseName)
}
$vcRedistPath = Join-Path $PSScriptRoot 'third_party\\vc_redist.x64.exe'
$licensePath = Join-Path $PSScriptRoot 'license.rtf'
$bundleIconPath = Join-Path $PSScriptRoot 'package_flutter\\icon.ico'

if (!(Test-Path $MsiPath)) {
  throw "MSI not found at: $MsiPath. Build it first with build_msi_flutter.ps1"
}
if (!(Test-Path $vcRedistPath)) {
  throw "VC++ Redistributable not found at: $vcRedistPath. Download vc_redist.x64.exe and place it there."
}
if (!(Test-Path $licensePath)) {
  throw "license.rtf not found at: $licensePath. Provide a license file for the bundle UI."
}
if (!(Test-Path $bundleIconPath)) {
  throw "bundle icon not found at: $bundleIconPath. Build MSI first to generate package_flutter\\icon.ico"
}

New-Item -ItemType Directory -Force -Path $outDir | Out-Null

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
  Write-Host "Using Bundle Version: $productVersion"

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

  & candle.exe Bundle_flutter.wxs "-dProductVersion=$productVersion" "-dVcRedistPath=$vcRedistPath" "-dMsiPath=$MsiPath" "-dBundleIconPath=$bundleIconPath" "-dBundleName=$BundleName" -out ".\\" -ext WixBalExtension -ext WixUtilExtension | Tee-Object -FilePath candle_output_bundle.txt | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "candle.exe failed with exit code $LASTEXITCODE. See: $(Join-Path $PSScriptRoot 'candle_output_bundle.txt')" }

  $bundleTmp = (Join-Path $outDir ("{0}.bundle.tmp.exe" -f $OutputBaseName))
  $bundleFinal = (Join-Path $outDir ("{0}-setup.exe" -f $OutputBaseName))
  Remove-Item -Force -ErrorAction SilentlyContinue $bundleTmp

  & light.exe Bundle_flutter.wixobj -out $bundleTmp -ext WixBalExtension -ext WixUtilExtension | Tee-Object -FilePath light_output_bundle.txt | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "light.exe failed with exit code $LASTEXITCODE. See: $(Join-Path $PSScriptRoot 'light_output_bundle.txt')" }

  if (Test-Path $bundleFinal) { Remove-Item -Force $bundleFinal }
  Move-Item -Force $bundleTmp $bundleFinal
} finally {
  Pop-Location
}

Write-Host ("Bundle generated: {0}" -f (Join-Path $outDir ("{0}-setup.exe" -f $OutputBaseName)))
