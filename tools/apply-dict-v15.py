# 기법 사전 v1.5 반영 — 복합 기호의 '함께 쓰는 기법(also)'을 앱·knitup 에디터에 넣는다 (2026-10-09 대표 "에디터 수정까지 같이")
#   python tools/apply-dict-v15.py
#   입력: knitup/knitup_technique_dictionary_v1.5.json (다른 세션이 만든 원본) → resources/symbols/ 에 복사
#   출력 1) resources/symbols/editor_symbol_techs_v1.5.json — 에디터 기호 키 → 기법 ID 목록(대표 + also). 앱·에디터가 같은 표를 쓴다
#        2) docs/index.html — TECH_VARIANTS(also 포함)·TECH_DRAW·PKG_SYM_TECHS 줄 교체
#        3) knitup/docs/knitup-studio.html (+ 루트 knitup-studio.html 동일 사본) — SYMS ids·TECH·TECH_LV·techsFromText·DATA 를 v1.5 로. Studio 의 SYMS 는 사전 변형 키 94종을 그대로 쓰므로 사전 키는 자동 대응
#   규칙(v1.5): 도안 필요 기법 = 기호마다 {대표 기법} ∪ also 를 모아 중복 제거. 기법 ID·단계·선행은 v1.4 와 같다
#   다시 실행해도 같은 결과(앵커를 정규식으로 찾아 통째로 바꿈)
import io, json, os, re, shutil, sys
sys.stdout.reconfigure(encoding='utf-8')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KNITUP = next(d for d in (os.path.join(os.path.dirname(ROOT), n) for n in ('knitup-studio', 'knitup')) if os.path.isdir(d))   # 저장소 이름 knitup-studio(2026-10-10), 로컬 폴더는 둘 중 있는 쪽
SYM = os.path.join(ROOT, 'resources', 'symbols')
VER = '1.5'

# ---------- 0) 원본 복사 ----------
for a, b in [('knitup_technique_dictionary_v1.5.json', 'technique_dictionary_v1.5.json'), ('knitup_기법사전_v1.5.md', '기법사전_v1.5.md')]:
    shutil.copy(os.path.join(KNITUP, a), os.path.join(SYM, b))
d = json.load(io.open(os.path.join(SYM, 'technique_dictionary_v1.5.json'), encoding='utf-8'))
assert d['version'] == VER, d['version']
techs = {t['id']: t for t in d['techniques']}
variants = d['variants']
vindex = {v['key']: (tid, [a for a in v.get('also', []) if a != tid]) for tid, arr in variants.items() for v in arr}

# ---------- 1) 에디터 기호 키 → 기법 ID 목록 ----------
# 에디터(knitup-studio SYMS)의 키는 v1.3 때 만든 짧은 키. 사전의 변형 키와 같은 것은 그대로, 이름만 다른 것은 대응표, 사전에 없는 것은 손으로
EDITOR_TO_DICT = {'chain': 'chain', 'slip': 'slip', 'sc': 'sc', 'hdc': 'hdc', 'dc': 'dc', 'tr': 'tr', 'dtr': 'dtr',
                  'sc_inc': 'sc_inc', 'dc_inc': 'dc_inc', 'sc_dec': 'sc_dec', 'dc_dec': 'dc_dec', 'shell': 'shell5', 'bobble': 'dc3_cl', 'popcorn': 'dc5_pc',
                  'v_st': 'v_st', 'cross_dc': 'cross_dc', 'picot': 'picot', 'blo': 'sc_blo_rows', 'sc_inc3': 'sc_inc3', 'sc_dec3': 'sc_dec3', 'sc_loop': 'sc_loop',
                  'fpdc': 'fpdc', 'bpdc': 'bpdc', 'k2tog': 'k2tog', 'ssk': 'ssk', 'cast_on': 'cast_on'}
MANUAL = {'sc_loop2': ['C30', 'C07'], 'sc_loop3': ['C30', 'C07'],   # 링 짧은뜨기 N코 넣기 = 링뜨기 + 코 늘리기
          'knit': ['K02'], 'purl': ['K03'], 'yo': ['K12'], 'sl1': [], 'no_st': [], 'cdd': ['K22'], 'k3tog': ['K13'], 'p2tog': ['K13'],
          'm1r': ['K15'], 'm1l': ['K15'], 'kfb': ['K15'], 'k_tbl': ['K17'], 'p_tbl': ['K17'], 'cbl_r2': ['K18'], 'cbl_l2': ['K18'], 'cbl_r3': ['K18'], 'cbl_l3': ['K18'],
          'magic_ring': ['C05'], 'bind_off': ['K04'], 'join': ['K10'], 'cut': [], 'marker': [], 'turn': ['C04']}
SYM_TECHS = {}
for k, vk in EDITOR_TO_DICT.items():
    tid, also = vindex[vk]; SYM_TECHS[k] = [tid] + also
SYM_TECHS.update(MANUAL)
# knitup Studio(2026-10-10)는 사전 변형 키(코바늘 94종 등)를 그대로 기호 키로 쓴다 → 사전에 있는 키는 그대로 대표 기법 + also
for vk, (tid, also) in vindex.items():
    SYM_TECHS.setdefault(vk, [tid] + also)
for k, ids in SYM_TECHS.items():
    for i in ids: assert i in techs, (k, i)
json.dump({'version': VER, 'rule': '도안 필요 기법 = 기호마다 {대표 기법} ∪ also, 중복 제거', 'editor_key_to_dict_key': EDITOR_TO_DICT, 'techs': SYM_TECHS},
          io.open(os.path.join(SYM, 'editor_symbol_techs_v1.5.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)

def jsdump(o): return json.dumps(o, ensure_ascii=False, separators=(',', ':'))

# ---------- 2) 앱(docs/index.html) ----------
p = os.path.join(ROOT, 'docs', 'index.html'); s = io.open(p, encoding='utf-8').read()
def sub1(pattern, repl, text, flags=0):
    new, n = re.subn(pattern, lambda m: repl, text, count=1, flags=flags); assert n == 1, pattern[:60]; return new
tv = {tid: [dict(k=v['key'], ko=v['ko'], ja=v.get('ja', ''), **({'also': v['also']} if v.get('also') else {})) for v in arr] for tid, arr in variants.items()}
s = sub1(r'const TECH_VARIANTS = \{.*?\};\n', 'const TECH_VARIANTS = ' + jsdump(tv) + ';\n', s)
s = sub1(r'const TECH_DRAW = \{.*?\};\n', 'const TECH_DRAW = ' + jsdump(d['primary_symbol']) + ';\n', s)
line = "const PKG_SYM_TECHS = " + jsdump(SYM_TECHS) + ";   // knitup 에디터 기호 키 → 필요 기법(대표 + 함께 쓰는 기법), 사전 v1.5 · resources/symbols/editor_symbol_techs_v1.5.json\n"
if 'const PKG_SYM_TECHS = ' in s: s = sub1(r'const PKG_SYM_TECHS = \{.*?\};[^\n]*\n', line, s)
else: s = s.replace('const TECH_DRAW = ', line + 'const TECH_DRAW = ', 1)
s = s.replace('// 기법 기호 라이브러리 v1.2 (2026-09-28)', '// 기법 기호 라이브러리 v1.2 (2026-09-28, 사전 v1.5 연결 2026-10-09: TECH_VARIANTS[].also = 함께 쓰는 기법)', 1)
io.open(p, 'w', encoding='utf-8', newline='').write(s)

# ---------- 3) knitup 에디터·기법맵 (knitup-studio.html) ----------
p9 = os.path.join(KNITUP, 'docs', 'knitup-studio.html'); e = io.open(p9, encoding='utf-8').read()
# 3a) SYMS: ids 추가 + 이름을 v1.5 명칭으로(긴뜨기 계열). 에디터 HTML 은 템플릿 리터럴 안이라 역따옴표·${ 를 쓰지 않는다
RENAME = {'hdc': ('긴뜨기', '긴뜨기'), 'dc': ('한길긴', '한길 긴뜨기'), 'tr': ('두길긴', '두길 긴뜨기'), 'dtr': ('세길긴', '세길 긴뜨기'),
          'dc_inc': ('한길늘림', '한길 긴 2코 늘려뜨기'), 'dc_dec': ('한길모아', '한길 긴 2코 모아뜨기'), 'v_st': ('V스티치', '한길 긴 2코 늘려뜨기(사이에 사슬 1코)'),
          'shell': ('솔잎', '솔잎뜨기'), 'ssk': ('오른모아', '모아뜨기(오른코)'), 'k2tog': ('왼코모아', '모아뜨기(왼코)')}
def fix_sym(m):
    t = m.group(1); ids = SYM_TECHS.get(t)
    assert ids is not None, t
    body = m.group(0)
    body = re.sub(r"\s*ids:\[[^\]]*\],?", "", body)   # 이미 ids 가 있으면(다시 실행) 지우고 새로
    body = re.sub(r"id:(?:'[CK]\d\d'|null),?\s*", "id:%s, ids:%s, " % ("'%s'" % ids[0] if ids else 'null', jsdump(ids)), body, count=1)
    if t in RENAME:
        n, full = RENAME[t]
        body = re.sub(r"n:'[^']*'", "n:'%s'" % n, body, count=1); body = re.sub(r"full:'[^']*'", "full:'%s'" % full, body, count=1)
    return body
i0 = e.index('const SYMS = ['); i1 = e.index('];', i0)
block = e[i0:i1]; n_sym = len(re.findall(r"\{t:'([a-z0-9_]+)'", block))
block2 = re.sub(r"\{t:'([a-z0-9_]+)'[^}]*\}", fix_sym, block)
assert len(re.findall(r'ids:\[', block2)) == n_sym, (n_sym, len(re.findall(r'ids:\[', block2)))
e = e[:i0] + block2 + e[i1:]
anchor = 'const SYM_BY_T = Object.fromEntries(SYMS.map(s=>[s.t,s]));'
helper = anchor + '\n/* 사전 v1.5: 기호 하나가 여러 기법(대표 + 함께 쓰는 기법)에 걸칠 수 있다 — 집계는 symIds() 로 */\nconst symIds=function(t){ const s=SYM_BY_T[t]; return s? (s.ids||(s.id?[s.id]:[])) : []; };'
if 'const symIds=' not in e: e = e.replace(anchor, helper, 1)
# 3b) 집계 지점: SYM_BY_T 한 개 매핑 → symIds
for pat, rep in [
    (r"const s=SYM_BY_T\[n\.t\]; if\(s&&s\.id\) set\.add\(s\.id\);", "symIds(n.t).forEach(id=>set.add(id));"),
    (r"const s=SYM_BY_T\[t\]; if\(s&&s\.id\) set\.add\(s\.id\);", "symIds(t).forEach(id=>set.add(id));"),
    (r"const s=SYM_BY_T\[ap\.t\]; if\(s&&s\.id\) set\.add\(s\.id\);", "symIds(ap.t).forEach(id=>set.add(id));"),
    (r"const s2=SYM_BY_T\[ap\.syms\[k\]\]; if\(s2&&s2\.id\) set\.add\(s2\.id\);", "symIds(ap.syms[k]).forEach(id=>set.add(id));"),
    (r"const sy=SYM_BY_T\[t\]; if\(sy&&sy\.id\) ids\.add\(sy\.id\);", "symIds(t).forEach(id=>ids.add(id));"),
    (r"const sy=SYM_BY_T\[ap\.t\]; if\(sy&&sy\.id\) ids\.add\(sy\.id\);", "symIds(ap.t).forEach(id=>ids.add(id));"),
    (r"const sy=SYM_BY_T\[n\.t\]; if\(sy&&sy\.id\) ids\.add\(sy\.id\);", "symIds(n.t).forEach(id=>ids.add(id));")]:
    e, n = re.subn(pat, rep, e); assert n >= 1 or rep.split('(')[0] + '(' in e, pat
assert 'SYM_BY_T[' not in re.sub(r'const symIds=.*', '', e).split('function usedTechs')[1].split('function renderProps')[0], '집계에 옛 매핑이 남음'
# 3c) 에디터 TECH(이름)·TECH_LV(단계) — v1.5 전체(숨긴 K06·K14 도 옛 데이터 표시용으로 둠)
order = sorted(techs.values(), key=lambda t: t['sort'])
tech_js = 'const TECH = {   /* 사전 v1.5 (2026-10-09) — tools/apply-dict-v15.py 가 씀 */\n  ' + ', '.join("%s:'%s'" % (t['id'], t['name_ko'].replace("'", '')) for t in order) + '\n};'
i0 = e.index('const TECH = {'); i1 = e.index('};', i0) + 2; e = e[:i0] + tech_js + e[i1:]
lv_js = 'const TECH_LV={' + ','.join('%s:%d' % (t['id'], t['level']) for t in order) + '};   /* 사전 v1.5 단계 */'
i0 = e.index('const TECH_LV={'); i1 = e.index(chr(10), i0); e = e[:i0] + lv_js + e[i1:]   # 줄 전체 교체(끝 주석이 매번 덧붙지 않게)
# 3d) 지시문 글 → 기법: 복합 기호 이름(대표 + also)·SYMS 전체 이름·기법 이름·별칭. 긴 이름부터
seqs = {}
def put(text, ids):
    text = text.strip()
    if text and text not in seqs: seqs[text] = ids
sym_full = dict(re.findall(r"\{t:'([a-z0-9_]+)'[^}]*full:'([^']*)'", block2))
for k, full in sym_full.items():
    if SYM_TECHS.get(k): put(full, SYM_TECHS[k])
for tid, arr in variants.items():
    for v in arr: put(v['ko'], [tid] + [a for a in v.get('also', []) if a != tid])
for t in order:
    put(t['name_ko'], [t['id']])
    for a in t.get('aliases', []):
        if re.search(r'[가-힣]', a): put(a, [t['id']])
for text, ids in [('케이블', ['K18']), ('코잡기', ['K01']), ('사슬', ['C01']), ('늘려뜨기', ['C07']), ('늘리기', ['C07']), ('모아뜨기', ['C08']), ('줄이기', ['C08']), ('왕복뜨기', ['C04'])]: put(text, ids)
seq_list = sorted(seqs.items(), key=lambda kv: -len(kv[0]))
seq_js = '[' + ','.join("['%s',%s]" % (k.replace("'", ''), jsdump(v)) for k, v in seq_list) + ']'
new_fn = ("function techsFromText(t){\n  t=String(t||''); const out=[];\n"
          "  /* 사전 v1.5: 복합 기호 이름(예: 한길 긴 2코 늘려뜨기)은 대표 기법 + 함께 쓰는 기법을 모두 센다. 긴 이름부터 맞춘다 (tools/apply-dict-v15.py 생성) */\n"
          "  const seqs=" + seq_js + ";\n"
          "  for(const e of seqs){ if(t.includes(e[0])){ e[1].forEach(id=>out.push(id)); t=t.split(e[0]).join(' '); } }\n"
          "  return [...new Set(out)];\n}")
i0 = e.index('function techsFromText(t){'); i1 = e.index('\n}', i0) + 2; e = e[:i0] + new_fn + e[i1:]
assert '`' not in new_fn and '${' not in new_fn and '\\' not in new_fn
# 3e) 기법맵 DATA: 이름·단계·선행·설명을 v1.5 로(기호 열은 기존 유지, 새 기법은 사전 기호)
i0 = e.index('const DATA = ['); i1 = e.index('\n].map(', i0)
old_rows = {}
for m in re.finditer(r'^ \[("[CK]\d\d"),("[a-z]+"),"([^"]*)","([^"]*)","([^"]*)",(\d),(\[[^\]]*\]),"([^"]*)","([^"]*)"(?:,"[^"]*")?\]', e[i0:i1], re.M):
    old_rows[json.loads(m.group(1))] = dict(ab=m.group(4), sym=m.group(5), symStd=m.group(9))
rows = []
has_merged = ',merged])' in e[i1:i1 + 200]   # Studio(2026-10-10)의 DATA 는 10번째 열 merged(합쳐진 기법 ID) → hidden 판정. 있으면 그대로 써 준다
for t in order:
    o = old_rows.get(t['id'], {}); sym = o.get('sym') or (t.get('symbol') or '–'); ab = o.get('ab') or t.get('abbr', ''); std = o.get('symStd') or (t.get('symbol') if t.get('symbol') and len(t['symbol']) <= 2 else '–')
    rows.append(' [%s,%s,%s,%s,%s,%d,%s,%s,%s%s]' % (jsdump(t['id']), jsdump(t['craft']), jsdump(t['name_ko']), jsdump(ab), jsdump(sym), t['level'], jsdump(t.get('prereq', [])), jsdump(t.get('desc', '')), jsdump(std),
                                                      (',' + jsdump(t['merged_into'])) if has_merged and t.get('merged_into') else ''))
e = e[:i0] + 'const DATA = [   /* 기법 사전 v1.5 (2026-10-09, tools/apply-dict-v15.py) — ID 는 지우지 않음(K06·K14 는 v1.4 에서 K01·K13 에 합쳐짐) */\n' + ',\n'.join(rows) + e[i1:]
io.open(p9, 'w', encoding='utf-8', newline='').write(e)
shutil.copy(p9, os.path.join(KNITUP, 'knitup-studio.html'))   # 루트 사본(= docs 와 동일)
print('ok: SYM_TECHS', len(SYM_TECHS), '| also 기호', sum(1 for v in SYM_TECHS.values() if len(v) > 1), '| TECH_VARIANTS', sum(len(v) for v in tv.values()), '| DATA rows', len(rows), '| seqs', len(seq_list))
