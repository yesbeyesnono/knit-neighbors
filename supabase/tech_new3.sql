-- 155. 새 기법 3개 — 걸러뜨기(K31) · 아이코드(K32) · 방안뜨기(C39) (2026-11-20 대표 "새 기법 3개를 올려줘", 시안 tech_new3_v1)
--   추가 기법(extra = true): 체크하면 한 것으로 세지만 단계 기준(절반)에는 넣지 않는다(schema 154) → 누구의 단계도 내려가지 않는다
--   sort 는 서버가 자동으로 만든다(단계·번호)
--   1.0.10 이 양쪽 스토어에 나온 뒤(2026-11-20) 등록
insert into public.techniques (id, craft, name_ko, level, category, prereq, descr, symbol, name_ja, name_en, abbr, extra) values
('K31','knitting','걸러뜨기',2,'질감',array['K02']::text[],'코를 뜨지 않고 오른쪽 바늘로 그대로 옮기는 기법. 무늬·배색·가장자리 정리에 쓴다','–','すべり目',null,'sl',true),
('K32','knitting','아이코드',3,'구성',array['K01','K02']::text[],'몇 코를 돌려 뜨지 않고 밀어 가며 떠서 만드는 가는 끈. 끈·테두리·손잡이에 쓴다','–','アイコード',null,'i-cord',true),
('C39','crochet','방안뜨기',3,'질감',array['C01','C13']::text[],'사슬과 한길 긴뜨기로 빈 칸과 채운 칸을 만들어 모눈 무늬를 그리는 기법','조합','方眼編み','filet crochet','filet',true)
on conflict (id) do nothing;
