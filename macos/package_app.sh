#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build-macos}"
APP_DIR="${APP_DIR:-$ROOT_DIR/dist/RemoteJoyLite.app}"
CONFIG="${CONFIG:-Release}"

SDL_PREFIX="${SDL_PREFIX:-$(brew --prefix sdl3)}"
LIBUSB_PREFIX="${LIBUSB_PREFIX:-$(brew --prefix libusb)}"

SDL_DYLIB="$SDL_PREFIX/lib/libSDL3.0.dylib"
LIBUSB_DYLIB="$LIBUSB_PREFIX/lib/libusb-1.0.0.dylib"
ICON_SRC="$ROOT_DIR/RemoteJoyLite_pc/RemoteJoyLite.ico"
APP_BIN_NAME="RemoteJoyLite"
ICON_NAME="RemoteJoyLite"
APP_BIN_SRC="$BUILD_DIR/RemoteJoyLite-cross"
APP_BIN_DST="$APP_DIR/Contents/MacOS/$APP_BIN_NAME"
FW_DIR="$APP_DIR/Contents/Frameworks"
RES_DIR="$APP_DIR/Contents/Resources"
ICONSET_DIR="$(mktemp -d)"

trap 'rm -rf "$ICONSET_DIR"' EXIT

if ! command -v cmake >/dev/null 2>&1; then
  echo "cmake is required" >&2
  exit 1
fi

if ! command -v install_name_tool >/dev/null 2>&1; then
  echo "install_name_tool is required" >&2
  exit 1
fi

if ! command -v pkg-config >/dev/null 2>&1; then
  echo "pkg-config is required" >&2
  exit 1
fi

if ! command -v sips >/dev/null 2>&1; then
  echo "sips is required" >&2
  exit 1
fi

if ! command -v iconutil >/dev/null 2>&1; then
  echo "iconutil is required" >&2
  exit 1
fi

if [ ! -f "$SDL_DYLIB" ]; then
  echo "Missing SDL3 dylib: $SDL_DYLIB" >&2
  exit 1
fi

if [ ! -f "$LIBUSB_DYLIB" ]; then
  echo "Missing libusb dylib: $LIBUSB_DYLIB" >&2
  exit 1
fi

if [ ! -f "$ICON_SRC" ]; then
  echo "Missing icon source: $ICON_SRC" >&2
  exit 1
fi

cmake -S "$ROOT_DIR/RemoteJoyLite_sdl" -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE="$CONFIG" \
  -DCMAKE_PREFIX_PATH="$SDL_PREFIX"
cmake --build "$BUILD_DIR" -j"$(sysctl -n hw.ncpu)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$FW_DIR" "$RES_DIR"

cp "$APP_BIN_SRC" "$APP_BIN_DST"
cp "$SDL_DYLIB" "$FW_DIR/"
cp "$LIBUSB_DYLIB" "$FW_DIR/"

mkdir -p "$ICONSET_DIR/$ICON_NAME.iconset"
BASE_ICON="$ICONSET_DIR/icon_base.png"
sips -s format png "$ICON_SRC" --out "$BASE_ICON" >/dev/null
sips -z 16 16 "$BASE_ICON" --out "$ICONSET_DIR/$ICON_NAME.iconset/icon_16x16.png" >/dev/null
sips -z 32 32 "$BASE_ICON" --out "$ICONSET_DIR/$ICON_NAME.iconset/icon_32x32.png" >/dev/null
sips -z 64 64 "$BASE_ICON" --out "$ICONSET_DIR/$ICON_NAME.iconset/icon_64x64.png" >/dev/null
sips -z 128 128 "$BASE_ICON" --out "$ICONSET_DIR/$ICON_NAME.iconset/icon_128x128.png" >/dev/null
sips -z 256 256 "$BASE_ICON" --out "$ICONSET_DIR/$ICON_NAME.iconset/icon_256x256.png" >/dev/null
sips -z 512 512 "$BASE_ICON" --out "$ICONSET_DIR/$ICON_NAME.iconset/icon_512x512.png" >/dev/null
cp "$ICONSET_DIR/$ICON_NAME.iconset/icon_32x32.png" "$ICONSET_DIR/$ICON_NAME.iconset/icon_16x16@2x.png"
cp "$ICONSET_DIR/$ICON_NAME.iconset/icon_64x64.png" "$ICONSET_DIR/$ICON_NAME.iconset/icon_32x32@2x.png"
cp "$ICONSET_DIR/$ICON_NAME.iconset/icon_128x128.png" "$ICONSET_DIR/$ICON_NAME.iconset/icon_64x64@2x.png"
cp "$ICONSET_DIR/$ICON_NAME.iconset/icon_256x256.png" "$ICONSET_DIR/$ICON_NAME.iconset/icon_128x128@2x.png"
cp "$ICONSET_DIR/$ICON_NAME.iconset/icon_512x512.png" "$ICONSET_DIR/$ICON_NAME.iconset/icon_256x256@2x.png"
cp "$ICONSET_DIR/$ICON_NAME.iconset/icon_512x512.png" "$ICONSET_DIR/$ICON_NAME.iconset/icon_512x512@2x.png"
iconutil -c icns "$ICONSET_DIR/$ICON_NAME.iconset" -o "$RES_DIR/$ICON_NAME.icns"

chmod +x "$APP_BIN_DST"

cat > "$APP_DIR/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>RemoteJoyLite</string>
  <key>CFBundleExecutable</key>
  <string>RemoteJoyLite</string>
  <key>CFBundleIconFile</key>
  <string>RemoteJoyLite</string>
  <key>CFBundleIdentifier</key>
  <string>com.psparchive.rjl</string>
  <key>CFBundleName</key>
  <string>RemoteJoyLite</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.19</string>
  <key>CFBundleVersion</key>
  <string>0.19</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

cat > "$APP_DIR/Contents/PkgInfo" <<'EOF'
APPL????
EOF

install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BIN_DST"
install_name_tool -change "$SDL_DYLIB" "@rpath/libSDL3.0.dylib" "$APP_BIN_DST"
install_name_tool -change "$LIBUSB_DYLIB" "@rpath/libusb-1.0.0.dylib" "$APP_BIN_DST"
install_name_tool -id "@rpath/libSDL3.0.dylib" "$FW_DIR/libSDL3.0.dylib"
install_name_tool -id "@rpath/libusb-1.0.0.dylib" "$FW_DIR/libusb-1.0.0.dylib"

if [ -n "${CODESIGN_IDENTITY:-}" ]; then
  CODESIGN_OPTS=(--force --options runtime --timestamp --sign "$CODESIGN_IDENTITY")
  codesign "${CODESIGN_OPTS[@]}" "$FW_DIR/libSDL3.0.dylib"
  codesign "${CODESIGN_OPTS[@]}" "$FW_DIR/libusb-1.0.0.dylib"
  codesign "${CODESIGN_OPTS[@]}" "$APP_BIN_DST"
  codesign "${CODESIGN_OPTS[@]}" "$APP_DIR"
fi

touch "$APP_DIR"

if command -v /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister >/dev/null 2>&1; then
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR" >/dev/null 2>&1 || true
fi

if [ "${CREATE_ZIP:-0}" = "1" ]; then
  mkdir -p "$ROOT_DIR/dist"
  ditto -c -k --keepParent "$APP_DIR" "$ROOT_DIR/dist/RemoteJoyLite-macOS.zip"
fi

echo "Created: $APP_DIR"
