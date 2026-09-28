# 기법 사전 v1.4 생성 — 코바늘 명칭 통일(v3)+새 기법 8 · 대바늘 B안(단계 재배치 + 변형 합치기). 2026-09-28 대표 확정
#   입력: resources/symbols/names_v3.json (build-names-v3.py 결과) + knitup 사전 v1.3
#   출력: resources/symbols/technique_dictionary_v1.4.json · 기법사전_v1.4.md (+ knitup 폴더에 같은 파일 복사)
#   원칙: 기법 ID는 지우지 않는다(옛 데이터 호환). 합쳐진 기법은 hidden + merged_into 로 표시하고 이름은 별칭으로 남긴다
import io, json, os, shutil, sys
sys.stdout.reconfigure(encoding='utf-8')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KNITUP = os.path.join(os.path.dirname(ROOT), 'knitup')
SYM = os.path.join(ROOT, 'resources', 'symbols')
names = json.load(io.open(os.path.join(SYM, 'names_v3.json'), encoding='utf-8'))
techs = {t['id']: dict(t) for t in names['techniques']}

# ---- 대바늘 B안
MOVE = {'K07': 1, 'K11': 3, 'K26': 5, 'K28': 5}            # 메리야스→1, 줄무늬 배색→3, 아란무늬→5, 의류 구성→5
MERGE = {'K06': 'K01', 'K14': 'K13'}                         # 롱테일 캐스트온→기본 코잡기 변형, 오른코 모아뜨기→모아뜨기 변형
for k, lv in MOVE.items(): techs[k]['level'] = lv
techs['K13'].update(name_ko='모아뜨기', name_ja='2目一度', abbr='k2tog / ssk', symbol='人 入', desc='두 코를 한 번에 떠서 코 수를 줄이는 기법. 왼코(人, k2tog)·오른코(入, ssk) 방향 변형이 있다',
                    aliases=sorted(set(techs['K13'].get('aliases', []) + ['왼코 모아뜨기', '오른코 모아뜨기', '左上2目一度', '右上2目一度', 'k2tog', 'ssk'])))
techs['K01'].update(desc='바늘에 첫 코들을 만드는 뜨개의 시작. 기본(손가락 걸기)·롱테일 캐스트온 등 방법 변형이 있다',
                    aliases=sorted(set(techs['K01'].get('aliases', []) + ['롱테일 캐스트온', '指でかける作り目', 'long-tail cast on'])))
for old, into in MERGE.items():
    techs[old].update(hidden=True, merged_into=into)
    for t in techs.values():                                  # 선행 관계에서 합쳐진 ID를 대체
        if old in t.get('prereq', []): t['prereq'] = sorted({into if p == old else p for p in t['prereq']} - {t['id']})
# 대바늘 변형 기호(라이브러리 v1.1 키)
KVAR = {'K01': [('cast_on', '기본 코잡기', '作り目'), ('long_tail', '롱테일 캐스트온', '指でかける作り目')], 'K13': [('k2tog', '왼코 모아뜨기', '左上2目一度'), ('ssk', '오른코 모아뜨기', '右上2目一度')]}

# ---- 코바늘 새 기법 확정(후보→정식), 정렬
for t in techs.values():
    if t.get('status') == 'candidate': t['status'] = 'new_in_1.4'   # 단계·선행 2026-09-29 대표 확정
order = {'crochet': 0, 'knitting': 1}
alive = [t for t in techs.values() if not t.get('hidden')]
alive.sort(key=lambda t: (order[t['craft']], t['level'], t['id']))
for i, t in enumerate(alive): t['sort'] = i + 1
for t in techs.values():
    if t.get('hidden'): t['sort'] = 999

# ---- 검증: 선행 단계 ≤ 자기 단계, 순환 없음, 숨긴 ID 참조 없음
def chk():
    for t in alive:
        for p in t.get('prereq', []):
            assert p in techs and not techs[p].get('hidden'), (t['id'], p)
            assert techs[p]['level'] <= t['level'], ('level', t['id'], p)
    seen = {}
    def walk(i, path):
        assert i not in path, ('cycle', path); path = path + [i]
        for p in techs[i].get('prereq', []): walk(p, path)
    for t in alive: walk(t['id'], [])
chk()

# ---- 기호 변형: 기법 → [ {key, ko, ja} ]
lib = json.load(io.open(os.path.join(SYM, 'crochet_symbols_v1.2.json'), encoding='utf-8'))['symbols']
byno = {v['no']: (k, v) for k, v in lib.items()}
variants = {}
for s in names['symbols']:
    k, v = byno[s['no']]
    if s['tech']: variants.setdefault(s['tech'], []).append(dict(key=k, no=s['no'], ko=s['ko'], ja=s['ja'], en=s['en']))
for tid, arr in KVAR.items(): variants[tid] = [dict(key=k, ko=ko, ja=ja) for k, ko, ja in arr]
# 기법 칸에 그릴 대표 기호
PRIMARY = {'C01': 'chain', 'C02': 'sc', 'C03': 'slip', 'C05': 'magic_ring', 'C07': 'sc_inc', 'C08': 'sc_dec', 'C10': 'sc_blo_rows', 'C12': 'hdc', 'C13': 'dc', 'C14': 'picot', 'C15': 'shell5', 'C18': 'tr',
           'C19': 'dc3_cl', 'C20': 'dc5_pc', 'C21': 'cross_dc', 'C24': 'fpdc', 'C27': 'bullion7', 'C30': 'sc_loop', 'C31': 'dtr', 'C32': 'trtr', 'C33': 'y_st', 'C34': 'x_st_2', 'C35': 'triangle', 'C36': 'solomon', 'C37': 'rsc', 'C38': 'hdc3_puff',
           'K02': 'knit', 'K03': 'purl', 'K04': 'bind_off', 'K12': 'yo', 'K13': 'k2tog', 'K15': 'm1l', 'K17': 'k_tbl', 'K18': 'cable', 'K21': 'lace', 'K22': 'cdd', 'K24': 'stranded', 'K25': 'intarsia'}

out = dict(version='1.4', updated='2026-09-29', basis='v1.3 + 코바늘 명칭 통일(한국 관행)·새 기법 8(C31~C38) + 대바늘 B안(메리야스→1, 줄무늬 배색→3, 아란무늬·의류 구성→5, K06→K01·K14→K13 변형 합침)',
           techniques=sorted(techs.values(), key=lambda t: t['sort']), variants=variants, primary_symbol=PRIMARY)
json.dump(out, io.open(os.path.join(SYM, 'technique_dictionary_v1.4.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)

def dist(craft):
    d = {}
    for t in alive:
        if t['craft'] == craft: d[t['level']] = d.get(t['level'], 0) + 1
    return ' · '.join('Lv.%d ×%d' % (l, d.get(l, 0)) for l in range(1, 6))
md = ['# knitup 기법 사전 v1.4', '', '작성일: 2026-09-29 (v1.3: 2026-09-02) · 데이터: technique_dictionary_v1.4.json', '', '## 0. v1.4 변경 요약', '',
      '- **한국어 명칭 통일(대표 확정)**: 中長編み=긴뜨기 · 長編み=한길 긴뜨기 · 長々編み=두길 긴뜨기 · 三つ巻き=세길 · 四つ巻き=네길. 옛 이름은 aliases 로 보존(검색·기법 후보 AI 매칭)',
      '- **코바늘 새 기법 8**: C31 세길 긴뜨기 · C32 네길 긴뜨기 · C33 Y자·역Y자뜨기 · C34 X자뜨기 · C35 삼각뜨기 · C36 칠보뜨기 · C37 되돌아 짧은뜨기 · C38 변형 구슬뜨기(퍼프). 단계·선행 2026-09-29 대표 확정',
      '- **코바늘 기호 94종**(JIS 마스터표) → 기법별 변형 기호로 연결(`variants`). 기법표는 기법 단위만, 높이·코 수·코 아래에서 변형은 ID 없이 기호로',
      '- **대바늘 B안(대표 확정)**: 메리야스뜨기→Lv.1, 줄무늬 배색→Lv.3, 아란무늬·의류 구성→Lv.5. 롱테일 캐스트온(K06)→기본 코잡기(K01) 변형, 오른코 모아뜨기(K14)→**모아뜨기(K13)** 변형(人/入). K06·K14 는 hidden + merged_into (옛 데이터 호환)',
      '- 분포: 코바늘 ' + dist('crochet') + ' / 대바늘 ' + dist('knitting'), '',
      '## 1. 코바늘', '', '| ID | 기법명 | 日本語 | 약어 | Lv | 선행 | 변형 기호 | 설명 |', '|---|---|---|---|---|---|---|---|']
for t in alive:
    if t['craft'] == 'crochet': md.append('| %s | %s%s | %s | %s | %d | %s | %d | %s |' % (t['id'], t['name_ko'], ' (신설)' if t.get('status') == 'new_in_1.4' else '', t.get('name_ja', ''), t.get('abbr', ''), t['level'], ', '.join(t.get('prereq', [])), len(variants.get(t['id'], [])), t.get('desc', '')))
md += ['', '## 2. 대바늘', '', '| ID | 기법명 | 日本語 | 약어 | Lv | 선행 | 설명 |', '|---|---|---|---|---|---|---|']
for t in alive:
    if t['craft'] == 'knitting': md.append('| %s | %s | %s | %s | %d | %s | %s |' % (t['id'], t['name_ko'], t.get('name_ja', ''), t.get('abbr', ''), t['level'], ', '.join(t.get('prereq', [])), t.get('desc', '')))
md += ['', '## 3. 합쳐진 ID (숨김, 삭제하지 않음)', '', '| ID | 이름 | → | 이유 |', '|---|---|---|---|']
for old, into in MERGE.items(): md.append('| %s | %s | %s %s | 방법·방향 변형이라 기법 단위로 합침 |' % (old, techs[old]['name_ko'], into, techs[into]['name_ko']))
md += ['', '## 4. 기법별 변형 기호', '']
for tid in sorted(variants):
    md.append('- **%s %s**: ' % (tid, techs[tid]['name_ko']) + ' · '.join('%s(%s)' % (v['ko'], v['ja']) for v in variants[tid]))
txt = '\n'.join(md) + '\n'
io.open(os.path.join(SYM, '기법사전_v1.4.md'), 'w', encoding='utf-8').write(txt)
if os.path.isdir(KNITUP):
    io.open(os.path.join(KNITUP, 'knitup_기법사전_v1.4.md'), 'w', encoding='utf-8').write(txt)
    shutil.copy(os.path.join(SYM, 'technique_dictionary_v1.4.json'), os.path.join(KNITUP, 'knitup_technique_dictionary_v1.4.json'))
print('alive', len(alive), 'crochet', dist('crochet'), '| knitting', dist('knitting'), '| variants', sum(len(v) for v in variants.values()))
