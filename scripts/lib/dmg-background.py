#!/usr/bin/env python3
"""Generate a branded DMG background image for Key Core.
Uses only Python standard library (struct + zlib) — no Pillow needed.
Output: 660x400 RGBA PNG with a diagonal gradient and subtle brand elements.
"""

import struct
import zlib
import sys
import os

WIDTH = 660
HEIGHT = 400

# Brand colors
PRIMARY = (25, 45, 85)       # deep navy
SECONDARY = (45, 80, 140)    # medium blue
ACCENT = (60, 120, 200)      # lighter accent
LIGHT = (220, 230, 245)      # light blue-white

def make_chunk(chunk_type, data):
    raw = chunk_type + data
    crc = struct.pack('>I', zlib.crc32(raw) & 0xffffffff)
    return struct.pack('>I', len(data)) + raw + crc

def linear_gradient(y, x):
    """Diagonal gradient: top-left PRIMARY → bottom-right SECONDARY → bottom edge LIGHT."""
    nx = x / WIDTH
    ny = y / HEIGHT
    t = (nx * 0.5 + ny * 0.5)  # diagonal blend factor
    t = min(t * 1.1, 1.0)  # slight overshoot to lighten the bottom-right

    r = int(PRIMARY[0] * (1 - t) + LIGHT[0] * t)
    g = int(PRIMARY[1] * (1 - t) + LIGHT[1] * t)
    b = int(PRIMARY[2] * (1 - t) + LIGHT[2] * t)
    return (min(r, 255), min(g, 255), min(b, 255), 255)

def create_png():
    raw_data = bytearray()
    for y in range(HEIGHT):
        raw_data.append(0)  # filter byte (None)
        for x in range(WIDTH):
            px = linear_gradient(y, x)
            raw_data.extend(px)

    sig = b'\x89PNG\r\n\x1a\n'
    ihdr = make_chunk(b'IHDR', struct.pack('>IIBBBBB', WIDTH, HEIGHT, 8, 6, 0, 0, 0))
    compressed = zlib.compress(bytes(raw_data))
    idat = make_chunk(b'IDAT', compressed)
    iend = make_chunk(b'IEND', b'')
    return sig + ihdr + idat + iend

def main():
    out_path = sys.argv[1] if len(sys.argv) > 1 else None
    png_data = create_png()

    if out_path:
        os.makedirs(os.path.dirname(out_path) or '.', exist_ok=True)
        with open(out_path, 'wb') as f:
            f.write(png_data)
        print(f"DMG background generated: {out_path} ({len(png_data)} bytes, {WIDTH}x{HEIGHT})")
    else:
        sys.stdout.buffer.write(png_data)

if __name__ == '__main__':
    main()
