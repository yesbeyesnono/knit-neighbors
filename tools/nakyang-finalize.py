# 검수 결과(map.txt: "상품번호[(top)]: idx:색번호 ...")를 tiles.json 과 합쳐 최종 색상 사진 목록을 만든다
#   → <작업폴더>/out/nakyang/<상품no>_<색번호>.jpg (200px) + <작업폴더>/final.json [{no, product, color_no, name, file, hex[], mode}]
# 사용: python tools/nakyang-finalize.py <작업폴더>
import sys, os, io, json, re, shutil
from PIL import Image
ROOT = os.path.join(os.path.dirname(__file__), '..')
WORK = sys.argv[1]
DATA = {p['no']: p for p in json.load(io.open(os.path.join(ROOT, 'resources', 'yarn', 'nakyang.json'), encoding='utf-8'))}
TILES = json.load(io.open(os.path.join(WORK, 'tiles.json'), encoding='utf-8'))

def opt_key(o):
    m = re.match(r'\s*([A-Za-z]*)(\d+)([A-Za-z]*)', o)
    return (m.group(1), int(m.group(2)), m.group(3)) if m else ('~', 0, o)
def parse_opt(o):
    o = re.sub(r'\s*\(품절\)|\(\+[\d,]+₩\)', '', o).strip()
    m = re.match(r'^\s*([A-Za-z]?\d+[A-Za-z]?)\s*[.\s]\s*(.+)$', o)
    return (m.group(1), m.group(2).strip()) if m else ('', o)

MAP = {}; TOP = set()
for line in io.open(os.path.join(WORK, 'map.txt'), encoding='utf-8'):
    line = line.strip()
    if not line or ':' not in line: continue
    head, rest = line.split(':', 1)
    no = head.replace('(top)', '').strip()
    if '(top)' in head: TOP.add(no)
    MAP[no] = {int(a): b for a, b in (x.split(':', 1) for x in rest.split())}

def dominant(img, top):
    t = img.resize((80, 80)); box = (12, 4, 68, 30) if top else (12, 12, 68, 68)
    c = t.crop(box).quantize(colors=5, method=Image.Quantize.MEDIANCUT).convert('RGB')
    cnt = {}
    for px in c.getdata(): cnt[px] = cnt.get(px, 0) + 1
    tot = sum(cnt.values()); cols = sorted(cnt.items(), key=lambda x: -x[1])
    def dist(p, q): return sum((p[i] - q[i]) ** 2 for i in range(3)) ** .5
    keep = [cols[0]]
    for p, n in cols[1:]:
        if n / tot >= 0.18 and all(dist(p, k[0]) > 70 for k in keep): keep.append((p, n))
    hexes = ['#%02x%02x%02x' % p for p, n in keep[:3]]
    return hexes, ('solid' if len(hexes) == 1 else 'mix')

out = []; outdir = os.path.join(WORK, 'out', 'nakyang'); os.makedirs(outdir, exist_ok=True)
for no, tiles in TILES.items():
    p = DATA[no]; opts = dict(parse_opt(o) for o in p['opts'])
    for t in tiles:
        idx = t['idx']
        if no in MAP: cno = MAP[no].get(idx)
        else: cno = (parse_opt(t['guess'])[0] if t.get('guess') else None)
        if not cno: continue
        # 라벨이 이름뿐인 경우(연하늘 등): 옵션에서 이름으로 번호 찾기
        if not re.match(r'^[A-Za-z]?\d+[A-Za-z]?$', cno):
            found = [k for k, v in opts.items() if v == cno]
            if not found: continue
            cno = found[0]
        name = opts.get(cno) or cno
        src = os.path.join(WORK, 'tiles', no, f'{idx}.jpg'); fn = f'{no}_{cno}.jpg'
        img = Image.open(src).convert('RGB')
        if no in TOP: img = img.crop((0, 0, 200, 70)).resize((200, 200), Image.LANCZOS)   # 라벨 띠가 있는 사진은 윗부분만
        img.resize((160, 160), Image.LANCZOS).save(os.path.join(outdir, fn), quality=78)
        hexes, mode = dominant(img, False)
        out.append({'no': no, 'product': p['name'], 'color_no': cno, 'name': name, 'file': 'nakyang/' + fn, 'hex': hexes, 'mode': mode})
io.open(os.path.join(WORK, 'final.json'), 'w', encoding='utf-8').write(json.dumps(out, ensure_ascii=False))
print(len(out), 'colors with photo;', len({o['no'] for o in out}), 'products')
