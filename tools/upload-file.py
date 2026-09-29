# 파일 하나를 버킷에 올린다(기본 yarn-colors, 4번째 인자로 버킷 지정)(테스트 계정 demo1, 임시 insert 정책이 켜져 있을 때만)
# 사용: python tools/upload-file.py <로컬 파일> <버킷 경로> [content-type]
import sys, os, io, re, json, urllib.request
ROOT = os.path.join(os.path.dirname(__file__), '..')
html = io.open(os.path.join(ROOT, 'docs', 'index.html'), encoding='utf-8').read()
URL = re.search(r"const SB_URL = '([^']+)'", html).group(1); KEY = re.search(r"const SB_KEY = '([^']+)'", html).group(1)
src, key = sys.argv[1], sys.argv[2]; ctype = sys.argv[3] if len(sys.argv) > 3 else 'application/octet-stream'; bucket = sys.argv[4] if len(sys.argv) > 4 else 'yarn-colors'
req = urllib.request.Request(f'{URL}/auth/v1/token?grant_type=password', data=json.dumps({'email': 'demo1@knit.local', 'password': 'knit1234'}).encode(), headers={'apikey': KEY, 'Content-Type': 'application/json'}, method='POST')
tok = json.loads(urllib.request.urlopen(req, timeout=30).read().decode())['access_token']
req = urllib.request.Request(f'{URL}/storage/v1/object/{bucket}/{key}', data=io.open(src, 'rb').read(), headers={'apikey': KEY, 'Authorization': f'Bearer {tok}', 'x-upsert': 'true', 'Content-Type': ctype}, method='POST')
with urllib.request.urlopen(req, timeout=120) as r: print(r.status, f'{URL}/storage/v1/object/public/{bucket}/{key}')
