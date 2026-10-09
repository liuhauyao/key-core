"""Key geometry for Key Core icon concepts (shapely -> SVG path)."""
import math
from shapely.geometry import Point, Polygon, box
from shapely.ops import unary_union
from shapely import affinity

def ngon(cx, cy, r, n=6, rot=0.0):
    return Polygon([(cx + r*math.cos(math.radians(rot + 360*i/n)),
                     cy + r*math.sin(math.radians(rot + 360*i/n))) for i in range(n)])

def soften(g, convex=6, concave=6):
    if concave: g = g.buffer(concave, join_style=1).buffer(-concave, join_style=1)
    if convex:  g = g.buffer(-convex, join_style=1).buffer(convex, join_style=1)
    return g

def rounded_ngon(cx, cy, r, n=6, rot=0, rr=20):
    return ngon(cx, cy, r, n, rot).buffer(-rr, join_style=2).buffer(rr, join_style=1)

def place(g, angle, cx, cy, size=None):
    g = affinity.rotate(g, angle, origin=(0, 0))
    minx, miny, maxx, maxy = g.bounds
    if size:
        s = size / max(maxx-minx, maxy-miny)
        g = affinity.scale(g, s, s, origin=(0, 0))
        minx, miny, maxx, maxy = g.bounds
    return affinity.translate(g, cx-(minx+maxx)/2, cy-(miny+maxy)/2)

def to_path(g, nd=2):
    polys = [g] if g.geom_type == 'Polygon' else list(g.geoms)
    out = []
    def ring(c):
        pts = list(c.coords)[:-1]
        return 'M' + ' L'.join(f'{x:.{nd}f} {y:.{nd}f}' for x, y in pts) + ' Z'
    for p in polys:
        out.append(ring(p.exterior))
        out += [ring(i) for i in p.interiors]
    return ' '.join(out)

# ---------------- concept keys (local coords: bow at origin, shaft to +x, teeth to +y) -------------
def key_A(tray=False):
    """Classic round-bow key with hexagonal 'core' cut-out, collar and two bit teeth."""
    t = 64 if tray else 40          # half shaft thickness
    bow = Point(0, 0).buffer(170 if tray else 165, 128)
    hole = rounded_ngon(0, 0, 88 if tray else 80, 6, 0, 10)
    shaft = box(120, -t, 520 if tray else 560, t)
    parts = [bow, shaft]
    if not tray:
        parts.append(box(178, -t-18, 214, t+18))      # collar
        parts += [box(392, t-5, 442, t+92), box(474, t-5, 560, t+128)]
    else:
        parts += [box(330, t-5, 400, t+85), box(440, t-5, 520, t+110)]
    g = soften(unary_union(parts), convex=10 if not tray else 14, concave=10)
    return g.difference(hole)

def key_B(tray=False):
    """Hexagon chip bow (= 'core'), round core hole, straight shaft, stepped teeth."""
    t = 64 if tray else 44
    bow = rounded_ngon(0, 0, 190 if tray else 185, 6, 30, 26)
    hole = Point(0, 0).buffer(78 if tray else 74, 128)
    shaft = box(140, -t, 540 if tray else 590, t)
    if tray:
        teeth = [box(370, t-5, 440, t+95), box(470, t-5, 540, t+70)]
    else:
        teeth = [box(380, t-5, 420, t+70), box(440, t-5, 490, t+110), box(510, t-5, 590, t+80)]
    g = soften(unary_union([bow, shaft] + teeth), convex=10 if not tray else 14, concave=10)
    return g.difference(hole), Point(0, 0).buffer(34, 128)   # (key, core dot)

def key_C(tray=False):
    """Rounded-square 'chip' bow with circular hole + four pin notches, vertical key."""
    t = 74 if tray else 42
    s = 182 if tray else 160
    bow = box(-s, -s, s, s).buffer(-60, join_style=2).buffer(60, join_style=1)
    hole = Point(0, 0).buffer(78 if tray else 70, 128)
    shaft = box(120, -t, 500 if tray else 600, t)
    if tray:
        teeth = [box(340, t-5, 410, t+90), box(430, t-5, 500, t+60)]
        notches = []
    else:
        teeth = [box(420, t-5, 462, t+82), box(482, t-5, 524, t+120), box(544, t-5, 600, t+82)]
        # chip pins as notches on the three free sides of the bow
        notches = []
        for k in (-1, 1):
            notches.append(box(-s-1, k*90-14, -s+26, k*90+14))   # left side
            notches.append(box(k*90-14, -s-1, k*90+14, -s+26))   # top
            notches.append(box(k*90-14, s-26, k*90+14, s+1))     # bottom
    g = soften(unary_union([bow, shaft] + teeth), convex=10 if not tray else 14, concave=10)
    for n in notches: g = g.difference(n)
    return g.difference(hole)

def squircle(cx=512, cy=512, half=412, n=5.0, steps=360):
    pts = []
    for i in range(steps):
        a = 2*math.pi*i/steps
        c, s = math.cos(a), math.sin(a)
        x = half * math.copysign(abs(c)**(2/n), c)
        y = half * math.copysign(abs(s)**(2/n), s)
        pts.append((cx+x, cy+y))
    return 'M' + ' L'.join(f'{x:.2f} {y:.2f}' for x, y in pts) + ' Z'

def continuous_rect(x, y, w, h, r):
    """Apple-style continuous-corner rounded rect (iOS/macOS squircle) as SVG path."""
    a = [(1.52866483, 0), (1.08849323, 0), (0.86840689, 0), (0.66993427, 0.06549600),
         (0.39337051, 0.15616606), (0.15616606, 0.39337051), (0.06549600, 0.66993427),
         (0, 0.86840689), (0, 1.08849323), (0, 1.52866483)]
    # corner pts expressed as (dx from corner along edge-in, dy) for top-right corner
    def corner(cx, cy, sx, sy, swap):
        pts = []
        for u, v in a:
            dx, dy = (v, u) if swap else (u, v)
            pts.append((cx - sx*dx*r, cy + sy*dy*r))
        return pts
    tr = corner(x+w, y, 1, 1, False)
    br = corner(x+w, y+h, 1, -1, True)
    bl = corner(x, y+h, -1, -1, False)
    tl = corner(x, y, -1, 1, True)
    def seg(p):
        s = f'L{p[0][0]:.2f} {p[0][1]:.2f} '
        for i in (1, 4, 7):
            s += 'C' + ' '.join(f'{px:.2f} {py:.2f}' for px, py in p[i:i+3]) + ' '
        return s
    d = f'M{tl[-1][0]:.2f} {tl[-1][1]:.2f} ' if False else ''
    path = seg(tr) + seg(br) + seg(bl) + seg(tl)
    return 'M' + path[1:] + 'Z'


def key_D(hole='round', tray=False):
    """Minimal vertical key: round bow + one hole (round or hexagon), straight thick shaft, 2 teeth."""
    t = 76 if tray else 54
    R = 190 if tray else 170
    bow = Point(0, 0).buffer(R, 128)
    if hole == 'hex':
        h = rounded_ngon(0, 0, 92 if tray else 82, 6, 0, 12)
    else:
        h = Point(0, 0).buffer(82 if tray else 76, 128)
    L = 520 if tray else 600
    shaft = box(R - 40, -t, L, t)
    if tray:
        teeth = [box(L-215, t-5, L-135, t+90), box(L-68, t-5, L, t+70)]
    else:
        teeth = [box(L-190, t-5, L-130, t+92), box(L-95, t-5, L, t+66)]
    k = soften(unary_union([bow, shaft] + teeth), convex=14 if tray else 12, concave=12)
    return k.difference(h)


PHI = (1 + 5 ** 0.5) / 2

def key_G_spec(W=100.0):
    """Golden-ratio key (vertical, y down, axis x=0, bow centre at origin). All lengths from W & phi."""
    p = PHI
    D = p**2 * W            # bow outer diameter            D : W = phi^2
    d = W                   # hole diameter                 D : d = phi^2, d = W
    S = p * D               # shaft length below bow        S : D = phi
    L = D + S               # total length                  L : D = phi^2, L = phi^4 W
    y_bow_bottom = D / 2
    y_tip = y_bow_bottom + S
    y_block = y_bow_bottom + S / p      # golden section of the shaft (from bow)
    t = W / p               # tooth width (along shaft)      t : g = phi : 1
    g = W / p**2            # gap
    h = p / 2 * W           # tooth height (protrusion) = ring thickness -> tooth edge flush with bow edge
    teeth = [(y_block, y_block + t), (y_block + t + g, y_block + 2*t + g)]
    return dict(W=W, D=D, d=d, S=S, L=L, y_bow_bottom=y_bow_bottom, y_tip=y_tip, y_block=y_block,
                t=t, g=g, h=h, teeth=teeth)

def key_G(W=100.0):
    s = key_G_spec(W)
    bow = Point(0, 0).buffer(s['D']/2, 256)
    shaft = box(-W/2, 0, W/2, s['y_tip'])
    core = unary_union([bow, shaft])
    f = 0.14 * W                                     # small fillet only at bow/shaft junction
    core = core.buffer(f, join_style=1).buffer(-f, join_style=1)
    teeth = [box(-W/2 - s['h'], a, -W/2 + 1, b) for a, b in s['teeth']]
    k = unary_union([core] + teeth)
    r = 0.025 * W                                    # hairline convex softening (keeps rectangles crisp)
    k = k.buffer(-r, join_style=1).buffer(r, join_style=1)
    return k.difference(Point(0, 0).buffer(s['d']/2, 256))


def key_H_spec(W=100.0):
    """Bow-dominant golden-ratio key (D1h). Vertical, y down, axis x=0, bow centre at origin."""
    p = PHI
    D = p**3 * W            # bow outer diameter          D = phi^3 W
    d = D / p**2            # hole diameter               D : d = phi^2  (d = phi W)
    S = D / p               # shaft below bow             D : S = phi    (S = phi^2 W)
    L = D + S               # total                       L = phi D = phi^4 W
    y_bow_bottom = D / 2
    y_tip = y_bow_bottom + S
    plain = S / p**2        # plain shaft = W             (minor section, near bow)
    y_block = y_bow_bottom + plain      # teeth block = S/phi = phi W (major section, at tip)
    t = W / p               # tooth width                 t : g = phi : 1
    g = W / p**2
    h = W                   # tooth protrusion            h : t = phi -> each tooth is a golden rectangle
    teeth = [(y_block, y_block + t), (y_block + t + g, y_block + 2*t + g)]
    return dict(W=W, D=D, d=d, S=S, L=L, y_bow_bottom=y_bow_bottom, y_tip=y_tip, y_block=y_block,
                plain=plain, t=t, g=g, h=h, teeth=teeth)

def key_H(W=100.0):
    s = key_H_spec(W)
    bow = Point(0, 0).buffer(s['D']/2, 256)
    shaft = box(-W/2, 0, W/2, s['y_tip'])
    core = unary_union([bow, shaft])
    f = 0.18 * W
    core = core.buffer(f, join_style=1).buffer(-f, join_style=1)
    teeth = [box(-W/2 - s['h'], a, -W/2 + 1, b) for a, b in s['teeth']]
    k = unary_union([core] + teeth)
    r = 0.025 * W
    k = k.buffer(-r, join_style=1).buffer(r, join_style=1)
    return k.difference(Point(0, 0).buffer(s['d']/2, 256))


def key_K_spec(k, W=100.0):
    """Generalised golden-ratio key (D1i/D1j): bow D = phi^k W, total length fixed L = phi^4 W.
    hole d = D/phi^2; shaft S = L - D split at golden section: plain = S/phi^2 (near bow), teeth block = S/phi (tip);
    tooth t = S/phi^3, gap g = S/phi^4 (t:g = phi:1, 2t+g = S/phi); protrusion h = W.
    k = 3 reproduces D1h exactly."""
    p = PHI
    L = p**4 * W
    D = p**k * W
    d = D / p**2
    S = L - D
    y_bow_bottom = D / 2
    y_tip = y_bow_bottom + S
    plain = S / p**2
    y_block = y_bow_bottom + plain
    t, g, h = S / p**3, S / p**4, W
    teeth = [(y_block, y_block + t), (y_block + t + g, y_block + 2*t + g)]
    return dict(W=W, D=D, d=d, S=S, L=L, y_bow_bottom=y_bow_bottom, y_tip=y_tip, y_block=y_block,
                plain=plain, t=t, g=g, h=h, teeth=teeth, k=k)

def key_K(k, W=100.0):
    s = key_K_spec(k, W)
    bow = Point(0, 0).buffer(s['D']/2, 256)
    shaft = box(-W/2, 0, W/2, s['y_tip'])
    core = unary_union([bow, shaft])
    f = 0.18 * W
    core = core.buffer(f, join_style=1).buffer(-f, join_style=1)
    teeth = [box(-W/2 - s['h'], a, -W/2 + 1, b) for a, b in s['teeth']]
    kk = unary_union([core] + teeth)
    r = 0.025 * W
    kk = kk.buffer(-r, join_style=1).buffer(r, join_style=1)
    return kk.difference(Point(0, 0).buffer(s['d']/2, 256))
