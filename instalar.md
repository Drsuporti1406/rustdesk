Windows (um comando)
Completa (DrSuporti Remote Tecnico):
powershell -ExecutionPolicy Bypass -File packaging/windows/build_all_flutter.ps1 -Mode full

Lite (DrSuporti Remote Cliente):
powershell -ExecutionPolicy Bypass -File packaging/windows/build_all_flutter.ps1 -Mode lite


Linux (um comando)
Completa:

APP_MODE=full ./build_linux_package.sh
Lite:

APP_MODE=lite ./build_linux_package.sh


$env:PATH += ";C:\Users\Antonio\flutter\bin"
flutter build windows --release --dart-define=APP_LITE=true


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


VERSÔES


Segue o resumo completo, por sistema, para Lite e Completa.
(Substitua os caminhos se necessário.)

Pré‑requisito (comum)
Sempre rode primeiro:

cd C:\github\rustdesk
cargo build -p rustdesk --lib --release --features flutter
Windows – Completa (DrSuporti Remote Tecnico)

cd C:\github\rustdesk\flutter
C:\Users\Antonio\flutter\bin\flutter build windows --release

cd C:\github\rustdesk
powershell -ExecutionPolicy Bypass -File packaging/windows/build_bundle_flutter.ps1
Windows – Lite (DrSuporti Remote Cliente)

cd C:\github\rustdesk\flutter
C:\Users\Antonio\flutter\bin\flutter build windows --release --dart-define=APP_LITE=true

cd C:\github\rustdesk
powershell -ExecutionPolicy Bypass -File packaging/windows/build_bundle_flutter.ps1
Linux – Completa (DrSuporti Remote Tecnico)

cd /home/suporte/rustdesk
cargo build -p rustdesk --lib --release --features flutter

cd /home/suporte/rustdesk/flutter
/root/flutter/bin/flutter build linux --release

cd /home/suporte/rustdesk
./build_linux_package.sh
Linux – Lite (DrSuporti Remote Cliente)

cd /home/suporte/rustdesk
cargo build -p rustdesk --lib --release --features flutter

cd /home/suporte/rustdesk/flutter
/root/flutter/bin/flutter build linux --release --dart-define=APP_LITE=true

cd /home/suporte/rustdesk
./build_linux_package.sh
Mac – Completa (DrSuporti Remote Tecnico)

cd /path/to/rustdesk
cargo build -p rustdesk --lib --release --features flutter

cd /path/to/rustdesk/flutter
flutter build macos --release
Mac – Lite (DrSuporti Remote Cliente)

cd /path/to/rustdesk
cargo build -p rustdesk --lib --release --features flutter

cd /path/to/rustdesk/flutter
flutter build macos --release --dart-define=APP_LITE=true


