"""Render preview sheets concept_X.png using resvg + PIL."""
import os, subprocess, sys, io
from PIL import Image, ImageDraw, ImageFont
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
F = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
FB = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
font = lambda s, b=False: ImageFont.truetype(FB if b else F, s)

def render(svg, px):
    base, dn = os.path.basename(svg), os.path.dirname(svg)
    if base.startswith('tray_'):
        f = os.path.join(dn, 'px', f"tray_{px}_{'template_black' if 'black' in base else 'white'}.png")
        if os.path.exists(f): return Image.open(f).convert('RGBA')
    if base in ('app_mac_small.svg', 'app_square_small.svg'):
        f = os.path.join(dn, 'px', f"app_{base.split('_')[1]}_{px}.png")
        if os.path.exists(f): return Image.open(f).convert('RGBA')
    if px == 16 and os.path.basename(svg).startswith('tray_'):
        snap = svg.replace('tray_template_black.svg', 'tray_16_template_black.png').replace('tray_white.svg', 'tray_16_white.png')
        if os.path.exists(snap):     # hand pixel-snapped 16px glyph
            return Image.open(snap).convert('RGBA')
    if os.path.basename(svg).startswith('tray_'):
        name = 'template_black' if 'black' in svg else 'white'
        snap = os.path.join(os.path.dirname(svg), 'tray_px', f'tray_{px}_{name}.png')
        if os.path.exists(snap):     # pixel-aligned render
            return Image.open(snap).convert('RGBA')
    out = subprocess.run(['resvg', svg, '-c', '-w', str(px), '-h', str(px)], capture_output=True, check=True).stdout
    return Image.open(io.BytesIO(out)).convert('RGBA')

def zoom(im, k): return im.resize((im.width*k, im.height*k), Image.NEAREST)

NAMES = {'D1i': 'D1i · Golden-ratio Key, bow D = φ^2.5·W (~39%)', 'D1j': 'D1j · Golden-ratio Key, bow D = φ^2.75·W (~44%)', 'D1h': 'D1h · Golden-ratio Key, bow-dominant (vertical)', 'D1g': 'D1g · Golden-ratio Graphite Key (vertical)', 'D1': 'D1 · Graphite Key, round hole (vertical)', 'D2': 'D2 · Graphite Key, hex hole (vertical)', 'A': 'A · Graphite Hex Key', 'B': 'B · Black & Gold Core Key', 'C': 'C · Frost Key on Brushed Slate'}

def sheet(kind):
    d = os.path.join(ROOT, f'concept_{kind}_src')
    svg = lambda n: os.path.join(d, n)
    W, H = 2420, 2060
    im = Image.new('RGBA', (W, H), '#e9e9ec')
    dr = ImageDraw.Draw(im)
    dr.text((40, 24), f'Key Core icon — concept {NAMES[kind]}', fill='#111', font=font(40, True))
    # hero 1024 on split light/dark
    hero_bg = Image.new('RGBA', (1104, 1104), '#f5f5f7')
    ImageDraw.Draw(hero_bg).rectangle([552, 0, 1104, 1104], fill='#1d1d1f')
    hero_bg.alpha_composite(render(svg('app_mac.svg'), 1024), (40, 40))
    im.alpha_composite(hero_bg, (40, 90))
    dr.text((40, 1200), 'macOS 1024 (824 grid + shadow) on light / dark', fill='#333', font=font(22))

    x0 = 1180
    def row(y, label, file_big, file_small, sizes, bg, fg):
        dr.rectangle([x0, y, W-40, y+590 if sizes[0] == 512 else y+300], fill=bg)
        dr.text((x0+16, y+10), label, fill=fg, font=font(22, True))
        x = x0 + 16
        for s in sizes:
            f = file_small if s <= 32 else file_big
            ic = render(svg(f), s)
            yy = y + 44 + (sizes[0]-s if sizes[0] == 512 else (256 - s)) // 1 if False else y + 44
            im.alpha_composite(ic, (x, y + 44))
            dr.text((x, y + 44 + s + 6), f'{s}', fill=fg, font=font(18))
            x += s + 18
        return x
    row(90, 'macOS sizes — light', 'app_mac.svg', 'app_mac_small.svg', [512, 256, 128, 64, 32, 16], '#f5f5f7', '#222')
    row(690, 'macOS sizes — dark', 'app_mac.svg', 'app_mac_small.svg', [512, 256, 128, 64, 32, 16], '#1d1d1f', '#ddd')
    # windows / linux square variant
    y = 1290
    dr.rectangle([x0, y, W-40, y+330], fill='#f3f3f3')
    dr.text((x0+16, y+10), 'Windows / Linux (rounded-square variant) — light | dark', fill='#222', font=font(22, True))
    x = x0 + 16
    for s in [256, 128, 64, 48, 32, 24, 16]:
        f = 'app_square_small.svg' if s <= 32 else 'app_square.svg'
        im.alpha_composite(render(svg(f), s), (x, y + 44)); dr.text((x, y+44+s+4), str(s), fill='#222', font=font(16)); x += s + 14
    dr.rectangle([x, y+40, W-40, y+330], fill='#202020')
    x += 14
    for s in [64, 48, 32, 24, 16]:
        f = 'app_square_small.svg' if s <= 32 else 'app_square.svg'
        im.alpha_composite(render(svg(f), s), (x, y + 44)); dr.text((x, y+44+s+4), str(s), fill='#ddd', font=font(16)); x += s + 14
    # pixel zooms
    y = 1630
    dr.text((x0+16, y), 'pixel zoom ×6: app mac 16, 32 | app win/linux 16, 32 | tray 16, 22', fill='#333', font=font(20, True))
    x = x0 + 16
    for f, s in [('app_mac_small.svg', 16), ('app_mac_small.svg', 32), ('app_square_small.svg', 16), ('app_square_small.svg', 32), ('tray_template_black.svg', 16), ('tray_template_black.svg', 22)]:
        z = 6
        bgc = Image.new('RGBA', (s*z, s*z), '#f5f5f7'); bgc.alpha_composite(zoom(render(svg(f), s), z))
        im.alpha_composite(bgc, (x, y + 34)); x += s*z + 20

    # tray mocks
    y = 1260
    dr.text((40, y), 'Tray / menu-bar glyph (template black, white for dark) @16 / 22 / 32 px, + ×3 zoom', fill='#333', font=font(22, True))
    bars = [('macOS menu bar — light', '#e8e8ea', '#000', 'tray_template_black.svg'),
            ('macOS menu bar — dark', '#2a2a2c', '#fff', 'tray_white.svg'),
            ('Windows taskbar — dark', '#1c1c1c', '#fff', 'tray_white.svg'),
            ('Windows / Linux panel — light', '#f0f0f0', '#000', 'tray_template_black.svg')]
    yy = y + 40
    for label, bg, fg, f in bars:
        bar = Image.new('RGBA', (360, 40), bg)
        bd = ImageDraw.Draw(bar)
        x = 12
        for s in (16, 22, 32):
            bar.alpha_composite(render(svg(f), s), (x, (40 - s)//2)); x += s + 14
        # fake neighbours: battery + clock
        bd.rounded_rectangle([x+20, 14, x+44, 26], 3, outline=fg, width=1); bd.rectangle([x+22, 16, x+36, 24], fill=fg)
        bd.text((x+60, 11), 'Fri 22:31', fill=fg, font=font(14))
        im.alpha_composite(bar, (40, yy))
        im.alpha_composite(zoom(bar.crop((0, 0, 130, 40)), 3), (420, yy - 40 if False else yy))
        dr.text((40, yy + 44), label, fill='#333', font=font(16))
        yy += 180
    return im

if __name__ == '__main__':
    for k in sys.argv[1:] or ['A', 'B', 'C', 'D1', 'D2']:
        sheet(k).convert('RGB').save(os.path.join(ROOT, f'concept_{k}.png'), optimize=True)
        print('saved', k)
