# 브랜드 자산(명함·인쇄용) — 앱 아이콘(실뭉치, tools/make-icon.py 와 같은 기하)을 벡터 SVG 로 다시 그리고, 털실체 '뜨개동네' 글자를 붙인 로고 조합을 만든다.
#   python tools/brand-assets.py  →  resources/brand/*.svg + *.png (PNG 는 headless Chrome 렌더)
#   색: 피스타치오 팔레트(바탕 #EDF2DD · 실뭉치 올리브 #3F4F22). 글자는 resources/fonts/Teolsil-Bold.ttf 의 외곽선을 path 로 넣어 폰트 없이 열린다
import io, os, math, subprocess, sys
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'resources', 'brand'); os.makedirs(OUT, exist_ok=True)
BG, FG, INK = '#EDF2DD', '#3F4F22', '#3C4043'
CHROME = r'C:\Program Files\Google\Chrome\Application\chrome.exe'

# ---------- 실뭉치(1024 기준 좌표) ----------
S = 1024; CX = CY = 512; R = S * 0.34; SW = S * 0.028
def ball(fg=FG, bg=BG, ox=0, oy=0, scale=1.0, cid='c'):   # bg=None 이면 투명(감긴 실 틈을 마스크로 뚫음)
    """실뭉치 그림 요소. 감긴 실 = 기울인 타원 호(바탕색 선, 원 안으로 클립), 풀린 실 꼬리 = 곡선"""
    r, sw = R * scale, SW * scale; cx, cy = CX * scale + ox, CY * scale + oy
    rings = ''.join(f'<ellipse cx="{cx:.1f}" cy="{cy:.1f}" rx="{r*0.98:.1f}" ry="{r*ry:.1f}" transform="rotate({-ang} {cx:.1f} {cy:.1f})" fill="none" stroke="{bg or '#000'}" stroke-width="{sw:.1f}"/>'
                    for ang, ry in [(-28, 0.62), (-10, 0.80), (12, 0.90), (34, 0.74), (52, 0.50)])
    pts = []
    for t in range(0, 101):
        u = t / 100
        x = cx + r * 0.55 + u * (S * scale * 0.34 - r * 0.55)
        y = cy + r * 0.62 + math.sin(u * math.pi) * S * scale * 0.06 + u * S * scale * 0.05
        pts.append(f'{x:.1f},{y:.1f}')
    tail = f'<polyline points="{" ".join(pts)}" fill="none" stroke="{fg}" stroke-width="{sw:.1f}" stroke-linecap="round" stroke-linejoin="round"/>'
    if bg is None:   # 투명용: 감긴 실 자리를 뚫는다(마스크) — 어떤 바탕색 위에 올려도 틈으로 바탕이 비침
        return (f'<mask id="{cid}" maskUnits="userSpaceOnUse" x="0" y="0" width="{S*scale+ox:.0f}" height="{S*scale+oy:.0f}"><circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r:.1f}" fill="#fff"/>'
                f'<g clip-path="url(#{cid}c)">{rings.replace(f"stroke=\"{bg}\"", "stroke=\"#000\"")}</g></mask>'
                f'<clipPath id="{cid}c"><circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r-sw:.1f}"/></clipPath>'
                f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r:.1f}" fill="{fg}" mask="url(#{cid})"/>' + tail)
    return (f'<clipPath id="{cid}"><circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r-sw:.1f}"/></clipPath>'
            f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r:.1f}" fill="{fg}"/>'
            f'<g clip-path="url(#{cid})">{rings}</g>' + tail)

def svg(w, h, body, bg=None, rx=0):
    bgel = f'<rect width="{w}" height="{h}" rx="{rx}" fill="{bg}"/>' if bg else ''
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{bgel}{body}</svg>'

# ---------- 털실체 글자 → path ----------
_font = TTFont(os.path.join(ROOT, 'resources', 'fonts', 'Teolsil-Bold.ttf'))
_cmap = _font.getBestCmap(); _glyphs = _font.getGlyphSet(); _upm = _font['head'].unitsPerEm; _asc = _font['hhea'].ascent
def text_path(text, size, x, y, fill=INK, tracking=-0.01):
    """글자 외곽선을 path 로. (x, y) = 왼쪽·베이스라인. 자간 -1%(앱 제목 규격)"""
    k = size / _upm; out = []; pen_x = x
    for ch in text:
        g = _cmap.get(ord(ch));
        if not g: continue
        pen = SVGPathPen(_glyphs); _glyphs[g].draw(pen); d = pen.getCommands()
        if d: out.append(f'<path d="{d}" transform="translate({pen_x:.1f} {y:.1f}) scale({k:.5f} {-k:.5f})" fill="{fill}"/>')
        pen_x += _glyphs[g].width * k + size * tracking
    return ''.join(out), pen_x - x

def render(svg_path, png_path, w, h, scale=1):
    html = os.path.splitext(png_path)[0] + '.html'
    io.open(html, 'w', encoding='utf-8').write(f'<!doctype html><meta charset="utf-8"><style>html,body{{margin:0;background:transparent}}body{{zoom:{scale}}}</style><body>' + io.open(svg_path, encoding='utf-8').read())
    subprocess.run([CHROME, '--headless=new', '--hide-scrollbars', '--default-background-color=00000000', f'--window-size={int(w*scale)},{int(h*scale)}', f'--screenshot={png_path}', 'file:///' + html.replace('\\', '/')], check=True, capture_output=True)
    os.remove(html)

files = []
def emit(name, w, h, body, bg=None, rx=0, scale=1):
    p = os.path.join(OUT, name + '.svg'); io.open(p, 'w', encoding='utf-8').write(svg(w, h, body, bg, rx)); files.append(p)
    png = os.path.join(OUT, name + '.png'); render(p, png, w, h, scale); files.append(png)

# 1) 앱 아이콘 그대로(정사각, 바탕색) — 스토어와 같은 그림
emit('icon-square', S, S, ball(), bg=BG)
# 2) 모서리 둥근 아이콘(iOS 식 곡률 22.4%) — 명함에 '앱 아이콘'으로 보일 때
emit('icon-rounded', S, S, ball(), bg=BG, rx=int(S * 0.224))
# 3) 바탕 없는 실뭉치(투명) — 명함 바탕색 위에 올릴 때
emit('icon-mark', S, S, ball(bg=None))
# 4) 가로 로고: 실뭉치 + 뜨개동네(털실체 Bold) — 투명 바탕
tp, tw = text_path('뜨개동네', 300, 0, 0)
emit('logo-horizontal', int(420 + tw + 60), 420, ball(bg=None, scale=0.41, ox=0, oy=0) + f'<g transform="translate(400 318)">{tp}</g>')
# 5) 세로 로고: 실뭉치 위, 글자 아래 — 투명 바탕
tp2, tw2 = text_path('뜨개동네', 220, 0, 0)
W = max(560, int(tw2 + 80)); emit('logo-vertical', W, 760, ball(bg=None, scale=0.5, ox=(W - 512) / 2, oy=0) + f'<g transform="translate({(W - tw2) / 2:.1f} 690)">{tp2}</g>')
# 6) 인쇄용 큰 PNG(3배)
render(os.path.join(OUT, 'icon-rounded.svg'), os.path.join(OUT, 'icon-rounded@3x.png'), S, S, 3); files.append(os.path.join(OUT, 'icon-rounded@3x.png'))
render(os.path.join(OUT, 'logo-horizontal.svg'), os.path.join(OUT, 'logo-horizontal@3x.png'), int(420 + tw + 60), 420, 3); files.append(os.path.join(OUT, 'logo-horizontal@3x.png'))
print('\n'.join(os.path.relpath(f, ROOT) for f in files))
