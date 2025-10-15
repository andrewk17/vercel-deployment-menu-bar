#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")"/.. && pwd)
PRODUCT_NAME="Vercel Status"
BUILD_DIR="$ROOT/.build/arm64-apple-macosx/debug"
EXECUTABLE="$BUILD_DIR/vercel-status-menubar"
APP_DIR="$ROOT/build/${PRODUCT_NAME}.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cat > "$APP_DIR/Contents/Info.plist" <<'INFO'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>Vercel Status</string>
    <key>CFBundleExecutable</key>
    <string>vercel-status-menubar</string>
    <key>CFBundleIdentifier</key>
    <string>com.andrew.vercel-status-menubar</string>
    <key>CFBundleName</key>
    <string>Vercel Status</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
INFO

cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/"
chmod +x "$APP_DIR/Contents/MacOS/vercel-status-menubar"

printf 'App bundle created at %s\n' "$APP_DIR"
