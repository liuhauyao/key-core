"""Generate SVG sources for Key Core icon concepts A/B/C."""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from geom import *

OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))

# --------------------------------------------------------------------------------------------
def bg_stops(top, bottom=(6, 6, 7), n=14):
    """Eased (smoothstep) multi-stop ramp to avoid Mach bands in dark gradients."""
    t0 = tuple(int(top[i:i+2], 16) for i in (1, 3, 5))
    out = []
    for i in range(n + 1):
        u = i / n
        e = 1 - (1 - u) ** 2.2          # ease-out: light falls off quickly then flattens
        c = tuple(round(a + (b - a) * e) for a, b in zip(t0, bottom))
        out.append(f'<stop offset="{u*0.85:.3f}" stop-color="#{c[0]:02x}{c[1]:02x}{c[2]:02x}"/>')
    return ''.join(out)

def bg_defs(kind):
    """Background: near-black squircle with radial light, grain, rim highlight."""
    brushed = kind in ('C', 'D1', 'D2', 'D1g', 'D1h', 'D1i', 'D1j')
    turb = ('<feTurbulence type="fractalNoise" baseFrequency="0.0015 0.55" numOctaves="2" seed="3"/>'
            if brushed else
            '<feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves="3" seed="7" stitchTiles="stitch"/>')
    top = {'A': '#323337', 'B': '#302b23', 'C': '#2a2b30', 'D1': '#2e2f33', 'D2': '#2e2f33', 'D1g': '#2e2f33', 'D1h': '#2e2f33', 'D1i': '#2e2f33', 'D1j': '#2e2f33'}[kind]
    return f'''
    <radialGradient id="bg" cx="50%" cy="0%" r="125%">{bg_stops(top)}
    </radialGradient>
    <linearGradient id="rim" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#fff" stop-opacity="0.30"/>
      <stop offset="0.18" stop-color="#fff" stop-opacity="0.06"/>
      <stop offset="0.8" stop-color="#fff" stop-opacity="0.0"/>
      <stop offset="1" stop-color="#fff" stop-opacity="0.07"/>
    </linearGradient>
    <filter id="grainW" x="0" y="0" width="100%" height="100%" color-interpolation-filters="sRGB">
      {turb}
      <feColorMatrix type="matrix" values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  1.4 0 0 0 -0.45"/>
    </filter>
    <filter id="grainB" x="0" y="0" width="100%" height="100%" color-interpolation-filters="sRGB">
      {turb.replace('seed="7"', 'seed="11"').replace('seed="3"', 'seed="5"')}
      <feColorMatrix type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  1.4 0 0 0 -0.4"/>
    </filter>
    <filter id="appShadow" x="-20%" y="-20%" width="140%" height="145%" color-interpolation-filters="sRGB">
      <feGaussianBlur stdDeviation="14"/>
    </filter>'''

def key_filter():
    """Bevel (specular) + inner shadow + soft drop shadow for the key glyph."""
    return '''
    <filter id="keyFx" x="-25%" y="-25%" width="150%" height="150%" color-interpolation-filters="sRGB">
      <!-- bevel -->
      <feGaussianBlur in="SourceAlpha" stdDeviation="7" result="blur"/>
      <feSpecularLighting in="blur" surfaceScale="6" specularConstant="0.9" specularExponent="28" lighting-color="#ffffff" result="spec">
        <feDistantLight azimuth="235" elevation="38"/>
      </feSpecularLighting>
      <feComposite in="spec" in2="SourceAlpha" operator="in" result="specIn"/>
      <feComposite in="SourceGraphic" in2="specIn" operator="arithmetic" k1="0" k2="1" k3="0.55" k4="0" result="lit"/>
      <!-- inner shadow (bottom-right) -->
      <feComponentTransfer in="SourceAlpha" result="inv"><feFuncA type="table" tableValues="1 0"/></feComponentTransfer>
      <feOffset in="inv" dx="-4" dy="-6" result="invO"/>
      <feGaussianBlur in="invO" stdDeviation="5" result="invB"/>
      <feComposite in="invB" in2="SourceAlpha" operator="in" result="innerSh"/>
      <feColorMatrix in="innerSh" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 0.45 0" result="innerShD"/>
      <!-- drop shadow -->
      <feGaussianBlur in="SourceAlpha" stdDeviation="16" result="ds"/>
      <feOffset in="ds" dy="18" result="dsO"/>
      <feColorMatrix in="dsO" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 0.75 0" result="dsD"/>
      <feMerge><feMergeNode in="dsD"/><feMergeNode in="lit"/><feMergeNode in="innerShD"/></feMerge>
    </filter>'''

METALS = {
    'A': [('0', '#fbfcfd'), ('0.18', '#c3c8cf'), ('0.36', '#6a7079'), ('0.5', '#dfe3e8'), ('0.62', '#f7f8fa'), ('0.8', '#8a9099'), ('1', '#4b4f56')],
    'B': [('0', '#fff4cc'), ('0.22', '#e8c46e'), ('0.45', '#9c7428'), ('0.62', '#f6dc95'), ('0.82', '#b88d3a'), ('1', '#6e4f17')],
    'D1': None, 'D2': None, 'D1g': None, 'D1h': None, 'D1i': None, 'D1j': None,
    'C': [('0', '#ffffff'), ('0.35', '#eef1f6'), ('0.7', '#c9cfda'), ('1', '#9aa3b2')],
}

def metal_grad(kind, gid='metal'):
    stops = ''.join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in (METALS[kind] or METALS['A']))
    return f'<linearGradient id="{gid}" x1="0.1" y1="0" x2="0.9" y2="1">{stops}</linearGradient>'

# ------------------------------------------------------------------------------------------
LAYOUT = {  # angle, target bbox (for mac 824 squircle)
    'A': (45, 560), 'B': (-45, 560), 'C': (90, 590), 'D1': (90, 600), 'D2': (90, 600), 'D1g': (0, 610), 'D1h': (0, 667), 'D1i': (0, 667), 'D1j': (0, 667),
}

def key_geom(kind, small=False):
    if kind == 'A': return key_A(tray=small), None
    if kind == 'B': return key_B(tray=small)
    if kind == 'D1g': return key_G(), None
    if kind == 'D1h': return key_H(), None
    if kind == 'D1i': return key_K(2.5), None
    if kind == 'D1j': return key_K(2.75), None
    if kind == 'D1': return key_D('round', tray=small), None
    if kind == 'D2': return key_D('hex', tray=small), None
    return key_C(tray=small), None

def app_svg(kind, variant='mac'):
    """variant: mac (824 squircle + shadow), square (full-bleed for Win/Linux), small (<=32px simplified)."""
    small = variant.endswith('small')
    mac = variant.startswith('mac')
    half = 412 if mac else 472
    ang, size = LAYOUT[kind]
    size = size * half / 412 * ((1.14 if kind.startswith('D') else 1.08) if small else 1.0)
    k, core = key_geom(kind, small)
    from shapely import affinity
    # transform key and core consistently
    def tf(g):
        g2 = affinity.rotate(g, ang, origin=(0, 0))
        return g2
    kr = tf(k)
    minx, miny, maxx, maxy = kr.bounds
    s = size / max(maxx-minx, maxy-miny)
    def fin(g):
        g = affinity.scale(tf(g), s, s, origin=(0, 0))
        return affinity.translate(g, 512-(minx+maxx)/2*s, 512-(miny+maxy)/2*s + (6 if mac else 0))
    kp = to_path(fin(k))
    sq = continuous_rect(100, 100, 824, 824, 185.4) if mac else continuous_rect(40, 40, 944, 944, 212)
    shadow = (f'<path d="{sq}" transform="translate(0 12)" fill="#000" opacity="0.5" filter="url(#appShadow)"/>\n  '
              if (mac and not small) else '')
    grain = '' if small else f'''
      <g clip-path="url(#clip)">
        <rect width="1024" height="1024" filter="url(#grainW)" opacity="{0.035 if kind.startswith('D') else 0.055}"/>
        <rect width="1024" height="1024" filter="url(#grainB)" opacity="{0.16 if kind.startswith('D') else 0.30}"/>
      </g>'''
    glow = ''
    if kind.startswith('D') and not small:   # faint neutral halo behind the key
        glow = f'''<g clip-path="url(#clip)"><path d="{kp}" fill="#d9dde4" opacity="0.13" filter="url(#underGlow)"/></g>'''
    if kind == 'C':   # cool underglow behind the frosted key
        glow = f'''<g clip-path="url(#clip)"><path d="{kp}" fill="#7f9cff" opacity="{0.55 if not small else 0.0}" filter="url(#underGlow)"/></g>'''
    coreSvg = ''
    if core is not None and not small:
        c = fin(core).centroid
        r = 34 * s
        coreSvg = f'''
      <circle cx="{c.x:.2f}" cy="{c.y:.2f}" r="{r*2.4:.2f}" fill="url(#coreGlow)"/>
      <circle cx="{c.x:.2f}" cy="{c.y:.2f}" r="{r:.2f}" fill="url(#coreFill)" filter="url(#keyFx)"/>'''
    keyfx = '' if small else 'filter="url(#keyFx)"'
    brush = '' if (small or kind == 'C') else f'''
  <g clip-path="url(#keyClip)"><rect x="-300" y="-300" width="1624" height="1624" filter="url(#brushed)" opacity="0.13" transform="rotate({ang if ang else 90} 512 512)"/></g>'''
    stroke = ''
    if small:  # crisp edge for tiny sizes
        stroke = 'stroke="#000" stroke-opacity="0.35" stroke-width="6"'
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <!-- Key Core app icon, concept {kind}, variant {variant}. Hand-authored; regenerate via src/build.py -->
  <defs>{bg_defs(kind)}{key_filter()}
    {metal_grad(kind)}
    <clipPath id="clip"><path d="{sq}"/></clipPath>
    <clipPath id="keyClip"><path d="{kp}"/></clipPath>
    <filter id="brushed" x="0" y="0" width="100%" height="100%" color-interpolation-filters="sRGB">
      <feTurbulence type="fractalNoise" baseFrequency="0.003 0.6" numOctaves="2" seed="21"/>
      <feColorMatrix type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  2.2 0 0 0 -0.9"/>
    </filter>
    <filter id="underGlow" x="-40%" y="-40%" width="180%" height="180%" color-interpolation-filters="sRGB"><feGaussianBlur stdDeviation="38"/></filter>
    <radialGradient id="coreGlow"><stop offset="0" stop-color="#ffcf6a" stop-opacity="0.55"/><stop offset="1" stop-color="#ffcf6a" stop-opacity="0"/></radialGradient>
    <radialGradient id="coreFill" cx="40%" cy="35%" r="70%"><stop offset="0" stop-color="#fff6d8"/><stop offset="0.5" stop-color="#f0c35a"/><stop offset="1" stop-color="#a5721c"/></radialGradient>
  </defs>
  {shadow}<path d="{sq}" fill="url(#bg)"/>{grain}
  <path d="{sq}" fill="none" stroke="url(#rim)" stroke-width="{4 if not small else 8}" clip-path="url(#clip)"/>
  {glow}
  <path d="{kp}" fill="url(#metal)" {keyfx} {stroke}/>{brush}{coreSvg}
</svg>
'''

def tray_svg(kind, color='#000000'):
    ang = {'A': 45, 'B': -45, 'C': 90, 'D1': 90, 'D2': 90, 'D1g': 0, 'D1h': 0, 'D1i': 0, 'D1j': 0}[kind]
    k, _ = key_geom(kind, small=True)
    g = place(k, ang, 16, 16, size=30)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">
  <!-- Key Core tray glyph, concept {kind}. Monochrome; macOS template = black on transparent -->
  <path d="{to_path(g, 3)}" fill="{color}"/>
</svg>
'''

if __name__ == '__main__':
    for kind in (sys.argv[1:] or ['A', 'B', 'C', 'D1', 'D2']):
        d = os.path.join(OUT, f'concept_{kind}_src')
        os.makedirs(d, exist_ok=True)
        for v in ('mac', 'mac_small', 'square', 'square_small'):
            open(os.path.join(d, f'app_{v}.svg'), 'w').write(app_svg(kind, v))
        open(os.path.join(d, 'tray_template_black.svg'), 'w').write(tray_svg(kind, '#000000'))
        open(os.path.join(d, 'tray_white.svg'), 'w').write(tray_svg(kind, '#ffffff'))
    print('ok')
