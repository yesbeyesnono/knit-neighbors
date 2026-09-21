# 앱 아이콘(평면 로고풍) — 실타래처럼 감긴 지구. 음영·입체 없음, 단색 면 + 실 사이 틈만. 한가운데 점 = 한국.
#   python tools/gen-app-icon-flat.py <land-110m.json> [출력 png]
#   환경변수: LANDC / SEA / BG / DOT (hex) · TAIL=0 실 꼬리 없음 · DOTR 점 크기 · GAP 틈 굵기 · BANDS 감긴 줄 수
import json, math, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

LAND = sys.argv[1]
OUT = sys.argv[2] if len(sys.argv) > 2 else 'resources/icon.png'
LON0, LAT0 = 127.5, 36.0
SIZE, SS = 1024, 3
N = SIZE * SS
E = os.environ.get
hexc = lambda h: np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float32)
BG, SEA, LANDC, DOT = hexc(E('BG', 'FBF8F1')), hexc(E('SEA', '6FB1DE')), hexc(E('LANDC', '7CC093')), hexc(E('DOT', 'EE7668'))
GAP = float(E('GAP', '0.06')); BANDS = float(E('BANDS', '9')); DOTR = float(E('DOTR', '0.10')); TAIL = E('TAIL', '1') != '0'
R = 0.35; CX, CY = (0.46, 0.47) if TAIL else (0.5, 0.5)

def land_mask(w=1440, h=720):
    t = json.load(open(LAND, encoding='utf-8')); sc, tr = t['transform']['scale'], t['transform']['translate']
    arcs = []
    for a in t['arcs']:
        x = y = 0; pts = []
        for dx, dy in a:
            x += dx; y += dy; pts.append((x * sc[0] + tr[0], y * sc[1] + tr[1]))
        arcs.append(pts)
    def ring(idx):
        out = []
        for i in idx:
            p = arcs[i] if i >= 0 else arcs[~i][::-1]
            out += p if not out else p[1:]
        return out
    img = Image.new('L', (w, h), 0); d = ImageDraw.Draw(img)
    for g in t['objects']['land']['geometries']:
        for poly in (g['arcs'] if g['type'] == 'MultiPolygon' else [g['arcs']]):
            for k, r in enumerate(poly):
                pts = [((p[0] + 180) / 360 * w, (90 - p[1]) / 180 * h) for p in ring(r)]
                if len(pts) >= 3: d.polygon(pts, fill=255 if k == 0 else 0)
    return img

# 해안선을 뭉개서 큰 덩어리만 남긴다(단순화)
m = land_mask(); MW, MH = m.size
m = m.filter(ImageFilter.GaussianBlur(radius=float(E('SMOOTH', '3.2')) * MW / 360))
MASK = np.asarray(m, dtype=np.float32) / 255.0

ys, xs = np.mgrid[0:N, 0:N].astype(np.float32)
X = (xs / N - CX) / R; Y = -(ys / N - CY) / R
rr = X * X + Y * Y; inside = rr < 1.0
Z = np.sqrt(np.clip(1 - rr, 0, 1))
la0 = math.radians(LAT0)
a = -Y * math.sin(la0) + Z * math.cos(la0); n = Y * math.cos(la0) + Z * math.sin(la0)
lat = np.degrees(np.arcsin(np.clip(n, -1, 1))); lon = LON0 + np.degrees(np.arctan2(X, a))
u = (((lon + 180) % 360) / 360 * MW).astype(int) % MW; v = np.clip(((90 - lat) / 180 * MH).astype(int), 0, MH - 1)
land = MASK[v, u] > 0.47

# 실이 감긴 줄: 기울어진 축을 기준으로 한 '위도선' 묶음 3개(실타래를 여러 방향으로 감은 모양)
def axis(tilt_deg, lean=0.35):
    t = math.radians(tilt_deg); v = np.array([math.sin(t), math.cos(t), lean]); return v / np.linalg.norm(v)
def family(ax):
    w = X * ax[0] + Y * ax[1] + Z * ax[2]                     # -1~1
    f = (w * BANDS / 2.0) % 1.0
    return np.minimum(f, 1 - f) < GAP * BANDS / 4.0, w
gapA, _ = family(axis(-38))
gapB, _ = family(axis(52, 0.2))
gapC, _ = family(axis(8, 0.5))
capB = X * 0.62 + Y * 0.70 + Z * 0.35                         # B 묶음이 덮는 영역(오른쪽 위)
capC = -X * 0.75 - Y * 0.45 + Z * 0.48                        # C 묶음(왼쪽 아래)
selB = capB > 0.50; selC = (capC > 0.62) & ~selB
edge = (np.abs(capB - 0.50) < GAP * 0.55) | ((np.abs(capC - 0.62) < GAP * 0.55) & ~selB)
gap = np.where(selB, gapB, np.where(selC, gapC, gapA)) | edge

img = np.empty((N, N, 3), np.float32); img[:] = BG
img[inside] = np.where(land[..., None], LANDC, SEA)[inside]
img[inside & gap] = BG
out = Image.fromarray(img.astype(np.uint8), 'RGB'); d = ImageDraw.Draw(out)

# 실 꼬리
if TAIL:
    lw = int(2 * R * N / BANDS * (1 - GAP * BANDS / 2) * 0.85)   # 감긴 실 한 줄과 비슷한 굵기
    p0, p1, p2, p3 = (CX + R * 0.62, CY + R * 0.80), (CX + R * 1.02, CY + R * 1.20), (CX + R * 1.34, CY + R * 1.12), (CX + R * 1.26, CY + R * 0.78)
    pts = []
    for k in range(401):
        t = k / 400.0; q = [(1 - t) ** 3 * p0[i] + 3 * (1 - t) ** 2 * t * p1[i] + 3 * (1 - t) * t * t * p2[i] + t ** 3 * p3[i] for i in (0, 1)]
        pts.append((q[0] * N, q[1] * N))
    col = tuple(int(c) for c in SEA)
    for px, py in pts: d.ellipse((px - lw / 2, py - lw / 2, px + lw / 2, py + lw / 2), fill=col)

# 한국 = 한가운데 점
if DOTR > 0:
    cx, cy, r1 = CX * N, CY * N, DOTR * R * N
    d.ellipse((cx - r1 * 1.45, cy - r1 * 1.45, cx + r1 * 1.45, cy + r1 * 1.45), fill=tuple(int(c) for c in BG))
    d.ellipse((cx - r1, cy - r1, cx + r1, cy + r1), fill=tuple(int(c) for c in DOT))

out.resize((SIZE, SIZE), Image.LANCZOS).save(OUT)
print('saved', OUT)
