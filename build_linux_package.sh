#!/usr/bin/env bash
set -euo pipefail

APP="DrSuporti Remote"
ID="drsuporti-remote"
VERSION="1.4.4.1"
ROOT="$(pwd)"
ICON="$ROOT/src/logo.png"
FLUTTER_BIN="/root/flutter/bin/flutter"
FLUTTER_DIR="$ROOT/flutter"
BUNDLE="$FLUTTER_DIR/build/linux/x64/release/bundle"
STAGE="/tmp/pkg-$ID"

export PATH="/root/flutter/bin:$PATH"

# 0) Flutter deps
cd "$FLUTTER_DIR"
"$FLUTTER_BIN" pub get

# 1) Gerar bridge
cd "$ROOT"
flutter_rust_bridge_codegen --rust-input ./src/flutter_ffi.rs --dart-output ./flutter/lib/generated_bridge.dart

# 2) Build Rust (Flutter lib)
VCPKG_ROOT=/opt/vcpkg VCPKG_INSTALLED_ROOT="$ROOT/vcpkg_installed" \
  cargo build -p rustdesk --lib --release --features flutter

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
