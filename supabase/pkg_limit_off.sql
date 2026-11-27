-- 174. 도안 꾸러미 크기 한도 해제 (2026-11-27 대표 지시: "완전해제")
--   set_pattern_pkg(3MB) · studio_submit(3MB) · lab_pattern_put(4MB) 의 크기 검사 줄을 뺀다. 함수의 나머지는 그대로(지금 정의에서 그 줄만 바꿔 다시 만든다 — 권한은 유지됨)
--   서버가 받을 수 있는 요청 크기 자체(인프라 한도)는 그대로 남는다
do $do$
declare d text; a text;
begin
  d := pg_get_functiondef('public.set_pattern_pkg(uuid,jsonb)'::regprocedure);
  a := 'if pg_column_size(p_pkg) > 3000000 then raise exception ''패키지가 너무 커요 (3MB 이하)''; end if;';
  if position(a in d) = 0 then raise exception 'set_pattern_pkg: 한도 줄을 찾지 못함'; end if;
  execute replace(d, a, '-- 크기 한도 없음(schema 174)');

  d := pg_get_functiondef('public.studio_submit(text,text,jsonb,jsonb)'::regprocedure);
  a := 'if length(p_pkg::text) > 3*1024*1024 then return false; end if;';
  if position(a in d) = 0 then raise exception 'studio_submit: 한도 줄을 찾지 못함'; end if;
  execute replace(d, a, '-- 크기 한도 없음(schema 174)');

  d := pg_get_functiondef('public.lab_pattern_put(text,text,text,jsonb,jsonb)'::regprocedure);
  a := 'if n > 4 * 1024 * 1024 then raise exception ''too big'' using errcode = ''P0001''; end if;';
  if position(a in d) = 0 then raise exception 'lab_pattern_put: 한도 줄을 찾지 못함'; end if;
  execute replace(d, a, '-- 크기 한도 없음(schema 174)');
end $do$;
