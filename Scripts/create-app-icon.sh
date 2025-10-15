#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")"/.. && pwd)
ICONSET_DIR="$ROOT/Resources/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

# Create a simple upside-down triangle using Swift
cat > /tmp/create_icon.swift <<'SWIFT'
import AppKit

let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Flip coordinate system to match image orientation (top-left origin)
let transform = NSAffineTransform()
transform.translateX(by: 0, yBy: CGFloat(size))
transform.scaleX(by: 1.0, yBy: -1.0)
transform.concat()

// Black background for better visibility
NSColor.black.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()

// White upside-down triangle (point down)
let path = NSBezierPath()
let centerX = CGFloat(size) / 2.0
let topY = CGFloat(size) * 0.25     // Flat edge at top
let bottomY = CGFloat(size) * 0.75  // Point at bottom
let leftX = CGFloat(size) * 0.2
let rightX = CGFloat(size) * 0.8

// For upside-down: flat edge on top, point at bottom
path.move(to: NSPoint(x: leftX, y: topY))         // Top left corner
path.line(to: NSPoint(x: rightX, y: topY))        // Top right corner
path.line(to: NSPoint(x: centerX, y: bottomY))    // Bottom point
path.close()

NSColor.white.setFill()
path.fill()

image.unlockFocus()

// Save as PNG
if let tiffData = image.tiffRepresentation,
   let bitmapImage = NSBitmapImageRep(data: tiffData),
   let pngData = bitmapImage.representation(using: .png, properties: [:]) {
    let url = URL(fileURLWithPath: "/tmp/icon_1024.png")
    try? pngData.write(to: url)
    print("Created base icon at /tmp/icon_1024.png")
}
SWIFT

# Compile and run Swift script
swiftc -o /tmp/create_icon /tmp/create_icon.swift -framework AppKit
/tmp/create_icon

# Create all required sizes using sips
sips -z 16 16 /tmp/icon_1024.png --out "$ICONSET_DIR/icon_16x16.png" > /dev/null
sips -z 32 32 /tmp/icon_1024.png --out "$ICONSET_DIR/icon_16x16@2x.png" > /dev/null
sips -z 32 32 /tmp/icon_1024.png --out "$ICONSET_DIR/icon_32x32.png" > /dev/null
sips -z 64 64 /tmp/icon_1024.png --out "$ICONSET_DIR/icon_32x32@2x.png" > /dev/null
sips -z 128 128 /tmp/icon_1024.png --out "$ICONSET_DIR/icon_128x128.png" > /dev/null
sips -z 256 256 /tmp/icon_1024.png --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null
sips -z 256 256 /tmp/icon_1024.png --out "$ICONSET_DIR/icon_256x256.png" > /dev/null
sips -z 512 512 /tmp/icon_1024.png --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null
sips -z 512 512 /tmp/icon_1024.png --out "$ICONSET_DIR/icon_512x512.png" > /dev/null
cp /tmp/icon_1024.png "$ICONSET_DIR/icon_512x512@2x.png"

# Convert iconset to icns
iconutil -c icns "$ICONSET_DIR" -o "$ROOT/Resources/AppIcon.icns"

echo "App icon created at $ROOT/Resources/AppIcon.icns"

# Clean up
rm -rf "$ICONSET_DIR"
rm /tmp/icon_1024.png /tmp/create_icon.swift /tmp/create_icon
