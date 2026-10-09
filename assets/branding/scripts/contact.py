"""Contact sheet of every exported raster (+ ICO/ICNS frames)."""
import os, io, sys, struct
from PIL import Image, ImageDraw, ImageFont
EXP = os.path.abspath(sys.argv[1]); OUTP = sys.argv[2]
F = lambda s, b=False: ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans%s.ttf' % ('-Bold' if b else ''), s)
W = 2400; im = Image.new('RGBA', (W, 7000), '#ececef'); dr = ImageDraw.Draw(im)
y = 20
dr.text((30, y), 'Key Core D1j — export contact sheet (all outputs at native pixel size)', fill='#111', font=F(36, True)); y += 70
def row(title, items, bg='#f7f7f8', fg='#222', h=None):
    global y
    dr.text((30, y), title, fill='#111', font=F(24, True)); y += 36
    hh = h or max(i.height for _, i in items) + 40
    dr.rectangle([30, y, W - 30, y + hh], fill=bg)
    x = 46
    for lab, i in items:
        if x + i.width > W - 40: break
        im.alpha_composite(i, (x, y + 8)); dr.text((x, y + 12 + i.height), lab, fill=fg, font=F(14)); x += max(i.width, int(dr.textlength(lab, font=F(14)))) + 22
    y += hh + 22
def L(p): return Image.open(os.path.join(EXP, p)).convert('RGBA')
mac = [(f'{s}', L(f'macos/AppIcon.appiconset/app_icon_{s}.png')) for s in (512, 256, 128, 64, 32, 16)]
row('macOS AppIcon.appiconset (app_icon_N.png) — light', mac)
row('macOS AppIcon.appiconset — dark', mac, '#1d1d1f', '#ddd')
# icns frames
d = open(os.path.join(EXP, 'macos/AppIcon.icns'), 'rb').read(); i = 8; fr = []
while i < len(d):
    t = d[i:i+4].decode(); l = struct.unpack('>I', d[i+4:i+8])[0]; fi = Image.open(io.BytesIO(d[i+8:i+l])).convert('RGBA')
    if fi.width <= 256: fr.append((f'{t} {fi.width}', fi))
    i += l
row('AppIcon.icns frames (≤256 shown; ic09/ic10/ic14 = 512/1024/512 also present)', fr)
st = [('StatusBarIcon 18 (1x)', L('macos/StatusBarIcon.imageset/StatusBarIcon.png')), ('StatusBarIcon@2x 36', L('macos/StatusBarIcon.imageset/StatusBarIcon@2x.png'))]
row('macOS StatusBarIcon.imageset (template) — on light menu bar', st, '#e8e8ea', '#222')
def ico_frames(p):
    ic = Image.open(os.path.join(EXP, p)); out = []
    for s in sorted(ic.info['sizes']):
        ic.size = s; ic.load(); out.append((f'{s[0]}', ic.copy().convert('RGBA')))
    return out
row('Windows app_icon.ico frames — light', ico_frames('windows/app_icon.ico'), '#f3f3f3')
row('Windows app_icon.ico frames — dark', ico_frames('windows/app_icon.ico'), '#202020', '#ddd')
row('Windows tray_icon_white.ico (= assets/icons/app_icon.ico) — dark taskbar', ico_frames('windows/tray_icon_white.ico'), '#1c1c1c', '#ddd')
row('Windows tray_icon_black.ico — light taskbar', ico_frames('windows/tray_icon_black.ico'), '#f3f3f3')
lx = [(f'{s}', L(f'linux/hicolor/{s}x{s}/apps/key-core.png')) for s in (512, 256, 128, 64, 48, 32, 24, 22, 16)]
row('Linux hicolor/NxN/apps/key-core.png', lx)
tw = [(f'{s}', L(f'tray/tray_white_{s}.png')) for s in (16, 18, 22, 24, 32, 36, 44, 64)] + [('assets/icons/app_icon.png', L('app/assets/icons/app_icon.png'))]
row('Tray PNG — white (dark panels)', tw, '#2a2a2c', '#ddd')
tb = [(f'{s}', L(f'tray/tray_black_{s}.png')) for s in (16, 18, 22, 24, 32, 36, 44, 64)]
row('Tray PNG — black / template (light panels)', tb, '#e8e8ea')
ia = [('assets/images/app_about.png 256', L('app/assets/images/app_about.png')), ('assets/icons/icon.png 1224 (shown at 1/4)', L('app/assets/icons/icon.png').resize((306, 306), Image.LANCZOS))]
row('In-app images', ia)
z = []
for lab, p in (('mac 16', 'macos/AppIcon.appiconset/app_icon_16.png'), ('mac 32', 'macos/AppIcon.appiconset/app_icon_32.png'), ('linux/win 16', 'linux/hicolor/16x16/apps/key-core.png'), ('linux/win 32', 'linux/hicolor/32x32/apps/key-core.png'), ('tray 16', 'tray/tray_black_16.png'), ('status bar 18', 'macos/StatusBarIcon.imageset/StatusBarIcon.png')):
    a = L(p); b = Image.new('RGBA', a.size, '#f7f7f8'); b.alpha_composite(a); z.append((lab + ' ×8', b.resize((a.width*8, a.height*8), Image.NEAREST)))
row('Pixel zoom ×8 (pixel-snapped small sizes)', z)
im = im.crop((0, 0, W, y + 10)); im.convert('RGB').save(OUTP, optimize=True); print(OUTP, im.size)
