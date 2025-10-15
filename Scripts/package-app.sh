#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")"/.. && pwd)
PRODUCT_NAME="Vercel Deployment Menu Bar"
BUILD_DIR="$ROOT/.build/release"
EXECUTABLE="$BUILD_DIR/vercel-deployment-menu-bar"
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
    <string>Vercel Deployment Menu Bar</string>
    <key>CFBundleExecutable</key>
    <string>vercel-deployment-menu-bar</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.andrew.vercel-deployment-menu-bar</string>
    <key>CFBundleName</key>
    <string>Vercel Deployment Menu Bar</string>
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
chmod +x "$APP_DIR/Contents/MacOS/vercel-deployment-menu-bar"

# Copy app icon if it exists
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/"
fi

printf 'App bundle created at %s\n' "$APP_DIR"
