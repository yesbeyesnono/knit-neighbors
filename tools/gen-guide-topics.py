# 사용법 묶음(뜨친 찾기 · 모임 · 작가 · 가게 · 내 실함) — 그림과 문구의 원본
# 실행: python tools/gen-guide-topics.py
#   → docs/guides/<이름>.svg (카드 그림)  · resources/plans/guides_topics.json (app_config.guides 에 넣을 값, 완성작품 인증 5장은 따로 있음)
#   → resources/mockups/guide_topics_20261115.html (대표 확인용 시안)
# 그림 좌표는 0~230 × 0~150 안에서 그린다(완성작품 인증 그림과 같은 틀: viewBox -45 -14 320 178)
import io, os, json
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
G, GD, CR, IN, MU, YL, GO, RD, BL, PK = '#3E6B48', '#22362A', '#F3F1EA', '#22362A', '#B9C2B4', '#FFD95C', '#E2A91C', '#C8453A', '#6E9BC9', '#F2B8A0'

def pin(x, y, c=G, s=1.0, inner='#fff'):
    return f'<g transform="translate({x} {y}) scale({s})"><path d="M0 -44 c-16 0 -28 12 -28 27 c0 19 28 43 28 43 s28 -24 28 -43 c0 -15 -12 -27 -28 -27z" fill="{c}"/><circle cx="0" cy="-17" r="12" fill="{inner}"/></g>'
def hand(x, y, s=1.0, c=IN):
    return f'<g transform="translate({x} {y}) scale({s})" fill="{c}"><rect x="-7" y="-2" width="14" height="12" rx="4"/><rect x="-7" y="-11" width="3" height="12" rx="1.5"/><rect x="-3.2" y="-13" width="3" height="14" rx="1.5"/><rect x="0.6" y="-12.500" width="3" height="13" rx="1.5"/><rect x="4.3" y="-10" width="3" height="11" rx="1.5"/><rect x="-11" y="-1" width="3" height="9" rx="1.5" transform="rotate(-28 -9.5 3)"/></g>'
def badge(x, y, r=13):
    return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{YL}" stroke="#fff" stroke-width="2.5"/>' + hand(x, y + 1, r / 15)
def person(x, y, c, s=1.0, skin='#F0D2B6'):
    return f'<g transform="translate({x} {y}) scale({s})"><circle cx="0" cy="-22" r="11" fill="{skin}"/><path d="M-17 12 q17 -28 34 0z" fill="{c}"/></g>'
def yarn(x, y, r, c, d):
    return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{c}"/><g fill="none" stroke="{d}" stroke-width="{max(1.4, r/9):.1f}" stroke-linecap="round"><path d="M{x-r*.7:.1f} {y-r*.3:.1f} q{r*.7:.1f} {-r*.5:.1f} {r*1.4:.1f} {r*.1:.1f}"/><path d="M{x-r*.8:.1f} {y+r*.2:.1f} q{r*.8:.1f} {-r*.5:.1f} {r*1.6:.1f} {r*.1:.1f}"/><path d="M{x-r*.5:.1f} {y+r*.6:.1f} q{r*.5:.1f} {-r*.4:.1f} {r*1.1:.1f} 0"/></g>'
def cardbox(x, y, w, h, rx=9):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="#fff"/>'
def line(x, y, w, c=IN, h=6):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{h/2}" fill="{c}"/>'
def check(x, y, r=11, c=G):
    return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{c}"/><path d="M{x-r*.45:.1f} {y} l{r*.33:.1f} {r*.33:.1f} {r*.62:.1f} {-r*.62:.1f}" fill="none" stroke="#fff" stroke-width="{r*.24:.1f}" stroke-linecap="round" stroke-linejoin="round"/>'
def ground(c): return f'<path d="M-45 126 Q40 108 115 120 T275 112 V164 H-45Z" fill="{c}"/>'
def bubble(x, y, w, h, c, right=False):
    tail = f'<path d="M{x+w-14} {y+h-2} l10 12 -18 -8z" fill="{c}"/>' if right else f'<path d="M{x+14} {y+h-2} l-10 12 18 -8z" fill="{c}"/>'
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{h/2.4:.0f}" fill="{c}"/>' + tail
def crown(x, y, s=1.0, c=GO):
    return f'<path transform="translate({x} {y}) scale({s})" d="M-14 8 l2 -18 8 9 4 -13 4 13 8 -9 2 18z" fill="{c}"/>'
def shop(x, y, s=1.0):
    return (f'<g transform="translate({x} {y}) scale({s})"><rect x="-38" y="-18" width="76" height="52" rx="4" fill="#fff"/><rect x="-44" y="-36" width="88" height="22" rx="5" fill="{RD}"/>'
            + ''.join(f'<rect x="{-44+i*22}" y="-36" width="11" height="22" fill="#fff" opacity=".85"/>' for i in range(4))
            + f'<rect x="-26" y="-4" width="22" height="38" rx="3" fill="{G}"/><rect x="4" y="-4" width="24" height="18" rx="3" fill="#DDE8D6"/></g>')

ART = {
 'wave-1': ('#FFF4CF', ground('#F2E3A8') + pin(115, 112, G, 1.5) + badge(150, 42, 19)),
 'wave-2': ('#E8F0E2', '<g stroke="#fff" stroke-width="9" stroke-linecap="round"><path d="M-30 96 L260 60"/><path d="M70 -10 L104 160"/><path d="M168 -10 L150 160"/></g>'
            + pin(52, 74, G, .95) + badge(70, 26, 11) + pin(196, 118, G, .95) + badge(214, 70, 11) + pin(128, 132, MU, .8)
            + '<rect x="60" y="4" width="112" height="24" rx="12" fill="#22362A"/>' + hand(76, 17, .62, YL) + line(90, 13, 68, '#F3F1EA', 6)),
 'wave-3': ('#FBE7DF', person(40, 122, RD, 1.25) + person(190, 122, BL, 1.25, '#E8C39E') + bubble(58, 18, 92, 30, '#fff') + line(72, 30, 62, MU) + bubble(96, 60, 84, 30, G, True) + line(110, 72, 54, '#DDE8D6')
            + '<path d="M115 116 c-5 -7 -14 -1 -8 6 l8 8 8 -8 c6 -7 -3 -13 -8 -6z" fill="' + RD + '"/>'),
 'meet-1': ('#F6EBD3', ground('#EADBB8') + pin(115, 96, G, 1.25) + check(115, 75, 9, G) + person(44, 128, RD) + person(84, 136, GO, .85) + person(150, 136, '#8FB58A', .85) + person(190, 128, BL, 1, '#E8C39E')),
 'meet-2': ('#DDE8D6', f'<rect x="20" y="40" width="70" height="70" rx="18" fill="{G}"/><path d="M55 58 v34 M38 75 h34" stroke="#fff" stroke-width="7" stroke-linecap="round"/>'
            + cardbox(108, 22, 104, 108) + line(120, 36, 60) + line(120, 54, 80, MU, 5) + f'<rect x="120" y="68" width="80" height="16" rx="5" fill="{CR}"/><rect x="120" y="90" width="80" height="16" rx="5" fill="{CR}"/>' + f'<rect x="164" y="112" width="36" height="12" rx="6" fill="{G}"/>'),
 'meet-3': ('#FFF4CF', f'<circle cx="62" cy="76" r="36" fill="{GO}"/><circle cx="62" cy="76" r="28" fill="{YL}"/><text x="62" y="87" text-anchor="middle" font-size="30" font-weight="800" fill="#8A6A12" font-family="Arial,sans-serif">₩</text>'
            + cardbox(116, 26, 96, 100) + check(134, 48, 8) + line(148, 45, 52, MU, 5) + check(134, 76, 8) + line(148, 73, 44, MU, 5) + f'<circle cx="134" cy="104" r="8" fill="none" stroke="{MU}" stroke-width="2"/>' + line(148, 101, 50, MU, 5)),
 'meet-4': ('#E4ECF2', '<g transform="rotate(-5 80 76)">' + cardbox(30, 22, 100, 108) + f'<rect x="38" y="30" width="84" height="62" rx="6" fill="#C9D8BF"/>' + yarn(66, 64, 15, PK, '#D98F76') + yarn(96, 68, 12, BL, '#4A78AB') + line(38, 100, 56) + line(38, 113, 36, MU, 5) + '</g>'
            + ''.join(f'<path transform="translate({150+i*24} 62)" d="M0 -11 l3.300 6.800 7.500 .9 -5.600 5.100 1.500 7.400 -6.700 -3.700 -6.700 3.700 1.500 -7.400 -5.600 -5.100 7.500 -.9z" fill="{GO}"/>' for i in range(3)) + line(140, 88, 68, '#fff', 8) + line(140, 104, 50, '#fff', 8)),
 'author-1': ('#FBF1CF', ''.join(cardbox(14 + i * 44, 44 + (i % 2) * 6, 38, 50, 6) + f'<rect x="{19+i*44}" y="{49+(i%2)*6}" width="28" height="22" rx="4" fill="#DDE8D6"/>' + check(33 + i * 44, 82 + (i % 2) * 6, 7) for i in range(3))
              + '<path d="M150 74 h22 m-8 -8 l8 8 -8 8" fill="none" stroke="#22362A" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/>' + f'<circle cx="202" cy="74" r="24" fill="#fff"/>' + crown(202, 76, 1.25)),
 'author-2': ('#FBF1CF', ground('#F0E0A8') + ''.join(f'<path d="M115 34 l{dx} {dy}" stroke="{GO}" stroke-width="3" stroke-linecap="round" opacity=".55"/>' for dx, dy in [(-62, -14), (-44, -30), (62, -14), (44, -30), (0, -34)]) + pin(115, 114, GO, 1.55) + crown(115, 90, 1.05)
              + '<rect x="84" y="8" width="62" height="20" rx="10" fill="#22362A"/><text x="115" y="22" text-anchor="middle" font-size="11" font-weight="800" fill="#FFD95C" font-family="Arial,sans-serif">♛ 작가</text>'),
 'author-3': ('#E4ECF2', cardbox(34, 18, 162, 116, 12) + f'<rect x="46" y="30" width="138" height="40" rx="8" fill="#DDE8D6"/><path d="M92 54 q11 -14 22 0 q11 -14 22 0" fill="none" stroke="{G}" stroke-width="3.500" stroke-linecap="round"/>' + line(46, 80, 84) + ''.join(f'<circle cx="{56+i*20}" cy="108" r="8" fill="{c}"/>' for i, c in enumerate([PK, '#E8C39E', '#F0D2B6', MU])) + f'<rect x="136" y="98" width="48" height="20" rx="10" fill="{G}"/>'),
 'shop-1': ('#E4ECF2', ground('#CFDCE6') + shop(96, 84, 1.25) + pin(188, 96, RD, 1.0)),
 'shop-2': ('#FBE7DF', cardbox(96, 28, 116, 96, 10) + f'<rect x="106" y="38" width="96" height="36" rx="6" fill="#F6EBD3"/>' + yarn(132, 56, 12, PK, '#D98F76') + yarn(160, 58, 10, '#8FB58A', G) + line(106, 84, 70) + line(106, 100, 50, MU, 5)
            + f'<path d="M38 60 q0 -22 22 -22 q22 0 22 22 v22 l8 10 h-60 l8 -10z" fill="{YL}"/><circle cx="60" cy="100" r="7" fill="{GO}"/><circle cx="84" cy="42" r="11" fill="{RD}"/><text x="84" y="46.500" text-anchor="middle" font-size="12" font-weight="800" fill="#fff" font-family="Arial,sans-serif">N</text>'),
 'shop-3': ('#DDE8D6', shop(62, 86, 1.0) + cardbox(118, 26, 96, 100, 10) + f'<rect x="128" y="36" width="76" height="30" rx="6" fill="#F3F1EA"/><path d="M148 55 q9 -12 18 0 q9 -12 18 0" fill="none" stroke="{G}" stroke-width="3" stroke-linecap="round"/>' + line(128, 76, 56) + line(128, 90, 40, MU, 5) + f'<rect x="166" y="104" width="38" height="14" rx="7" fill="{G}"/>'),
 'stash-1': ('#FBE7DF', f'<rect x="62" y="6" width="106" height="138" rx="16" fill="#22362A"/><rect x="69" y="14" width="92" height="108" rx="9" fill="#F3E3C8"/>' + yarn(115, 66, 30, PK, '#D98F76') + f'<rect x="101" y="52" width="28" height="30" rx="3" fill="#fff" stroke="{G}" stroke-width="1.5"/>' + line(105, 58, 20, G, 5) + line(107, 68, 16, IN, 4)
             + '<path d="M79 24 h12 m-12 0 v12 M151 24 h-12 m12 0 v12 M79 112 h12 m-12 0 v-12 M151 112 h-12 m12 0 v-12" stroke="#fff" stroke-width="2.500" fill="none" stroke-linecap="round"/><circle cx="115" cy="133" r="7" fill="#fff"/>'),
 'stash-2': ('#DDE8D6', ''.join(f'<rect x="12" y="{30+i*32}" width="84" height="24" rx="12" fill="#fff"/><circle cx="28" cy="{42+i*32}" r="7" fill="{c}"/>' + line(40, 39 + i * 32, 44, MU, 5) for i, c in enumerate([PK, BL, '#8FB58A']))
             + f'<rect x="12" y="30" width="84" height="24" rx="12" fill="none" stroke="{G}" stroke-width="2.500"/>' + '<path d="M106 76 h20 m-8 -8 l8 8 -8 8" fill="none" stroke="#22362A" stroke-width="3.500" stroke-linecap="round" stroke-linejoin="round"/>'
             + cardbox(138, 24, 78, 104, 10) + f'<rect x="146" y="32" width="62" height="44" rx="6" fill="#F3E3C8"/><path d="M162 68 Q162 44 177 44 Q192 44 192 68Z" fill="{BL}"/>' + f'<circle cx="152" cy="92" r="6" fill="{PK}"/>' + line(162, 89, 40, IN, 5) + check(200, 114, 8)),
 'stash-3': ('#F6EBD3', f'<rect x="20" y="70" width="190" height="8" rx="3" fill="#C9B79A"/><rect x="20" y="132" width="190" height="8" rx="3" fill="#C9B79A"/>'
             + yarn(54, 50, 20, PK, '#D98F76') + yarn(112, 48, 22, BL, '#4A78AB') + yarn(172, 52, 18, '#8FB58A', G) + yarn(70, 112, 20, YL, GO) + yarn(140, 114, 18, '#D8C8E8', '#9C86B8')
             + ''.join(f'<rect x="{x}" y="{y}" width="26" height="15" rx="7.500" fill="#22362A"/><text x="{x+13}" y="{y+11}" text-anchor="middle" font-size="9.500" font-weight="800" fill="#fff" font-family="Arial,sans-serif">{t}</text>' for x, y, t in [(62, 24, '3볼'), (124, 20, '1볼'), (178, 28, '2볼'), (80, 86, '4볼'), (146, 90, '1볼')])),
}
V = lambda v: {"type": "view", "view": v}
TOPICS = [
 {"id": "wave", "title": "뜨친 찾기", "sub": "손 들기 · 신청 · 첫 인사", "emoji": "✋", "bg": "#FFF4CF", "cards": [
  {"img": "wave-1", "title": "손을 들면 이웃이 먼저 알아봐요", "body": "마이 맨 위에서 손 들기를 켜면 지도의 내 핀에 ✋ 표시가 올라가요. \"먼저 말 걸어도 돼요\"라는 뜻이에요. 14일 뒤 저절로 내려가고, 언제든 끌 수 있어요.", "btn": "손 들러 가기", "link": V("wave")},
  {"img": "wave-2", "title": "지도에서 이웃을 찾아 신청해요", "body": "지도에서 '친구 찾는 이웃'을 누르면 손 든 이웃만 보여요. 핀을 눌러 프로필을 보고 친구 신청을 보내요. 내 위치는 정확한 주소가 아니라 동네 근처로만 보여요.", "btn": "지도 보기", "link": V("map")},
  {"img": "wave-3", "title": "뜨친이 되면 첫 인사를 건네요", "body": "신청이 오면 앱을 열 때 알려 드려요. 수락하면 뜨친이 되고 둘만의 대화방이 열려요. 인사말을 골라 보내기만 해도 돼요.", "btn": "채팅 보기", "link": V("chats")}]},
 {"id": "meet", "title": "모임", "sub": "참여하기 · 직접 열기 · 참가비", "emoji": "📍", "bg": "#F6EBD3", "cards": [
  {"img": "meet-1", "title": "동네 모임, 구경부터 해요", "body": "커뮤니티의 모임 탭과 지도에서 가까운 모임을 볼 수 있어요. [참여]를 누르면 모임 대화방에 들어가요. 완성작품 인증이 없어도 참여할 수 있어요.", "btn": "모임 보러 가기", "link": V("meets")},
  {"img": "meet-2", "title": "직접 모임을 열 수 있어요", "body": "완성작품 인증이 1개 있으면 ＋ 버튼에서 모임을 열 수 있어요. 날짜, 장소, 인원, 함께 뜰 기법을 적으면 끝이에요.", "btn": "완성작품 인증하러 가기", "link": V("cert")},
  {"img": "meet-3", "title": "참가비가 있는 모임은 이렇게", "body": "대관비처럼 참가비가 있으면 금액, 어디에 쓰는지, 환불 안내를 적어요. 신청을 받고 여는 분이 확정하는 방식으로 할 수 있어요. 돈은 앱에서 오가지 않고, 확정된 분들에게 대화방에서 직접 안내해요."},
  {"img": "meet-4", "title": "다녀온 뒤엔 후기를 남겨요", "body": "모임이 끝나면 사진과 함께 후기를 올릴 수 있어요. 다음에 올 이웃에게 큰 도움이 돼요."}]},
 {"id": "author", "title": "작가", "sub": "작가가 되려면 · 클래스 열기", "emoji": "♛", "bg": "#FBF1CF", "cards": [
  {"img": "author-1", "title": "작가가 되려면", "body": "가장 높은 전문(5단계) 기법이 들어간 완성작품 인증이 3개 모이면 신청할 수 있어요. 마이 › 설정 › 작가 신청을 누르면 운영진이 확인한 뒤 작가로 바꿔 드려요.", "btn": "작가 신청 알아보기", "link": V("author")},
  {"img": "author-2", "title": "작가가 되면 달라지는 것", "body": "지도에 황금색 작가 핀으로, 멀리서도 보여요. 내 작가 화면에 대표작 사진과 링크 3개를 걸 수 있고, 이웃이 팔로우하거나 문의를 보낼 수 있어요."},
  {"img": "author-3", "title": "클래스를 열 수 있어요", "body": "수업 내용, 날짜, 인원, 수강료를 적어 클래스를 열어요. 신청이 오면 확정하고, 확정된 분들과 클래스 대화방이 열려요. 수강료는 대화방에서 직접 안내해요."}]},
 {"id": "shop", "title": "가게", "sub": "우리 가게 등록 · 소식 · 클래스", "emoji": "🏪", "bg": "#E4ECF2", "cards": [
  {"img": "shop-1", "title": "우리 가게를 지도에 올려요", "body": "마이 › 설정 › 우리 가게 등록 신청에서 상호, 주소, 사업자등록증을 올려요. 확인되면 지도에 가게 핀이 생겨요.", "btn": "가게 등록 신청", "link": V("shopclaim")},
  {"img": "shop-2", "title": "소식을 올리면 이웃에게 알림이 가요", "body": "새 실 입고, 할인, 휴무 같은 소식을 올려요. 가게를 팔로우한 이웃에게 알림이 가요."},
  {"img": "shop-3", "title": "가게에서 클래스를 열어요", "body": "가게 화면의 [클래스 열기]에서 수업을 만들어요. 신청을 받고 확정하면 클래스 대화방이 열려요."}]},
 {"id": "stash", "title": "내 실함", "sub": "실 담기 · 인증에서 꺼내 쓰기", "emoji": "🧺", "bg": "#FBE7DF", "cards": [
  {"img": "stash-1", "title": "산 실을 사진으로 담아 둬요", "body": "실 전체 한 장, 띠지 뒷면 한 장을 찍으면 이름, 색, 무게를 읽어 실함에 담아요. 틀린 곳은 눌러서 고치면 돼요. 내 실함은 다른 회원에게 보이지 않아요.", "btn": "내 실함 열기", "link": V("stash")},
  {"img": "stash-2", "title": "인증할 때 한 번에 꺼내 써요", "body": "완성작품 인증에서 내 실함의 실을 누르면 이름과 색이 바로 들어가요. 쓴 만큼 남은 볼 수가 저절로 줄어요."},
  {"img": "stash-3", "title": "남은 실을 한눈에 봐요", "body": "남은 실과 다 쓴 실을 나눠 볼 수 있어요. 나눠 주거나 잃어버린 실은 남은 볼 수를 직접 고치면 돼요."}]},
]
out = os.path.join(root, 'docs', 'guides'); os.makedirs(out, exist_ok=True)
for name, (bg, body) in ART.items():
    io.open(os.path.join(out, name + '.svg'), 'w', encoding='utf-8', newline='').write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="-45 -14 320 178" width="640" height="356"><rect x="-45" y="-14" width="320" height="178" fill="{bg}"/>{body}</svg>\n')
os.makedirs(os.path.join(root, 'resources', 'plans'), exist_ok=True)
io.open(os.path.join(root, 'resources', 'plans', 'guides_topics.json'), 'w', encoding='utf-8', newline='').write(json.dumps(TOPICS, ensure_ascii=False, indent=1))
esc = lambda t: t.replace('&', '&amp;').replace('<', '&lt;')
rows = ''.join(f'<h2>{t["emoji"]} {t["title"]} <small>{t["sub"]} · {len(t["cards"])}장</small></h2><div class="row">' + ''.join(
    f'<div class="gc"><img src="../../docs/guides/{c["img"]}.svg"><div class="tx"><div class="k">{t["title"]} · {i+1}/{len(t["cards"])}</div><b>{esc(c["title"])}</b><p>{esc(c["body"])}</p>' + (f'<div class="btn">{esc(c["btn"])}</div>' if c.get('btn') else '') + '</div></div>'
    for i, c in enumerate(t['cards'])) + '</div>' for t in TOPICS)
html = '''<!doctype html><html lang="ko"><head><meta charset="utf-8"><title>사용법 묶음 시안</title><style>
*{box-sizing:border-box;margin:0;padding:0}body{font-family:-apple-system,"Apple SD Gothic Neo","Malgun Gothic","Noto Sans KR",sans-serif;background:#E7E4DB;padding:26px 22px 30px;color:#22362A;width:1180px}
h1{font-size:21px;margin-bottom:6px}.sub{font-size:13.5px;color:#55604F;margin-bottom:8px}h2{font-size:16px;margin:22px 0 10px}h2 small{font-weight:400;color:#8A9384;font-size:12.5px;margin-left:6px}
.row{display:flex;gap:14px}.gc{width:268px;background:#fff;border-radius:18px;overflow:hidden;box-shadow:0 4px 14px rgba(0,0,0,.08)}.gc img{display:block;width:100%}
.tx{padding:13px 15px 15px}.k{font-size:11px;font-weight:800;color:#3E6B48;margin-bottom:4px}.tx b{font-size:15.5px;line-height:1.3;display:block;margin-bottom:6px}.tx p{font-size:12.5px;line-height:1.55;color:#55604F}
.btn{margin-top:11px;background:#3E6B48;color:#fff;border-radius:12px;height:38px;display:grid;place-items:center;font-weight:700;font-size:13.5px}</style></head><body>
<h1>사용법 묶음 — 뜨친 찾기 · 모임 · 작가 · 가게 · 내 실함</h1><div class="sub">마이 › 소식·사용법 › 사용법에 '완성작품 인증' 옆으로 추가되는 묶음입니다. 카드는 옆으로 넘겨 봅니다.</div>''' + rows + '</body></html>'
io.open(os.path.join(root, 'resources', 'mockups', 'guide_topics_20261115.html'), 'w', encoding='utf-8', newline='').write(html)
print('ok', len(ART), 'svgs', sum(len(t['cards']) for t in TOPICS), 'cards')
