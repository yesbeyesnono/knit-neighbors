# 색상 타일을 Supabase Storage 버킷 yarn-colors 에 올린다 (테스트 계정 demo1 로 로그인 — 임시 insert 정책이 켜져 있을 때만 동작)
# 사용: python tools/upload-yarn-colors.py <타일 폴더 루트(out)>   → out/nakyang/*.jpg 를 nakyang/*.jpg 로
import sys, os, io, re, json, urllib.request, concurrent.futures
ROOT = os.path.join(os.path.dirname(__file__), '..')
html = io.open(os.path.join(ROOT, 'docs', 'index.html'), encoding='utf-8').read()
URL = re.search(r"const SB_URL = '([^']+)'", html).group(1)
KEY = re.search(r"const SB_KEY = '([^']+)'", html).group(1)   # publishable key (앱에 공개된 값)
SRC = sys.argv[1]

def post_json(url, body, headers):
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={**headers, 'Content-Type': 'application/json'}, method='POST')
    with urllib.request.urlopen(req, timeout=30) as r: return json.loads(r.read().decode())

tok = post_json(f'{URL}/auth/v1/token?grant_type=password', {'email': 'demo1@knit.local', 'password': 'knit1234'}, {'apikey': KEY})['access_token']
H = {'apikey': KEY, 'Authorization': f'Bearer {tok}', 'x-upsert': 'true', 'Content-Type': 'image/jpeg'}

files = []
for d, _, fs in os.walk(SRC):
    for f in fs:
        if f.endswith('.jpg'): files.append((os.path.join(d, f), os.path.relpath(os.path.join(d, f), SRC).replace('\\', '/')))
print('files', len(files))
def up(item):
    path, key = item
    req = urllib.request.Request(f'{URL}/storage/v1/object/yarn-colors/{key}', data=io.open(path, 'rb').read(), headers=H, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=60) as r: return key, r.status
    except urllib.error.HTTPError as e: return key, f'ERR {e.code} {e.read()[:80]}'
ok = 0; bad = []
with concurrent.futures.ThreadPoolExecutor(8) as ex:
    for key, st in ex.map(up, files):
        if st == 200: ok += 1
        else: bad.append((key, st))
print('ok', ok, 'bad', len(bad), bad[:5])
