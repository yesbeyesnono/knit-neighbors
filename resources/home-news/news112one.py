# 홈페이지 업데이트 소식 시안: 1.0.10~1.0.12 를 한 건(v1.0.12)으로 — 올리지 않음(시안만)
#   python -X utf8 resources/home-news/news112one.py <화면 사진 폴더> <결과 폴더>
#   화면 사진: e_dong.png(동네 탭) · b_search.png(검색) · g_yarnpick.png(실 고르기) — demo 계정 화면만
import io, base64, subprocess, sys, os
from PIL import Image
RAW, OUT = sys.argv[1].rstrip('/'), sys.argv[2].rstrip('/')
os.makedirs(OUT, exist_ok=True)
CH = 'C:/Program Files/Google/Chrome/Application/chrome.exe'
def b64(f): return 'data:image/' + ('png' if f.endswith('.png') else 'jpeg') + ';base64,' + base64.b64encode(open(f, 'rb').read()).decode()
def shot(html, png, w, h, scale=1):
    hp = png[:-4] + '.html'; io.open(hp, 'w', encoding='utf-8').write('<!doctype html><meta charset="utf-8">' + html)
    subprocess.run([CH, '--headless=new', '--no-sandbox', '--hide-scrollbars', '--force-device-scale-factor=%d' % scale, f'--window-size={w},{h}', '--screenshot=' + png, 'file:///' + hp], check=True, capture_output=True)
IM = [(RAW + '/e_dong.png', '동네 탭 · 내 주변의 글'), (RAW + '/b_search.png', '검색 · 글과 닉네임 찾기'), (RAW + '/g_yarnpick.png', '완성작품 인증 · 실 고르기')]
cards = ''.join(f'<div style="text-align:center"><div style="font-weight:700;font-size:22px;color:#22362A;margin-bottom:20px">{t}</div><div style="width:300px;height:640px;border-radius:32px 32px 0 0;border:8px solid #22362A;border-bottom:0;overflow:hidden;background:#F3F1EA;box-shadow:0 12px 40px rgba(34,54,42,.25)"><img src="{b64(f)}" style="width:100%;height:100%;object-fit:cover;object-position:top;display:block"></div></div>' for f, t in IM)
shot(f'<body style="margin:0;background:#DDE8D6;display:flex;justify-content:center;align-items:flex-end;gap:44px;height:760px;overflow:hidden;font-family:\'Malgun Gothic\',sans-serif">{cards}</body>', OUT + '/_u112.png', 1200, 760)
Image.open(OUT + '/_u112.png').convert('RGB').crop((0, 0, 1200, 760)).save(OUT + '/update-1.0.12.jpg', quality=86)
VER, DATE = 'v1.0.12', '2026.11.24'
TITLE = '검색이 생기고, 내 주변의 글과 모임이 더 잘 보여요'
BODY = ('그동안 달라진 것을 모았어요. 홈 맨 위의 돋보기로 글과 닉네임을 찾을 수 있어요. 커뮤니티 \'동네\' 탭은 내 동네 주변의 글을 보여 주고, 동네는 그 자리에서 바꿀 수 있어요. '
        '지도에는 모임이 노란 카드로 보이고, 가까운 곳에 모임이 열리면 알려 드려요. 모임에 누가 함께하는지도 볼 수 있어요. '
        '일반 글에 30초까지 짧은 영상을 올릴 수 있고, 앱을 열면 이웃의 완성작품을 먼저 만나요. '
        '완성작품 인증은 어떤 도안으로 떴는지와 실을 얼마나 썼는지를 함께 적고, 미리보기로 확인한 뒤 올려요. 보낸 뜨친 신청은 취소할 수 있어요.')
ALT = '커뮤니티 동네 탭, 검색 화면, 완성작품 인증의 실 고르기 화면'
art = f'''<article style="background: #FFFFFF; border-radius: 20px; padding: 24px 28px; display: flex; flex-wrap: wrap; gap: 20px; align-items: flex-start">
<div class="upmeta" style="flex: 0 0 140px; display: flex; flex-direction: column; gap: 6px">
<span style="align-self: flex-start; background: #3E6B48; color: #FFFFFF; font-size: 13px; font-weight: 700; padding: 3px 10px; border-radius: 999px">업데이트 · {VER}</span>
<span style="font-size: 14px; color: #55604F">{DATE}</span>
</div>
<div style="flex: 1 1 400px; min-width: 0">
<h3 style="margin: 0 0 6px; font-size: 19px">{TITLE}</h3>
<p style="margin: 0; color: #55604F; font-size: 15px">{BODY}</p>
<img src="images/update-1.0.12.jpg" alt="{ALT}" loading="lazy" style="display: block; margin-top: 16px; width: 100%; max-width: 560px; border-radius: 14px">
</div>
</article>
'''
io.open(OUT + '/article-1.0.12.html', 'w', encoding='utf-8', newline='\n').write(art)
io.open(OUT + '/news-1.0.12.txt', 'w', encoding='utf-8', newline='\n').write(TITLE + '\n' + BODY + '\n')
body = art.replace('images/update-1.0.12.jpg', 'file:///' + OUT + '/update-1.0.12.jpg').replace('loading="lazy" ', '')
# 시안: 휴대폰 폭(420)으로
shot(f'<body style="margin:0;background:#F3F1EA;padding:20px 16px;width:420px;box-sizing:border-box;font-family:\'Malgun Gothic\',sans-serif;color:#22362A;line-height:1.6"><div style="font-weight:700;color:#3E6B48;margin-bottom:4px">업데이트 소식 시안</div><div style="font-size:26px;font-weight:800;margin-bottom:16px">새로 바뀐 것들</div>{body}</body>', OUT + '/preview-112one.png', 420, 1100, 2)
print('ok')
