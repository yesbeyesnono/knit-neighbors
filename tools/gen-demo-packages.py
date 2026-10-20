# 예시 도안 12개(뷰어 패키지가 없던 것)에 knitup 패키지(차트)를 만든다 — 설명회용. 출력: resources/plans/demo_packages.sql (pattern_contents upsert)
# 패키지 형식은 기존 코스터·수세미 패키지와 같다: {app, ver, title, level, meta, notes, techs, charts[{kind, part, yarn, graph, instr[], rounds[{cnt, syms, region}], startText}]}
import json, io, os
R = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def rnd(cnt, syms): return { "cnt": cnt, "syms": syms, "region": "var" }
def instr(rows, start=None):
    out = [{ "no": "시작", "cnt": "", "text": start }] if start else []
    for i, (cnt, text) in enumerate(rows, 1): out.append({ "no": f"{i}단", "cnt": f"총 {cnt}코", "text": text })
    return out
def chart(kind, part, color, start, rows, name="실"):
    return { "kind": kind, "part": part, "yarn": { "name": name, "color": color }, "graph": None, "instr": instr([(r["cnt"], t) for r, t in rows], start), "rounds": [r for r, _ in rows], "startText": start }
def pkg(title, level, meta, notes, techs, charts):
    return { "app": "knitup-pattern-package", "ver": 1, "title": title, "level": level, "meta": meta, "notes": notes, "techs": techs, "charts": charts, "exportedAt": "" }

def circle(n0, upto, sym="sc", inc="sc_inc"):   # 매직링 원형 늘리기
    rows = [(rnd(n0, { sym: n0 }), f"짧은뜨기 {n0}코")]
    c = n0
    while c < upto:
        rows.append((rnd(c + n0, { sym: c, inc: n0 } if c else { inc: n0 }), f"({'짧은뜨기 '+str(c//n0)+'코, ' if c//n0 else ''}늘려뜨기) ×{n0}"))
        c += n0
    return rows
def flat(c, n, sym="sc", text="짧은뜨기 {c}코"):
    return [(rnd(c, { sym: c }), text.format(c=c)) for _ in range(n)]

P = {}
# ---- 코바늘
r = circle(6, 24) + flat(24, 4) + [(rnd(18, { "sc": 12, "sc_dec": 6 }), "(짧은뜨기 2코, 줄이기) ×6 — 솜 넣기"), (rnd(12, { "sc_dec": 6 }), "줄이기 ×6"), (rnd(6, { "sc_dec": 6 }), "줄이기 ×6 — 실 자르고 조이기")]
ear = circle(6, 12) + flat(12, 1)
P["곰돌이 키링"] = pkg("곰돌이 키링", 2, { "실": "면사 4ply 15g", "바늘": "코바늘 4호(2.5mm)", "난이도": "초급 (2단계)" }, ["머리·귀·주둥이를 따로 떠서 돗바늘로 붙여요.", "눈은 6단과 7단 사이, 5코 간격으로 달아요."], ["C02", "C05", "C06", "C07", "C08", "C11"],
    [chart("round", "머리", "#c8a27a", "매직링 잡아 시작", r, "브라운"), chart("round", "귀 (2개)", "#c8a27a", "매직링 잡아 시작", ear, "브라운"), chart("round", "주둥이", "#f1e4cf", "매직링 잡아 시작", circle(6, 12), "아이보리")])
base = circle(6, 48); side = [(rnd(48, { "sc_blo_round": 48 }), "뒤쪽 반 코만 떠서 옆면 세우기 (짧은뜨기 48코)")] + flat(48, 7) + [(rnd(48, { "sc": 48 }), "색 바꿔 짧은뜨기 48코")] + flat(48, 3) + [(rnd(48, { "slip": 48 }), "빼뜨기 48코로 테두리 마무리")]
P["두 톤 수납 바구니"] = pkg("두 톤 수납 바구니", 2, { "실": "패브릭얀 2색 각 1볼", "바늘": "코바늘 10호(6.0mm)", "난이도": "초급 (2단계)" }, ["바닥은 늘려뜨기로 평평하게, 옆면 첫 단은 뒤쪽 반 코만 떠서 각을 세워요.", "9단부터 색을 바꾸면 두 톤이 돼요."], ["C02", "C05", "C06", "C07", "C09", "C10"],
    [chart("round", "바닥", "#8a9a7b", "매직링 잡아 시작", base, "올리브"), chart("round", "옆면", "#8a9a7b", "바닥 48코에서 이어서", side, "올리브 → 크림")])
nb = circle(6, 60); net = [(rnd(30, { "chain": 150, "sc": 30 }), "(사슬 5코, 2코 건너 짧은뜨기) ×30 — 네트 시작")] + [(rnd(30, { "chain": 150, "sc": 30 }), "사슬 5코 공간마다 짧은뜨기 — 네트") for _ in range(11)] + [(rnd(60, { "hdc": 60 }), "긴뜨기 60코로 입구 단"), (rnd(60, { "dc": 60 }), "한길 긴뜨기 60코")]
P["여름 네트백"] = pkg("여름 네트백", 3, { "실": "면사 DK 150g", "바늘": "코바늘 7호(4.0mm)", "난이도": "중급 (3단계)" }, ["바닥 원형 10단 뒤 네트는 사슬 5코 아치로 12단.", "손잡이는 사슬 40코 + 짧은뜨기 2단으로 따로 떠서 붙여요."], ["C02", "C06", "C07", "C12", "C13", "C16"],
    [chart("round", "바닥", "#e6d8bf", "매직링 잡아 시작", nb, "에크루"), chart("round", "몸통 (네트)", "#e6d8bf", "바닥 60코에서 이어서", net, "에크루")])
gs = [(rnd(12, { "chain": 2, "dc": 12 }), "매직링에 (한길 긴뜨기 3코, 사슬 2코) ×4"), (rnd(24, { "chain": 2, "dc": 24 }), "모서리마다 (3코, 사슬 2, 3코) · 변 사슬 1"), (rnd(36, { "chain": 2, "dc": 36 }), "모서리 (3코, 사슬 2, 3코) · 변마다 3코 1묶음"), (rnd(48, { "chain": 2, "dc": 48 }), "모서리 (3코, 사슬 2, 3코) · 변마다 3코 2묶음 — 색 바꿔도 좋아요")]
P["그래니 스퀘어 무릎담요"] = pkg("그래니 스퀘어 무릎담요", 3, { "실": "울 혼방 DK 4색 400g", "바늘": "코바늘 7호(4.0mm)", "난이도": "중급 (3단계)" }, ["같은 스퀘어를 20장(4×5) 떠서 빼뜨기로 잇고, 테두리 2단을 둘러요.", "단마다 색을 바꾸면 전통 그래니 느낌이에요."], ["C05", "C13", "C17", "C09"],
    [chart("round", "그래니 스퀘어 (20장)", "#b5605a", "매직링 잡아 시작", gs, "로즈·머스터드·네이비·크림")])
sh = []
for i in range(1, 25):
    n = 2 * i + 1; sh.append((rnd(n * 5 + 2, { "shell5": n, "dc": 2, "chain": n + 1 }), f"양 끝 한길 긴뜨기, 사이에 셸 {n}개 (사슬 1코 간격) — {'첫 셸' if i == 1 else '매 단 양쪽 1개씩 늘어요'}"))
P["셸무늬 삼각 숄"] = pkg("셸무늬 삼각 숄", 3, { "실": "메리노 4ply 300g", "바늘": "코바늘 6호(3.5mm)", "난이도": "중급 (3단계)" }, ["위 꼭짓점에서 시작해 매 단 양쪽에 셸이 하나씩 늘어나요.", "원하는 크기까지 24단 이상 떠도 돼요. 마지막 단은 피코로 마무리."], ["C01", "C13", "C14", "C15"],
    [chart("row", "숄 본체", "#d9c6d6", "사슬 6코, 첫 코에 빼뜨기로 고리", sh, "라벤더")])
pc = []
for i in range(1, 25):
    pc.append((rnd(40, { "popcorn": 10, "dc": 30 }) if i % 2 == 0 else rnd(40, { "dc": 40 }), "(한길 긴뜨기 3코, 팝콘) ×10" if i % 2 == 0 else "한길 긴뜨기 40코"))
P["팝콘 쿠션 커버"] = pkg("팝콘 쿠션 커버", 4, { "실": "코튼 아란 250g", "바늘": "코바늘 8호(5.0mm)", "난이도": "상급 (4단계)" }, ["앞판은 짝수 단마다 팝콘, 뒤판은 한길 긴뜨기만 24단.", "두 장을 겹쳐 짧은뜨기로 3면을 잇고 지퍼를 달아요."], ["C13", "C18", "C20", "C11"],
    [chart("row", "앞판 (팝콘)", "#e8d5c0", "사슬 42코로 시작", pc, "오트밀"), chart("row", "뒤판", "#e8d5c0", "사슬 42코로 시작", [(rnd(40, { "dc": 40 }), "한길 긴뜨기 40코") for _ in range(24)], "오트밀")])
# ---- 대바늘
P["첫 대바늘 가터 목도리"] = pkg("첫 대바늘 가터 목도리", 1, { "실": "울 벌키 300g", "바늘": "대바늘 10mm", "난이도": "입문 (1단계)" }, ["모든 단을 겉뜨기만 하면 가터 무늬가 돼요. 160cm까지 반복.", "마지막은 느슨하게 코막음하고 실 끝을 숨겨요."], ["K01", "K02", "K04", "K05"],
    [chart("row", "목도리", "#c9d6c2", "일반 코잡기 30코", [(rnd(30, { "knit": 30 }), "겉뜨기 30코 (160cm 될 때까지 반복)") for _ in range(40)], "세이지")])
bn = [(rnd(80, { "knit": 40, "purl": 40 }), "(겉 1, 안 1) ×40 — 고무단") for _ in range(8)] + [(rnd(80, { "knit": 80 }), "겉뜨기 80코") for _ in range(18)]
for c in (72, 64, 56, 48, 40, 32, 24, 16, 8): bn.append((rnd(c, { "knit": c, "k2tog": 8 }), f"(겉 {c // 8 - 1}, 왼코 모아뜨기) ×8 → {c}코"))
P["폼폼 고무단 비니"] = pkg("폼폼 고무단 비니", 2, { "실": "울 아란 100g", "바늘": "대바늘 5.0mm 줄바늘", "난이도": "초급 (2단계)" }, ["원통으로 떠서 꼭지를 조이고 폼폼을 달아요.", "고무단은 접어 올려 써도 좋아요."], ["K06", "K07", "K08", "K13", "K10"],
    [chart("round", "비니", "#8e9fb3", "원통 코잡기 80코", bn, "더스티 블루")])
hw = []
for i in range(30):
    hw.append((rnd(36, { "knit": 18, "purl": 18 }), "(겉 1, 안 1) ×18" if i % 2 == 0 else "(안 1, 겉 1) ×18 — 멍석무늬"))
P["멍석무늬 핸드워머"] = pkg("멍석무늬 핸드워머", 2, { "실": "울 DK 60g", "바늘": "대바늘 4.0mm", "난이도": "초급 (2단계)" }, ["평평하게 떠서 옆선을 꿰매고 엄지 구멍 5cm를 남겨요.", "같은 것을 2장 떠요."], ["K03", "K08", "K09", "K04"],
    [chart("row", "핸드워머 (2장)", "#d8b4a0", "일반 코잡기 36코", hw, "코랄")])
cb = [(rnd(88, { "knit": 44, "purl": 44 }), "(겉 2, 안 2) ×22 — 고무단") for _ in range(8)]
for i in range(1, 25):
    cb.append((rnd(88, { "cbl_r3": 8, "knit": 16, "purl": 48 }) if i % 6 == 0 else rnd(88, { "knit": 40, "purl": 48 }), "(안 6, 케이블 3/3 오른쪽 꼬기, 안 0) ×8 — 케이블 교차" if i % 6 == 0 else "(안 6, 겉 5) ×8"))
for c in (80, 72, 64, 56, 48, 40, 32, 24, 16, 8): cb.append((rnd(c, { "knit": c, "k2tog": 8 }), f"8코마다 왼코 모아뜨기 → {c}코"))
P["케이블 비니"] = pkg("케이블 비니", 3, { "실": "울 아란 120g", "바늘": "대바늘 4.5mm · 5.0mm 줄바늘", "난이도": "중급 (3단계)" }, ["케이블은 6단마다 꼬아요. 꽈배기바늘 없이 코를 바꿔 떠도 돼요.", "고무단은 4.5mm, 본체는 5.0mm."], ["K07", "K08", "K16", "K18", "K13"],
    [chart("round", "비니", "#6f6a8a", "원통 코잡기 88코 (4.5mm)", cb, "플럼")])
ls = []
for i in range(1, 41):
    n = 3 + 2 * i; ls.append((rnd(n, { "knit": n - 4, "yo": 2, "k2tog": 1, "ssk": 1 }) if i % 2 == 1 else rnd(n, { "purl": n }), f"겉 1, 바늘 비우기, 겉 {n - 4}, 바늘 비우기, 겉 1 — 양쪽 1코씩 늘어 {n}코" if i % 2 == 1 else f"안뜨기 {n}코 (되돌아오는 단)"))
P["첫 레이스 삼각 숄"] = pkg("첫 레이스 삼각 숄", 3, { "실": "메리노 핑거링 100g", "바늘": "대바늘 4.0mm 줄바늘", "난이도": "중급 (3단계)" }, ["홀수 단마다 양 끝에 바늘 비우기로 2코씩 늘어요. 짝수 단은 안뜨기.", "다 뜨면 물에 적셔 핀으로 당겨 말리면(블로킹) 무늬가 살아나요."], ["K12", "K13", "K14", "K21", "K22"],
    [chart("row", "숄 본체", "#e5d0dc", "일반 코잡기 3코", ls, "피치")])
yk = [(rnd(120, { "knit": 60, "purl": 60 }), "(겉 1, 안 1) ×60 — 목 고무단") for _ in range(6)]
for i in range(1, 25):
    inc = i in (4, 10, 16, 22); c = 120 + 40 * ((i - 1) // 6 + (1 if inc else 0)) if False else 120 + 40 * sum(1 for k in (4, 10, 16, 22) if k <= i)
    yk.append((rnd(c, { "kfb": 40, "knit": c - 80 }) if inc else rnd(c, { "knit": c }), f"(겉 {c // 40 - 2}, 늘리기) ×40 → {c}코 — 요크 늘리기" if inc else f"배색 차트 {i}단 — 바탕·무늬색 번갈아 겉뜨기 {c}코"))
P["페어아일 요크 스웨터"] = pkg("페어아일 요크 스웨터", 4, { "실": "울 DK 바탕 400g · 배색 4색 각 50g", "바늘": "대바늘 3.5mm · 4.0mm 줄바늘", "난이도": "상급 (4단계)" }, ["탑다운: 목에서 시작해 요크를 4번 늘리고 배색 무늬를 넣어요(여기는 요크 차트만).", "요크 뒤 몸통·소매는 겉뜨기 원통 — 가슴둘레 86~122cm 5사이즈는 코 수 표 참고.", "뒷목은 숏로우 6단으로 높여요."], ["K16", "K20", "K23", "K24", "K28"],
    [chart("round", "요크 (배색)", "#2f3e5c", "원통 코잡기 120코 (3.5mm)", yk, "네이비 바탕 · 머스터드·레드·크림 배색")])

out = []
for title, p in P.items():
    j = json.dumps(p, ensure_ascii=False).replace("'", "''")
    out.append(f"insert into public.pattern_contents(pattern_id, pkg, updated_at) select id, '{j}'::jsonb, now() from public.patterns where title = '{title}' on conflict (pattern_id) do update set pkg = excluded.pkg, updated_at = now();")
out.append("update public.patterns set has_viewer = exists(select 1 from public.pattern_contents c where c.pattern_id = patterns.id);")
sql = "\n".join(out)
io.open(os.path.join(R, "resources", "plans", "demo_packages.sql"), "w", encoding="utf-8", newline="").write(sql)
print(len(P), "packages,", len(sql), "chars")
for t, p in P.items(): print(t, sum(len(c["rounds"]) for c in p["charts"]), "rounds")
