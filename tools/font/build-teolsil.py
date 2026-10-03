# 털실체 폰트 빌드 — export-glyphs.js 가 뽑은 획 중심선을 두께만큼 부풀려(끝·모서리 둥글게) 외곽선으로 만들고 TTF/WOFF2 로 조립
# 사용: python tools/font/build-teolsil.py <glyphs.json> <Regular|Bold> <out폴더>
#   좌표: 엔진 1000 유닛(y 아래로) → 폰트 UPM 1000, 어센더 880 / 디센더 -120 (font_y = 880 - svg_y)
#   외곽선: shapely buffer(round cap/join) → 합집합 → simplify 로 점 정리 → 직선 윤곽(TrueType). 라틴 글자는 넣지 않음(앱에서 다음 글꼴로 넘어감)
import io, os, sys, json, math
from svgpathtools import parse_path
from shapely.geometry import LineString, Polygon, Point, MultiPolygon
from shapely.ops import unary_union
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont

SRC, STYLE, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.load(io.open(SRC, encoding='utf-8')); SW = data['sw']; G = data['glyphs']
ASC, DESC, UPM = 880, -120, 1000
FAMILY, FAMILY_KO = 'Teolsil', '털실체'
SIMPLIFY = 1.2   # 유닛 — 점 수를 줄이되 둥근 끝이 각지지 않을 만큼

def sample(seg, n):
    return [(seg.point(t).real, seg.point(t).imag) for t in [k / n for k in range(n + 1)]]

def subpaths(d):
    # svgpathtools 의 Path 를 연속 구간(subpath)별 점 목록으로. 닫힌 경로(Z)는 마지막 점을 첫 점으로
    p = parse_path(d); out = []; cur = []; last_end = None
    for seg in p:
        if last_end is None or abs(seg.start - last_end) > 1e-6:
            if cur: out.append(cur)
            cur = [(seg.start.real, seg.start.imag)]
        name = type(seg).__name__
        n = 1 if name == 'Line' else 10 if name == 'QuadraticBezier' else 14 if name == 'CubicBezier' else max(8, int(abs(seg.length()) / 25))
        cur += sample(seg, n)[1:]
        last_end = seg.end
    if cur: out.append(cur)
    return out

def outline(g):
    shapes = []
    if g.get('d'):
        for pts in subpaths(g['d']):
            if len(pts) < 2: shapes.append(Point(pts[0]).buffer(SW / 2, resolution=6)); continue
            shapes.append(LineString(pts).buffer(SW / 2, cap_style=1, join_style=1, resolution=6))
    if g.get('circle'):
        cx, cy, r = g['circle']; shapes.append(Point(cx, cy).buffer(r, resolution=8))
    if not shapes: return None
    u = unary_union(shapes).simplify(SIMPLIFY, preserve_topology=True)
    return u

def draw(pen, geom):
    polys = list(geom.geoms) if isinstance(geom, MultiPolygon) else [geom]
    for poly in polys:
        # TrueType: 바깥 윤곽 시계 방향, 구멍 반시계 (y 를 뒤집으므로 shapely 의 기본 방향(바깥 반시계)이 그대로 시계가 됨)
        for ring, hole in [(poly.exterior, False)] + [(r, True) for r in poly.interiors]:
            pts = list(ring.coords)[:-1]
            ccw = ring.is_ccw
            if (not hole and not ccw) or (hole and ccw): pts = pts[::-1]
            pts = [(round(x), round(ASC - y)) for x, y in pts]
            pen.moveTo(pts[0])
            for q in pts[1:]: pen.lineTo(q)
            pen.closePath()

def gname(ch):
    cp = ord(ch)
    if ch == ' ': return 'space'
    if ch == '·': return 'periodcentered'
    if '0' <= ch <= '9': return ['zero','one','two','three','four','five','six','seven','eight','nine'][cp - 48]
    return 'uni%04X' % cp

order = ['.notdef']; cmap = {}; glyphs = {}; metrics = {}; empty = []
pen = TTGlyphPen(None); glyphs['.notdef'] = pen.glyph(); metrics['.notdef'] = (1000, 0)
for ch, g in G.items():
    if g is None: continue
    name = gname(ch); order.append(name); cmap[ord(ch)] = name
    pen = TTGlyphPen(None)
    geom = outline(g)
    if geom is not None and not geom.is_empty: draw(pen, geom)
    elif ch != ' ': empty.append(ch)
    gl = pen.glyph(); glyphs[name] = gl
    try: gl.recalcBounds(None); lsb = gl.xMin
    except Exception: lsb = 0
    metrics[name] = (int(g['adv']), int(lsb) if hasattr(gl, 'xMin') else 0)
if 0x00A0 not in cmap: order.append('nbspace'); cmap[0x00A0] = 'nbspace'; pen = TTGlyphPen(None); glyphs['nbspace'] = pen.glyph(); metrics['nbspace'] = (360, 0)

fb = FontBuilder(UPM, isTTF=True)
fb.setupGlyphOrder(order); fb.setupCharacterMap(cmap); fb.setupGlyf(glyphs); fb.setupHorizontalMetrics(metrics)
fb.setupHorizontalHeader(ascent=ASC, descent=DESC, lineGap=0)
bold = STYLE.lower() == 'bold'
names = dict(familyName=FAMILY, styleName=STYLE, uniqueFontIdentifier=f'{FAMILY}-{STYLE}-1.0', fullName=f'{FAMILY} {STYLE}', psName=f'{FAMILY}-{STYLE}', version='Version 1.0',
             copyright='Copyright 2026 Firmtech (뜨개동네). All rights reserved.', manufacturer='Firmtech', designer='뜨개동네',
             description='털실체 — 뜨개동네 앱 제목 글자. 모노라인(한 굵기 선), 둥근 끝. 한글 음절·숫자·가운뎃점.')
fb.setupNameTable(names, windows=True, mac=False)
# 한국어 패밀리 이름도 함께
fb.font['name'].setName(FAMILY_KO, 1, 3, 1, 0x412); fb.font['name'].setName(f'{FAMILY_KO} {STYLE}', 4, 3, 1, 0x412)
fb.setupOS2(version=4, sTypoAscender=ASC, sTypoDescender=DESC, sTypoLineGap=0, usWinAscent=ASC + 20, usWinDescent=-DESC + 20, achVendID='FTCH',
            usWeightClass=700 if bold else 400, fsSelection=(0x20 if bold else 0x40) | 0x80, ulUnicodeRange1=0, ulCodePageRange1=(1 << 19), xAvgCharWidth=980,
            sxHeight=500, sCapHeight=700, usBreakChar=32, usDefaultChar=0)
fb.setupPost(isFixedPitch=0)
fb.font['head'].macStyle = 1 if bold else 0
fb.font['OS/2'].ulUnicodeRange2 = (1 << (56 - 32))   # Hangul Syllables bit 56
os.makedirs(OUT, exist_ok=True)
ttf = os.path.join(OUT, f'{FAMILY}-{STYLE}.ttf'); fb.save(ttf)
f = TTFont(ttf); f.flavor = 'woff2'; f.save(os.path.join(OUT, f'{FAMILY}-{STYLE}.woff2'))
print(STYLE, 'glyphs', len(order), 'empty', len(empty), empty[:10], 'ttf', os.path.getsize(ttf) // 1024, 'KB', 'woff2', os.path.getsize(os.path.join(OUT, f'{FAMILY}-{STYLE}.woff2')) // 1024, 'KB')
