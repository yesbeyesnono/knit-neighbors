# resources/yarn/nakyang.json → yarn_catalog_import 용 JSON(resources/yarn/nakyang_import.json)
import json, io, re, os
ROOT = os.path.join(os.path.dirname(__file__), '..')
D = json.load(io.open(os.path.join(ROOT, 'resources', 'yarn', 'nakyang.json'), encoding='utf-8'))
FIB = [('combed cotton','면'),('mercerized cotton','면'),('cotton','면'),('merino wool','울'),('superwash wool','울'),('super wash wool','울'),('wool','울'),('polyester','폴리에스터'),('acrylic','아크릴'),('nylon','나일론'),('polyamid','나일론'),('linen','린넨'),('viscose rayon','레이온'),('rayon','레이온'),('baby alpaca','알파카'),('alpaca','알파카'),('cashmere','캐시미어'),('kid mohair','모헤어'),('mohair','모헤어'),('mulberry silk','실크'),('silk','실크'),('korean paper','한지'),('paper','종이'),('metallic','메탈릭'),('metalic','메탈릭'),('ferret hair','담비'),('raccoon hair','라쿤'),('soybean fibre','콩섬유')]
def fibers(s):
    s = s.split('/')[0]   # '코코넛: 일반 / 메탈 혼방' → 일반만
    out = {}
    for m in re.finditer(r'([A-Za-z][A-Za-z ]*?)\s*(\d{1,3})\s*%', s):
        name = m.group(1).strip().lower(); name = re.sub(r'^(extra fine|super baby|super|2)\s+', '', name)
        ko = next((k for e, k in FIB if e == name), None) or next((k for e, k in FIB if e in name), None) or m.group(1).strip()
        out[ko] = out.get(ko, 0) + int(m.group(2))
    return out
def num(s):
    if not s: return None
    s = s.split('/')[0].replace(',', '')
    m = re.search(r'(\d+(?:\.\d+)?)\s*(kg|g|m)?', s)
    if not m: return None
    v = float(m.group(1)); return v * 1000 if m.group(2) == 'kg' else v
def season(f):
    main = max(f.items(), key=lambda x: x[1])[0] if f else ''
    if main in ('면','린넨','레이온','한지','종이'): return '여름'
    if main in ('울','알파카','모헤어','캐시미어','담비','라쿤'): return '겨울'
    return '사계절'
def color(o):
    o = re.sub(r'\s*\(품절\)|\(\+[\d,]+₩\)', '', o).strip()
    m = re.match(r'^\s*([A-Za-z]?\d+[A-Za-z]?)\s*[.\s]\s*(.+)$', o)
    if m: return f'{m.group(1)}|{m.group(2).strip()}'
    return f'|{o}'
out = []
for p in D:
    sp = p['spec']; f = fibers(sp.get('성분', ''))
    out.append({'b': '낙양모사', 'p': p['name'], 'g': num(sp.get('무게')), 'm': num(sp.get('길이')), 'fm': (max(f.items(), key=lambda x: x[1])[0] if f else None), 'f': f or None,
                's': '낙양모사', 'u': p['url'], 'se': season(f), 'nk': sp.get('대바늘') or None, 'nc': sp.get('코바늘') or None, 'ga': None, 'pu': None,
                'c': [color(o) for o in p['opts']], '_no': p['no'], '_img': p['img'], '_sub': p['sub']})
io.open(os.path.join(ROOT, 'resources', 'yarn', 'nakyang_import.json'), 'w', encoding='utf-8').write(json.dumps(out, ensure_ascii=False, indent=1))
print(len(out), 'colors', sum(len(x['c']) for x in out))
for x in out[:47]: print(x['p'], x['g'], x['m'], x['fm'], x['f'], x['se'], x['c'][:2])
