$env:PATH = "$env:PATH;$env:USERPROFILE\.cargo\bin"
cargo --version
cargo build -p rustdesk --lib --release --features flutter


cd C:\github\rustdesk
cargo build -p rustdesk --lib --release --features flutter

cd C:\github\rustdesk\flutter
C:\Users\Antonio\flutter\bin\flutter build windows --release


cd C:\github\rustdesk
powershell -ExecutionPolicy Bypass -File packaging/windows/build_msi_flutter.ps1
powershell -ExecutionPolicy Bypass -File packaging/windows/build_bundle_flutter.ps1

força instalação limpa:
# 1) Rebuild Rust (tray icon embutido no librustdesk.dll)
$env:PATH = "$env:PATH;$env:USERPROFILE\.cargo\bin"
cd C:\github\rustdesk
cargo build -p rustdesk --lib --release --features flutter

# 2) Limpar Flutter e rebuild (força novo app_icon.ico no exe)
cd C:\github\rustdesk\flutter
C:\Users\Antonio\flutter\bin\flutter clean
C:\Users\Antonio\flutter\bin\flutter pub get
C:\Users\Antonio\flutter\bin\flutter build windows --release

# 3) Regerar MSI + bundle
cd C:\github\rustdesk
powershell -ExecutionPolicy Bypass -File packaging/windows/build_msi_flutter.ps1
powershell -ExecutionPolicy Bypass -File packaging/windows/build_bundle_flutter.ps1

