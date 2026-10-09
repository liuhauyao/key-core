"""Full export of the chosen design (D1j) for macOS / Windows / Linux / tray / in-app assets."""
import os, io, sys, json, struct, shutil, subprocess
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
CONCEPTS = os.path.abspath(os.path.join(HERE, '..'))
KIND = os.environ.get('KIND', 'D1j')
SRC = os.path.join(CONCEPTS, f'concept_{KIND}_src')
PX = os.path.join(SRC, 'px')
OUT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(CONCEPTS, '..', 'export'))

def svg(name, size):
    data = subprocess.run(['resvg', os.path.join(SRC, name), '-c', '-w', str(size), '-h', str(size)],
                          capture_output=True, check=True).stdout
    im = Image.open(io.BytesIO(data)).convert('RGBA'); assert im.size == (size, size); return im

def px(name):
    im = Image.open(os.path.join(PX, name)).convert('RGBA'); return im

def mac_app(size):        # macOS grid (824 squircle + shadow); 16/32 pixel-snapped
    if size in (16, 32): return px(f'app_mac_{size}.png')
    return svg('app_mac.svg', size)

def square_app(size):     # Windows / Linux rounded-square variant
    if size in (16, 32): return px(f'app_square_{size}.png')
    if size < 40: return svg('app_square_small.svg', size)
    return svg('app_square.svg', size)

def tray(size, color):
    p = os.path.join(PX, f'tray_{size}_{color}.png')
    if os.path.exists(p): return Image.open(p).convert('RGBA')
    # fallback: render vector tray glyph
    return svg('tray_template_black.svg' if color == 'template_black' else 'tray_white.svg', size)

def save(im, *parts):
    p = os.path.join(OUT, *parts); os.makedirs(os.path.dirname(p), exist_ok=True); im.save(p, optimize=True); return p

def write_icns(path, images):
    """images: dict type->PIL image. Writes PNG-based icns."""
    chunks = b''
    for t, im in images.items():
        b = io.BytesIO(); im.save(b, 'PNG'); data = b.getvalue()
        chunks += t.encode() + struct.pack('>I', len(data) + 8) + data
    open(path, 'wb').write(b'icns' + struct.pack('>I', len(chunks) + 8) + chunks)

def main():
    if os.path.exists(OUT): shutil.rmtree(OUT)
    # ---------------- macOS ----------------
    sizes = [16, 32, 64, 128, 256, 512, 1024]
    for s in sizes: save(mac_app(s), 'macos', 'AppIcon.appiconset', f'app_icon_{s}.png')
    contents = {"images": [], "info": {"version": 1, "author": "xcode"}}
    for pt in (16, 32, 128, 256, 512):
        for sc in (1, 2):
            contents["images"].append({"size": f"{pt}x{pt}", "idiom": "mac", "filename": f"app_icon_{pt*sc}.png", "scale": f"{sc}x"})
    open(os.path.join(OUT, 'macos', 'AppIcon.appiconset', 'Contents.json'), 'w').write(json.dumps(contents, indent=2) + '\n')
    iconset = {}
    for pt in (16, 32, 128, 256, 512):
        for sc in (1, 2):
            name = f'icon_{pt}x{pt}' + ('@2x' if sc == 2 else '') + '.png'
            iconset[name] = mac_app(pt*sc); save(iconset[name], 'macos', 'AppIcon.iconset', name)
    write_icns(os.path.join(OUT, 'macos', 'AppIcon.icns'), {
        'icp4': mac_app(16), 'icp5': mac_app(32), 'icp6': mac_app(64), 'ic07': mac_app(128), 'ic08': mac_app(256),
        'ic09': mac_app(512), 'ic10': mac_app(1024), 'ic11': mac_app(32), 'ic12': mac_app(64), 'ic13': mac_app(256),
        'ic14': mac_app(512)})
    save(tray(18, 'template_black'), 'macos', 'StatusBarIcon.imageset', 'StatusBarIcon.png')
    save(tray(36, 'template_black'), 'macos', 'StatusBarIcon.imageset', 'StatusBarIcon@2x.png')
    open(os.path.join(OUT, 'macos', 'StatusBarIcon.imageset', 'Contents.json'), 'w').write(json.dumps({
        "images": [{"idiom": "universal", "filename": "StatusBarIcon.png", "scale": "1x"},
                   {"idiom": "universal", "filename": "StatusBarIcon@2x.png", "scale": "2x"},
                   {"idiom": "universal", "scale": "3x"}],
        "info": {"version": 1, "author": "xcode"},
        "properties": {"template-rendering-intent": "template"}}, indent=2) + '\n')
    # ---------------- Windows ----------------
    wsizes = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256]
    os.makedirs(os.path.join(OUT, 'windows'), exist_ok=True)
    imgs = [square_app(s) for s in wsizes]
    imgs[-1].save(os.path.join(OUT, 'windows', 'app_icon.ico'), format='ICO', sizes=[(s, s) for s in wsizes],
                  append_images=imgs[:-1], bitmap_format='bmp')
    tsizes = [16, 20, 24, 32, 40, 48]
    for color, tag in (('white', 'white'), ('template_black', 'black')):
        ti = [tray(s, color) if s not in (20, 40) else None for s in tsizes]
        # 20/40: centre the 18/36 glyphs on a 20/40 canvas (keeps pixel snapping)
        for i, s in enumerate(tsizes):
            if ti[i] is None:
                base = tray({20: 18, 40: 36}[s], color); c = Image.new('RGBA', (s, s), (0, 0, 0, 0)); c.alpha_composite(base, (1, 1) if s == 20 else (2, 2)); ti[i] = c
        ti[-1].save(os.path.join(OUT, 'windows', f'tray_icon_{tag}.ico'), format='ICO', sizes=[(s, s) for s in tsizes],
                    append_images=ti[:-1], bitmap_format='bmp')
    # ---------------- Linux ----------------
    for s in (16, 22, 24, 32, 48, 64, 128, 256, 512):
        save(square_app(s), 'linux', 'hicolor', f'{s}x{s}', 'apps', 'key-core.png')
    d = os.path.join(OUT, 'linux', 'hicolor', 'scalable', 'apps'); os.makedirs(d, exist_ok=True)
    shutil.copy(os.path.join(SRC, 'app_square.svg'), os.path.join(d, 'key-core.svg'))
    open(os.path.join(OUT, 'linux', 'key-core.desktop'), 'w').write(
        "[Desktop Entry]\nType=Application\nName=Key Core\nName[zh_CN]=密枢\nComment=API key manager for AI coding tools\n"
        "Comment[zh_CN]=AI 编程工具 API 密钥管理器\nExec=key_core\nIcon=key-core\nTerminal=false\nCategories=Utility;Security;Development;\n"
        "StartupWMClass=key_core\n")
    # ---------------- tray PNGs ----------------
    for s in (16, 18, 22, 24, 32, 36, 44, 64):
        for color, tag in (('white', 'white'), ('template_black', 'black')):
            save(tray(s, color), 'tray', f'tray_{tag}_{s}.png')
    # ---------------- in-app ----------------
    icon = Image.new('RGBA', (1224, 1224), (0, 0, 0, 0)); icon.alpha_composite(mac_app(1024), (100, 100))
    save(icon, 'app', 'assets', 'icons', 'icon.png')
    save(mac_app(256), 'app', 'assets', 'images', 'app_about.png')
    save(tray(64, 'white'), 'app', 'assets', 'icons', 'app_icon.png')          # Linux tray (dark panels)
    shutil.copy(os.path.join(OUT, 'windows', 'tray_icon_white.ico'), os.path.join(OUT, 'app', 'assets', 'icons', 'app_icon.ico'))
    # ---------------- masters ----------------
    m = os.path.join(OUT, 'source'); os.makedirs(m, exist_ok=True)
    for f in os.listdir(SRC):
        if f.endswith('.svg'): shutil.copy(os.path.join(SRC, f), os.path.join(m, f))
    print('exported to', OUT)

if __name__ == '__main__':
    main()
