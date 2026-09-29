# 색상 실물 사진 만들기 (normalized.json 기준)
#  ① 옵션 이미지(쎄비 option_button)가 있는 색: 바로 내려받아 160px 정사각으로
#  ② 없는 실: 상세 이미지(chart_images)에서 색상표 타일 자동 검출(nakyang-swatches 방식) → 옵션 번호 순서와 개수가 맞으면 자동 매칭, 아니면 검수 몽타주
# 결과: <out>/photos/<site>/<slug>_<no>.jpg + <out>/photos.json [{site, product, no, name, file, hex, mode, how}] + review_*.jpg
# 사용: python tools/shops-photos.py <out폴더> [site]
import io, os, sys, json, re, hashlib, urllib.request, urllib.parse, importlib.util
import numpy as np
from PIL import Image, ImageDraw, ImageFont
ROOT = os.path.join(os.path.dirname(__file__), '..')
RESUME = '--resume' in sys.argv; ARGS = [a for a in sys.argv[1:] if a != '--resume']
OUT = ARGS[0]; ONLY = ARGS[1] if len(ARGS) > 1 else None   # --resume: map 파일에 있는 실도 이미 결과가 있으면 건너뜀
rows = json.load(io.open(os.path.join(OUT, 'normalized.json'), encoding='utf-8'))
UA = {'User-Agent': 'Mozilla/5.0'}
FONT = ImageFont.truetype('C:/Windows/Fonts/malgun.ttf', 13)
spec = importlib.util.spec_from_file_location('sw', os.path.join(ROOT, 'tools', 'nakyang-swatches.py'))
# nakyang-swatches 는 실행 시 argv 를 읽으므로 함수만 빌려 쓴다
src = io.open(os.path.join(ROOT, 'tools', 'nakyang-swatches.py'), encoding='utf-8').read().split("if __name__ == '__main__':")[0]
src = src.replace("WORK = sys.argv[1]\nONLY = sys.argv[2:]", "WORK = OUT\nONLY = []").replace("DATA = json.load(io.open(os.path.join(ROOT, 'resources', 'yarn', 'nakyang.json'), encoding='utf-8'))", "DATA = []")
ns = {'OUT': OUT, 'sys': sys, 'os': os, 'io': io, 'json': json, 're': re, 'urllib': urllib, 'np': np, 'Image': Image, 'ImageDraw': ImageDraw, 'ImageFont': ImageFont, '__file__': os.path.join(ROOT, 'tools', 'nakyang-swatches.py')}
exec(src, ns)
find_tiles, dominant, opt_key, fetch = ns['find_tiles'], ns['dominant'], ns['opt_key'], ns['fetch']

def slug(s): return re.sub(r'[^A-Za-z0-9가-힣]+', '_', s).strip('_')[:40] or hashlib.md5(s.encode()).hexdigest()[:8]
def dl(u):
    f = os.path.join(OUT, 'img', hashlib.md5(u.encode()).hexdigest() + os.path.splitext(urllib.parse.urlparse(u).path)[1][:5])
    os.makedirs(os.path.dirname(f), exist_ok=True)
    if not os.path.exists(f):
        req = urllib.request.Request(urllib.parse.quote(u, safe=':/?=&%'), headers=UA)
        with urllib.request.urlopen(req, timeout=60) as r: io.open(f, 'wb').write(r.read())
    return f
def square(img, side=160):
    w, h = img.size; s = min(w, h); return img.convert('RGB').crop(((w - s) // 2, (h - s) // 2, (w - s) // 2 + s, (h - s) // 2 + s)).resize((side, side), Image.LANCZOS)

# 검수 결과: <out>/photos_map.txt 의 줄 "site|product: idx:색번호 idx:색번호=이름 …" → 타일을 그 색으로 연결(=이름 은 옵션에 없는 색을 새로 넣을 때)
MAP = {}
mp = os.path.join(OUT, 'photos_map.txt')
if os.path.exists(mp):
    for line in io.open(mp, encoding='utf-8'):
        if ':' not in line or '|' not in line: continue
        head, rest = line.strip().split(':', 1); site_, prod_ = head.split('|', 1)
        toks = []
        for x in rest.split():   # ':' 없는 낱말은 앞 이름에 붙임(이름에 띄어쓰기 허용)
            if ':' in x: toks.append(x)
            elif toks: toks[-1] += ' ' + x
        MAP[(site_.strip(), prod_.strip())] = {int(a): b for a, b in (x.split(':', 1) for x in toks)}   # 값은 '번호' 또는 '번호=이름'(옵션에 없는 색 추가)
res_path = os.path.join(OUT, 'photos.json'); res = json.load(io.open(res_path, encoding='utf-8')) if os.path.exists(res_path) else []
done = {(r['site'], r['product'], r['no'] or r['name']) for r in res}
for r in rows:
    if ONLY and r['site'] != ONLY: continue
    if not r['colors']: continue
    site = r['site']; pdir = os.path.join(OUT, 'photos', site); os.makedirs(pdir, exist_ok=True); sl = slug(r['product'])
    if any((site, r['product'], c['no'] or c['name']) in done for c in r['colors']) and ((site, r['product']) not in MAP or RESUME): continue
    if (site, r['product']) in MAP: res = [x for x in res if not (x['site'] == site and x['product'] == r['product'])]
    # ① 옵션 이미지
    if all(c.get('img') for c in r['colors']):
        ok = 0
        for c in r['colors']:
            try:
                im = square(Image.open(dl(c['img'])))
                if np.asarray(im).mean() > 243: continue   # 흰 빈 칸(자리표시 이미지)은 건너뜀
                fn = f"{sl}_{slug(c['no'] or c['name'])}.jpg"; im.save(os.path.join(pdir, fn), quality=80)
                hexes, mode = dominant(im); res.append({'site': site, 'product': r['product'], 'brand': r['brand'], 'no': c['no'], 'name': c['name'], 'file': f'{site}/{fn}', 'hex': hexes, 'mode': mode, 'how': 'option'}); ok += 1
            except Exception as e: print('  opt fail', r['product'], c['no'], e)
        print(site, r['product'], 'option images', ok, flush=True)
        io.open(res_path, 'w', encoding='utf-8').write(json.dumps(res, ensure_ascii=False)); continue
    # ② 색상표 타일
    tiles = []
    cimgs = sorted(r.get('chart_images', []), key=lambda u: (0 if re.search(r'color|chart|컬러|swatch|_c_|colour', u, re.I) else 1))[:20]   # 색상표로 보이는 주소를 먼저
    for u in cimgs:
        try: img = Image.open(dl(u))
        except Exception: continue
        if img.size[0] < 500 or img.size[1] < 300: continue
        try: t = find_tiles(img)
        except Exception: t = []
        if len(t) >= 3: tiles += [(img, x) for x in t]
        if len(tiles) >= len(r['colors']) and re.search(r'color|chart|컬러|swatch|_c_|colour', u, re.I): break   # 색상표 하나로 충분하면 중단
    if not tiles: print(site, r['product'], 'no chart', flush=True); continue
    opts = sorted(r['colors'], key=lambda c: opt_key(c['no'] or c['name'])); guess = opts if len(opts) == len(tiles) else None
    mm = MAP.get((site, r['product']))
    if mm:   # 사람이 읽은 라벨로 연결
        byno = {(c['no'] or c['name']): c for c in r['colors']}
        def _g(i):
            if i not in mm: return None
            v = mm[i]
            if '=' in v: no, name = v.split('=', 1); return {'no': no, 'name': name}   # 사람이 적은 번호=이름이 우선(옵션의 번호 없는 항목을 덮음)
            return byno.get(v) or {'no': v, 'name': v}
        guess = [_g(i) for i in range(len(tiles))]
    cells = []
    for i, (img, (x, y, w, h, lab)) in enumerate(tiles):
        side = min(w, h); crop = img.convert('RGB').crop((x + (w - side) // 2, y + (h - side) // 2, x + (w - side) // 2 + side, y + (h - side) // 2 + side)).resize((160, 160), Image.LANCZOS)
        lx, ly, lw, lh = lab; labimg = img.convert('RGB').crop((lx, ly, lx + lw, ly + lh))
        cells.append((crop, labimg))
        if guess and guess[i]:
            c = guess[i]; fn = f"{sl}_{slug(c['no'] or c['name'])}.jpg"; crop.save(os.path.join(pdir, fn), quality=80); hexes, mode = dominant(crop)
            res.append({'site': site, 'product': r['product'], 'brand': r['brand'], 'no': c['no'], 'name': c['name'], 'file': f'{site}/{fn}', 'hex': hexes, 'mode': mode, 'how': 'chart-auto'})
    # 검수 몽타주(자동 매칭이든 아니든 저장 — 불일치는 사람이 라벨을 읽어 map 파일로)
    CW, CH, COLS = 150, 205, 8; rws = (len(cells) + COLS - 1) // COLS
    mont = Image.new('RGB', (CW * COLS, CH * rws + 24), 'white'); d = ImageDraw.Draw(mont)
    d.text((6, 4), f"{site} {r['product']} — 타일 {len(cells)} / 옵션 {len(opts)}" + ('' if guess else '  (개수 불일치)'), fill='black', font=FONT)
    for i, (crop, labimg) in enumerate(cells):
        cx, cy = (i % COLS) * CW, 24 + (i // COLS) * CH; mont.paste(crop.resize((120, 120)), (cx + 15, cy + 4))
        lw = min(140, int(labimg.size[0] * 22 / max(1, labimg.size[1]))); mont.paste(labimg.resize((lw, 22)), (cx + 5, cy + 128))
        d.text((cx + 5, cy + 152), f"#{i}", fill='red', font=FONT); d.text((cx + 30, cy + 152), ((guess[i]['no'] + ' ' + guess[i]['name']) if guess and guess[i] else '?')[:14], fill='black', font=FONT)
    os.makedirs(os.path.join(OUT, 'review'), exist_ok=True); mont.save(os.path.join(OUT, 'review', f'{site}_{sl}.jpg'), quality=80)
    if not guess:   # 타일은 저장해 두고(idx 이름) 나중에 map 으로 연결
        for i, (crop, _) in enumerate(cells): crop.save(os.path.join(pdir, f'{sl}__tile{i}.jpg'), quality=80)
    print(site, r['product'], 'chart tiles', len(cells), 'opts', len(opts), 'auto' if guess else 'REVIEW', flush=True)
    io.open(res_path, 'w', encoding='utf-8').write(json.dumps(res, ensure_ascii=False))
print('done', len(res))
