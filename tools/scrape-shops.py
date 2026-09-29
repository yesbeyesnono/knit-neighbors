# 협력 뜨개실 쇼핑몰 4곳(쎄비·앵콜스·청송뜨개실 = Cafe24, 바늘이야기 = 메이크샵)의 실 상품 공개 정보 수집 → <out>/<site>.json
# (2026-09-29 대표: 4곳 모두 구두 협업 확인. 상품명·규격·소재·권장 바늘·색 옵션·색 이미지 주소·카테고리만 수집)
# 사용: python tools/scrape-shops.py <out폴더> [site ...]
import re, io, os, sys, json, time, html, urllib.request, urllib.parse
UA = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36'}
OUT = sys.argv[1]; SITES = sys.argv[2:] or ['sevy', 'ancalls', 'tgesil', 'banul']; SITE_NOW = ''
os.makedirs(OUT, exist_ok=True)

def get(u, tries=3):
    q = urllib.parse.quote(u, safe=':/?=&%+')
    for t in range(tries):
        try:
            r = urllib.request.urlopen(urllib.request.Request(q, headers=UA), timeout=40); b = r.read()
            for enc in ('utf-8', 'euc-kr', 'cp949'):
                try: return b.decode(enc)
                except Exception: pass
            return b.decode('utf-8', 'ignore')
        except Exception as e:
            if t == tries - 1: raise
            time.sleep(2)

def load_partial(site):
    f = os.path.join(OUT, site + '.json')
    try: return json.load(io.open(f, encoding='utf-8'))
    except Exception: return []
def save(site, data): io.open(os.path.join(OUT, site + '.json'), 'w', encoding='utf-8').write(json.dumps(data, ensure_ascii=False, indent=0))
def clean(s): return re.sub(r'\s+', ' ', html.unescape(re.sub(r'<[^>]+>', ' ', s or ''))).strip()
def uniq(xs):
    out = []; [out.append(x) for x in xs if x not in out]; return out
def absurl(base, u):
    if u.startswith('//'): return 'https:' + u
    if u.startswith('/'): return base + u
    return u

# ---------- Cafe24 공통
def cafe24_list(base, cate, pattern):
    ids = []
    for p in range(1, 40):
        h = get(f'{base}/product/list.html?cate_no={cate}&page={p}')
        found = uniq(re.findall(pattern, h)); found = [x for x in found if x not in ids]
        if not found: break
        ids += found; time.sleep(0.3)
    return ids

def cafe24_product(base, url):
    h = get(url)
    d = {'url': url}
    m = re.search(r'<meta property="og:title" content="([^"]*)"', h); d['title'] = html.unescape(m.group(1)).strip() if m else clean(re.search(r'<title>(.*?)</title>', h, re.S).group(1))
    spec = {}
    for th, td in re.findall(r'<th[^>]*>\s*(?:<span[^>]*>)?([^<]{1,30}?)(?:</span>)?\s*</th>\s*<td[^>]*>(.*?)</td>', h, re.S):
        k = th.strip(); v = clean(td)
        if k and v and k not in spec and not re.search(r'배송|적립|구매방법|주기|할부|판매가|소비자가|수량', k): spec[k] = v[:300]
    d['spec'] = spec
    m = re.search(r'<script type="application/ld\+json">(\{.*?\})</script>', h, re.S)
    if m:
        try:
            ld = json.loads(m.group(1)); d['ld_brand'] = (ld.get('brand') or {}).get('name'); d['ld_desc'] = ld.get('description')
            d['ld_variants'] = [v.get('name', '') for v in ld.get('hasVariant', [])][:400]
        except Exception: pass
    # 옵션(색상): li option_value(이미지 버튼형) 또는 select option
    opts = []
    for grp in re.findall(r'<ul[^>]+option_title="([^"]*)"[^>]*>(.*?)</ul>', h, re.S):   # 옵션 묶음(색상/호수/추가상품)별로
        for li in re.findall(r'<li[^>]+option_value="([^"]*)"[^>]*>(.*?)</li>', grp[1], re.S):
            img = re.search(r'src="([^"]+option_button[^"]+)"', li[1]); opts.append({'name': html.unescape(li[0]).strip(), 'img': absurl(base, img.group(1)) if img else None, 'group': html.unescape(grp[0]).strip()})
    if not opts:
        for li in re.findall(r'<li[^>]+option_value="([^"]*)"[^>]*>(.*?)</li>', h, re.S):
            img = re.search(r'src="([^"]+option_button[^"]+)"', li[1]); opts.append({'name': html.unescape(li[0]).strip(), 'img': absurl(base, img.group(1)) if img else None})
    if not opts:
        sel = re.findall(r'<select[^>]+(?:option1|ProductOption0|option_[^"]*)"[^>]*>(.*?)</select>', h, re.S)
        for s in sel:
            for v, t in re.findall(r'<option[^>]*value="([^"]*)"[^>]*>([^<]*)</option>', s):
                t = html.unescape(t).strip()
                if v and v not in ('*', '**') and t and not re.search(r'옵션|선택|-----', t): opts.append({'name': t, 'img': None})
    d['options'] = opts[:500]
    # 대표·추가 이미지, 상세 이미지
    d['images'] = uniq([absurl(base, u) for u in re.findall(r'(?:ec-data-src|src)="([^"]*/web/product/(?:big|medium|extra/big)/[^"]+)"', h)])[:40]
    det = re.search(r'id="prdDetail"(.*?)(?:id="prdReview"|id="prdQnA"|id="prdInfo"|class="xans-product-additional")', h, re.S)
    imgs = re.findall(r'(?:ec-data-src|data-src|src)="([^"]+\.(?:jpg|jpeg|png|gif|webp)[^"]*)"', det.group(1) if det else h, re.I)
    imgs = [absurl(base, u) for u in imgs if not re.search(r'icon|btn|logo|banner|dfloor|echosting|/skin/|blank|loading|coupon|/menu/|review|_ro\.', u, re.I)]
    d['detail_images'] = uniq(imgs)[:60]
    m = re.search(r'class="xans-product-headcategory[^"]*"(.*?)</div>', h, re.S); d['crumb'] = [clean(x) for x in re.findall(r'<a[^>]*>(.*?)</a>', m.group(1))] if m else []
    txt = clean(det.group(1))[:3000] if det else ''
    d['detail_text'] = txt
    return d

def cafe24_cats(base, cate_list):
    """하위 카테고리별 상품 목록 → {product_id: [카테고리명]} (시즌·소재·바늘·굵기·용도 속성 파악용)"""
    memb = {}
    for name, cate, pattern in cate_list:
        try: ids = cafe24_list(base, cate, pattern)
        except Exception as e: print('  cat fail', name, e); continue
        for i in ids: memb.setdefault(i, []).append(name)
        print('  cat', name, len(ids))
    return memb

def run_sevy():
    base = 'https://www.sevy.co.kr'; pat = r'product_no=(\d+)'
    ids = cafe24_list(base, 42, pat); print('sevy ids', len(ids))
    h = get(base + '/'); cats = uniq(re.findall(r'<a[^>]+href="/product/list\.html\?cate_no=(\d+)"[^>]*>([^<]{1,40})</a>', h))
    want = []
    memb = cafe24_cats(base, want) if want else {}
    out = load_partial(SITE_NOW); done = {str(d.get('id')) for d in out}
    for i, pid in enumerate(ids):
        if pid in done: continue
        try: d = cafe24_product(base, f'{base}/product/detail.html?product_no={pid}'); d['id'] = pid; d['cats'] = memb.get(pid, []); out.append(d); print(i, pid, d['title'][:40], len(d['options']), flush=True)
        except Exception as e: print('ERR', pid, e, flush=True)
        if len(out) % 20 == 0: save(SITE_NOW, out)
        time.sleep(0.4)
    return out

def run_tgesil():
    base = 'https://tgesil.com'; pat = r'product_no=(\d+)'
    ids = cafe24_list(base, 44, pat); print('tgesil ids', len(ids))
    h = get(base + '/'); cats = uniq(re.findall(r'<a[^>]+href="/product/list\.html\?cate_no=(\d+)"[^>]*>([^<]{1,40})</a>', h))
    want = []
    memb = cafe24_cats(base, want) if want else {}
    out = load_partial(SITE_NOW); done = {str(d.get('id')) for d in out}
    for i, pid in enumerate(ids):
        if pid in done: continue
        try: d = cafe24_product(base, f'{base}/product/detail.html?product_no={pid}'); d['id'] = pid; d['cats'] = memb.get(pid, []); out.append(d); print(i, pid, d['title'][:40], len(d['options']), flush=True)
        except Exception as e: print('ERR', pid, e, flush=True)
        if len(out) % 20 == 0: save(SITE_NOW, out)
        time.sleep(0.4)
    return out

def run_ancalls():
    base = 'https://ancalls.com'
    pages = {}
    for p in range(1, 15):
        h = get(f'{base}/product/list.html?cate_no=12&page={p}')
        found = uniq(re.findall(r'href="(/product/[^"/]+/(\d+)/category/12/[^"]*)"', h))
        new = [(href.split('?')[0], i) for href, i in found if i not in pages]
        if not new: break
        for href, i in new: pages[i] = href
        time.sleep(0.3)
    print('ancalls ids', len(pages))
    h = get(base + '/'); cats = uniq(re.findall(r'href="/product/list\.html\?cate_no=(\d+)"[^>]*>([^<]{1,40})</a>', h))
    sub = uniq(re.findall(r'href="/category/([^/"]+)/(\d+)/"', h))
    want = [(clean(urllib.parse.unquote(n)), c, r'/(\d+)/category/' + c + '/') for n, c in sub if c != '12' and re.search(r'실|얀|울|면|린넨|모헤어|알파카|여름|겨울|콘사|수세미|브랜드|made|다루마|퐁티|랑|필콜라나|키트꾸뛰르|굵기|ply', n, re.I)]
    memb = {}
    out = load_partial(SITE_NOW); done = {str(d.get('id')) for d in out}
    for i, (pid, href) in enumerate(pages.items()):
        if pid in done: continue
        try: d = cafe24_product(base, base + href); d['id'] = pid; d['cats'] = memb.get(pid, []); out.append(d); print(i, pid, d['title'][:40], len(d['options']), flush=True)
        except Exception as e: print('ERR', pid, e, flush=True)
        if len(out) % 20 == 0: save(SITE_NOW, out)
        time.sleep(0.4)
    return out

def run_banul():
    base = 'https://www.banul.co.kr'
    ids = {}
    for mcode in ('001', '002', '003', '004'):
        for p in range(1, 30):
            h = get(f'{base}/shop/shopbrand.html?type=N&xcode=107&mcode={mcode}&page={p}')
            found = uniq(re.findall(r'branduid=(\d+)', h)); new = [x for x in found if x not in ids]
            # 소분류 이름(scode) → 속성
            for x in found: ids.setdefault(x, set())
            if not new and p > 1: break
            if not found: break
            time.sleep(0.3)
    print('banul ids', len(ids))
    out = load_partial(SITE_NOW); done = {str(d.get('id')) for d in out}
    for i, pid in enumerate(ids):
        if pid in done: continue
        url = f'{base}/shop/shopdetail.html?branduid={pid}'
        try:
            h = get(url); d = {'url': url, 'id': pid}
            m = re.search(r'<meta property="og:title" content="([^"]*)"', h); d['title'] = html.unescape(m.group(1)).strip() if m else clean(re.search(r'<title>(.*?)</title>', h, re.S).group(1))
            d['title'] = re.sub(r'\s*-\s*바늘이야기\s*$', '', d['title'])
            txt = clean(h)
            d['detail_text'] = ' '.join(re.findall(r'\+\s*[^+]{3,160}', txt))[:3000]
            d['spec'] = {}
            for k, pat in [('중량/길이', r'중\s*량\s*[:：]\s*([^+]{3,80})'), ('사용바늘', r'(?:사용|권장)\s*바늘\s*[:：]?\s*([^+]{3,80})'), ('혼용률', r'혼용\s*[율률]\s*[:：]\s*([^+]{3,80})'), ('게이지', r'게이지\s*[:：]\s*([^+]{3,100})'), ('원산지', r'원산지\s*[:：]\s*([^+]{2,30})'), ('소재', r'소\s*재\s*[:：]\s*([^+]{2,60})')]:
                m = re.search(pat, txt)
                if m: d['spec'][k] = m.group(1).strip()
            opts = []
            for on, ov in re.findall(r"opt_name:'([^']*)'[^{}]*?opt_value:'([^']*)'", h):   # 메이크샵: optionJsonData 의 opt_name(묶음 이름)·opt_value(쉼표 구분 목록)
                for t in ov.split(','):
                    t = html.unescape(t).strip()
                    if t and not re.search(r'선택|옵션|-----', t): opts.append({'name': re.sub(r'\s*\(품절\)|\s*\[품절\]', '', t), 'img': None, 'soldout': '품절' in t, 'group': html.unescape(on).strip()})
            if not opts:
                for s in re.findall(r'<select[^>]*>(.*?)</select>', h, re.S):
                    for v, t in re.findall(r'<option[^>]*value="([^"]*)"[^>]*>([^<]*)</option>', s):
                        t = html.unescape(t).strip()
                        if v and t and not re.search(r'선택|옵션|-----|배송', t): opts.append({'name': re.sub(r'\s*\(품절\)|\s*\[품절\]', '', t), 'img': None, 'soldout': '품절' in t})
            d['options'] = [o for i, o in enumerate(opts) if o['name'] not in [x['name'] for x in opts[:i]]]
            m = re.search(r'현재 위치(.*?)</div>', h, re.S)
            imgs = re.findall(r'(?:src|data-original)="([^"]+\.(?:jpg|jpeg|png|gif)[^"]*)"', h, re.I)
            d['detail_images'] = uniq([absurl(base, u) for u in imgs if re.search(r'jpg3\.kr/makeshop/image/|shopimages', u) and not re.search(r'icon|btn|logo|banner|main/|event|caution|regulation|purchase|bar\.jpg|diy_re|re_new|yarn_0', u)])[:60]
            m = re.search(r'shopimages/banulfren/(\d+)\.jpg', h); d['images'] = [absurl(base, x) for x in uniq(re.findall(r'(//cdn[^"]*shopimages/banulfren/\d+\.jpg[^"]*)', h))][:5]
            m = re.search(r'현재 위치(.*?)</div>', h, re.S); d['crumb'] = [clean(x) for x in re.findall(r'<a[^>]*>(.*?)</a>', m.group(1))] if m else []
            out.append(d); print(i, pid, d['title'][:40], len(d['options']), flush=True)
        except Exception as e: print('ERR', pid, e, flush=True)
        if len(out) % 20 == 0: save(SITE_NOW, out)
        time.sleep(0.4)
    return out

CATS = {
  'tgesil': ('https://tgesil.com', r'product_no=(\d+)', [('수세미실',362),('여름 가방뜨개실 / 모자뜨개실',365),('여름 의류실',366),('인형실',430),('블랑켓실',431),('목도리실 / 겨울모자실',355),('머플러실 / 숄',421),('스웨터실 / 겨울의류실',356),('아기실 / 키즈',357),('패브릭얀',364),('가방뜨개실 / 소품실',363),('레이스용 / 도일리실',367),('핑거니팅 / 자이언트얀',598),('마크라메',521),('사계절용',352),('봄 / 여름 뜨개실',353),('가을 / 겨울 털실',354),('종이실 / 펠트',569),('라피아',586),('실크 / 레이온 / 메탈실 / 스팽글',383),('린넨 / 마 / 모달 / 대나무',382),('면 100% (순면)',376),('오가닉',378),('면 혼방',377),('인조 가죽실',692),('삼베실',590),('아크릴실 / 폴리 혼방',379),('울 100% (순모)',374),('울 혼방',375),('수면사 수면실 / 극세사 / 인조퍼',384),('모헤어 / 솔잎사 / 팝콘실',381),('캐시미어 / 앙고라 / 알파카',380),('0.1mm~1mm',387),('1mm~2mm',422),('2mm~3mm',416),('3mm~5mm',388),('5mm~7mm',389),('7mm 이상',390),('메탈/스팽글',688),('낙양모사 BRAND COLLECTION',640),('알리제 BRAND COLLECTION',681),('순면콘사 / 소콘',417),('그라데이션',398),('원산지 대한민국',411),('원산지 일본',413),('원산지 터키',414),('원산지 이탈리아',412),('원산지 인도',415),('팩단위 구매',478),('세트상품(전체색상)',423)]),
  'ancalls': ('https://ancalls.com', r'/(\d+)/category/', [('봄/여름용',26),('가을 겨울 뜨개실',25),('사계절 뜨개실',250),('여름 의류',252),('수세미',28),('섞어뜨는 실',842),('울100% 순모',186),('울 혼방',188),('코튼 100% 순면',608),('모헤어│알파카│라마',196),('린넨│대나무│종이',195),('실크 | 레이온',192),('대바늘 2.0-2.5mm',532),('대바늘 3.0-4.5mm',263),('대바늘 5.0-7.0mm',264),('대바늘 8mm 이상',266),('모사용 코바늘 2/0 - 4/0호',533),('모사용 코바늘 5/0 - 8/0호',265),('모사용 코바늘 9/0호 이상',724),('레이스용 코바늘',262),('대용량 실',271),('프리미엄 실',274),('Fur 밍크실',402),('패브릭얀',403)]),
  'sevy': ('https://www.sevy.co.kr', r'product_no=(\d+)', [('봄/여름',135),('가을/겨울',277),('사계절',136),('울 100% 순모',144),('울혼방',147),('면 100%',145),('면혼방',148),('오가닉',195),('캐시미어, 실크',196),('모헤어, 알파카',150),('린넨, 종이, 밤부레이욘',149),('아크릴, 폴리, 나일론',146),('극세사, 수면사',197),('코바늘 레이스용',599),('코바늘 2/0~4/0호',600),('코바늘 5/0~7/0호',601),('코바늘 8/0~10/0호',602),('코바늘 점보',603),('대바늘 2.0~3.0mm',604),('대바늘 3.0~5.0mm',605),('대바늘 5.0~7.0mm',606),('대바늘 7.0~9.0mm',607),('대바늘 10.0mm 이상',608),('LACE 0',249),('SUPER FINE 1',250),('FINE 2',251),('LIGHT 3',252),('MEDIUM 4',253),('BULKY 5',254),('SUPER BULKY 6',255),('JUMBO 7',256),('Made by SEVY',613),('Designed by SEVY',614),('올림푸스',615),('몬디알',616),('가방',617),('의류',618),('목도리/스카프',619),('모자',620),('인형',621),('수세미/리빙',622),('유아용',623),('태팅레이스',624),('콘사',735)]),
}
def run_cats(site):
    base, pat, lst = CATS[site]; memb = {}
    for name, cate in lst:
        try: ids = cafe24_list(base, cate, pat if site != 'ancalls' else r'/(\d+)/category/' + str(cate) + '/')
        except Exception as e: print('  cat fail', name, e); continue
        for i in ids: memb.setdefault(i, []).append(name)
        print('  cat', name, len(ids)); time.sleep(0.3)
    io.open(os.path.join(OUT, site + '_cats.json'), 'w', encoding='utf-8').write(json.dumps(memb, ensure_ascii=False)); print('saved cats', site, len(memb))

if __name__ == '__main__':
    for s in SITES:
        if s.startswith('cats:'): run_cats(s[5:]); continue
        print('=====', s, flush=True); SITE_NOW = s
        data = {'sevy': run_sevy, 'ancalls': run_ancalls, 'tgesil': run_tgesil, 'banul': run_banul}[s]()
        save(s, data)
        print('saved', s, len(data), flush=True)
