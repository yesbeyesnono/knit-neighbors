# 코바늘 JIS 기호 94종 SVG 생성기 (knitup 기호 라이브러리 v1.2 후보)
#   입력: tools/crochet-symbols-master.json (knitup_코바늘기호_마스터_v2.xlsx 에서 뽑은 94행: 日本語·한국어·English·사전 ID)
#   출력: resources/symbols/crochet_symbols_v1.2.json + 검수 시트 resources/symbols/review.html
# 원칙: 책 그림을 베끼지 않고 JIS 편목기호 '규칙'으로 부품을 조합해 그린다 → 94종이 한 벌로 일관됨
#   · 사선 수 = 실 감는 횟수(긴 0 · 한길 긴 1 · 두길 2 · 세길 3 · 네길 4)
#   · 밑이 한 점에 모임 = 코에 넣어 뜸 / 밑이 떨어져 있음 = 코 아래(사슬 공간, 束)에서 뜸
#   · 위가 한 점(가로대 하나)에 모임 = 모아뜨기·구슬뜨기
#   · viewBox 0 0 w 48, stroke 2, fill none, currentColor (v1.1 라이브러리와 같은 규격)
import io, json, math, os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
F = lambda v: ('%.1f' % v).rstrip('0').rstrip('.')
HEIGHT = {'hdc': 0, 'dc': 1, 'tr': 2, 'dtr': 3, 'trtr': 4}

def seg(x0, y0, x1, y1): return 'M%s %s %s %s' % (F(x0), F(y0), F(x1), F(y1))
def ell(cx, cy, rx, ry, rot=0, fill=False):
    t = ' transform="rotate(%s %s %s)"' % (F(rot), F(cx), F(cy)) if rot else ''
    f = ' fill="currentColor" stroke="none"' if fill else ''
    return '<ellipse cx="%s" cy="%s" rx="%s" ry="%s"%s%s/>' % (F(cx), F(cy), F(rx), F(ry), t, f)
def path(d, sw=None): return '<path%s d="%s"/>' % (' stroke-width="%s"' % sw if sw else '', ' '.join(d))

def post(bx, by, tx, ty, n=0, bar=6.0, s0=0.30, gap=None, slash=4.6):
    """밑(bx,by)→위(tx,ty) 기둥 + 위 가로대(bar=반폭, 0이면 없음) + 사선 n개"""
    d = [seg(bx, by, tx, ty)]
    L = math.hypot(tx - bx, ty - by); ux, uy = (tx - bx) / L, (ty - by) / L; px, py = -uy, ux
    if px < 0: px, py = -px, -py
    if bar: d.append(seg(tx - px * bar, ty - py * bar, tx + px * bar, ty + py * bar))
    gap = gap if gap is not None else min(0.17, 0.62 / max(n, 1))
    for i in range(n):
        t = s0 + gap * i; cx, cy = tx - ux * L * t, ty - uy * L * t
        vx, vy = px * slash + ux * slash * 0.5, py * slash + uy * slash * 0.5
        if vy > 0: vx, vy = px * slash - ux * slash * 0.5, py * slash - uy * slash * 0.5
        d.append(seg(cx - vx, cy - vy, cx + vx, cy + vy))
    return d
def xmark(cx, cy, r=6.0): return [seg(cx - r, cy - r, cx + r, cy + r), seg(cx + r, cy - r, cx - r, cy + r)]
def tick(bx, by, tx, ty, t=0.62, r=4.6):
    """짧은뜨기 늘림·줄임의 팔에 긋는 짧은 가로 표시"""
    L = math.hypot(tx - bx, ty - by); ux, uy = (tx - bx) / L, (ty - by) / L; px, py = -uy, ux
    cx, cy = bx + ux * L * t, by + uy * L * t
    return seg(cx - px * r, cy - py * r, cx + px * r, cy + py * r)
def hook(x, y, side):  # 걸어뜨기 갈고리: side=-1 앞걸어(왼쪽으로 감김) / +1 뒤걸어
    return 'M%s %s C%s %s %s %s %s %s' % (F(x), F(y), F(x), F(y + 7.5), F(x + side * 7.5), F(y + 8.5), F(x + side * 9.5), F(y + 2.5))
def spread(n, half): return [0.0] if n == 1 else [-half + 2 * half * i / (n - 1) for i in range(n)]

def S_basic(kind, under=False):
    d = xmark(24, 22 if under else 24) if kind == 'sc' else post(24, 40 if not under else 37, 24, 9 if under else 11, HEIGHT[kind], bar=12 if kind != 'sc' else 0, slash=5)
    if under: d.append(seg(13, 43, 35, 43))
    return 48, path(d)

def S_fan(kind, n, space=False, ch=0, w=None):
    """늘려뜨기: 밑에서 위로 부채꼴. space=코 아래에서(밑이 떨어짐). ch=가운데 사슬 수"""
    if kind == 'sc':
        half = 10.5 if n == 2 else 13; xs = spread(n, half); d = []
        for dx in xs: d += [seg(24, 41, 24 + dx, 13.5), tick(24, 41, 24 + dx, 13.5)]
        out = path(d)
        if ch: out += ell(24, 9.5, 4.6, 2.8)
        return 48, out
    w = w or (48 if n <= 3 else 72 if n <= 5 else 84); cx = w / 2
    half = {2: 9, 3: 14, 4: 25, 5: 27}.get(n, 27); xs = spread(n, half); d = []
    hn = HEIGHT[kind]
    for i, dx in enumerate(xs):
        if ch and n == 4: dx = dx + (-2.5 if i < 2 else 2.5)
        if ch and n == 2: dx = dx * 1.45
        bx = cx + (dx * 0.34 if space else 0)
        top_y = 9 + (abs(dx) / half) ** 2 * (7 if n >= 4 else 2)
        d += post(bx, 42, cx + dx, top_y, hn, bar=4.4 if n >= 4 else 5, slash=3.6 if n >= 4 else 4.2)
    out = path(d)
    if ch: out += ell(cx, 7.5 if n == 4 else 9, 4.6, 2.8)
    return w, out

def S_dec(kind, n, skip_mid=False, hooks=0):
    """모아뜨기: 위가 한 점 + 가로대 하나"""
    if kind == 'sc':
        xs = spread(n, 10.5 if n == 2 else 13); d = []
        for i, dx in enumerate(xs):
            d.append(seg(24, 7, 24 + dx, 35))
            if not (skip_mid and dx == 0): d.append(tick(24, 7, 24 + dx, 35))
        if skip_mid: d = [x for x in d]  # 가운데 팔은 표시 없이(건너뛴 코)
        return 48, path(d)
    hn = HEIGHT[kind]; xs = spread(n, 9 if n == 2 else 13); by = 34 if hooks else 42; d = [seg(15, 8, 33, 8)]; extra = ''
    for dx in xs:
        d += post(24 + dx, by, 24, 8, hn, bar=0, s0=0.34, slash=3.8)
        if hooks: d.append(hook(24 + dx, by, hooks))
    return 48, path(d)

def S_cluster(kind, n, space=False, popcorn=False, puff_var=False, leg=False):
    """구슬뜨기(위·아래가 모이는 방추형). popcorn=위에 사슬 고리. puff_var=변형 구슬(위에 조임 코). leg=다리 달린 구슬"""
    hn = HEIGHT[kind]; top, bot = (9, 43) if not (puff_var or leg) else ((22, 44) if puff_var else (26, 45))
    if popcorn: top = 13
    half = {3: 8.5, 5: 11}[n]; xs = spread(n, half); mid = (top + bot) / 2; d = []; thin = []
    for dx in xs:
        bx = 24 + (dx * 0.55 if space else 0); c = 24 + dx * 1.45
        d.append('M%s %s C%s %s %s %s %s %s' % (F(24 if not popcorn else 24 + dx * 0.55), F(top), F(c), F(top + (mid - top) * 0.55), F(c), F(bot - (bot - mid) * 0.55), F(bx), F(bot)))
        for k in range(hn):
            y = mid - 3 + k * 5.5 - (hn - 1) * 2.75; x = 24 + dx * 1.06
            thin.append(seg(x - 2.1, y + 1.3, x + 2.1, y - 1.3))
    out = ''
    if popcorn: d.append(seg(24 - half * 0.55, top, 24 + half * 0.55, top)); out += ell(24, 7.5, 5.2, 3.2)
    elif puff_var: d += [seg(24, top, 24, 9), seg(17, 9, 31, 9), seg(19.5, 15, 28.5, 15)]
    elif leg: d += post(24, top, 24, 7, hn, bar=7, s0=0.5, slash=3.6)
    else: d.append(seg(24 - 8, top, 24 + 8, top))
    return 48, path(d) + (path(thin, '1.6') if thin else '') + out

def S_cross(kind, ch=0, over=None, hooks=0):
    hn = HEIGHT[kind]; by = 34 if hooks else 42; d = []
    a = post(15, by, 33, 9, hn, bar=5, s0=0.2, slash=3.8); b = post(33, by, 15, 9, hn, bar=5, s0=0.2, slash=3.8)
    if over:  # 변형 교차: 뒤로 지나가는 기둥을 교차점에서 끊어 그린다
        back = b if over == 'right' else a; front = a if over == 'right' else b
        bx0, tx0 = (33, 15) if over == 'right' else (15, 33)
        mx, my = 24, (by + 9) / 2; ux, uy = (tx0 - bx0), (9 - by); L = math.hypot(ux, uy); ux, uy = ux / L, uy / L
        back[0] = seg(bx0, by, mx - ux * 4.5, my - uy * 4.5) + ' ' + seg(mx + ux * 4.5, my + uy * 4.5, tx0, 9)
        d = front + back
    else: d = a + b
    if hooks: d += [hook(15, by, hooks), hook(33, by, hooks)]
    out = path(d)
    if ch: out += ell(24, 8, 4.4, 2.6)
    return 48, out

def S_cross13(right_over):
    w = 72; d = []
    ones = (12, 60) if right_over else (60, 12)
    for i in range(3):
        bx = (30 + i * 12) if right_over else (42 - i * 12); tx = bx - 22 if right_over else bx + 22
        p = post(bx, 42, tx, 9, 1, bar=4.4, s0=0.22, slash=3.6)
        ux, uy = tx - bx, -33.0; t = 0.5; mx, my = bx + ux * t, 42 + uy * t   # 1코짜리 아래로 지나가므로 가운데를 끊는다
        p[0] = seg(bx, 42, bx + ux * 0.36, 42 + uy * 0.36) + ' ' + seg(bx + ux * 0.62, 42 + uy * 0.62, tx, 9)
        d += p
    d += post(ones[0], 42, ones[1], 9, 1, bar=4.4, s0=0.12, slash=3.6)
    return w, path(d)

def S_postst(kind, side):
    if kind == 'sc': return 48, path(xmark(24, 13, 5.5) + [seg(24, 13, 24, 31), hook(24, 31, side)])
    return 48, path(post(24, 33, 24, 8, HEIGHT[kind], bar=11, s0=0.34, slash=4.6) + [hook(24, 33, side)])

def S_y(kind='Y', wraps=2, arms_ch=0, combo=False, w=48):
    """Y자·역Y자·X자(クロス)·역Y+Y 조합. 허리(waist)에 사선"""
    cx = w / 2; d = []; out = ''
    if kind == 'Y':       # 기둥 + 중간에서 갈라져 나온 가지
        d += post(cx - 4, 42, cx - 4, 9, 2, bar=5.5, s0=0.2, gap=0.42, slash=4)
        d += post(cx - 4, 27, cx + 13, 9, 1, bar=5, s0=0.45, slash=3.6)
    elif kind == 'invY':  # 밑 두 다리가 모여 기둥 하나로
        d += [seg(cx - 11, 42, cx, 25), seg(cx + 11, 42, cx, 25)] + post(cx, 25, cx, 8, wraps - 1, bar=7, s0=0.34, gap=0.3, slash=4)
        d += [tick(cx - 11, 42, cx, 25, 0.5, 3.4), tick(cx + 11, 42, cx, 25, 0.5, 3.4)]
    elif kind == 'X':     # 밑 두 다리 → 허리 → 위 두 팔 (+사이 사슬)
        waist = 0 if wraps == 2 else 7; half = 11 if arms_ch <= 1 else 15 + (arms_ch - 2) * 3; my = 25
        d += [seg(cx - half, 42, cx, my + waist / 2), seg(cx + half, 42, cx, my + waist / 2)]
        if waist: d.append(seg(cx, my + waist / 2, cx, my - waist / 2))
        d += post(cx, my - waist / 2, cx - half, 10, 1, bar=4.4, s0=0.4, slash=3.4) + post(cx, my - waist / 2, cx + half, 10, 1, bar=4.4, s0=0.4, slash=3.4)
        d += [tick(cx - half, 42, cx, my + waist / 2, 0.5, 3.2), tick(cx + half, 42, cx, my + waist / 2, 0.5, 3.2)]
        for i in range(arms_ch): out += ell(cx + (i - (arms_ch - 1) / 2) * 8.4, 7.5, 3.8, 2.3)
    if combo:             # 역Y 위에 Y: 다리 둘 → 긴 허리(사선) → 팔 둘
        d = [seg(cx - 10, 43, cx, 31), seg(cx + 10, 43, cx, 31)] + post(cx, 31, cx, 19, wraps - 2, bar=0, s0=0.3, gap=0.4, slash=3.6)
        d += post(cx, 19, cx - 10, 8, 1, bar=4.2, s0=0.45, slash=3.2) + post(cx, 19, cx + 10, 8, 1, bar=4.2, s0=0.45, slash=3.2)
        out = ell(cx, 6.5, 3.8, 2.3)
    return w, path(d) + out

def S_triangle():
    d = [];  # 높이가 차례로 줄어드는 기둥들이 위 한 점에서 모임
    for i, bx in enumerate([9, 17, 25, 33, 41]): d += post(bx, 43, 38, 7, 0, bar=0) + [tick(bx, 43, 38, 7, 0.45, 3.2)] * (1 if i < 4 else 0)
    return 48, path(d + [seg(32, 7, 44, 7)])
def S_solomon(): return 48, '<path d="M24 14 C34 22 30 38 24 44 C18 38 14 22 24 14 Z"/>' + path(xmark(24, 9, 3.6))
def S_bullion(): return 48, path(post(24, 42, 24, 8, 0, bar=9)) + ell(24, 20, 6.5, 3.2) + ell(24, 25.5, 6.5, 3.2) + ell(24, 31, 6.5, 3.2)
def S_ring(kind):
    if kind == 'sc': return 48, '<path d="M13 12 13 28 C13 40 35 40 35 28 L35 12"/>' + path(xmark(24, 22, 5))
    return 48, '<path d="M12 6 12 32 C12 45 36 45 36 32 L36 6"/>' + path(post(24, 38, 24, 11, 1, bar=7, slash=4))
def S_topmark(mark):
    d = xmark(24, 32, 6.5)
    if mark == 'tilde': return 48, path(d) + '<path d="M12 14 C16 7 21 7 24 12 C27 17 32 17 36 10"/>'
    if mark == 'loop': return 48, path(d) + '<path d="M15 20 C22 20 30 6 24 6 C18 6 26 20 33 20"/>'
    return 48, path(d)
def S_picot(variant):
    arch = ell(24, 12, 4, 7.2) + ell(14.5, 19, 4, 7.2, -52) + ell(33.5, 19, 4, 7.2, 52)
    if variant == 'ch3': return 48, arch.replace('cy="12"', 'cy="17"').replace('cy="19"', 'cy="24"').replace(' 19)', ' 24)')
    if variant == 'sl_on_sc': return 48, arch + '<circle cx="24" cy="29" r="2.6" fill="currentColor" stroke="none"/>' + path(xmark(24, 39, 5))
    if variant == 'sc': return 48, arch + path(xmark(24, 33, 5.5))
    if variant == 'sl_on_dc':
        small = ell(24, 5.5, 2.6, 4.6) + ell(18, 10, 2.6, 4.6, -52) + ell(30, 10, 2.6, 4.6, 52)
        return 48, small + '<circle cx="24" cy="16.5" r="2.4" fill="currentColor" stroke="none"/>' + path(post(24, 44, 24, 20, 1, bar=8, s0=0.36, slash=4.2))
    w = 72; out = ''  # 사슬 위의 빼뜨기 피코: 사슬 아치 가운데에 피코 고리
    for cx, cy, r in [(10, 38, -40), (20, 29, -40), (52, 29, 40), (62, 38, 40)]: out += ell(cx, cy, 5.6, 2.8, r)
    out += ell(36, 8, 2.8, 5) + ell(29.5, 13, 2.8, 5, -52) + ell(42.5, 13, 2.8, 5, 52) + '<circle cx="36" cy="20.5" r="2.6" fill="currentColor" stroke="none"/>'
    return w, out
def S_into_sc(on_leg):
    """짧은뜨기와 같은 코에 / 짧은뜨기의 다리에 한길 긴 3코"""
    w = 72; bx, by = (16, 40) if not on_leg else (20, 33); d = xmark(14, 38, 5.2)
    for tx, ty in [(30, 8), (46, 13), (58, 24)]: d += post(bx, by, tx, ty, 1, bar=4.2, s0=0.3, slash=3.4)
    return w, path(d)

# No(마스터표 번호) → (라이브러리 키, 그리기). 같은 JIS 기호를 쓰는 항목은 같은 그림(뜨는 법만 다름)
SPEC = {
 1: ('chain', lambda: (48, ell(24, 24, 10, 6))), 2: ('slip', lambda: (48, ell(24, 24, 8, 4.6, fill=True))), 3: ('sc', lambda: S_basic('sc')),
 4: ('hdc', lambda: S_basic('hdc')), 5: ('dc', lambda: S_basic('dc')), 6: ('tr', lambda: S_basic('tr')), 7: ('dtr', lambda: S_basic('dtr')), 8: ('trtr', lambda: S_basic('trtr')),
 9: ('hdc3_cl', lambda: S_cluster('hdc', 3)), 10: ('dc3_cl', lambda: S_cluster('dc', 3)), 11: ('dc5_cl', lambda: S_cluster('dc', 5)),
 12: ('hdc3_cl_sp', lambda: S_cluster('hdc', 3, space=True)), 13: ('dc3_cl_sp', lambda: S_cluster('dc', 3, space=True)), 14: ('dc5_cl_sp', lambda: S_cluster('dc', 5, space=True)),
 15: ('tr5_cl', lambda: S_cluster('tr', 5)), 16: ('hdc3_puff', lambda: S_cluster('hdc', 3, puff_var=True)), 17: ('hdc3_puff_sp', lambda: S_cluster('hdc', 3, space=True, puff_var=True)),
 18: ('dc5_pc', lambda: S_cluster('dc', 5, popcorn=True)), 19: ('tr5_pc', lambda: S_cluster('tr', 5, popcorn=True)), 20: ('dc5_pc_sp', lambda: S_cluster('dc', 5, space=True, popcorn=True)), 21: ('hdc5_pc', lambda: S_cluster('hdc', 5, popcorn=True)),
 22: ('sc_inc', lambda: S_fan('sc', 2)), 23: ('sc_inc_ch1', lambda: S_fan('sc', 2, ch=1)), 24: ('sc_inc3', lambda: S_fan('sc', 3)),
 25: ('hdc_inc', lambda: S_fan('hdc', 2)), 26: ('hdc_inc3', lambda: S_fan('hdc', 3)), 27: ('dc_inc', lambda: S_fan('dc', 2)),
 28: ('hdc_inc_sp', lambda: S_fan('hdc', 2, space=True)), 29: ('hdc_inc3_sp', lambda: S_fan('hdc', 3, space=True)), 30: ('dc_inc_sp', lambda: S_fan('dc', 2, space=True)),
 31: ('v_st', lambda: S_fan('dc', 2, ch=1)), 32: ('dc_inc3', lambda: S_fan('dc', 3)), 33: ('shell5', lambda: S_fan('dc', 5)),
 34: ('v_st_sp', lambda: S_fan('dc', 2, space=True, ch=1)), 35: ('dc_inc3_sp', lambda: S_fan('dc', 3, space=True)), 36: ('shell5_sp', lambda: S_fan('dc', 5, space=True)),
 37: ('shell4_ch1', lambda: S_fan('dc', 4, ch=1)), 38: ('shell4_ch1_sp', lambda: S_fan('dc', 4, space=True, ch=1)),
 39: ('dc3_in_sc', lambda: S_into_sc(False)), 40: ('dc3_on_sc_leg', lambda: S_into_sc(True)),
 41: ('sc_dec', lambda: S_dec('sc', 2)), 42: ('hdc_dec', lambda: S_dec('hdc', 2)), 43: ('dc_dec', lambda: S_dec('dc', 2)), 44: ('sc_dec3', lambda: S_dec('sc', 3)),
 45: ('sc_dec3_skip', lambda: S_dec('sc', 3, skip_mid=True)), 46: ('hdc_dec3', lambda: S_dec('hdc', 3)), 47: ('dc_dec3', lambda: S_dec('dc', 3)),
 48: ('sc_blo_rows', lambda: S_basic('sc', under=True)), 49: ('sc_blo_round', lambda: S_basic('sc', under=True)), 50: ('sc_ridge', lambda: S_basic('sc', under=True)),
 51: ('hdc_blo', lambda: S_basic('hdc', under=True)), 52: ('dc_blo', lambda: S_basic('dc', under=True)),
 53: ('picot', lambda: S_picot('ch3')), 54: ('picot_sl_on_sc', lambda: S_picot('sl_on_sc')), 55: ('picot_sc', lambda: S_picot('sc')), 56: ('picot_sl_on_dc', lambda: S_picot('sl_on_dc')), 57: ('picot_sl_on_ch', lambda: S_picot('sl_on_ch')),
 58: ('cross_hdc', lambda: S_cross('hdc')), 59: ('cross_dc', lambda: S_cross('dc')), 60: ('cross_dc_ch1', lambda: S_cross('dc', ch=1)),
 61: ('cross_dc_right', lambda: S_cross('dc', over='right')), 62: ('cross_dc_left', lambda: S_cross('dc', over='left')), 63: ('cross_tr', lambda: S_cross('tr')),
 64: ('cross_1x3_right', lambda: S_cross13(True)), 65: ('cross_1x3_left', lambda: S_cross13(False)),
 66: ('fpsc', lambda: S_postst('sc', -1)), 67: ('fphdc', lambda: S_postst('hdc', -1)), 68: ('fpdc', lambda: S_postst('dc', -1)),
 69: ('bpsc', lambda: S_postst('sc', 1)), 70: ('bphdc', lambda: S_postst('hdc', 1)), 71: ('bpdc', lambda: S_postst('dc', 1)),
 72: ('fpdc_dec', lambda: S_dec('dc', 2, hooks=-1)), 73: ('fptr_dec', lambda: S_dec('tr', 2, hooks=-1)), 74: ('fpdc_cross_ch1', lambda: S_cross('dc', ch=1, hooks=-1)),
 75: ('fpdc_inc', lambda: (48, path(post(24, 33, 13, 9, 1, bar=5, slash=3.8) + post(24, 33, 35, 9, 1, bar=5, slash=3.8) + [hook(24, 33, -1)]))),
 76: ('y_st', lambda: S_y('Y')), 77: ('inv_y_2', lambda: S_y('invY', wraps=2)), 78: ('inv_y_3', lambda: S_y('invY', wraps=3)),
 79: ('x_st_2', lambda: S_y('X', wraps=2, arms_ch=1)), 80: ('x_st_3', lambda: S_y('X', wraps=3, arms_ch=2, w=60)), 81: ('x_st_tr', lambda: S_y('X', wraps=3, arms_ch=3, w=72)),
 82: ('dc5_cl_leg', lambda: S_cluster('dc', 5, leg=True)), 83: ('inv_y_y_3', lambda: S_y(combo=True, wraps=3)), 84: ('triangle', S_triangle), 85: ('inv_y_y_4', lambda: S_y(combo=True, wraps=4)),
 86: ('solomon', S_solomon), 87: ('bullion7', S_bullion), 88: ('sc_loop', lambda: S_ring('sc')), 89: ('dc_loop', lambda: S_ring('dc')),
 90: ('rsc', lambda: S_topmark('tilde')), 91: ('twisted_sc', lambda: S_topmark('loop')), 92: ('rsc_var_2loops', lambda: S_topmark('tilde')), 93: ('rsc_var_1loop', lambda: S_topmark('tilde')), 94: ('yo_sc', lambda: S_topmark('none')),
}
SAME = {49: 48, 50: 48, 92: 90, 93: 90, 94: 3}   # JIS 기호가 같은 항목(뜨는 법만 다름) — 검수 시트에 표시

def main():
    master = json.load(io.open(os.path.join(ROOT, 'tools', 'crochet-symbols-master.json'), encoding='utf-8'))
    out = {'_meta': {'version': '1.2-draft', 'basis': 'JIS L 0201 편목기호 규칙으로 부품 조합 생성 (tools/gen-crochet-symbols.py). 명칭: 한국 관행(긴/한길 긴/두길 긴/세길/네길) — 2026-09-21 대표 확정',
                     'viewBox': '0 0 w 48', 'stroke': 'stroke 2 · fill none · linecap round · currentColor'}, 'symbols': {}}
    cards = []
    for m in master:
        key, fn = SPEC[m['no']]; w, svg = fn()
        out['symbols'][key] = {'no': m['no'], 'w': w, 'svg': svg, 'jp': m['jp'], 'ko': m['ko'], 'en': m['en'], 'abbr': m['abbr'], 'tech': m['tech'] if m['tech'].startswith('C') else None, 'same_as': SPEC[SAME[m['no']]][0] if m['no'] in SAME else None}
        cards.append((m, key, w, svg))
    os.makedirs(os.path.join(ROOT, 'resources', 'symbols'), exist_ok=True)
    json.dump(out, io.open(os.path.join(ROOT, 'resources', 'symbols', 'crochet_symbols_v1.2.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    esc = lambda s: (s or '').replace('&', '&amp;').replace('<', '&lt;')
    html = ['<!doctype html><meta charset="utf-8"><title>코바늘 기호 94종 검수 시트</title><style>body{font-family:-apple-system,"Malgun Gothic",sans-serif;margin:20px;color:#3C4043}h1{font-size:20px}h2{font-size:15px;margin:22px 0 8px;padding-top:10px;border-top:1px solid #ddd}.g{display:grid;grid-template-columns:repeat(auto-fill,minmax(330px,1fr));gap:10px}.c{border:1px solid #e3e3e3;border-radius:10px;padding:10px;display:grid;grid-template-columns:150px 1fr;gap:4px 10px;align-items:center}.c .pic{display:flex;gap:6px;align-items:center}.c svg{background:#fafafa;border-radius:6px;color:#3C4043}.c img{height:44px;border-radius:4px;border:1px solid #eee}.no{font-weight:700;color:#5C7A4C}.ko{font-weight:600;font-size:14px}.jp,.en{font-size:12px;color:#6A6E73}.tag{display:inline-block;font-size:11px;padding:1px 6px;border-radius:99px;background:#E6EDDF;color:#5C7A4C;margin-right:4px}.tag.new{background:#F6EBD3;color:#8a6d1a}.tag.same{background:#eee;color:#666}</style>',
            '<h1>코바늘 기호 94종 검수 시트 <small style="font-weight:400;color:#6A6E73">왼쪽 = 새로 그린 기호(SVG) · 오른쪽 = 원본 표의 기호. 모양이 다르면 번호를 알려 주세요</small></h1>']
    sec = None
    for m, key, w, svg in cards:
        if m['sec'] != sec: html.append(('</div>' if sec else '') + '<h2>%s</h2><div class="g">' % esc(m['sec'])); sec = m['sec']
        tags = ('<span class="tag">%s</span>' % m['tech'] if m['tech'].startswith('C') else '<span class="tag new">새 기법 후보</span>') + ('<span class="tag same">기호는 %d번과 같음</span>' % SAME[m['no']] if m['no'] in SAME else '')
        html.append('<div class="c"><div class="pic"><svg width="%d" height="56" viewBox="0 0 %d 48" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">%s</svg><img src="ref/%02d.png" alt=""></div><div><span class="no">%d</span> <span class="ko">%s</span><div class="jp">%s</div><div class="en">%s · <code>%s</code></div>%s</div></div>' % (round(56 * w / 48), w, svg, m['no'], m['no'], esc(m['ko']), esc(m['jp']), esc(m['en']), key, tags))
    html.append('</div>')
    io.open(os.path.join(ROOT, 'resources', 'symbols', 'review.html'), 'w', encoding='utf-8').write('\n'.join(html))
    print('symbols', len(out['symbols']), 'unique keys', len(set(k for k, _ in SPEC.values())))
main()
