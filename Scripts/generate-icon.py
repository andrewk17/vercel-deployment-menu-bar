#!/usr/bin/env python3
import os
from pathlib import Path

# SVG content for upside-down triangle
svg_template = '''<?xml version="1.0" encoding="UTF-8"?>
<svg width="{size}" height="{size}" viewBox="0 0 {size} {size}" xmlns="http://www.w3.org/2000/svg">
  <polygon points="{x1},{y1} {x2},{y2} {x3},{y3}" fill="black"/>
</svg>'''

# Icon sizes needed for macOS
sizes = [16, 32, 64, 128, 256, 512, 1024]

root = Path(__file__).parent.parent
iconset_dir = root / "Resources" / "AppIcon.iconset"
iconset_dir.mkdir(parents=True, exist_ok=True)

for size in sizes:
    # Calculate triangle points (upside-down)
    center_x = size / 2
    top_y = size * 0.25
    bottom_y = size * 0.75
    left_x = size * 0.2
    right_x = size * 0.8

    # Create SVG
    svg_content = svg_template.format(
        size=size,
        x1=center_x, y1=bottom_y,  # Bottom point
        x2=left_x, y2=top_y,       # Top left
        x3=right_x, y3=top_y       # Top right
    )

    # Write SVG files
    if size <= 512:
        svg_path = iconset_dir / f"icon_{size}x{size}.svg"
        with open(svg_path, 'w') as f:
            f.write(svg_content)

    # For @2x versions
    if size >= 32 and size <= 512:
        svg_path = iconset_dir / f"icon_{size//2}x{size//2}@2x.svg"
        with open(svg_path, 'w') as f:
            f.write(svg_content)

print(f"SVG icons created in {iconset_dir}")
print("Note: You'll need to convert these to PNG manually using a tool like Inkscape or ImageMagick")
