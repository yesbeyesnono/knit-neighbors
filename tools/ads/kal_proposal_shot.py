# '함께 뜨기' 한 장 제안서를 그림으로 찍는다: resources/ads/kal_proposal/proposal.html
#   python -X utf8 tools/ads/kal_proposal_shot.py <저장 폴더> [받는 곳 이름]
# 받는 곳 이름을 주면 맨 위 표시와 맨 아래 한 줄이 그 이름으로 바뀐다(없으면 '공방 · 작가님께').
# 결과: 제안서_전체.png + 제안서_1.png(위) · 제안서_2.png(아래) — 가로 1260(420 x 3배)
import os, subprocess, sys, urllib.parse
from PIL import Image

root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))).replace('\\', '/')
out = os.path.abspath(sys.argv[1]); to = sys.argv[2] if len(sys.argv) > 2 else ''
os.makedirs(out, exist_ok=True)
url = 'file:///' + root + '/resources/ads/kal_proposal/proposal.html' + ('?to=' + urllib.parse.quote(to) if to else '')
raw = os.path.join(out, '_raw.png')
subprocess.run(['C:/Program Files/Google/Chrome/Application/chrome.exe', '--headless=new', '--no-sandbox', '--hide-scrollbars',
                '--force-device-scale-factor=3', '--window-size=420,3000', '--screenshot=' + raw, url], capture_output=True)
im = Image.open(raw).convert('RGB'); w, h = im.size; px = im.load(); bg = px[w - 5, h - 5]
blank = lambda y: all(abs(px[x, y][i] - bg[i]) < 4 for x in range(0, w, 30) for i in range(3))
y = h - 1
while y > 0 and blank(y): y -= 1
im = im.crop((0, 0, w, min(h, y + 40))); h = im.size[1]; px = im.load()
# 가운데쯤의 가장 넓은 빈 띠에서 둘로 나눈다
ys = [v for v in range(int(h * 0.5), int(h * 0.75)) if blank(v)]
runs = []; s = p = ys[0]
for v in ys[1:]:
    if v != p + 1: runs.append((s, p)); s = v
    p = v
runs.append((s, p)); a, b = max(runs, key=lambda r: r[1] - r[0]); c = (a + b) // 2
im.save(os.path.join(out, '제안서_전체.png')); im.crop((0, 0, w, c)).save(os.path.join(out, '제안서_1.png')); im.crop((0, c, w, h)).save(os.path.join(out, '제안서_2.png'))
os.remove(raw); print(im.size, '나눈 곳', c, '→', out)
