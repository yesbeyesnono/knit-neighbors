# 다이소 목록 → 실(제품) 이름 · 색 이름 나누기 → 색 사진(160px) + photos_apply.json(색이 없으면 새로 만듦)
import json, io, os, re, sys, hashlib, urllib.request
import numpy as np
from PIL import Image
ROOT = r'C:\Users\yesbe\OneDrive\Documents\Claude\Projects\knit-neighbors'
S = r'C:/Users/yesbe/AppData/Local/Temp/claude/0422a6549ab0c97e/133c9d28-0c4f-477d-bad5-02a0fc6721eb/scratchpad/daiso'
src = io.open(os.path.join(ROOT, 'tools', 'nakyang-swatches.py'), encoding='utf-8').read().split("if __name__ == '__main__':")[0]
src = src.replace("WORK = sys.argv[1]\nONLY = sys.argv[2:]", "WORK = OUT\nONLY = []").replace("DATA = json.load(io.open(os.path.join(ROOT, 'resources', 'yarn', 'nakyang.json'), encoding='utf-8'))", "DATA = []")
ns = {'OUT': S, 'sys': sys, 'os': os, 'io': io, 'json': json, 're': re, 'urllib': urllib, 'np': np, 'Image': Image, '__file__': os.path.join(ROOT, 'tools', 'nakyang-swatches.py')}
from PIL import ImageDraw, ImageFont; ns.update({'ImageDraw': ImageDraw, 'ImageFont': ImageFont}); exec(src, ns); dominant = ns['dominant']
lines = [x['product'] for x in json.load(io.open(S + '/../brands3.json', encoding='utf-8'))['다이소']]
def nk(s): return re.sub(r'[\s()]', '', s)
rows = json.load(io.open(S + '/list.json', encoding='utf-8'))
by = {}
for r in rows:
    m = re.match(r'^(.*?)\s*(\d+(?:\.\d+)?)\s*g\s*(.*)$', r['name'])
    cand = []
    if m:
        base, g, color = m.group(1).strip(), m.group(2), m.group(3).strip() or '기본'
        cand = [l for l in lines if nk(l) in (nk(base), nk(f'{base}({g}g)'))]
    if not cand:   # '날개실 노랑' · '코튼로프 뜨개실 (민트) 40g' · '면 뜨개실 네이비 25g' 처럼 무게가 뒤에 있거나 없는 이름
        t = re.sub(r'\s*\d+(?:\.\d+)?\s*g\b', '', r['name']).strip()
        t = t.replace('코튼케이크 뜨개실', '코튼 케이크').replace('코튼 케이크 뜨개실', '코튼 케이크').replace('수세미 실', '수세미 뜨개실')
        if t.startswith('면 뜨개실') and '25' in r['name']: t = t.replace('면 뜨개실', '면 뜨개실(25g)', 1)
        best = max((l for l in lines if nk(t).startswith(nk(l))), key=len, default=None)
        if not best: continue
        k = len(best.replace(' ', '')); i = 0; n = 0
        while i < len(t) and n < k:
            if t[i] != ' ': n += 1
            i += 1
        color = re.sub(r'^[\s(]+|[\s)]+$', '', t[i:]).strip() or '기본'; cand = [best]
    by.setdefault((cand[0], color), r)
os.makedirs(S + '/photos/daiso', exist_ok=True)
items = []; miss = []
for (prod, color), r in by.items():
    url = 'https://cdn.daisomall.co.kr' + r['img']
    fn = 'daiso/' + hashlib.md5((prod + '|' + color).encode('utf-8')).hexdigest()[:16] + '.jpg'
    dst = os.path.join(S, 'photos', fn.replace('/', os.sep))
    try:
        if not os.path.exists(dst):
            im = Image.open(io.BytesIO(urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'}), timeout=40).read())).convert('RGB')
            w, h = im.size; s = int(min(w, h) * 0.62); im = im.crop(((w - s) // 2, (h - s) // 2, (w - s) // 2 + s, (h - s) // 2 + s)).resize((160, 160), Image.LANCZOS)   # 공 가운데만
            im.save(dst, quality=82)
        hexes, mode = dominant(Image.open(dst))
        items.append({'brand': '다이소', 'product': prod, 'no': '', 'name': color[:40], 'file': fn, 'hex': hexes, 'mode': mode, 'soldout': r['soldout'] == 'Y', 'url': 'https://www.daisomall.co.kr/pd/pdr/SCR_PDR_0001?pdNo=' + r['pdNo']})
    except Exception as e: miss.append((prod, color, str(e)[:60]))
io.open(S + '/photos_apply.json', 'w', encoding='utf-8').write(json.dumps(items, ensure_ascii=False))
io.open(S + '/photos_files.txt', 'w', encoding='utf-8').write('\n'.join(i['file'] for i in items))
unm = sorted({re.match(r'^(.*?)\s*\d', r['name']).group(1) if re.match(r'^(.*?)\s*\d', r['name']) else r['name'] for r in rows} - {b for b in []})
print('colors', len(items), 'lines with colors', len({i['product'] for i in items}), 'of', len(lines), 'fail', len(miss), miss[:3])
print('lines without any color:', [l for l in lines if l not in {i['product'] for i in items}])
