# 앱 아이콘 — 뜨개실로 뜬 지구(한국이 한가운데). 코(메리야스 V) 하나하나를 구 곡면 위에 그리고, 코 단위로 바다/육지 색을 정한다.
#   python tools/gen-app-icon.py <land-110m.json 경로> [출력 png]
# land-110m.json = Natural Earth 육지 윤곽(world-atlas, 퍼블릭 도메인). 저장소에는 넣지 않는다.
import json, math, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

LAND = sys.argv[1]
OUT = sys.argv[2] if len(sys.argv) > 2 else 'resources/icon.png'
LON0, LAT0 = 127.5, 36.0          # 한국
SS, SIZE = 2, 1024                 # 2배로 그려서 줄인다
N = SIZE * SS
R = 0.405                          # 구 반지름(그림 폭 대비)
CX, CY = 0.5, 0.485
COLS, ROWS = [int(v) for v in os.environ.get('STITCHES', '57,63').split(',')]                # 보이는 반구를 가로지르는 코 수 / 단 수
SEA = np.array([0.53, 0.76, 0.93]); LANDC = np.array([0.985, 0.968, 0.925])
BG_TOP = np.array([0.975, 0.982, 0.992]); BG_BOT = np.array([0.925, 0.940, 0.962])

# ---------- 육지 마스크(등장방형) ----------
def land_mask(w=2880, h=1440):
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
    def px(p): return ((p[0] + 180) / 360 * w, (90 - p[1]) / 180 * h)
    geoms = t['objects']['land']['geometries']
    for g in geoms:
        polys = g['arcs'] if g['type'] == 'MultiPolygon' else [g['arcs']]
        for poly in polys:
            for k, r in enumerate(poly):
                pts = [px(p) for p in ring(r)]
                if len(pts) >= 3: d.polygon(pts, fill=255 if k == 0 else 0)
    return img

mask_img = land_mask()
MW, MH = mask_img.size
cell_deg = 180.0 / COLS
blur = mask_img.filter(ImageFilter.GaussianBlur(radius=cell_deg * 0.20 * MW / 360))
MASK = np.asarray(blur, dtype=np.float32) / 255.0

def is_land(x, y, z):
    """보는 방향 좌표(x 오른쪽, y 위, z 앞) → 지리 좌표 → 육지 여부"""
    la0, lo0 = math.radians(LAT0), math.radians(LON0)
    a = -y * math.sin(la0) + z * math.cos(la0); e = x; n = y * math.cos(la0) + z * math.sin(la0)
    lat = np.arcsin(np.clip(n, -1, 1)); lon = lo0 + np.arctan2(e, a)
    u = ((np.degrees(lon) + 180) % 360) / 360 * MW; v = (90 - np.degrees(lat)) / 180 * MH
    return MASK[np.clip(v.astype(int), 0, MH - 1), np.clip(u.astype(int), 0, MW - 1)] > 0.40

# ---------- 화면 좌표 ----------
ys, xs = np.mgrid[0:N, 0:N].astype(np.float32)
X = (xs / N - CX) / R; Y = -(ys / N - CY) / R
rr = X * X + Y * Y
inside = rr < 1.0
Z = np.sqrt(np.clip(1 - rr, 0, 1))

# 코 격자: 보는 방향 기준 경도 α(세로 줄 = 코 기둥), 위도 β(가로 줄 = 단)
alpha = np.arctan2(X, Z); beta = np.arcsin(np.clip(Y, -1, 1))
da, db = math.pi / COLS, math.pi / ROWS
U = alpha / da + 0.5 * (COLS % 2); V = beta / db + 0.5 * (ROWS % 2)   # 홀수면 한가운데(한국)에 코 하나가 정확히 온다
iu = np.floor(U); s = U - iu
iv = np.floor(V); t = V - iv

def leg(s, t):
    """코(V) 한 개의 실 가닥. 아래 꼭짓점(0.5,-0.34)에서 위 양끝(0.13 / 0.87, 1.0)으로. 반환: 높이 h(0~1), 가닥 가로 위치 q(-1~1), 가닥 방향 거리 l"""
    sm = np.where(s < 0.5, s, 1 - s)                     # 왼쪽 다리로 접기
    ax, ay, bx, by = 0.47, -0.34, 0.15, 1.02
    asp = 0.92                                           # 코 세로/가로 비
    px_, py_ = sm - ax, (t - ay) * asp
    vx, vy = bx - ax, (by - ay) * asp
    L = math.hypot(vx, vy); vx /= L; vy /= L
    l = px_ * vx + py_ * vy
    q = px_ * vy - py_ * vx                               # 부호 있는 가로 거리
    lc = np.clip(l, 0, L)
    d = np.sqrt((px_ - lc * vx) ** 2 + (py_ - lc * vy) ** 2)
    r = 0.255
    h = np.sqrt(np.clip(1 - (d / r) ** 2, 0, 1))
    return h, np.clip(q / r, -1, 1), l, np.where(s < 0.5, 1.0, -1.0)

h0, q0, l0, side0 = leg(s, t)           # 이 코
h1, q1, l1, side1 = leg(s, t - 1)       # 윗단 코의 아래 끝(위에 얹힌다)
top = h1 > 0.02
h = np.where(top, h1, h0); q = np.where(top, q1, q0); l = np.where(top, l1, l0); side = np.where(top, side1, side0)
civ = np.where(top, iv + 1, iv)

# 코 중심 방향 → 색
ac = (iu + 0.5 - 0.5 * (COLS % 2)) * da; bc = (civ + 0.5 - 0.5 * (ROWS % 2)) * db
cx_, cy_, cz_ = np.cos(bc) * np.sin(ac), np.sin(bc), np.cos(bc) * np.cos(ac)
land = is_land(cx_, cy_, cz_)
base = np.where(land[..., None], LANDC, SEA)
import os
if os.environ.get('KOREA_ACCENT'):   # 선택: 한가운데(한국) 코만 포인트 색 실로
    korea = land & (iu == 0) & (civ >= 0) & (civ <= 1)
    base = np.where(korea[..., None], np.array([0.91, 0.42, 0.36]), base)

# 실 질감: 가닥의 둥근 단면 + 꼬임 줄 + 잔 보풀
rng = np.random.default_rng(7)
twist = 0.5 + 0.5 * np.sin(2 * math.pi * (l * 3.4 + q * 0.55 * side))
fuzz = rng.normal(0, 1, (N // 2, N // 2)).astype(np.float32)
fuzz = np.asarray(Image.fromarray(fuzz).resize((N, N), Image.BILINEAR))
strand = 0.60 + 0.40 * h                                    # 가닥 사이 골은 어둡게
strand *= 0.86 + 0.14 * twist
strand += 0.10 * (-q * side * 0.6 + 0.4 * q * 0)            # 가닥 한쪽 면에 빛
strand += 0.025 * fuzz
gap = h < 0.05
strand = np.where(gap, 0.50, strand)

# 구 전체 명암(왼쪽 위에서 오는 빛) + 가장자리 어둡게
Lx, Ly, Lz = -0.38, 0.50, 0.78; Ln = math.sqrt(Lx * Lx + Ly * Ly + Lz * Lz)
lam = np.clip((X * Lx + Y * Ly + Z * Lz) / Ln, 0, 1)
sphere = 0.66 + 0.44 * lam
sphere *= 0.80 + 0.20 * np.clip(Z, 0, 1) ** 0.6
# 육지는 살짝 도드라져 보이게(참고 이미지처럼)
sphere = np.where(land, sphere * 1.03, sphere)

col = base * (strand * sphere)[..., None]
col = np.clip(col, 0, 1)

# ---------- 배경 + 그림자 ----------
g = (ys / N)[..., None]
bg = BG_TOP * (1 - g) + BG_BOT * g
sx, sy = (xs / N - CX) / (R * 0.92), (ys / N - (CY + R * 1.02)) / (R * 0.16)
shadow = np.exp(-(sx * sx + sy * sy) * 1.6) * 0.20
bg = bg * (1 - shadow[..., None])
# 구 가장자리 부드럽게
edge = np.clip((1.0 - np.sqrt(rr)) * R * N / 1.5, 0, 1)[..., None]
img = np.where(inside[..., None], col * edge + bg * (1 - edge), bg)

out = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), 'RGB').resize((SIZE, SIZE), Image.LANCZOS)
out.save(OUT)
print('saved', OUT, out.size)
