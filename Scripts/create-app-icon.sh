#!/usr/bin/env bash
# Draws the app icon (a status light on a dark tile) and writes
# Resources/AppIcon.icns plus app-icon.png for the README.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")"/.. && pwd)
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
ICONSET_DIR="$WORK_DIR/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

cat > "$WORK_DIR/draw_icon.swift" <<'SWIFT'
import AppKit

let canvas: CGFloat = 1024
let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

// macOS icon grid: an 824pt tile centered on the 1024pt canvas.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGradient(
    starting: NSColor(calibratedWhite: 0.16, alpha: 1),
    ending: NSColor(calibratedWhite: 0.04, alpha: 1)
)!.draw(in: tilePath, angle: -90)

let center = NSPoint(x: canvas / 2, y: canvas / 2)
let green = NSColor(calibratedRed: 0.20, green: 0.84, blue: 0.42, alpha: 1)

// Soft glow around the light.
NSGradient(colors: [green.withAlphaComponent(0.45), green.withAlphaComponent(0)])!
    .draw(fromCenter: center, radius: 0, toCenter: center, radius: 330, options: [])

// Recessed housing, then the lit lens.
let housing = NSRect(x: center.x - 200, y: center.y - 200, width: 400, height: 400)
NSColor(calibratedWhite: 0.02, alpha: 1).setFill()
NSBezierPath(ovalIn: housing).fill()

let lens = housing.insetBy(dx: 30, dy: 30)
NSGradient(colors: [
    NSColor(calibratedRed: 0.62, green: 1.0, blue: 0.72, alpha: 1),
    green,
    NSColor(calibratedRed: 0.06, green: 0.52, blue: 0.24, alpha: 1),
])!.draw(in: NSBezierPath(ovalIn: lens), relativeCenterPosition: NSPoint(x: -0.25, y: 0.3))

image.unlockFocus()

let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT

swiftc -o "$WORK_DIR/draw_icon" "$WORK_DIR/draw_icon.swift" -framework AppKit
BASE="$WORK_DIR/icon_1024.png"
"$WORK_DIR/draw_icon" "$BASE"

for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$BASE" --out "$ICONSET_DIR/icon_${size}x${size}.png" > /dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$BASE" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" > /dev/null
done

iconutil -c icns "$ICONSET_DIR" -o "$ROOT/Resources/AppIcon.icns"
sips -z 512 512 "$BASE" --out "$ROOT/app-icon.png" > /dev/null

echo "Wrote $ROOT/Resources/AppIcon.icns and $ROOT/app-icon.png"
