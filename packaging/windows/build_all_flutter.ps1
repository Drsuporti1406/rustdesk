param(
  [ValidateSet('full','lite')]
  [string]$Mode = 'full',
  [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\\..')).Path,
  [string]$FlutterBin = 'C:\\Users\\Antonio\\flutter\\bin\\flutter.exe',
  [string]$WixBinPath = ''
)

$ErrorActionPreference = 'Stop'

$productName = 'DrSuporti Remote Tecnico'
$productId = 'DrSuportiRemoteTecnico'
$installFolder = 'DrSuporti Remote Tecnico'
$outputBase = 'DrSuportiRemoteTecnico'
$dartDefine = ''

if ($Mode -eq 'lite') {
  $productName = 'DrSuporti Remote Cliente'
  $productId = 'DrSuportiRemoteCliente'
  $installFolder = 'DrSuporti Remote Cliente'
  $outputBase = 'DrSuportiRemoteCliente'
  $dartDefine = '--dart-define=APP_LITE=true'
}

if (!(Test-Path $FlutterBin)) {
  throw "Flutter not found at: $FlutterBin"
}

Push-Location $Root
try {
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
