# 홈페이지 업데이트 소식 시안: 1.0.6~1.0.9 를 한 건(v1.0.9)으로 — 올리지 않음
import io, base64, subprocess
from PIL import Image
S = 'C:/Users/yesbe/AppData/Local/Temp/claude/0422a6549ab0c97e/27c68b59-113b-41d4-b2cf-d0547eb8f68d/scratchpad'
RAW, OUT = S + '/shots/raw', S + '/news'
CH = 'C:/Program Files/Google/Chrome/Application/chrome.exe'
def b64(f): return 'data:image/' + ('png' if f.endswith('.png') else 'jpeg') + ';base64,' + base64.b64encode(open(f, 'rb').read()).decode()
def shot(html, png, w, h):
    hp = png[:-4] + '.html'; io.open(hp, 'w', encoding='utf-8').write('<!doctype html><meta charset="utf-8">' + html)
    subprocess.run([CH, '--headless=new', '--no-sandbox', '--hide-scrollbars', '--force-device-scale-factor=1', f'--window-size={w},{h}', '--screenshot=' + png, 'file:///' + hp], check=True, capture_output=True)
IM = [(RAW + '/cr-3-story.png', '완성작품 인증 · 뜨개 이야기'), (S + '/ag_1.jpeg', '작가·공방 · 팔로우와 문의'), (RAW + '/fq-2.png', '뜨친 신청이 오면 바로')]
cards = ''.join(f'<div style="text-align:center"><div style="font-weight:700;font-size:22px;color:#22362A;margin-bottom:20px">{t}</div><div style="width:300px;height:640px;border-radius:32px 32px 0 0;border:8px solid #22362A;border-bottom:0;overflow:hidden;background:#F3F1EA;box-shadow:0 12px 40px rgba(34,54,42,.25)"><img src="{b64(f)}" style="width:100%;height:100%;object-fit:cover;object-position:top;display:block"></div></div>' for f, t in IM)
shot(f'<body style="margin:0;background:#DDE8D6;display:flex;justify-content:center;align-items:flex-end;gap:44px;height:760px;overflow:hidden;font-family:\'Malgun Gothic\',sans-serif">{cards}</body>', OUT + '/_u109.png', 1200, 760)
Image.open(OUT + '/_u109.png').convert('RGB').crop((0, 0, 1200, 760)).save(OUT + '/update-1.0.9.jpg', quality=86)
TITLE = '글을 고치고, 작가를 팔로우하고, 뜨개 이야기를 남겨요'
BODY = '그동안 달라진 것을 모았어요. 완성작품 인증에 걸린 시간과 뜨기 노하우를 적을 수 있고, 올린 인증은 knitup이 확인한 뒤 커뮤니티에 올려 드려요. 올린 글과 인증은 고치거나 프로필에 고정하고, 나만 보게 보관할 수 있어요. 작가와 공방은 팔로우하고 [문의]로 바로 대화할 수 있고, 가게 소식에는 좋아요와 댓글을 남길 수 있어요. 댓글에 댓글을 달 수 있고, 뜨친 신청이 오면 앱을 열 때 바로 알려 드려요. 채팅 목록은 왼쪽으로 밀어 보관하거나 나갈 수 있어요.'
art = f'''<article style="background: #FFFFFF; border-radius: 20px; padding: 24px 28px; display: flex; flex-wrap: wrap; gap: 20px; align-items: flex-start">
<div class="upmeta" style="flex: 0 0 140px; display: flex; flex-direction: column; gap: 6px">
<span style="align-self: flex-start; background: #3E6B48; color: #FFFFFF; font-size: 13px; font-weight: 700; padding: 3px 10px; border-radius: 999px">업데이트 · v1.0.9</span>
<span style="font-size: 14px; color: #55604F">2026.11.17</span>
</div>
<div style="flex: 1 1 400px; min-width: 0">
<h3 style="margin: 0 0 6px; font-size: 19px">{TITLE}</h3>
<p style="margin: 0; color: #55604F; font-size: 15px">{BODY}</p>
<img src="images/update-1.0.9.jpg" alt="완성작품 인증의 뜨개 이야기, 새 작가 화면, 뜨친 신청 알림 카드" loading="lazy" style="display: block; margin-top: 16px; width: 100%; max-width: 560px; border-radius: 14px">
</div>
</article>
'''
io.open(OUT + '/article-1.0.9.html', 'w', encoding='utf-8', newline='\n').write(art)
body = art.replace('images/update-1.0.9.jpg', 'file:///' + OUT + '/update-1.0.9.jpg').replace('loading="lazy" ', '')
shot(f'<body style="margin:0;background:#F3F1EA;padding:40px;font-family:\'Malgun Gothic\',sans-serif;color:#22362A;line-height:1.6"><div style="font-weight:700;color:#3E6B48;margin-bottom:6px">업데이트 소식</div><div style="font-size:40px;font-weight:800;margin-bottom:24px">새로 바뀐 것들</div>{body}</body>', OUT + '/preview-109one.png', 1100, 760)
print('ok')
