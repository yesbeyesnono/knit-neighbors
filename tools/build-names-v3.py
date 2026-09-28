# 기법·기호 명칭 통일표 v3 — 한국 관행(엑셀) 기준으로 한글을 통일하고, 일어는 日本ヴォーグ社 편목기호 명칭으로 맞춘다 (2026-09-28)
#   입력: tools/crochet-symbols-master.json(94종) + knitup/knitup_technique_dictionary_v1.3.json(60종)
#   출력: resources/symbols/names_v3.json (기계용) · resources/symbols/명칭통일_v3.md (검토용)
import io, json, os, sys
sys.stdout.reconfigure(encoding='utf-8')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KNITUP = os.path.join(os.path.dirname(ROOT), 'knitup')
master = json.load(io.open(os.path.join(ROOT, 'tools', 'crochet-symbols-master.json'), encoding='utf-8'))
dic = json.load(io.open(os.path.join(KNITUP, 'knitup_technique_dictionary_v1.3.json'), encoding='utf-8'))['techniques']

# ① 기존 60종 중 이름을 바꾸는 것 (옛 이름은 별칭으로 보존)
RENAME = {   # id: (새 한글, 새 일어, 메모)
 'C12': ('긴뜨기', '中長編み', '한국 관행: 中長編み=긴뜨기'),
 'C13': ('한길 긴뜨기', '長編み', '한국 관행: 長編み=한길 긴뜨기'),
 'C18': ('두길 긴뜨기', '長々編み', '띄어쓰기 통일'),
 'C10': ('이랑뜨기·줄기뜨기', 'うね編み・すじ編み', '뒤 반 코만 뜨는 기법 하나로 묶음. 왕복=이랑(うね), 원형=줄기(すじ)'),
 'C15': ('솔잎뜨기(셸뜨기)', '松編み', '엑셀: 松編み=솔잎뜨기, シェル編み=조개뜨기 → 둘 다 C15 변형'),
 'C27': ('감아뜨기(코일뜨기)', '巻き編み', 'JIS·ヴォーグ 명칭은 巻き編み. コイル編み는 별칭'),
 'C30': ('짧은 링뜨기', 'リング細編み', '엑셀 표기'),
}
# ② 새 기법 후보 (단계·선행은 초안 — 대표 확인)
NEW = [
 dict(id='C31', name_ko='세길 긴뜨기', name_ja='三つ巻き長編み', name_en='double treble crochet', abbr='dtr', level=4, prereq=['C18'], category='기본 코', desc='실을 세 번 감아 뜨는 코. 두길 긴뜨기보다 한 단 더 높다', rows=[10]),
 dict(id='C32', name_ko='네길 긴뜨기', name_ja='四つ巻き長編み', name_en='triple treble crochet', abbr='trtr', level=4, prereq=['C31'], category='기본 코', desc='실을 네 번 감아 뜨는 코', rows=[11]),
 dict(id='C33', name_ko='Y자뜨기·역Y자뜨기', name_ja='Y字編み・逆Y字編み', name_en='Y-stitch / inverted Y-stitch', abbr='Y-st', level=5, prereq=['C18'], category='응용 코', desc='두길 긴뜨기 기둥에서 가지를 내거나(Y), 두 다리를 한 기둥으로 모으는(역Y) 코', rows=[101, 102, 103, 108, 111]),
 dict(id='C34', name_ko='X자뜨기(클로스뜨기)', name_ja='クロス編み', name_en='X-stitch (crossed dc)', abbr='X-st', level=5, prereq=['C18'], category='응용 코', desc='두 다리를 모아 허리를 만들고 다시 두 팔로 벌리는 X 모양 코', rows=[104, 105, 106]),
 dict(id='C35', name_ko='삼각뜨기', name_ja='三角編み', name_en='triangle stitch', abbr='tri-st', level=5, prereq=['C33'], category='응용 코', desc='높이가 다른 미완성 코 여러 개를 한 점에 모아 삼각형을 만드는 코', rows=[109]),
 dict(id='C36', name_ko='칠보뜨기', name_ja='七宝編み', name_en="Solomon's knot", abbr='Sk', level=3, prereq=['C01', 'C02'], category='응용 코', desc='사슬 고리를 길게 뽑아 짧은뜨기로 고정하며 그물처럼 잇는 코', rows=[112]),
 dict(id='C37', name_ko='되돌아 짧은뜨기', name_ja='バック細編み', name_en='reverse single crochet (crab stitch)', abbr='rev sc', level=2, prereq=['C02'], category='기본 코', desc='왼쪽에서 오른쪽으로 되돌아가며 뜨는 짧은뜨기. 가장자리 마감용 (바늘 돌려서·실 돌려서 짧은뜨기는 변형)', rows=[121, 122, 123, 124, 125]),
 dict(id='C38', name_ko='변형 구슬뜨기(퍼프)', name_ja='変わり玉編み', name_en='puff stitch (modified cluster)', abbr='puff', level=4, prereq=['C19'], category='입체 코', desc='미완성 긴뜨기 고리만 먼저 빼고 남은 2고리를 한 번 더 빼서 위가 정돈된 구슬', rows=[23, 24]),
]
by_row = {n['id']: set(n['rows']) for n in NEW}

techs = []
for t in dic:
    t = dict(t); old_ko, old_ja = t['name_ko'], t.get('name_ja', '')
    t['aliases'] = []
    if t['id'] in RENAME:
        ko, ja, memo = RENAME[t['id']]; t['name_ko'], t['name_ja'], t['rename_memo'] = ko, ja, memo
        t['aliases'] = [x for x in {old_ko, old_ja} if x and x not in (ko, ja)]
    techs.append(t)
for n in NEW: techs.append(dict(n, craft='crochet', aliases=[], status='candidate'))

symbols = []
for m in master:
    tech = m['tech'] if m['tech'].startswith('C') else next((k for k, rs in by_row.items() if m['src'] in rs), None)
    ko = m['ko'].replace('から -> 사슬뜨기에서', '에서').replace('코 아래から', '코 아래에서').replace('※', '').strip()
    if m['no'] == 94: ko = '실 돌려서 짧은뜨기'
    old_dict_ko = m['ko_dict'].split(' (')[0] if m['ko_dict'] else ''
    aliases = sorted({x for x in [m['jp'], m['en'], m['abbr'], old_dict_ko] if x and x != ko})
    symbols.append(dict(no=m['no'], src_row=m['src'], ko=ko, ja=m['jp'], en=m['en'], abbr=m['abbr'], en_uk=m['uk'], tech=tech,
                        variant=(m['no'] not in (1, 2, 3, 4, 5, 6, 7, 8)), section=m['sec'], aliases=aliases))

RULE = '한글=한국 관행(中長編み 긴뜨기 · 長編み 한길 긴뜨기 · 長々編み 두길 긴뜨기 · 三つ巻き 세길 · 四つ巻き 네길), 일어=日本ヴォーグ社 編み目記号 명칭. 옛 이름은 aliases 로 보존'
out = dict(version='3-draft', date='2026-09-28', rule=RULE, techniques=techs, symbols=symbols)
os.makedirs(os.path.join(ROOT, 'resources', 'symbols'), exist_ok=True)
json.dump(out, io.open(os.path.join(ROOT, 'resources', 'symbols', 'names_v3.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)

md = ['# 기법·기호 명칭 통일표 v3 (초안 · 2026-09-28)', '', '규칙: ' + RULE, '', '## 1. 이름을 바꾸는 기존 기법 (7)', '', '| ID | 옛 한글 | → 새 한글 | 옛 일어 | → 새 일어 | 메모 |', '|---|---|---|---|---|---|']
for t in techs:
    if 'rename_memo' in t:
        o = next(x for x in dic if x['id'] == t['id']); md.append('| %s | %s | **%s** | %s | **%s** | %s |' % (t['id'], o['name_ko'], t['name_ko'], o.get('name_ja', ''), t['name_ja'], t['rename_memo']))
md += ['', '## 2. 새 기법 후보 (8) — 단계·선행은 초안', '', '| ID | 한글 | 일어 | 영어 | 단계 | 선행 | 마스터표 행 |', '|---|---|---|---|---|---|---|']
for n in NEW: md.append('| %s | **%s** | %s | %s | %d | %s | %s |' % (n['id'], n['name_ko'], n['name_ja'], n['name_en'], n['level'], ', '.join(n['prereq']), ', '.join(map(str, n['rows']))))
md += ['', '## 3. 코바늘 기법 30종 최종 이름', '', '| ID | 한글 | 일어 | 영어 | Lv |', '|---|---|---|---|---|']
for t in techs:
    if t['craft'] == 'crochet' and t.get('status') != 'candidate': md.append('| %s | %s | %s | %s | %s |' % (t['id'], t['name_ko'], t.get('name_ja', ''), t.get('name_en', ''), t['level']))
md += ['', '## 4. 기호 94종 (한글 · 일어 · 영어 · 기법)', '', '| No | 한글 | 일어 | 영어 | 기법 |', '|---|---|---|---|---|']
for s in symbols: md.append('| %d | %s | %s | %s | %s |' % (s['no'], s['ko'], s['ja'], s['en'], s['tech'] or '–'))
md += ['', '## 5. 대바늘 30종 — 이번에는 이름 변경 없음 (일어는 사전 v1.3 그대로)', '']
io.open(os.path.join(ROOT, 'resources', 'symbols', '명칭통일_v3.md'), 'w', encoding='utf-8').write('\n'.join(md))
print('techniques', len(techs), 'symbols', len(symbols), 'unmapped', [s['no'] for s in symbols if not s['tech']])
