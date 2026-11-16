# 다이소몰 '뜨개실' 분류의 상품(색 하나 = 상품 하나) 목록 → daiso/list.json
import json, io, os, re, time, urllib.request, urllib.parse
S = r'C:/Users/yesbe/AppData/Local/Temp/claude/0422a6549ab0c97e/133c9d28-0c4f-477d-bad5-02a0fc6721eb/scratchpad/daiso'
os.makedirs(S, exist_ok=True)
UA = {'User-Agent': 'Mozilla/5.0'}
out = []
for page in range(1, 10):
    u = 'https://www.daisomall.co.kr/ssn/search/SearchGoods?' + urllib.parse.urlencode({'searchTerm': '뜨개실', 'searchQuery': '', 'pageNum': page, 'brndCd': '', 'cntPerPage': 100, 'userId': '', 'searchSort': '', 'isCategory': 1, 'mallId': 'MALL_MAIN'})
    d = json.loads(urllib.request.urlopen(urllib.request.Request(u, headers=UA), timeout=40).read().decode('utf-8'))
    docs = d['resultSet']['result'][1]['resultDocuments']
    if not docs: break
    out += docs; time.sleep(0.5)
keep = [x for x in out if x.get('exhSmallCtgrNo') == 'CTGR_00640']
seen = {}; [seen.setdefault(x['pdNo'], x) for x in keep]
rows = [{'pdNo': x['pdNo'], 'name': x['pdNm'], 'img': x['pdImgUrl'], 'soldout': x.get('soldOutYn'), 'url_no': re.search(r'(\d{6,8})_\d\d_\d\d', x['pdImgUrl'] or '') and re.search(r'(\d{6,8})_\d\d_\d\d', x['pdImgUrl']).group(1)} for x in seen.values()]
io.open(S + '/list.json', 'w', encoding='utf-8').write(json.dumps(rows, ensure_ascii=False, indent=0))
print('all', len(out), 'yarn category', len(rows))
