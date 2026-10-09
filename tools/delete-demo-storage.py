# demo1~6 계정이 올린 Storage 파일 삭제(글 사진·아바타·볼밴드·채팅 사진) — 각 계정으로 로그인해 자기 폴더(<uid>/…)만 지운다
#   python tools/delete-demo-storage.py [--dry]
import sys, os, io, re, json, urllib.request
ROOT = os.path.join(os.path.dirname(__file__), '..')
html = io.open(os.path.join(ROOT, 'docs', 'index.html'), encoding='utf-8').read()
URL = re.search(r"const SB_URL = '([^']+)'", html).group(1); KEY = re.search(r"const SB_KEY = '([^']+)'", html).group(1)
DRY = '--dry' in sys.argv
BUCKETS = ['posts', 'avatars', 'bands', 'chat-photos', 'works']
def call(method, path, tok, body=None):
    req = urllib.request.Request(URL + path, data=json.dumps(body).encode() if body is not None else None, method=method,
                                 headers={'apikey': KEY, 'Authorization': 'Bearer ' + tok, 'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=60) as r: return r.status, json.loads(r.read().decode() or 'null')
    except urllib.error.HTTPError as e: return e.code, e.read().decode()[:200]
def listing(bucket, prefix, tok):
    out = []; st, rows = call('POST', f'/storage/v1/object/list/{bucket}', tok, {'prefix': prefix, 'limit': 1000})
    if st != 200: return out
    for r in rows or []:
        name = prefix + '/' + r['name'] if prefix else r['name']
        if r.get('id') is None: out += listing(bucket, name, tok)   # 폴더
        else: out.append(name)
    return out
total = 0
for n in range(1, 7):
    st, j = call('POST', '/auth/v1/token?grant_type=password', KEY, {'email': f'demo{n}@knit.local', 'password': 'knit1234'})
    if st != 200: print(f'demo{n}: login failed', st); continue
    tok, uid = j['access_token'], j['user']['id']
    for b in BUCKETS:
        files = listing(b, uid, tok)
        if not files: continue
        if DRY: print(f'demo{n} {b}: {len(files)} files'); total += len(files); continue
        st, res = call('DELETE', f'/storage/v1/object/{b}', tok, {'prefixes': files})
        print(f'demo{n} {b}: {len(files)} files -> {st} {str(res)[:80]}'); total += len(files) if st == 200 else 0
print('done', total)
