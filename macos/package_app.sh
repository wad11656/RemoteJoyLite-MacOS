#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build-macos}"
APP_DIR="${APP_DIR:-$ROOT_DIR/dist/RemoteJoyLite.app}"
CONFIG="${CONFIG:-Release}"
INCLUDE_PSP_PRX="${INCLUDE_PSP_PRX:-${CREATE_DMG:-0}}"
PSP_PRX_SRC="${PSP_PRX_SRC:-$ROOT_DIR/RemoteJoyLite.prx}"

SDL_PREFIX="${SDL_PREFIX:-$(brew --prefix sdl3)}"
LIBUSB_PREFIX="${LIBUSB_PREFIX:-$(brew --prefix libusb)}"

SDL_DYLIB="$SDL_PREFIX/lib/libSDL3.0.dylib"
LIBUSB_DYLIB="$LIBUSB_PREFIX/lib/libusb-1.0.0.dylib"
ICON_SRC="$ROOT_DIR/RemoteJoyLite_pc/RemoteJoyLite.ico"
APP_BIN_NAME="RemoteJoyLite"
ICON_NAME="RemoteJoyLite"
DMG_NAME="RemoteJoyLite-macOS"
APP_BIN_SRC="$BUILD_DIR/RemoteJoyLite-cross"
APP_BIN_DST="$APP_DIR/Contents/MacOS/$APP_BIN_NAME"
FW_DIR="$APP_DIR/Contents/Frameworks"
RES_DIR="$APP_DIR/Contents/Resources"
ICONSET_DIR="$(mktemp -d)"
DMG_STAGE_DIR="$(mktemp -d)"
PSP_TMP_DIR="$(mktemp -d)"
DMG_RW_PATH="$ROOT_DIR/dist/$DMG_NAME-rw.dmg"
DMG_FINAL_PATH="$ROOT_DIR/dist/$DMG_NAME.dmg"
DMG_MOUNT_POINT="$(mktemp -d /tmp/RemoteJoyLite-dmg-mount.XXXX)"
PSP_PRX_TMP="$PSP_TMP_DIR/RemoteJoyLite.prx"

trap 'rm -rf "$ICONSET_DIR" "$DMG_STAGE_DIR" "$PSP_TMP_DIR" "$DMG_MOUNT_POINT"' EXIT

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

if ! command -v hdiutil >/dev/null 2>&1; then
  echo "hdiutil is required" >&2
  exit 1
fi

if ! command -v osascript >/dev/null 2>&1; then
  echo "osascript is required" >&2
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

if [ "$INCLUDE_PSP_PRX" = "1" ]; then
  if [ ! -f "$PSP_PRX_SRC" ]; then
    echo "Missing PSP plugin: $PSP_PRX_SRC" >&2
    exit 1
  fi

  cp "$PSP_PRX_SRC" "$PSP_PRX_TMP"
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
  <key>NSMicrophoneUsageDescription</key>
  <string>RemoteJoyLite uses microphone input for live monitoring and recording.</string>
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

CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
if [ "$CODESIGN_IDENTITY" = "-" ]; then
  CODESIGN_OPTS=(--force --sign -)
else
  CODESIGN_OPTS=(--force --options runtime --timestamp --sign "$CODESIGN_IDENTITY")
fi
codesign "${CODESIGN_OPTS[@]}" "$FW_DIR/libSDL3.0.dylib"
codesign "${CODESIGN_OPTS[@]}" "$FW_DIR/libusb-1.0.0.dylib"
codesign "${CODESIGN_OPTS[@]}" "$APP_BIN_DST"
codesign "${CODESIGN_OPTS[@]}" "$APP_DIR"

touch "$APP_DIR"

if command -v /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister >/dev/null 2>&1; then
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR" >/dev/null 2>&1 || true
fi

if [ "${CREATE_ZIP:-0}" = "1" ]; then
  mkdir -p "$ROOT_DIR/dist"
  ditto -c -k --keepParent "$APP_DIR" "$ROOT_DIR/dist/RemoteJoyLite-macOS.zip"
fi

if [ "${CREATE_DMG:-0}" = "1" ]; then
  mkdir -p "$ROOT_DIR/dist"
  rm -f "$DMG_RW_PATH" "$DMG_FINAL_PATH"
  rm -rf "$DMG_STAGE_DIR"/*
  cp -R "$APP_DIR" "$DMG_STAGE_DIR/"
  if [ "$INCLUDE_PSP_PRX" = "1" ]; then
    cp "$PSP_PRX_TMP" "$DMG_STAGE_DIR/RemoteJoyLite.prx"
  fi
  cat > "$DMG_STAGE_DIR/Install.command" <<'EOF'
#!/bin/bash
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/RemoteJoyLite.app"
DST="/Applications/RemoteJoyLite.app"

if [ ! -d "$SRC" ]; then
  echo "RemoteJoyLite.app was not found next to this installer."
  echo "Make sure you ran Install.command from the mounted disk image."
  exit 1
fi

echo "Installing RemoteJoyLite to /Applications ..."
rm -rf "$DST"
cp -R "$SRC" "$DST"

echo "Clearing quarantine attribute ..."
xattr -cr "$DST"

echo
echo "Done. RemoteJoyLite is now in your Applications folder."
echo "You can close this Terminal window."
EOF
  chmod +x "$DMG_STAGE_DIR/Install.command"
  cat > "$DMG_STAGE_DIR/README.rtf" <<'EOF'
{\rtf1\ansi\deff0
{\fonttbl{\f0\fmodern\fcharset0 Menlo-Regular;}}
\fs24
===== Installation on Mac =====\par
Easiest:\par
1. Right-click Install.command and choose Open.\par
2. Confirm the prompt. Terminal will copy the app to Applications and clear the quarantine flag.\par
3. Launch RemoteJoyLite from Applications.\par
\par
Manual alternative:\par
1. Drag RemoteJoyLite.app into Applications.\par
2. Open Terminal and run:\par
   xattr -cr /Applications/RemoteJoyLite.app\par
3. Launch RemoteJoyLite from Applications.\par
\par
If macOS still blocks Install.command with "unidentified developer", go to:\par
System Settings > Privacy & Security\par
and click Open Anyway, then re-run it.\par
\par
===== Installation on PSP =====\par
1. Copy RemoteJoyLite.prx into ms0:/seplugins/\par
2. Add the following into ms0:/seplugins/game.txt, ms0:/seplugins/vsh.txt and ms0:/seplugins/pops.txt. Adapt this step for ARK-4 following:\par
   https://github.com/PSP-Archive/ARK-4/wiki/Plugins\par
\par
   ms0:/seplugins/RemoteJoyLite.prx 1\par
\par
On 2k/3k/Go/Street, you are recommended to disable extended/high memory layout in your CFW settings, as well as disable ISO/Inferno cache and memory stick speedup.\par
\par
On ARK CFW, you might also want to make the following change in ms0:/PSP/SAVEDATA/ARK_01234/SETTINGS.TXT if you plan to use RJL with GTA titles:\par
\par
   # Enable Extra RAM on GTA LCS and VCS for CheatDeviceRemastered\par
   ULUS10041 ULUS10160 ULES00151 ULES00502, highmem, on\par
\par
to:\par
\par
   # Enable Extra RAM on GTA LCS and VCS for CheatDeviceRemastered\par
   #ULUS10041 ULUS10160 ULES00151 ULES00502, highmem, on\par
}
EOF
  hdiutil create -ov -fs HFS+ -format UDRW -volname "RemoteJoyLite" \
    -srcfolder "$DMG_STAGE_DIR" "$DMG_RW_PATH" >/dev/null
  hdiutil attach "$DMG_RW_PATH" -mountpoint "$DMG_MOUNT_POINT" -nobrowse -quiet

osascript <<'EOF' || true
tell application "Finder"
  tell disk "RemoteJoyLite"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {120, 120, 500, 300}
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF

  hdiutil detach "$DMG_MOUNT_POINT" -quiet
  hdiutil convert "$DMG_RW_PATH" -format UDZO -imagekey zlib-level=9 -o "$DMG_FINAL_PATH" >/dev/null
  rm -f "$DMG_RW_PATH"
fi

echo "Created: $APP_DIR"
