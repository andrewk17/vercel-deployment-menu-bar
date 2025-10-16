#!/usr/bin/env bash
set -euo pipefail

# This script notarizes the built app bundle with Apple's notary service
#
# Prerequisites:
# 1. Create an App Store Connect API key:
#    - Go to https://appstoreconnect.apple.com/access/api
#    - Create a key with "Developer" role
#    - Download the .p8 file and save it to ~/.private_keys/
#
# 2. Set environment variables (add to ~/.zshrc or ~/.bash_profile):
#    export APPLE_API_KEY_ID="your-key-id"
#    export APPLE_API_ISSUER="your-issuer-id"
#    export APPLE_API_KEY_PATH="$HOME/.private_keys/AuthKey_XXXXXXXXXX.p8"

ROOT=$(cd "$(dirname "$0")"/.. && pwd)
PRODUCT_NAME="Vercel Deployment Menu Bar"
APP_DIR="$ROOT/build/${PRODUCT_NAME}.app"

# Check if environment variables are set
if [ -z "${APPLE_API_KEY_ID:-}" ] || [ -z "${APPLE_API_ISSUER:-}" ] || [ -z "${APPLE_API_KEY_PATH:-}" ]; then
    echo "⚠️  Notarization skipped: App Store Connect API credentials not configured"
    echo ""
    echo "To enable notarization, set these environment variables:"
    echo "  APPLE_API_KEY_ID       - Your API Key ID"
    echo "  APPLE_API_ISSUER       - Your Issuer ID"
    echo "  APPLE_API_KEY_PATH     - Path to your .p8 file"
    echo ""
    echo "See the script header for detailed setup instructions."
    exit 0
fi

# Create a ZIP for notarization
ZIP_PATH="$ROOT/build/${PRODUCT_NAME}.zip"
echo "Creating ZIP for notarization..."
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

echo "Submitting to Apple's notary service..."
xcrun notarytool submit "$ZIP_PATH" \
    --key "$APPLE_API_KEY_PATH" \
    --key-id "$APPLE_API_KEY_ID" \
    --issuer "$APPLE_API_ISSUER" \
    --wait

echo "Stapling notarization ticket to app..."
xcrun stapler staple "$APP_DIR"

echo "Verifying notarization..."
xcrun stapler validate "$APP_DIR"

# Clean up ZIP
rm "$ZIP_PATH"

echo "✅ App successfully notarized and stapled!"
