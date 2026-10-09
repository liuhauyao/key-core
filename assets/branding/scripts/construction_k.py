"""Construction diagram for D1g golden-ratio key."""
import os, sys, subprocess
sys.path.insert(0, os.path.dirname(__file__))
from geom import key_K, key_K_spec, to_path, PHI
KIND = sys.argv[1]; K = {'D1i': 2.5, 'D1j': 2.75}[KIND]; KS = {2.5: '2.5', 2.75: '2.75'}[K]
key_G = lambda W: key_K(K, W); key_G_spec = lambda W: key_K_spec(K, W)
from shapely import affinity
from PIL import Image
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
W = 108.0
sq = key_G_spec(1.0); PX = 667 / sq['L']
s = key_G_spec(W)
AX, CY = 640, 420                     # axis x, bow centre y
k = affinity.translate(key_G(W), AX, CY)
R = s['D']/2
top, tip = CY - R, CY + s['y_tip']
yb, yblk = CY + s['y_bow_bottom'], CY + s['y_block']
xl, xr = AX - W/2, AX + W/2
xt = xl - s['h']
(t1a, t1b), (t2a, t2b) = [(CY+a, CY+b) for a, b in s['teeth']]
G = '#c8932a'   # guide colour (gold)
B = '#2563eb'   # dimension colour
F = "font-family='DejaVu Sans'"
FC = "font-family='Noto Serif CJK SC, Noto Serif CJK JP, DejaVu Sans'"

def dimV(x, y1, y2, label, side=1, col=B):
    tx = x + 14*side
    anchor = 'start' if side > 0 else 'end'
    return (f"<line x1='{x}' y1='{y1}' x2='{x}' y2='{y2}' stroke='{col}' stroke-width='2' marker-start='url(#a{col[1:]})' marker-end='url(#a{col[1:]})'/>"
            f"<line x1='{x-10}' y1='{y1}' x2='{x+10}' y2='{y1}' stroke='{col}' stroke-width='1.5'/><line x1='{x-10}' y1='{y2}' x2='{x+10}' y2='{y2}' stroke='{col}' stroke-width='1.5'/>"
            f"<text x='{tx}' y='{(y1+y2)/2+8}' {F} font-size='24' fill='{col}' text-anchor='{anchor}'>{label}</text>")
def dimH(y, x1, x2, label, col=B, dy=-12):
    return (f"<line x1='{x1}' y1='{y}' x2='{x2}' y2='{y}' stroke='{col}' stroke-width='2' marker-start='url(#a{col[1:]})' marker-end='url(#a{col[1:]})'/>"
            f"<line x1='{x1}' y1='{y-10}' x2='{x1}' y2='{y+10}' stroke='{col}' stroke-width='1.5'/><line x1='{x2}' y1='{y-10}' x2='{x2}' y2='{y+10}' stroke='{col}' stroke-width='1.5'/>"
            f"<text x='{(x1+x2)/2}' y='{y+dy}' {F} font-size='24' fill='{col}' text-anchor='middle'>{label}</text>")
def guideH(y, x1=180, x2=1060, col=G, dash='8 6'):
    return f"<line x1='{x1}' y1='{y}' x2='{x2}' y2='{y}' stroke='{col}' stroke-width='1.5' stroke-dasharray='{dash}'/>"
def guideV(x, y1=120, y2=1290, col=G, dash='8 6'):
    return f"<line x1='{x}' y1='{y1}' x2='{x}' y2='{y2}' stroke='{col}' stroke-width='1.5' stroke-dasharray='{dash}'/>"

# unit grid (W/2 squares) behind the key
grid = ''.join(f"<line x1='{AX + i*W/2}' y1='120' x2='{AX + i*W/2}' y2='1290' stroke='#e3e5ea' stroke-width='1'/>" for i in range(-9, 10))
grid += ''.join(f"<line x1='180' y1='{top + j*W/2}' x2='1100' y2='{top + j*W/2}' stroke='#e3e5ea' stroke-width='1'/>" for j in range(-2, 19))

rows = [
 ('W', 'shaft width (unit)', '1'),
 (f'D = φ^{KS}·W', 'bow outer diameter', f"{sq['D']:.3f} W"),
 ('d = D/φ²', 'hole diameter', f"{sq['d']:.3f} W"),
 ('L = φ⁴·W', 'total length (same as D1g / D1h)', f"{sq['L']:.3f} W"),
 ('S = L − D', 'shaft below bow', f"{sq['S']:.3f} W"),
 ('S/φ²  |  S/φ', 'plain shaft | teeth block (golden section)', f"{sq['plain']:.3f} : {sq['S']/PHI:.3f} W"),
 ('t = S/φ³', 'tooth width', f"{sq['t']:.3f} W"),
 ('g = S/φ⁴', 'gap   (t : g = φ : 1, 2t+g = S/φ)', f"{sq['g']:.3f} W"),
 ('h = W', 'tooth protrusion', '1 W'),
 ('D : S', 'bow vs shaft', f"{sq['D']/sq['S']:.3f}"),
 ('D / squircle', 'bow share of 824 squircle width', f"{sq['D']*PX/824*100:.1f}%  ({sq['D']*PX:.0f}px)"),
 ('k: g=2 · i=2.5 · j=2.75 · h=3', 'D = φ^k·W, evenly spaced in log scale', ''),
]
tbl = f"<text x='1290' y='190' {F} font-size='30' font-weight='bold' fill='#111'>Golden-ratio construction   φ = (1+√5)/2 ≈ 1.618</text>"
tbl += f"<text x='1290' y='232' {FC} font-size='24' fill='#444'>所有尺寸均由杆宽 W 与 φ 推导；齿为纯矩形，对齐 W/2 网格</text>"
y = 290
for a, b, c in rows:
    tbl += (f"<text x='1290' y='{y}' {F} font-size='25' fill='#111' font-weight='bold'>{a}</text>"
            f"<text x='1290' y='{y+30}' {F} font-size='20' fill='#555'>{b}</text>"
            f"<text x='2140' y='{y}' {F} font-size='25' fill='{B}' text-anchor='end'>{c}</text>")
    y += 70

svg = f"""<svg xmlns='http://www.w3.org/2000/svg' width='2180' height='1340' viewBox='0 0 2180 1340'>
<defs>
 <marker id='a{B[1:]}' viewBox='0 0 10 10' refX='5' refY='5' markerWidth='7' markerHeight='7' orient='auto-start-reverse'><path d='M0 1 L9 5 L0 9 z' fill='{B}'/></marker>
 <marker id='a{G[1:]}' viewBox='0 0 10 10' refX='5' refY='5' markerWidth='7' markerHeight='7' orient='auto-start-reverse'><path d='M0 1 L9 5 L0 9 z' fill='{G}'/></marker>
</defs>
<rect width='2180' height='1340' fill='#f7f7f8'/>
<text x='40' y='60' {F} font-size='36' font-weight='bold' fill='#111'>Key Core — {KIND} construction (D = φ^{KS}·W)</text>
<text x='40' y='98' {FC} font-size='24' fill='#555'>竖直钥匙 · 黄金比例 φ 构造 · 钥匙环介于 D1g 与 D1h 之间（单位 W = 杆宽）</text>
{grid}
<path d='{to_path(k)}' fill='#d3d6dc' stroke='#1f2937' stroke-width='2.5' fill-rule='evenodd'/>
{guideV(AX, col='#9ca3af', dash='14 6 3 6')}
<circle cx='{AX}' cy='{CY}' r='{R}' fill='none' stroke='{G}' stroke-width='1.5' stroke-dasharray='8 6'/>
{guideH(top)}{guideH(yb)}{guideH(yblk, col='#dc2626', dash='10 5')}{guideH(tip)}
{guideH(t1b, 300, 640)}{guideH(t2a, 300, 640)}
{guideV(xl, yb, tip + 30)}{guideV(xr, yb, tip + 30)}
<text x='186' y='{yblk - 10}' {F} font-size='22' fill='#dc2626'>golden section of S  (S/φ² above · S/φ below)</text>
{dimH(CY - R - 34, AX - R, AX + R, f'D = φ^{KS}W')}
{dimH(CY, AX - s['d']/2, AX + s['d']/2, 'd = D/φ²', dy=-14)}
{dimH(tip + 60, xl, xr, 'W')}
{dimH(tip + 60, xt, xl, 'h = W', dy=36)}
{dimV(AX + R + 70, top, yb, 'D')}
{dimV(AX + R + 70, yb, yblk, 'S/φ²')}
{dimV(AX + R + 70, yblk, tip, 'S/φ')}
{dimV(AX + R + 200, yb, tip, 'S = L − D')}
{dimV(AX + R + 300, top, tip, 'L = φ⁴W')}
{dimV(xt - 40, t1a, t1b, 't = S/φ³', side=-1)}
{dimV(xt - 40, t1b, t2a, 'g = S/φ⁴', side=-1, col='#dc2626')}
{dimV(xt - 40, t2a, t2b, 't', side=-1)}
{tbl}
</svg>"""
# fix marker for red dims (reuse blue arrow markers is fine visually)
svg = svg.replace("url(#adc2626)", f"url(#a{B[1:]})")
out = os.path.join(ROOT, f'concept_{KIND}_src', 'construction.svg')
open(out, 'w').write(svg)
png = os.path.join(ROOT, f'concept_{KIND}_construction.png')
subprocess.run(['resvg', out, png], check=True)
print(png)
