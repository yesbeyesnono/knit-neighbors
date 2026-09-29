# 낙양모사 상세 이미지(color chart)에서 색상 타일을 잘라낸다 → 검수 몽타주 + 타일(200px) + 대표색(hex)
# 사용: python tools/nakyang-swatches.py <작업폴더> [상품번호...]
#   작업폴더/img/       원본 상세 이미지 캐시
#   작업폴더/tiles/<no>/<idx>.jpg   타일
#   작업폴더/review_<no>.jpg        검수용(타일 + 라벨 조각 + 번호 추정)
#   작업폴더/tiles.json             {no: [{idx, x, y, w, h, hex[], mode, guess}]}
import sys, os, io, json, re, urllib.request
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(__file__), '..')
DATA = json.load(io.open(os.path.join(ROOT, 'resources', 'yarn', 'nakyang.json'), encoding='utf-8'))
WORK = sys.argv[1]
ONLY = sys.argv[2:]
SHARED_BANNER = '82_212e41099dd4cb29f059a1d8aebe4007'
FONT = ImageFont.truetype('C:/Windows/Fonts/malgun.ttf', 13)

def fetch(url):
    os.makedirs(os.path.join(WORK, 'img'), exist_ok=True)
    f = os.path.join(WORK, 'img', os.path.basename(url))
    if not os.path.exists(f):
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=60) as r: io.open(f, 'wb').write(r.read())
    return f

def segments(mask1d, thr, min_gap, min_len):
    on = mask1d > thr; segs = []; start = None
    for i, v in enumerate(on):
        if v and start is None: start = i
        if not v and start is not None:
            segs.append([start, i]); start = None
    if start is not None: segs.append([start, len(on)])
    merged = []
    for s in segs:
        if merged and s[0] - merged[-1][1] < min_gap: merged[-1][1] = s[1]
        else: merged.append(s)
    return [s for s in merged if s[1] - s[0] >= min_len]

def content_mask(a):
    mn = a.min(axis=2); mx = a.max(axis=2)
    return (mn < 225) | ((mx.astype(int) - mn.astype(int)) > 25)

def find_tiles(img):
    a = np.asarray(img.convert('RGB')); H, W = a.shape[:2]
    m = content_mask(a)
    rows = m.mean(axis=1)
    bands = segments(rows, 0.02, 4, 8)
    tiles = []
    for bi, (y0, y1) in enumerate(bands):
        h = y1 - y0
        if h < 90: continue
        # 바로 아래 글자 띠(라벨)가 있어야 색상 차트로 본다
        lab = None
        for (ly0, ly1) in bands[bi + 1:bi + 3]:
            if ly0 - y1 > 60: break
            if 8 <= ly1 - ly0 < 60: lab = (ly0, ly1); break
        if not lab: continue
        cols = m[y0:y1].mean(axis=0)
        segs = segments(cols, 0.05, 6, 60)
        lcols = m[lab[0]:lab[1]].mean(axis=0)
        lsegs = segments(lcols, 0.01, 22, 12)
        lcent = [(s[0] + s[1]) / 2 for s in lsegs]
        for (x0, x1) in segs:
            w = x1 - x0
            sub = m[y0:y1, x0:x1]; rr = np.where(sub.mean(axis=1) > 0.05)[0]
            if len(rr) == 0: continue
            ty0, ty1 = y0 + rr[0], y0 + rr[-1] + 1; th = ty1 - ty0
            if th < 80: continue
            asp = w / th
            cents = [c for c in lcent if x0 - 10 <= c <= x1 + 10]
            if 0.6 <= asp <= 1.6 and 70 <= w <= 500:
                tiles.append((x0, ty0, w, th, (x0, lab[0], w, lab[1] - lab[0])))
            elif asp > 1.6 and len(cents) >= 2:
                bounds = [x0] + [int((cents[i] + cents[i + 1]) / 2) for i in range(len(cents) - 1)] + [x1]
                for i in range(len(cents)):
                    cx0, cx1 = bounds[i], bounds[i + 1]; cw = cx1 - cx0
                    side = min(cw, th); sx = int(cents[i] - side / 2); sx = max(cx0, min(sx, cx1 - side))
                    tiles.append((sx, ty0 + (th - side) // 2, side, side, (cx0, lab[0], cw, lab[1] - lab[0])))
    return tiles

def dominant(tile):
    t = tile.resize((80, 80)); c = t.crop((12, 12, 68, 68)).quantize(colors=5, method=Image.Quantize.MEDIANCUT).convert('RGB')
    cnt = {}
    for px in c.getdata(): cnt[px] = cnt.get(px, 0) + 1
    tot = sum(cnt.values()); cols = sorted(cnt.items(), key=lambda x: -x[1])
    def dist(p, q): return sum((p[i] - q[i]) ** 2 for i in range(3)) ** .5
    keep = [cols[0]]
    for p, n in cols[1:]:
        if n / tot >= 0.18 and all(dist(p, k[0]) > 70 for k in keep): keep.append((p, n))
    hexes = ['#%02x%02x%02x' % p for p, n in keep[:3]]
    return hexes, ('solid' if len(hexes) == 1 else 'mix')

def opt_key(o):
    m = re.match(r'\s*([A-Za-z]*)(\d+)([A-Za-z]*)', o)
    return (m.group(1), int(m.group(2)), m.group(3)) if m else ('~', 0, o)

def run(prod):
    no = prod['no']; opts = [o for o in prod['opts']]
    imgs = [u for u in prod['dets'] if SHARED_BANNER not in u]
    found = []   # (img, tiles)
    for u in imgs:
        try: img = Image.open(fetch(u))
        except Exception as e: print('  img fail', u[-30:], e); continue
        t = find_tiles(img)
        if len(t) >= 2: found.append((img, t))
    tiles = [(img, tl) for img, ts in found for tl in ts]
    print(no, prod['name'], 'opts', len(opts), 'tiles', len(tiles), [len(ts) for _, ts in found])
    sorted_opts = sorted(opts, key=opt_key)
    guess = sorted_opts if len(sorted_opts) == len(tiles) else None
    os.makedirs(os.path.join(WORK, 'tiles', no), exist_ok=True)
    out = []; cells = []
    for i, (img, (x, y, w, h, lab)) in enumerate(tiles):
        side = min(w, h); crop = img.convert('RGB').crop((x + (w - side) // 2, y + (h - side) // 2, x + (w - side) // 2 + side, y + (h - side) // 2 + side)).resize((200, 200), Image.LANCZOS)
        crop.save(os.path.join(WORK, 'tiles', no, f'{i}.jpg'), quality=85)
        hexes, mode = dominant(crop)
        lx, ly, lw, lh = lab; labimg = img.convert('RGB').crop((lx, ly, lx + lw, ly + lh))
        out.append({'idx': i, 'hex': hexes, 'mode': mode, 'guess': guess[i] if guess else None})
        cells.append((crop, labimg, out[-1]))
    # 검수 몽타주
    CW, CH, COLS = 150, 205, 8
    rows = (len(cells) + COLS - 1) // COLS
    mont = Image.new('RGB', (CW * COLS, CH * rows + 24), 'white'); d = ImageDraw.Draw(mont)
    d.text((6, 4), f"{no} {prod['name']} — 타일 {len(cells)} / 옵션 {len(opts)}" + ('' if guess else '  (개수 불일치: 라벨 보고 번호 적기)'), fill='black', font=FONT)
    for i, (crop, labimg, o) in enumerate(cells):
        cx, cy = (i % COLS) * CW, 24 + (i // COLS) * CH
        mont.paste(crop.resize((120, 120)), (cx + 15, cy + 4))
        lw = min(140, int(labimg.size[0] * 22 / max(1, labimg.size[1]))); mont.paste(labimg.resize((lw, 22)), (cx + 5, cy + 128))
        d.text((cx + 5, cy + 152), f"#{i}", fill='red', font=FONT)
        d.text((cx + 30, cy + 152), (o['guess'] or '?')[:14], fill='black', font=FONT)
        for k, hx in enumerate(o['hex'][:3]): d.rectangle([cx + 5 + k * 20, cy + 172, cx + 22 + k * 20, cy + 189], fill=hx)
    mont.save(os.path.join(WORK, f'review_{no}.jpg'), quality=80)
    return out

if __name__ == '__main__':
    res_path = os.path.join(WORK, 'tiles.json')
    res = json.load(io.open(res_path, encoding='utf-8')) if os.path.exists(res_path) else {}
    for p in DATA:
        if ONLY and p['no'] not in ONLY: continue
        try: res[p['no']] = run(p)
        except Exception as e: print('ERR', p['no'], e)
        io.open(res_path, 'w', encoding='utf-8').write(json.dumps(res, ensure_ascii=False))
    print('done')
