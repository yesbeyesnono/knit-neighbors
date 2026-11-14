-- schema 119 (2026-11-15): 실 = 브랜드 / 실 이름 나누기
-- 이름(name·raw_name)은 지금처럼 '브랜드 + 제품명' 한 줄로 남기고(옛 앱·매칭 호환), 브랜드를 따로 한 칸 더 저장한다.
-- 앱은 yarn_brands() 로 확정 실의 브랜드 목록(+별칭)을 한 번 받아, 이름 앞부분을 브랜드와 맞춰 화면에서 나눈다(옛 기록도 그대로 나뉨).

-- 1) 실함에 브랜드 칸
alter table public.yarn_stash add column if not exists brand text;
grant insert (brand), update (brand) on public.yarn_stash to authenticated;

-- 2) 브랜드 목록: 확정 실만, 실 수 + 별칭. 로그인 회원만(실 사전 본체는 계속 직접 조회 불가)
create or replace function public.yarn_brands()
returns table(brand text, n integer, aliases text[])
language sql stable security definer set search_path = 'public'
as $$
  select c.brand, count(*)::int,
         coalesce((select array_agg(a.alias order by a.alias) from public.yarn_brand_aliases a where a.brand = c.brand), '{}'::text[])
  from public.yarn_catalog c
  where c.status = 'verified' and c.merged_into is null and coalesce(btrim(c.brand), '') <> ''
  group by c.brand
  order by 2 desc, 1;
$$;
revoke all on function public.yarn_brands() from public, anon;
grant execute on function public.yarn_brands() to authenticated;

-- 3) 완성작품 인증의 실 기록에 brand 를 남긴다(저장 목록에 한 줄 추가) · 볼밴드 읽기 결과의 brand 를 실함에 남긴다
do $do$
declare d text; f regprocedure;
  a constant text := $s$'color_mode', case when q.y->>'color_mode' in ('solid','gradient','mix','melange') then q.y->>'color_mode' end,$s$;
  b constant text := $s$color_mode = case when 'color' = any(edited) or v_hex is null then color_mode else 'solid' end,$s$;
begin
  foreach f in array array['public.create_work(text,text[],text[],text,text,text[],jsonb)'::regprocedure, 'public.edit_work_yarn(uuid,text,jsonb)'::regprocedure] loop
    d := pg_get_functiondef(f);
    if position($s$'brand', nullif(left(btrim(q.y->>'brand')$s$ in d) > 0 then continue; end if;
    if position(a in d) = 0 then raise exception 'anchor not found in %', f; end if;
    execute replace(d, a, a || E'\n      ' || $s$'brand', nullif(left(btrim(q.y->>'brand'), 40), ''),$s$);
  end loop;
  d := pg_get_functiondef('public.stash_apply_read(uuid,jsonb,boolean)'::regprocedure);
  if position($s$brand = case when 'brand' = any(edited)$s$ in d) = 0 then
    if position(b in d) = 0 then raise exception 'anchor not found in stash_apply_read'; end if;
    execute replace(d, b, b || E'\n    ' || $s$brand = case when 'brand' = any(edited) then brand else coalesce(nullif(left(btrim(p_json->>'brand'), 40), ''), brand) end,$s$);
  end if;
end $do$;

-- 4) 이미 담긴 실함: 사전에 연결된 실은 사전의 브랜드, 아니면 볼밴드에서 읽은 브랜드
alter table public.yarn_stash disable trigger yarn_stash_fill;
update public.yarn_stash s set brand = c.brand from public.yarn_catalog c
 where s.catalog_id = c.id and s.brand is null and c.status = 'verified' and coalesce(btrim(c.brand), '') <> '';
update public.yarn_stash set brand = left(btrim(read_json->>'brand'), 40)
 where brand is null and coalesce(btrim(read_json->>'brand'), '') <> '';
alter table public.yarn_stash enable trigger yarn_stash_fill;
