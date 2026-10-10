# 生成 Mac App Store 截图（2880x1800）与宣传图。用法：python3 compose.py
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import os
RAW = '.'
OUT = '.'
ICON = '/workspace/key-core-ui/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png'
W, H = 2880, 1800
CJK_B = '/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc'
CJK_R = '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'

def font(bold, size, lang):
    return ImageFont.truetype(CJK_B if bold else CJK_R, size, index=2 if lang.startswith('zh') else 0)

COPY = {
 'zh-Hans': [
  ('01_keys', '一处管理所有大模型密钥', 'DeepSeek、通义千问、智谱、Kimi、豆包……卡片化收纳，一目了然'),
  ('02_tool_lens', '一键切换编程工具的当前密钥', '按工具查看正在使用的密钥，点一下即写入配置'),
  ('03_add_key', '国内主流大模型平台预设', '搜索平台，请求地址与模型自动填好'),
  ('04_drawer', '一把密钥，多处启用', '在详情里查看它用在哪些工具，设为当前或写入配置'),
  ('05_mcp_enable', '集中管理 MCP 服务', '按工具启用，一次配置同步到多个编程工具'),
  ('06_mcp_sync', 'MCP 同步，差异一目了然', '逐项对比、勾选推送或拉取，敏感字段自动打码'),
  ('07_skills', 'Skills 统一管理', '卡片浏览、分类筛选，同步到各个编程工具'),
  ('08_security', '主密码加密，数据只在本机', '密钥加密存储，不上传、不追踪'),
 ],
 'en': [
  ('01_keys', 'All your LLM API keys, in one place', 'DeepSeek, Qwen, GLM, Kimi, Doubao and more — organized as clean cards'),
  ('02_tool_lens', 'Switch keys for your coding tools', 'See the active key per tool and switch it in one click'),
  ('03_add_key', 'Ready-made platform presets', 'Search a platform and the base URL and models are filled in for you'),
  ('04_drawer', 'One key, every tool', 'See where a key is used, set it as current or write it to a tool config'),
  ('05_mcp_enable', 'Manage MCP servers centrally', 'Enable per tool and sync one config to several coding tools'),
  ('06_mcp_sync', 'MCP sync with clear diffs', 'Compare item by item, push or pull selectively, secrets masked'),
  ('07_skills', 'All your Skills, organized', 'Browse, filter by category and sync to your coding tools'),
  ('08_security', 'Encrypted. Local only.', 'Protect keys with a master password — nothing uploaded, no tracking'),
 ],
}

def background():
    bg = Image.new('RGB', (W, H))
    d = ImageDraw.Draw(bg)
    top, bot = (44, 46, 52), (12, 12, 14)
    for y in range(H):
        t = y / H
        d.line([(0, y), (W, y)], fill=tuple(int(top[i] * (1 - t) + bot[i] * t) for i in range(3)))
    glow = Image.new('L', (W, H), 0)
    ImageDraw.Draw(glow).ellipse((W * 0.15, -H * 0.35, W * 0.85, H * 0.55), fill=70)
    glow = glow.filter(ImageFilter.GaussianBlur(220))
    bg = Image.composite(Image.new('RGB', (W, H), (150, 156, 168)), bg, glow)
    return bg

# macOS 构建（MainFlutterWindow.layoutTrafficLights）：按钮 14×16，y = floor((52−16)/2) = 18，x = y+1 = 19，步长 20；
# 圆点直径 12、中心 (x+7, y+8) → 逻辑坐标 (26,26)/(46,26)/(66,26)，2x 后 (52,52)/(92,52)/(132,52)，半径 12。
# 原始截图用 KC_FORCE_MAC_CHROME 构建（macOS 布局：侧栏/页头左侧预留 96px），红绿灯直接画在应用自身顶部，不加额外标题条。
def window(raw):
    win = Image.open(raw).convert('RGB')
    d = ImageDraw.Draw(win)
    for i, c in enumerate([(255, 95, 87), (254, 188, 46), (40, 200, 64)]):
        cx, cy, r = 52 + i * 40, 52, 12
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=c, outline=tuple(max(0, v - 35) for v in c), width=1)
    return win

def place(bg, win, width, top):
    s = width / win.width
    win = win.resize((width, int(win.height * s)), Image.LANCZOS)
    rad = 26
    mask = Image.new('L', win.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, win.width - 1, win.height - 1), rad, fill=255)
    x = (W - win.width) // 2
    sh = Image.new('L', (W, H), 0)
    ImageDraw.Draw(sh).rounded_rectangle((x, top + 30, x + win.width, top + win.height + 30), rad, fill=170)
    sh = sh.filter(ImageFilter.GaussianBlur(50))
    bg.paste(Image.new('RGB', (W, H), (0, 0, 0)), (0, 0), sh)
    bg.paste(win, (x, top), mask)
    ImageDraw.Draw(bg).rounded_rectangle((x, top, x + win.width - 1, top + win.height - 1), rad, outline=(90, 92, 98), width=2)

def text(bg, lang, head, sub, y=110):
    d = ImageDraw.Draw(bg)
    f1, f2 = font(True, 104, lang), font(False, 50, lang)
    w = d.textlength(head, font=f1); d.text(((W - w) / 2, y), head, font=f1, fill=(245, 246, 248))
    w = d.textlength(sub, font=f2); d.text(((W - w) / 2, y + 150), sub, font=f2, fill=(178, 182, 190))

for lang, items in COPY.items():
    os.makedirs(f'{OUT}/{lang}/screenshots', exist_ok=True)
    for i, (name, head, sub) in enumerate(items, 1):
        bg = background()
        text(bg, lang, head, sub)
        place(bg, window(f"{RAW}/{lang}/raw/{name}.png"), 2040, 410)
        bg.save(f'{OUT}/{lang}/screenshots/{name}.png', optimize=True)

# 宣传主图（hero / poster）
icon = Image.open(ICON).convert('RGBA')
for lang, (head, sub) in {'zh-Hans': ('密枢 keycore', '一处管理所有大模型 API 密钥 · 一键切换编程工具的当前密钥'),
                          'en': ('keycore', 'One home for all your LLM API keys · switch your coding tools in a click')}.items():
    bg = background()
    win = window(f'{RAW}/{lang}/raw/01_keys.png')
    place(bg, win, 1760, 660)
    ic = icon.resize((300, 300), Image.LANCZOS)
    bg.paste(ic, ((W - 300) // 2, 70), ic)
    d = ImageDraw.Draw(bg)
    f1, f2 = font(True, 112, lang), font(False, 52, lang)
    w = d.textlength(head, font=f1); d.text(((W - w) / 2, 380), head, font=f1, fill=(245, 246, 248))
    w = d.textlength(sub, font=f2); d.text(((W - w) / 2, 530), sub, font=f2, fill=(178, 182, 190))
    bg.save(f'{OUT}/{lang}/hero_2880x1800.png', optimize=True)
