"""Pixel-snapped rasters for D1i / D1j (generalised phi^k bow). Straight edges on whole px, circles AA.
Integer sizes derived from the construction then rounded: S = round(L - D), t = round(S/phi^3), g = max(1, round(S/phi^4)),
plain = S - 2t - g, h = W."""
import os, re, io, sys, subprocess
from PIL import Image
sys.path.insert(0, os.path.dirname(__file__))
from geom import PHI
from snap_h import key_mask, metal
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
KS = {'D1i': 2.5, 'D1j': 2.75}

def params(k, Weff, Wpx, Lpx=None, boost=1.0):
    """Weff: construction unit in px (sets D); Wpx: drawn shaft width (int)."""
    L = Lpx if Lpx else PHI**4 * Weff
    D = PHI**k * Weff * boost
    d = D / PHI**2
    S = max(4, round(L - D))
    t = max(1, round(S / PHI**3)); g = max(1, round(S / PHI**4))
    plain = S - 2*t - g
    if plain < 1: t -= 1; plain = S - 2*t - g
    return Wpx, D, d, plain, t, g, Wpx

def tray(k, size, color):
    if size in (16, 18):   # W=2px, total length 16px (same rule as D1h 16px)
        W, D, d, plain, t, g, h = params(k, 16 / PHI**4, 2, Lpx=16)
    else:
        Wpx = {22: 3, 24: 3, 32: 4, 36: 5, 44: 6, 64: 9}[size]
        W, D, d, plain, t, g, h = params(k, Wpx, Wpx)
    S = plain + 2*t + g; L = D + S
    ax = size/2 if W % 2 == 0 else size//2 + 0.5
    tip = round((size + L) / 2)
    m = key_mask(size, W, D, d, plain, t, g, h, ax, tip)
    im = Image.new('RGBA', (size, size), color + (0,)); im.putalpha(m)
    return im, (W, round(D, 2), round(d, 2), plain, t, g, h)

APP = {   # name: (size, Wpx, Ltarget, axis_x, tip_y, base)
    'mac_16': (16, 2, 10.6, 8.0, 13, 'app_mac_small.svg'),
    'mac_32': (32, 3, 21.0, 16.5, 26, 'app_mac_small.svg'),
    'square_16': (16, 2, 12.4, 8.0, 14, 'app_square_small.svg'),
    'square_32': (32, 3, 23.0, 16.5, 28, 'app_square_small.svg'),
}
def app(kind, name):
    k = KS[kind]
    size, Wpx, L, ax, tip, base = APP[name]
    W, D, d, plain, t, g, h = params(k, L / PHI**4, Wpx, Lpx=L)
    src = os.path.join(ROOT, f'concept_{kind}_src')
    svg = open(os.path.join(src, base)).read()
    svg = re.sub(r'\n\s*<path d="[^"]*" fill="url\(#metal\)"[^>]*/>', '', svg)
    png = subprocess.run(['resvg', '-', '-c', '-w', str(size), '-h', str(size)], input=svg.encode(), capture_output=True, check=True).stdout
    bg = Image.open(io.BytesIO(png)).convert('RGBA')
    m = key_mask(size, W, D, d, plain, t, g, h, ax, tip)
    S = plain + 2*t + g
    bg.alpha_composite(metal(size, m, tip - S - D, tip))
    return bg, (W, round(D, 2), round(d, 2), plain, t, g, h)

if __name__ == '__main__':
    for kind in (sys.argv[1:] or KS):
        out = os.path.join(ROOT, f'concept_{kind}_src', 'px'); os.makedirs(out, exist_ok=True)
        for s in (16, 18, 22, 24, 32, 36, 44, 64):
            im, p = tray(KS[kind], s, (0, 0, 0)); im.save(os.path.join(out, f'tray_{s}_template_black.png'))
            tray(KS[kind], s, (255, 255, 255))[0].save(os.path.join(out, f'tray_{s}_white.png'))
            print(kind, 'tray', s, p)
        for n in APP:
            im, p = app(kind, n); im.save(os.path.join(out, f'app_{n}.png')); print(kind, n, p)
