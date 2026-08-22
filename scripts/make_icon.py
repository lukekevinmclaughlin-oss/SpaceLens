#!/usr/bin/env python3
"""SpaceLens icon v2 — a JARVIS-style holographic scanner: an arc-reactor core
inside concentric HUD reticles, with a data-node constellation being assembled
and a radar sweep. Holographic cyan on deep navy, with amber accents."""
import math, os, subprocess

OUT = "/tmp/spacelens_icon2"
os.makedirs(OUT, exist_ok=True)
CX = CY = 512

def P(r, a):  # polar -> cartesian
    return (CX + r*math.cos(a), CY + r*math.sin(a))

def sector(a0, a1, ri, ro):
    large = 1 if (a1 - a0) > math.pi else 0
    x0,y0 = P(ro, a0); x1,y1 = P(ro, a1); x2,y2 = P(ri, a1); x3,y3 = P(ri, a0)
    return (f"M{x0:.2f},{y0:.2f} A{ro},{ro} 0 {large} 1 {x1:.2f},{y1:.2f} "
            f"L{x2:.2f},{y2:.2f} A{ri},{ri} 0 {large} 0 {x3:.2f},{y3:.2f} Z")

def ticks():
    out = []
    n = 72
    for i in range(n):
        a = 2*math.pi*i/n - math.pi/2
        major = (i % 6 == 0)
        r0 = 452
        r1 = 452 - (34 if major else 16)
        x0,y0 = P(r0, a); x1,y1 = P(r1, a)
        op = 0.85 if major else 0.4
        w = 4 if major else 2
        out.append(f'<line x1="{x0:.1f}" y1="{y0:.1f}" x2="{x1:.1f}" y2="{y1:.1f}" '
                   f'stroke="#2FE6FF" stroke-opacity="{op}" stroke-width="{w}"/>')
    return "\n".join(out)

def scan_arcs():
    """Two segmented rings; the leading portion bright ('assembled'),
    the trailing portion faint ('yet to scan')."""
    out = []
    rings = [(300, 344), (356, 400)]
    for ri_idx, (ri, ro) in enumerate(rings):
        segs = 26 if ri_idx else 22
        start = -math.pi/2 + ri_idx*0.15
        gap = math.radians(1.6)
        for i in range(segs):
            a0 = start + 2*math.pi*i/segs
            a1 = a0 + 2*math.pi/segs - gap
            # brightness falls off going "backwards" from the sweep head
            frac = i/segs
            bright = frac < 0.62
            op = (0.9 - frac*0.5) if bright else 0.14
            col = "#31E9FF" if bright else "#1C6E82"
            out.append(f'<path d="{sector(a0,a1,ri,ro)}" fill="{col}" fill-opacity="{op:.2f}"/>')
    return "\n".join(out)

def sweep():
    # radar sweep wedge (faint, fading), from head angle
    head = -math.pi/2 + math.radians(150)
    span = math.radians(70)
    ro = 430
    x0,y0 = P(ro, head-span); x1,y1 = P(ro, head)
    return (f'<path d="M{CX},{CY} L{x0:.1f},{y0:.1f} A{ro},{ro} 0 0 1 {x1:.1f},{y1:.1f} Z" '
            f'fill="url(#sweep)" opacity="0.5"/>')

def constellation():
    """Data-node graph being assembled: fixed nodes + connecting links."""
    nodes = [
        (250, math.radians(-58)), (270, math.radians(18)), (235, math.radians(96)),
        (255, math.radians(158)), (245, math.radians(214)), (265, math.radians(276)),
        (180, math.radians(-20)), (175, math.radians(120)), (190, math.radians(240)),
        (140, math.radians(60)),
    ]
    pts = [P(r, a) for r, a in nodes]
    links = [(0,6),(6,1),(1,9),(9,7),(7,3),(3,8),(8,4),(4,2),(2,7),(6,9),(5,1),(5,8)]
    out = ['<g stroke="#31E9FF" stroke-opacity="0.32" stroke-width="2">']
    for a,b in links:
        out.append(f'<line x1="{pts[a][0]:.1f}" y1="{pts[a][1]:.1f}" '
                   f'x2="{pts[b][0]:.1f}" y2="{pts[b][1]:.1f}"/>')
    out.append('</g>')
    amber = {2, 7}  # a couple of Iron-Man amber accents
    for i,(x,y) in enumerate(pts):
        col = "#FFB43A" if i in amber else "#8FF4FF"
        glow = "ambGlow" if i in amber else "nodeGlow"
        rr = 9 if i in amber else 7
        out.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="20" fill="url(#{glow})"/>')
        out.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{rr}" fill="{col}"/>')
    return "\n".join(out)

def core():
    # arc-reactor: bloom + triangle reticle + bright center
    tri = []
    for k in range(3):
        a = -math.pi/2 + k*2*math.pi/3
        tri.append(P(78, a))
    tri_path = f'M{tri[0][0]:.1f},{tri[0][1]:.1f} L{tri[1][0]:.1f},{tri[1][1]:.1f} L{tri[2][0]:.1f},{tri[2][1]:.1f} Z'
    return f'''
  <circle cx="{CX}" cy="{CY}" r="150" fill="url(#coreBloom)"/>
  <circle cx="{CX}" cy="{CY}" r="112" fill="none" stroke="#2FE6FF" stroke-opacity="0.5" stroke-width="3"/>
  <path d="{tri_path}" fill="none" stroke="#BFF7FF" stroke-width="6" stroke-linejoin="round" opacity="0.9"/>
  <circle cx="{CX}" cy="{CY}" r="46" fill="url(#coreHot)"/>
  <circle cx="{CX}" cy="{CY}" r="20" fill="#FFFFFF"/>
'''

DEFS = '''
<defs>
  <radialGradient id="bg" cx="0.5" cy="0.42" r="0.75">
    <stop offset="0" stop-color="#0B2436"/>
    <stop offset="0.5" stop-color="#06121F"/>
    <stop offset="1" stop-color="#020509"/>
  </radialGradient>
  <radialGradient id="coreBloom" cx="0.5" cy="0.5" r="0.5">
    <stop offset="0" stop-color="#8FF4FF" stop-opacity="0.95"/>
    <stop offset="0.5" stop-color="#31E9FF" stop-opacity="0.35"/>
    <stop offset="1" stop-color="#31E9FF" stop-opacity="0"/>
  </radialGradient>
  <radialGradient id="coreHot" cx="0.5" cy="0.45" r="0.6">
    <stop offset="0" stop-color="#FFFFFF"/>
    <stop offset="0.6" stop-color="#B7F3FF"/>
    <stop offset="1" stop-color="#38D6F5"/>
  </radialGradient>
  <radialGradient id="nodeGlow" cx="0.5" cy="0.5" r="0.5">
    <stop offset="0" stop-color="#8FF4FF" stop-opacity="0.85"/>
    <stop offset="1" stop-color="#8FF4FF" stop-opacity="0"/>
  </radialGradient>
  <radialGradient id="ambGlow" cx="0.5" cy="0.5" r="0.5">
    <stop offset="0" stop-color="#FFC65A" stop-opacity="0.9"/>
    <stop offset="1" stop-color="#FFC65A" stop-opacity="0"/>
  </radialGradient>
  <linearGradient id="sweep" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0" stop-color="#31E9FF" stop-opacity="0"/>
    <stop offset="1" stop-color="#31E9FF" stop-opacity="0.55"/>
  </linearGradient>
</defs>
'''

def svg(full_bleed=True):
    if full_bleed:
        bg = '<rect x="0" y="0" width="1024" height="1024" fill="url(#bg)"/>'
        clip_open = clip_close = ""
    else:
        bg = '<rect x="100" y="100" width="824" height="824" rx="185" ry="185" fill="url(#bg)"/>'
        clip_open = ('<clipPath id="sq"><rect x="100" y="100" width="824" height="824" '
                     'rx="185" ry="185"/></clipPath>\n<g clip-path="url(#sq)">')
        clip_close = "</g>"
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
{DEFS}
{bg}
{clip_open}
{sweep()}
{ticks()}
{scan_arcs()}
{constellation()}
{core()}
{clip_close}
</svg>'''

with open(f"{OUT}/full.svg","w") as f: f.write(svg(True))
with open(f"{OUT}/mac.svg","w") as f: f.write(svg(False))

def render(svg_path, png, size):
    subprocess.run(["rsvg-convert","-w",str(size),"-h",str(size),svg_path,"-o",png], check=True)

render(f"{OUT}/full.svg", f"{OUT}/ios_1024.png", 1024)
for s in [16,32,64,128,256,512,1024]:
    render(f"{OUT}/mac.svg", f"{OUT}/mac_{s}.png", s)
print("done", os.listdir(OUT))
