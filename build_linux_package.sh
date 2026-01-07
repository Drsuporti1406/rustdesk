#!/usr/bin/env bash
set -euo pipefail
FLUTTER_BIN="/root/""/bin/"""
APP="DrSuporti Remote"
FLUTTER_BIN="/root/""/bin/"""
ID="drsuporti-remote"
VERSION="1.4.4.0"
ICON="/root/rustdesk/src/logo.png"

ROOT="/root/rustdesk"
FLUTTER_DIR="$ROOT/"""
BUNDLE="$FLUTTER_DIR/build/linux/x64/release/bundle"
STAGE="/tmp/pkg-$ID"

# 1) Gerar bridge
cd "$ROOT"
flutter_rust_bridge_codegen --rust-input ./src/flutter_ffi.rs --dart-output ./""/lib/generated_bridge.dart

# 2) Build Rust (Flutter lib)
VCPKG_ROOT=/opt/vcpkg VCPKG_INSTALLED_ROOT="$ROOT/vcpkg_installed" \
  cargo build -p rustdesk --lib --release --features ""

# 3) Build Flutter
cd "$FLUTTER_DIR"
"$FLUTTER_BIN" build linux --release

# 4) Preparar stage
rm -rf "$STAGE"
mkdir -p "$STAGE/opt/$ID"
mkdir -p "$STAGE/usr/share/applications"
mkdir -p "$STAGE/usr/share/icons/hicolor/256x256/apps"

cp -a "$BUNDLE/"* "$STAGE/opt/$ID/"
cp -a "$ICON" "$STAGE/usr/share/icons/hicolor/256x256/apps/$ID.png"

cat > "$STAGE/usr/share/applications/$ID.desktop" <<EOF
[Desktop Entry]
Name=$APP
Exec=/opt/$ID/rustdesk
Icon=$ID
Type=Application
Categories=Network;RemoteAccess;
Terminal=false
EOF

# 5) Gerar pacotes
cd "$ROOT"
fpm -s dir -t deb -n "$ID" -v "$VERSION" \
  --prefix=/ \
  -C "$STAGE" \
  --description "DrSuporti Remote (RustDesk custom)" \
  --maintainer "DrSuporti" \
  --license "Proprietary"

fpm -s dir -t rpm -n "$ID" -v "$VERSION" \
  --prefix=/ \
  -C "$STAGE" \
  --description "DrSuporti Remote (RustDesk custom)" \
  --maintainer "DrSuporti" \
  --license "Proprietary"

echo "OK: pacotes gerados em $ROOT"
