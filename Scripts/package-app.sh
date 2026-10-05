#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")"/.. && pwd)
PRODUCT_NAME="Deploylight"
BUILD_DIR="$ROOT/.build/release"
EXECUTABLE="$BUILD_DIR/Deploylight"
APP_DIR="$ROOT/build/${PRODUCT_NAME}.app"
# Kept from the app's original name so existing installs keep their settings and
# third-party install recipes keep matching the code signature.
BUNDLE_ID="com.andrew.vercel-deployment-menu-bar"
# Defaults to the latest release tag, skipping pre-releases; override with VERSION=x.y.z
# or VERSION=x.y.z-beta.1.
VERSION="${VERSION:-$({ git -C "$ROOT" describe --tags --abbrev=0 --exclude '*-*' 2>/dev/null || true; } | sed 's/^v//')}"
VERSION="${VERSION:-0.0.0}"
# Bundle versions must be numeric, so a pre-release suffix only appears in the file name.
BUNDLE_VERSION="${VERSION%%-*}"
export VERSION

# Always package a fresh build, never a stale binary left in .build.
swift build -c release --package-path "$ROOT"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cat > "$APP_DIR/Contents/Info.plist" <<INFO
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>${PRODUCT_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>Deploylight</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${PRODUCT_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${BUNDLE_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUNDLE_VERSION}</string>
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
chmod +x "$APP_DIR/Contents/MacOS/Deploylight"

# Copy app icon if it exists
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/"
fi

# Sign the app with Developer ID certificate
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: Andrew Kim (P44RGE92LU)}"
ENTITLEMENTS="$ROOT/Resources/entitlements.plist"

echo "Signing app with identity: $SIGNING_IDENTITY"
codesign --force --deep --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGNING_IDENTITY" \
    --timestamp \
    "$APP_DIR"

# Verify the signature
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

printf 'App bundle created at %s\n' "$APP_DIR"

# Notarize the app (if credentials are configured)
"$ROOT/Scripts/notarize-app.sh"
