-- ---------------------------------------------------------------
-- knitup Studio 전용 실 사전 검색 — 2026-10-11 대표 승인, 마이그레이션 `studio_yarn_search` 로 **적용됨**(뜨개동네 프로젝트 thfcrodfaitzrzlrxyir)
--   배경: Studio 는 뜨개동네와 다른 Supabase 프로젝트라 회원 세션이 없음(anon). yarn_gauge_search 는 본문에서 auth.uid() 를 검사해 anon 은 빈 결과.
--   방침("회사 자산 직접 조회 차단 — 앱은 함수로만")을 지키면서 Studio 계획서의 실 칩·"실 ○○로" 가 쓰도록, 같은 매칭으로 **이름·게이지만 8건** 돌려주는 함수를 anon 에 연다.
--   돌려주는 값: [{name, sts, rows, needle, stitch}] — id·가격·판매처·색·규격·브랜드 별칭 없음. 2글자 미만 검색어는 빈 배열.
--   Studio: PLAN.yarnSearch 가 studio_yarn_search → (실패 시) yarn_gauge_search 순으로 호출. 사전 편물(한길긴뜨기 단수)은 Studio 쪽에서 짧은뜨기 기준으로 환산.
--   권한 점검: permissions_test.sql 블록 ④ anon 에 'studio_yarn_search(anon)' 기대값 8(낙양) 추가.
-- ---------------------------------------------------------------
create or replace function public.studio_yarn_search(p_q text, p_craft text default 'crochet')
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $function$
  select case when length(btrim(coalesce(p_q,''))) < 2 then '[]'::jsonb else coalesce(jsonb_agg(x), '[]'::jsonb) end from (
    select jsonb_build_object(
      'name',   btrim(coalesce(c.brand||' ','')||c.product),
      'sts',    g->'sts',
      'rows',   g->'rows',
      'needle', g->>'needle',
      'stitch', g->>'stitch') x
    from public.yarn_catalog c
    cross join lateral (select case when p_craft = 'knitting' then c.gauge_knit else c.gauge_crochet end g) gg
    where c.merged_into is null and public.yarn_norm(p_q) is not null and g is not null
      and exists (select 1 from unnest(c.norm_keys || public.yarn_norm(coalesce(c.brand,'')||c.product) || public.yarn_norm(coalesce(c.brand,'')||coalesce(c.product_en,''))
          || coalesce((select array_agg(public.yarn_norm(a.alias||c.product)) from public.yarn_brand_aliases a where a.brand = c.brand), '{}')) kk where kk like '%'||public.yarn_norm(p_q)||'%')
    order by (c.status='verified') desc, c.uses desc, c.id limit 8) t;
$function$;
revoke all on function public.studio_yarn_search(text, text) from public;
grant execute on function public.studio_yarn_search(text, text) to anon, authenticated, service_role;
