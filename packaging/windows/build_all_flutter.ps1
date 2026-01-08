param(
  [ValidateSet('full','lite')]
  [string]$Mode = 'full',
  [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\\..')).Path,
  [string]$FlutterBin = '',
  [string]$WixBinPath = ''
)

$ErrorActionPreference = 'Stop'

$productName = 'DrSuporti Remote Tecnico'
$productId = $productName
$installFolder = 'DrSuporti Remote Tecnico'
$outputBase = 'DrSuportiRemoteTecnico'
$dartDefine = ''

if ($Mode -eq 'lite') {
  $productName = 'DrSuporti Remote Cliente'
  $productId = $productName
  $installFolder = 'DrSuporti Remote Cliente'
  $outputBase = 'DrSuportiRemoteCliente'
  $dartDefine = '--dart-define=APP_LITE=true'
}

if (-not $FlutterBin) {
  $flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
  if ($flutterCmd) {
    $FlutterBin = $flutterCmd.Path
  } else {
    $candidates = @(
      'C:\\Users\\Antonio\\flutter\\bin\\flutter.bat',
      'C:\\Users\\Antonio\\flutter\\bin\\flutter.exe'
    )
    $FlutterBin = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
  }
}
if (-not $FlutterBin -or !(Test-Path $FlutterBin)) {
  throw "Flutter not found. Set -FlutterBin or add flutter to PATH."
}

  Push-Location $Root
  try {
  $env:RUSTDESK_APP_NAME = $productName
  & cargo build -p rustdesk --lib --release --features flutter
  if ($LASTEXITCODE -ne 0) { throw "cargo build failed" }

  Push-Location (Join-Path $Root 'flutter')
  try {
    & $FlutterBin build windows --release $dartDefine
    if ($LASTEXITCODE -ne 0) { throw "flutter build failed" }
  } finally {
    Pop-Location
  }

  & (Join-Path $PSScriptRoot 'build_msi_flutter.ps1') -Root $Root -WixBinPath $WixBinPath -ProductName $productName -ProductId $productId -InstallFolderName $installFolder -OutputBaseName $outputBase
  if ($LASTEXITCODE -ne 0) { throw "MSI build failed" }

  $msiPath = Join-Path $PSScriptRoot ("output\\{0}.msi" -f $outputBase)
  & (Join-Path $PSScriptRoot 'build_bundle_flutter.ps1') -Root $Root -WixBinPath $WixBinPath -MsiPath $msiPath -BundleName $productName -OutputBaseName $outputBase
  if ($LASTEXITCODE -ne 0) { throw "Bundle build failed" }
} finally {
  Pop-Location
}

Write-Host ("Done: {0} ({1})" -f $productName, $Mode)
