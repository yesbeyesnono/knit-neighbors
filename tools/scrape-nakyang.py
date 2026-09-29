# 낙양모사 스토어(nakyang.store) YARN 카테고리 공개 정보 수집 → resources/yarn/nakyang.json
# (2026-09-29 대표: 구두 제휴로 진행. 상품명·규격·색 옵션·상세 이미지 주소만. 이미지 파일은 tools/nakyang-swatches.py 가 따로 받음)
import re, json, io, sys, time, os, html
import urllib.request

BASE = 'https://www.nakyang.store'
UA = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) knit-neighbors yarn-catalog (partner)'}
OUT = os.path.join(os.path.dirname(__file__), '..', 'resources', 'yarn', 'nakyang.json')

def get(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode('utf-8', 'ignore')

YARN_IDS = ['908','890','874','805','798','793','672','566','275','255','254','76','253','42','43','77','80','49','44','751','41','79','55','54','68','230','58','51','45','53','228','464','343','64','59','151','150','46','52','337','67','66','63','69','72','65','60']   # YARN 카테고리 47종(2026-09-29 브라우저에서 확인). 카탈로그 HTML 에는 추천 상품(키트 등)이 섞여 있어 목록은 고정
def ids():
    return YARN_IDS
def ids_scan():
    out = []
    for page in (1, 2, 3):
        h = get(f'{BASE}/goods/catalog?page={page}&searchMode=catalog&category=c0008&sorting=ranking&code=0008')
        found = []
        for m in re.finditer(r'goods/view\?no=(\d+)', h):
            if m.group(1) not in found: found.append(m.group(1))
        new = [i for i in found if i not in out]
        if not new: break
        out += new
    return out

def product(no):
    h = get(f'{BASE}/goods/view?no={no}')
    name = html.unescape(re.search(r'<title>(.*?)</title>', h, re.S).group(1)).strip()
    spec = {}
    for m in re.finditer(r'<ul class="detail_spec_table">\s*<li class="th">(.*?)</li>\s*<li>(.*?)</li>', h, re.S):
        k = re.sub(r'<[^>]+>', '', m.group(1)).strip(); v = re.sub(r'<[^>]+>', '', m.group(2)); v = html.unescape(re.sub(r'\s+', ' ', v)).strip()
        if k and len(k) < 12 and k not in spec: spec[k] = v[:80]
    opts = []
    for m in re.finditer(r'<option[^>]*>(.*?)</option>', h, re.S):
        t = html.unescape(re.sub(r'<[^>]+>', '', m.group(1))).strip()
        if t and not re.search(r'옵션|택배|선택', t): opts.append(t)
    sub = ''
    m = re.search(r'class="[^"]*(?:goods_summary|item_summary)[^"]*"[^>]*>(.*?)</', h, re.S)
    if m: sub = html.unescape(re.sub(r'<[^>]+>', '', m.group(1))).strip()[:80]
    img = ''
    m = re.search(r'<img[^>]+src="([^"]*view\.(?:png|jpg))"', h)
    if m: img = m.group(1)
    c = get(f'{BASE}/goods/view_contents?no={no}&zoom=1')
    dets = [u if u.startswith('http') else BASE + u for u in re.findall(r'<img[^>]+src="([^"]+editor[^"]+)"', c)]
    return {'no': no, 'name': name, 'sub': sub, 'spec': {k: v for k, v in spec.items() if k in ('브랜드','원산지','대바늘','코바늘','무게','길이','성분')}, 'opts': opts, 'img': img, 'dets': dets, 'url': f'{BASE}/goods/view?no={no}'}

if __name__ == '__main__':
    lst = ids(); print('ids', len(lst))
    out = []
    for no in lst:
        try:
            out.append(product(no)); print(no, out[-1]['name'], len(out[-1]['opts']))
        except Exception as e:
            print('ERR', no, e)
        time.sleep(0.4)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    io.open(OUT, 'w', encoding='utf-8').write(json.dumps(out, ensure_ascii=False, indent=1))
    print('saved', OUT)
