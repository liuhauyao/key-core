"""Pixel-snapped rasters for D1h: tray glyphs (16..64) and app icons 16/32 (mac + square).
Straight edges (shaft, teeth) sit on whole pixels; bow / hole are true circles (anti-aliased).
Each entry: canvas, W, D, d, plain, t, g, h, axis-x, tip-y   (D, d may be fractional; the rest integer)."""
import os, re, io, sys, subprocess
from PIL import Image, ImageDraw
sys.path.insert(0, os.path.dirname(__file__))
from geom import PHI
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
SRC = os.path.join(ROOT, 'concept_D1h_src')
P3 = PHI ** 3

TRAY = {   # size: (W, D, d, plain, t, g, h)
    16: (2, 10.0, 4.0, 1, 2, 1, 2),          # hand-tuned: bow pushed to 10px (hero), hole 4px
    18: (2, 10.0, 4.0, 1, 2, 1, 2),
    22: (3, 3*P3, 3*PHI, 3, 2, 1, 3),        # exact circles
    24: (3, 3*P3, 3*PHI, 3, 2, 1, 3),
    32: (4, 4*P3, 4*PHI, 3, 3, 2, 4),
    36: (5, 5*P3, 5*PHI, 5, 3, 2, 5),
    44: (6, 6*P3, 6*PHI, 6, 4, 2, 6),
    64: (9, 9*P3, 9*PHI, 9, 6, 3, 9),
}
APP = {    # name: (size, W, D, d, plain, t, g, h, axis_x, tip_y, base svg)
    'mac_16':    (16, 2, 6.6, 2.6, 1, 1, 1, 2, 8.0, 13, 'app_mac_small.svg'),
    'mac_32':    (32, 3, 3*P3, 3*PHI, 3, 2, 1, 3, 16.5, 26, 'app_mac_small.svg'),
    'square_16': (16, 2, 7.6, 3.0, 2, 1, 1, 2, 8.0, 14, 'app_square_small.svg'),
    'square_32': (32, 3, 14.0, 5.4, 3, 2, 1, 3, 16.5, 28, 'app_square_small.svg'),
}
SS = 16  # supersampling

def key_mask(size, W, D, d, plain, t, g, h, ax, tip):
    S = plain + 2*t + g
    cy = tip - S - D/2
    m = Image.new('L', (size*SS, size*SS), 0)
    dr = ImageDraw.Draw(m)
    sc = lambda v: round(v*SS)
    dr.ellipse([sc(ax - D/2), sc(cy - D/2), sc(ax + D/2) - 1, sc(cy + D/2) - 1], fill=255)
    dr.rectangle([sc(ax - W/2), sc(cy), sc(ax + W/2) - 1, sc(tip) - 1], fill=255)
    y = tip - S + plain
    for a, b in ((y, y + t), (y + t + g, y + 2*t + g)):
        dr.rectangle([sc(ax - W/2 - h), sc(a), sc(ax - W/2) - 1, sc(b) - 1], fill=255)
    dr.ellipse([sc(ax - d/2), sc(cy - d/2), sc(ax + d/2) - 1, sc(cy + d/2) - 1], fill=0)
    return m.resize((size, size), Image.BOX)

def tray(size, color):
    W, D, d, plain, t, g, h = TRAY[size]
    S = plain + 2*t + g
    L = D + S
    ax = size/2 if W % 2 == 0 else size//2 + 0.5
    tip = round((size + L) / 2)
    m = key_mask(size, W, D, d, plain, t, g, h, ax, tip)
    im = Image.new('RGBA', (size, size), color + (0,)); im.putalpha(m)
    return im

def metal(size, m, top, bot):
    """vertical silver ramp + 1px soft shadow below."""
    grad = Image.new('RGBA', (size, size))
    for y in range(size):
        u = min(1, max(0, (y - top) / max(1, bot - top)))
        c = tuple(round(a + (b - a)*u) for a, b in zip((246, 247, 249), (150, 156, 165)))
        for x in range(size): grad.putpixel((x, y), c + (255,))
    grad.putalpha(m)
    sh = Image.new('RGBA', (size, size), (0, 0, 0, 0)); sh.putalpha(m.point(lambda v: v*0.55))
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0)); out.alpha_composite(sh, (0, 1)); out.alpha_composite(grad)
    return out

def app(name):
    size, W, D, d, plain, t, g, h, ax, tip, base = APP[name]
    svg = open(os.path.join(SRC, base)).read()
    svg = re.sub(r'\n\s*<path d="[^"]*" fill="url\(#metal\)"[^>]*/>', '', svg)
    png = subprocess.run(['resvg', '-', '-c', '-w', str(size), '-h', str(size)], input=svg.encode(), capture_output=True, check=True).stdout
    bg = Image.open(io.BytesIO(png)).convert('RGBA')
    m = key_mask(size, W, D, d, plain, t, g, h, ax, tip)
    S = plain + 2*t + g
    bg.alpha_composite(metal(size, m, tip - S - D, tip))
    return bg

if __name__ == '__main__':
    out = os.path.join(SRC, 'px'); os.makedirs(out, exist_ok=True)
    for s in TRAY:
        tray(s, (0, 0, 0)).save(os.path.join(out, f'tray_{s}_template_black.png'))
        tray(s, (255, 255, 255)).save(os.path.join(out, f'tray_{s}_white.png'))
    for n in APP:
        app(n).save(os.path.join(out, f'app_{n}.png'))
    print('ok')
