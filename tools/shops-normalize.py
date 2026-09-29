# 쇼핑몰 수집 결과(<out>/<site>.json) → 표준 실 목록 <out>/normalized.json
# 실 1종 = 제조사 제품. 같은 실이 여러 가게에 있으면 판매처만 늘린다. 키트·도안·바늘·부자재는 제외
import re, io, os, sys, json, html
OUT = sys.argv[1]
SITE_SHOP = {'sevy': '쎄비하우스', 'ancalls': '앵콜스', 'tgesil': '청송뜨개실', 'banul': '바늘이야기'}
SITE_PB = {'sevy': '쎄비', 'ancalls': '앵콜스', 'tgesil': '청송뜨개실', 'banul': '바늘이야기'}
KNOWN_BRANDS = ['낙양모사', '다루마', '퐁티', '랑', '필콜라나', '킹콜', '필다르', '아마노', '샤켄마이어', '올림푸스', '몬디알', '알리제', '삼성', '구정', '드롭스', '로완', '이사거', '산네스', '클로버', '하마나카', '키트꾸뛰르', '라나그로사', '카타니아', '보스텟', '이스타', '퍼플', 'DMC', 'Lang', 'Fonty', 'Drops', 'Rowan', 'Isager', 'Sandnes', 'Hamanaka', 'Filcolana', 'King Cole', 'Phildar', 'Amano', 'Schachenmayr', 'Olympus', 'Mondial', 'Alize', 'Lana Grossa', 'Kit Couture', 'BC Garn', 'Knitting for Olive', 'Malabrigo', 'Noro', 'Katia', 'Scheepjes', 'Lion Brand', 'Bernat', 'Daruma', 'Nakyang']
BRAND_KO = {'fonty': '퐁티', 'lang': '랑', 'filcolana': '필콜라나', 'king cole': '킹콜', 'phildar': '필다르', 'amano': '아마노', 'schachenmayr': '샤켄마이어', 'olympus': '올림푸스', 'mondial': '몬디알', 'alize': '알리제', 'lana grossa': '라나그로사', 'kit couture': '키트꾸뛰르', 'daruma': '다루마', 'nakyang': '낙양모사', 'drops': '드롭스', 'rowan': '로완', 'isager': '이사거', 'sandnes': '산네스', 'hamanaka': '하마나카', 'knitting for olive': '니팅포올리브', 'bc garn': 'BC가른', 'malabrigo': '말라브리고', 'noro': '노로', 'katia': '카티아', 'scheepjes': '스킵예스', 'dmc': 'DMC'}
EXCLUDE = re.compile(r'키트|kit\b|패키지|쉽게 뜨는|만들기|DIY|세트상품|컬러표|색상표|샘플|스와치|도안|도서|책|바늘|가위|마커|스티치|라벨|샘플|컬러카드|색상표|체험|클래스|와펜|단추|지퍼|비즈|줄자|케이스|보빈|실감기|와인더|가방틀|프레임|손잡이|안전눈|솜\b|충전솜|장식|파우치|뜨개도구|니트프로|치아오구|addi|prym|클립|핀\b|워셔|테이프(?!얀| 얀)|접착|스티커|자석|고리|체인|끈\b|인형눈|바늘꽂이|골무|메시망|철사|리본(?!사)', re.I)
FIB = [('combed cotton', '면'), ('mercerized cotton', '면'), ('coma cotton', '면'), ('pima cotton', '면'), ('organic cotton', '면'), ('cotton', '면'), ('코튼', '면'), ('코마면', '면'), ('오가닉면', '면'), ('순면', '면'), ('면', '면'),
       ('superfine merino', '울'), ('extra fine merino', '울'), ('merino wool', '울'), ('merino', '울'), ('superwash wool', '울'), ('super wash wool', '울'), ('lambs wool', '울'), ('lambswool', '울'), ('wool', '울'), ('메리노', '울'), ('램스울', '울'), ('양모', '울'), ('울', '울'), ('모\b', '울'),
       ('polyester', '폴리에스터'), ('폴리에스터', '폴리에스터'), ('폴리', '폴리에스터'), ('폴리에스테르', '폴리에스터'), ('poly', '폴리에스터'), ('폴리\b', '폴리에스터'), ('acrylic', '아크릴'), ('아크릴', '아크릴'), ('nylon', '나일론'), ('polyamide', '나일론'), ('polyamid', '나일론'), ('나일론', '나일론'), ('폴리아미드', '나일론'),
       ('linen', '린넨'), ('린넨', '린넨'), ('리넨', '린넨'), ('마\b', '린넨'), ('ramie', '라미'), ('라미', '라미'), ('모시', '라미'), ('viscose rayon', '레이온'), ('viscose', '레이온'), ('rayon', '레이온'), ('레이온', '레이온'), ('비스코스', '레이온'), ('인견', '레이온'), ('tencel', '텐셀'), ('lyocell', '텐셀'), ('텐셀', '텐셀'), ('modal', '모달'), ('모달', '모달'), ('bamboo', '대나무'), ('밤부', '대나무'), ('대나무', '대나무'),
       ('baby alpaca', '알파카'), ('alpaca', '알파카'), ('알파카', '알파카'), ('cashmere', '캐시미어'), ('캐시미어', '캐시미어'), ('kid mohair', '모헤어'), ('mohair', '모헤어'), ('모헤어', '모헤어'), ('mulberry silk', '실크'), ('silk', '실크'), ('실크', '실크'), ('angora', '앙고라'), ('앙고라', '앙고라'), ('yak', '야크'), ('야크', '야크'), ('camel', '낙타'), ('raccoon', '라쿤'), ('라쿤', '라쿤'), ('mink', '밍크'), ('밍크', '밍크'), ('ferret', '담비'), ('담비', '담비'),
       ('paper', '종이'), ('종이', '종이'), ('한지', '한지'), ('korean paper', '한지'), ('raffia', '라피아'), ('라피아', '라피아'), ('metallic', '메탈릭'), ('metalic', '메탈릭'), ('lurex', '메탈릭'), ('메탈릭', '메탈릭'), ('메탈', '메탈릭'), ('spandex', '스판'), ('span', '스판'), ('스판', '스판'), ('polypropylene', '폴리프로필렌'), ('soybean', '콩섬유'), ('microfiber', '극세사'), ('극세사', '극세사'), ('polyurethane', '폴리우레탄'), ('pu\b', '폴리우레탄')]
def clean(s): return re.sub(r'\s+', ' ', html.unescape(s or '')).strip()

def fibers(text):
    out = {}
    for m in re.finditer(r'([A-Za-z가-힣][A-Za-z가-힣 \-]{0,24}?)\s*[:]?\s*(\d{1,3})\s*%', text or ''):
        name = m.group(1).strip().lower(); name = re.sub(r'^(약|about|소재|성분|혼용률|혼용율|재질)\s*', '', name)
        ko = None
        for e, k in FIB:
            if re.search(r'(?:^|[^a-z가-힣])' + e + r'(?:$|[^a-z가-힣])', ' ' + name + ' ') or name.endswith(e.replace('\\b', '')): ko = k; break
        if not ko:
            for e, k in FIB:
                if e.replace('\\b', '') in name: ko = k; break
        if ko: out[ko] = out.get(ko, 0) + int(m.group(2))
    tot = sum(out.values())
    if tot > 100 and len(out) > 1:   # 두 규격이 섞인 경우 앞의 100% 조합만
        acc = {}; s = 0
        for k, v in out.items():
            if s + v <= 100: acc[k] = v; s += v
        out = acc
    return out
def num_gm(text):
    text = (text or '').replace(',', '')
    g = re.search(r'(\d+(?:\.\d+)?)\s*(kg|g|그램)(?![a-z])', text, re.I) or re.search(r'^\s*(\d+(?:\.\d+)?)\s*(±)', text); m = re.search(r'(\d+(?:\.\d+)?)\s*(?:m|미터)(?![a-z])', text, re.I)
    gv = float(g.group(1)) * (1000 if g.group(2).lower() == 'kg' else 1) if g else None; mv = float(m.group(1)) if m else None
    return gv, mv
def needles(text):
    text = text or ''
    nk = re.search(r'대\s*바늘\s*[:：]?\s*([\d\.]+\s*(?:~|-|–|～)?\s*[\d\.]*\s*mm)', text) or re.search(r'([\d\.]+\s*(?:~|-|～)\s*[\d\.]+\s*mm)', text)
    nc = re.search(r'코\s*바늘\s*[:：]?\s*([^,/\n]{1,20}?호|[0-9]+/0\s*(?:~|-|～)?\s*[0-9]*/?0?호?|레이스\s*\d+호[^,\n]{0,12})', text)
    if not nc: m2 = re.search(r'(\d+/0\s*(?:~|-|～)\s*\d+/0\s*호?|\d+/0\s*호)', text); nc = m2
    return (nk.group(1).strip() if nk else None), (nc.group(1).strip() if nc else None)
def weight_from_cats(cats):
    for c in cats:
        cl = c.upper()
        if 'LACE' in cl: return '레이스·극세'
        if 'SUPER FINE' in cl: return '합세(Fingering)'
        if 'FINE' in cl: return '중세(Sport)'
        if 'LIGHT' in cl: return '합태(DK)'
        if 'MEDIUM' in cl: return '병태(Worsted)'
        if 'SUPER BULKY' in cl or 'JUMBO' in cl: return '초극태'
        if 'BULKY' in cl: return '극태(Bulky)'
    return None
def season(cats, f, name):
    s = ' '.join(cats)
    if '사계절' in s: return '사계절'
    if re.search(r'봄\s*/\s*여름|여름', s): return '여름'
    if re.search(r'가을\s*/?\s*겨울|겨울', s): return '겨울'
    if re.search(r'썸머|summer|쿨링|여름', name, re.I): return '여름'
    if re.search(r'윈터|winter|겨울', name, re.I): return '겨울'
    main = max(f.items(), key=lambda x: x[1])[0] if f else ''
    if main in ('면', '린넨', '레이온', '한지', '종이', '라피아', '라미', '대나무', '텐셀', '모달'): return '여름'
    if main in ('울', '알파카', '모헤어', '캐시미어', '담비', '라쿤', '앙고라', '야크', '밍크'): return '겨울'
    return '사계절' if f else None
def texture(name, f):
    n = name.lower()
    if re.search(r'모헤어|mohair|앙고라|헤일로|브러쉬드|brushed', n): return '모헤어·헤일로'
    if re.search(r'부클|boucle|퍼\b|fur|털실|푸들|테디|컬리|curly|양털', n): return '부클·퍼'
    if re.search(r'셔닐|벨벳|velvet|chenille|수면사|극세사|밍크|플리스|fleece|포그니|퐁듀|보들|폭신', n): return '셔닐·벨벳·수면사'
    if re.search(r'라피아|raffia|페이퍼|paper|한지|테이프|tape|리본사|리네아|라탄|레더|leather|가죽', n): return '테이프·라피아·페이퍼'
    if re.search(r'튜브사|tube|튜브얀', n): return '패브릭얀·코드'
    if re.search(r'패브릭|fabric|티셔츠얀|t-?shirt|코드\b|cord|로프|rope|마크라메|크로셰\b', n): return '패브릭얀·코드'
    if re.search(r'수세미', n): return '수세미사'
    if re.search(r'메탈|metal|반짝|글리터|lurex|스팽글', n) or (f and max(f.items(), key=lambda x: x[1])[0] == '메탈릭'): return '메탈릭'
    return '일반사'
def uses(cats, name, tex, se):
    u = set(); s = ' '.join(cats) + ' ' + name
    if re.search(r'가방|바구니|bag', s, re.I): u.add('가방·바구니')
    if re.search(r'의류|스웨터|가디건|니트|풀오버|조끼', s): u.add('여름 의류·소품' if se == '여름' else '의류')
    if re.search(r'목도리|스카프|머플러|숄|겨울모자|털모자|장갑|양말|방한', s): u.add('방한 소품')
    if re.search(r'여름 가방|여름 의류|모자뜨개실', s): u.add('여름 의류·소품')
    if re.search(r'인형|amigurumi|아미구루미', s, re.I): u.add('인형')
    if re.search(r'수세미|리빙', s): u.add('수세미')
    if re.search(r'유아|아기|베이비|baby', s, re.I): u.add('아기용품')
    if re.search(r'블랭킷|쿠션|담요', s): u.add('블랭킷·쿠션')
    if re.search(r'코스터|매트|러그|바스켓', s): u.add('코스터·매트')
    if tex == '수세미사': u.add('수세미')
    if tex == '테이프·라피아·페이퍼': u.add('가방·바구니')
    return sorted(u)
def parse_title(site, raw):
    t = clean(raw)
    t = re.sub(r'\s*[-|]\s*(쎄비 SEVY|앵콜스 ANCALLS|바늘이야기)\s*$', '', t)
    t = re.sub(r'^\[365일[^\]]*\]\s*청송뜨개실\s*\|\s*', '', t)
    t = re.sub(r'\s*-\s*[^-]{4,60}$', lambda m: '' if site == 'tgesil' and len(m.group(0)) > 12 else m.group(0), t)   # tgesil 은 '코튼필드 - 100% 코마면사로…' 꼴
    brand = None; tags = re.findall(r'\[([^\]]+)\]', t)
    for tag in tags:
        tg = tag.strip()
        if re.search(r'앵콜스\s*made', tg, re.I): brand = '앵콜스'
        elif re.search(r'sale|세일|추석|이벤트|event|한정|특가|신상|new|재입고|예약|무료배송|주말|타임', tg, re.I): pass
        else:
            for k, v in BRAND_KO.items():
                if k in tg.lower(): brand = v; break
            if not brand: brand = re.sub(r'\s*[A-Za-z][A-Za-z .&]+$', '', tg).strip() or tg
    t = re.sub(r'\[[^\]]*\]', ' ', t)
    t = re.sub(r'앵콜스\s*made', ' ', t, flags=re.I)
    for kb in KNOWN_BRANDS:
        if re.search(r'(?:^|\s)' + re.escape(kb) + r'(?:\s|$)', t):
            brand = brand or BRAND_KO.get(kb.lower(), kb); t = re.sub(r'(?:^|\s)' + re.escape(kb) + r'(?:\s|$)', ' ', t); break
    flags = {}
    m = re.search(r'(?:대용량\s*)?(\d{2,4}\s*g)\b', t)
    if m and re.search(r'대용량|\d{3,4}\s*g', t): flags['put_up'] = m.group(1).replace(' ', ''); t = re.sub(r'대용량\s*(\d{2,4}\s*g)?|\b\d{3,4}\s*g\b', ' ', t)
    if re.search(r'콘사|콘\b|cone', t, re.I): flags['put_up'] = '콘'
    if re.search(r'\d+\s*\+\s*\d+|묶음|볼팩|전색상|세트|모음|낱볼|낱개|합\s*구매|\d+\s*볼\b|kg|대용량|덕용', t): flags['bundle'] = True
    t = re.sub(r'\(([^)]*)\)', lambda m: ' ' if re.search(r'볼|g|m|낱|묶음|무료|특가|할인|%|원|정품|표기', m.group(1)) else m.group(0), t)
    t = re.sub(r'\d+\s*\+\s*\d+|\d+\s*볼\s*묶음|\d+\s*볼팩|\d+\s*볼\b|전색상|낱볼팩|낱볼|낱개|세트|모음|대용량|덕용|특가|할인|SALE|추석|new|신상|재입고', ' ', t, flags=re.I)
    t = re.sub(r'\s*[-–~]\s*.{0,40}(코마면사|합사|한정|추천|용|실\s*$).*$', '', t)
    t = re.sub(r'[\s\-–_,]+$', '', re.sub(r'\s+', ' ', t)).strip(' -–,')
    en = re.search(r'\(([A-Za-z][A-Za-z0-9 .+\-]{1,40})\)', t) or re.search(r'\s([A-Za-z][A-Za-z0-9 .+\-]{2,40})$', t)
    product_en = en.group(1).strip() if en else None
    if product_en: t = t.replace(en.group(0), '').strip(' ()')
    t = re.sub(r'\s+', ' ', t).strip()
    return brand, t, product_en, flags
def parse_colors(options, site):
    seen = {}; out = []
    groups = [o.get('group') for o in options if isinstance(o, dict) and o.get('group')]
    if groups:
        cg = [g for g in dict.fromkeys(groups) if re.search(r'색상|컬러|color|colour', g, re.I)]
        if cg: options = [o for o in options if o.get('group') == cg[0]]
        else: options = [o for o in options if not re.search(r'호|mm|바늘|추가|세트|묶음', o.get('group') or '')]
    if any(isinstance(o, dict) and o.get('img') for o in options): options = [o for o in options if isinstance(o, dict) and o.get('img')]   # 색상칩 이미지가 있는 옵션만
    for o in options:
        name = clean(o['name'] if isinstance(o, dict) else o); img = o.get('img') if isinstance(o, dict) else None
        if re.search(r'묶음|세트|볼팩|▶|★|\d+\s*볼\)|\(\s*\d+\s*볼|kg|콘\)|합\)|추가상품', name) and not re.search(r'낱볼', name): continue
        if re.search(r'미니\s*\(|\(★|★\d+볼|\d+볼묶음|묶음\)|세트\)|_\s*\d+볼', name): continue
        name = re.sub(r'\(\+?[\d,]+원\)|\(품절\)|\[품절\]|\(낱볼\)|\(낱개\)|\(1볼\)|\s*-\s*품절|품절|[♡♠♣♥★☆]+', '', name).strip(' -:_')
        name = re.sub(r'^[가-힣A-Za-z]{1,12}(?=\d{1,5}[\.\s])', '', name)   # '러브1.흰색' → '1.흰색'
        if not name or re.search(r'선택|옵션|------|색상\s*$', name): continue
        m = re.match(r'^\s*([A-Za-z]{0,2}\d{1,5}[A-Za-z]{0,2})\s*[\.\-:번호 ]\s*(.*)$', name) or re.match(r'^\s*(?:no\.?\s*)?(\d{1,5})\s+(.*)$', name, re.I)
        if m: no, cname = m.group(1), m.group(2).strip()
        else: no, cname = '', name
        cname = re.sub(r'\s*\(.*?\)\s*$', '', cname).strip() or no
        key = no or cname
        if key in seen: continue
        seen[key] = 1; out.append({'no': no, 'name': cname[:40], 'img': img})
    return out
def needles_from_cats(cats):
    nk = [c for c in cats if '대바늘' in c]; nc = [c for c in cats if '코바늘' in c]
    def rng(lst, pat):
        vals = []
        for c in lst:
            for m in re.finditer(pat, c): vals.append(m.group(0))
        return vals
    k = rng(nk, r'[\d\.]+\s*(?:~|-|–)\s*[\d\.]+\s*mm|[\d\.]+mm 이상'); c = rng(nc, r'\d+/0\s*(?:~|-|–)\s*\d+/0호?|\d+/0호 이상|레이스용?|점보')
    return (', '.join(sorted(set(k))) or None), (', '.join(sorted(set(c))) or None)
def weight_from_thickness(cats):
    for c in cats:
        m = re.search(r'^(0\.1|1|2|3|5|7)mm', c)
        if m: return {'0.1': '레이스·극세', '1': '합세(Fingering)', '2': '중세(Sport)', '3': '합태(DK)', '5': '병태(Worsted)', '7': '극태(Bulky)'}[m.group(1)]
    return None
def normalize_site(site, rows):
    out = []
    cp = os.path.join(OUT, site + '_cats.json'); CM = json.load(io.open(cp, encoding='utf-8')) if os.path.exists(cp) else {}
    for r in rows:
        if CM and not r.get('cats'): r['cats'] = CM.get(str(r.get('id')), [])
        title = r.get('title', '')
        if EXCLUDE.search(title) and not re.search(r'실\b|얀|yarn|콘사', title, re.I): continue
        brand, product, product_en, flags = parse_title(site, title)
        if not product or len(product) < 2: continue
        cats = r.get('cats', []) or []
        if not brand:
            if site == 'sevy' and any('올림푸스' in c for c in cats): brand = '올림푸스'
            elif site == 'sevy' and any('몬디알' in c for c in cats): brand = '몬디알'
            elif site == 'tgesil' and r.get('ld_brand') and not re.search(r'청송|365', r['ld_brand']): brand = r['ld_brand']
            else: brand = SITE_PB[site]
        spec = r.get('spec', {}) or {}
        blob = ' | '.join([spec.get(k, '') for k in ('상품요약정보', '중량/길이', '중량', '상품소재', '소재', '혼용률', '추천바늘', '권장바늘', '사용바늘', '게이지', '상품간략설명')] + [r.get('ld_desc') or '', r.get('detail_text') or ''])
        gm_src = spec.get('중량/길이') or spec.get('중량') or spec.get('상품요약정보') or title
        g, m = num_gm(gm_src)
        if (g is None or m is None): g2, m2 = num_gm(blob); g = g if g is not None else g2; m = m if m is not None else m2
        f = fibers(spec.get('상품소재') or spec.get('소재') or spec.get('혼용률') or '') or fibers(spec.get('상품요약정보') or '') or fibers(blob)
        nk, nc = needles(' '.join([spec.get(k, '') for k in ('추천바늘', '권장바늘', '사용바늘')]) or blob)
        ck, cc = needles_from_cats(cats); nk = nk or ck; nc = nc or cc
        gauge = (re.search(r'게이지\s*[:：]?\s*([^+|]{4,60})', blob) or [None, None])[1] if '게이지' in blob else spec.get('게이지')
        if not f:
            cs = ' '.join(cats)
            for pat, val in [(r'울\s*100|순모', {'울': 100}), (r'코튼 100|면 100|순면', {'면': 100}), (r'울\s*혼방', None), (r'면\s*혼방', None)]:
                if re.search(pat, cs):
                    if val: f = val
                    else: fm_fallback = '울' if '울' in pat else '면'
                    break
        if not f and not locals().get('fm_fallback'):
            blob2 = (spec.get('상품요약정보') or '') + ' ' + (spec.get('상품소재') or '') + ' ' + (spec.get('소재') or '') + ' ' + title
            for kw, ko in [('폴리100', '폴리에스터'), ('종이실', '종이'), ('한지', '한지'), ('면혼방', '면'), ('면 혼방', '면'), ('울혼방', '울'), ('울 혼방', '울'), ('알파카', '알파카'), ('모헤어', '모헤어'), ('캐시미어', '캐시미어'), ('린넨', '린넨'), ('라피아', '라피아'), ('레이온', '레이온'), ('인견', '레이온'), ('아크릴', '아크릴'), ('코튼', '면'), ('면', '면'), ('울', '울'), ('폴리', '폴리에스터'), ('나일론', '나일론'), ('메탈', '메탈릭')]:
                if kw in blob2: f = {ko: 100} if kw in ('폴리100',) else {}; fm_fallback = ko; break
            else: fm_fallback = None
        elif f: fm_fallback = None
        if not f and not fm_fallback:
            cs = ' '.join(cats)
            for pat, ko in [(r'모헤어', '모헤어'), (r'알파카|라마', '알파카'), (r'캐시미어', '캐시미어'), (r'앙고라', '앙고라'), (r'린넨|삼베', '린넨'), (r'대나무', '대나무'), (r'종이|페이퍼|펠트', '종이'), (r'라피아', '라피아'), (r'실크', '실크'), (r'레이온', '레이온'), (r'메탈', '메탈릭'), (r'수면사|극세사|인조퍼|밍크', '폴리에스터'), (r'아크릴', '아크릴'), (r'폴리', '폴리에스터')]:
                if re.search(pat, cs): fm_fallback = ko; break
        se = season(cats, f or ({fm_fallback: 1} if fm_fallback else {}), product); tex = texture(product + ' ' + title, f)
        wc = weight_from_cats(cats) or weight_from_thickness(cats)
        opts_src = r.get('options', [])
        lv = r.get('ld_variants') or []
        if lv and not any(isinstance(o, dict) and o.get('group') for o in opts_src):
            pn = r.get('spec', {}).get('상품명') or ''
            names = []
            for v in lv:
                v2 = v[len(pn):].strip() if pn and v.startswith(pn) else v
                names.append({'name': v2, 'img': None})
            opts_src = names
        colors = parse_colors(opts_src, site)
        out.append({'site': site, 'shop': SITE_SHOP[site], 'url': r['url'], 'src_id': r.get('id'), 'raw_title': title, 'brand': brand, 'product': product, 'product_en': product_en,
                    'g': g, 'm': m, 'fibers': f or None, 'fiber_main': (max(f.items(), key=lambda x: x[1])[0] if f else fm_fallback), 'season': se, 'needle_knit': nk, 'needle_crochet': nc, 'gauge': (gauge or '').strip()[:60] or None,
                    'put_up': flags.get('put_up'), 'bundle': flags.get('bundle', False), 'texture': tex, 'use_tags': uses(cats, product + ' ' + title, tex, se), 'weight_class': wc, 'cats': cats,
                    'colors': colors, 'images': r.get('images', [])[:3], 'chart_images': r.get('detail_images', []), 'price': (re.search(r'([\d,]+)\s*원', spec.get('판매가', '') or '') or [None, None])[1]})
    return out
def norm(s): return re.sub(r'[^0-9a-z가-힣]', '', (s or '').lower())
if __name__ == '__main__':
    allrows = []
    for site in ('sevy', 'ancalls', 'tgesil', 'banul'):
        p = os.path.join(OUT, site + '.json')
        if not os.path.exists(p): continue
        rows = json.load(io.open(p, encoding='utf-8')); n = normalize_site(site, rows); allrows += n
        print(site, 'raw', len(rows), '→', len(n))
    # 같은 실 합치기: (브랜드 없이) 제품명 정규화 키가 같으면 하나로. 규격은 첫 값, 색은 많은 쪽, 판매처는 누적
    groups = {}
    for r in allrows:
        k = norm(r['product'])
        g = groups.setdefault(k, {'rows': []}); g['rows'].append(r)
    merged = []
    for k, g in groups.items():
        rows = sorted(g['rows'], key=lambda r: (r['bundle'], -len(r['colors']), -(1 if r['g'] and r['m'] else 0)))
        base = dict(rows[0]); base['sellers'] = []; base['put_ups'] = sorted(set(r['put_up'] for r in rows if r['put_up']))
        seen = set()
        for r in rows:
            for key in ('g', 'm', 'fibers', 'fiber_main', 'season', 'needle_knit', 'needle_crochet', 'gauge', 'weight_class', 'product_en'):
                if not base.get(key) and r.get(key): base[key] = r[key]
            if len(r['colors']) > len(base['colors']): base['colors'] = r['colors']; base['chart_images'] = r['chart_images']; base['site'] = r['site']
            base['use_tags'] = sorted(set(base['use_tags']) | set(r['use_tags']))
            if r['shop'] not in seen: seen.add(r['shop']); base['sellers'].append({'shop': r['shop'], 'url': r['url'], 'price': r['price']})
            elif r['bundle'] is False and not any(s['url'] == r['url'] for s in base['sellers']): pass
        # 브랜드: PB 이름보다 명시된 제조사를 우선
        brands = [r['brand'] for r in rows if r['brand'] and r['brand'] not in SITE_PB.values()]
        if brands: base['brand'] = brands[0]
        merged.append(base)
    io.open(os.path.join(OUT, 'normalized.json'), 'w', encoding='utf-8').write(json.dumps(merged, ensure_ascii=False, indent=0))
    print('merged', len(merged), 'colors', sum(len(m['colors']) for m in merged), 'with g/m', sum(1 for m in merged if m['g'] and m['m']), 'with fibers', sum(1 for m in merged if m['fibers']))
