-- 140. 콘솔 › 회원 실 현황 (2026-11-17 대표 확정 시안 console_stash_v3) — 실함(갖고 있는 실)과 완성작품 인증(쓴 실)을 한 번에 집계
--   admin_yarn_overview(p_days): 관리자만. p_days = 기간(일, null 이면 전체). 테스트 계정 제외, 쓴 실은 승인된 인증만(인증이 지워져 남은 익명 기록은 포함)
--   돌려주는 것: tiles(요약) · months(최근 12달, 계절별 담은 볼·쓴 양 g·작품 수 — 기간과 무관) · items(작품 종류별 쓴 양) · yarns(실별 한 줄, 최대 600)
--   쓴 양 g = 볼 수 × 1볼 무게(본인 입력 → 사전 규격), g 단위로 적은 것은 그대로. 1볼 무게를 모르면 g 에 넣지 않고 g_unknown 으로 셈
create or replace function public.admin_yarn_overview(p_days int default 365) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare since timestamptz := case when p_days is null or p_days <= 0 then '-infinity'::timestamptz else now() - make_interval(days => p_days) end;
  m0 timestamp := date_trunc('month', now() at time zone 'Asia/Seoul') - interval '11 months';
  m1 timestamp := date_trunc('month', now() at time zone 'Asia/Seoul');
  out jsonb;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  with st as (
    select coalesce(c.id::text, 'raw:'||lower(btrim(coalesce(s.raw_name,'')))) k, c.id catalog_id, coalesce(c.brand, s.brand) brand, coalesce(c.product, s.raw_name) product,
           case when c.season in ('여름','겨울','사계절') then c.season else '미정' end season, c.weight_class w, c.fiber_main f,
           s.owner_id, coalesce(s.bought_balls,0) bought, coalesce(s.left_balls,0) left_b, s.color_hex[1] hex, s.created_at,
           date_trunc('month', s.created_at at time zone 'Asia/Seoul') mon
    from public.yarn_stash s join public.profiles p on p.id = s.owner_id and not coalesce(p.is_test,false)
      left join public.yarn_catalog c0 on c0.id = s.catalog_id left join public.yarn_catalog c on c.id = coalesce(c0.merged_into, c0.id)
  ), us as (
    select coalesce(c.id::text, 'raw:'||coalesce(e.norm_name, lower(btrim(coalesce(e.raw_name,''))))) k, c.id catalog_id, c.brand, coalesce(c.product, e.raw_name) product,
           case when c.season in ('여름','겨울','사계절') then c.season else '미정' end season, c.weight_class w, c.fiber_main f,
           coalesce(e.work_id::text, 'gone:'||e.id::text) wk, e.item_type, e.color_hex[1] hex, e.created_at,
           date_trunc('month', e.created_at at time zone 'Asia/Seoul') mon,
           case when e.amount is null then null when e.unit = 'g' then e.amount else e.amount * coalesce(e.ball_g, c.ball_g) end g,
           (e.amount is not null and coalesce(e.unit,'') <> 'g' and coalesce(e.ball_g, c.ball_g) is null) g_unknown
    from public.yarn_entries e left join public.works w on w.id = e.work_id left join public.profiles p on p.id = w.profile_id
      left join public.yarn_catalog c0 on c0.id = e.catalog_id left join public.yarn_catalog c on c.id = coalesce(c0.merged_into, c0.id)
    where coalesce(e.source,'work') = 'work' and (e.work_id is null or (w.review_status = 'approved' and not coalesce(p.is_test,false)))
  ), mons as (select g.m from generate_series(m0, m1, interval '1 month') g(m)),
  yr as (
    select a.k, max(a.catalog_id::text) id, max(a.brand) brand, max(a.product) name, max(a.season) season, max(a.w) w, max(a.f) f,
           count(distinct a.owner_id) members, sum(a.bought) bought, sum(a.left_b) left_b, count(distinct a.wk) works, round(sum(a.g)) g,
           mode() within group (order by a.item_type) item,
           (array_agg(distinct a.hex) filter (where a.hex is not null))[1:6] colors, count(distinct a.hex) ncolors
    from (select k, catalog_id, brand, product, season, w, f, owner_id, bought, left_b, null::text wk, null::numeric g, null::text item_type, hex from st where created_at >= since
          union all select k, catalog_id, brand, product, season, w, f, null, null, null, wk, g, item_type, hex from us where created_at >= since) a
    group by a.k order by round(sum(a.g)) desc nulls last, sum(a.bought) desc nulls last limit 600
  )
  select jsonb_build_object(
    'days', p_days,
    'tiles', jsonb_build_object(
      'stash_rows', (select count(*) from st where created_at >= since), 'stash_members', (select count(distinct owner_id) from st where created_at >= since),
      'bought', (select coalesce(sum(bought),0) from st where created_at >= since), 'left', (select coalesce(sum(left_b),0) from st where created_at >= since),
      'use_rows', (select count(*) from us where created_at >= since), 'use_works', (select count(distinct wk) from us where created_at >= since),
      'g', (select coalesce(round(sum(g)),0) from us where created_at >= since), 'g_unknown', (select count(*) from us where created_at >= since and g_unknown)),
    'months', (select jsonb_agg(jsonb_build_object('m', to_char(mons.m,'YYYY-MM'),
        'stash', (select coalesce(jsonb_object_agg(x.season, x.v), '{}'::jsonb) from (select season, sum(bought) v from st where st.mon = mons.m group by 1) x),
        'g', (select coalesce(jsonb_object_agg(x.season, x.v), '{}'::jsonb) from (select season, round(sum(g)) v from us where us.mon = mons.m and g is not null group by 1) x),
        'works', (select coalesce(jsonb_object_agg(x.season, x.v), '{}'::jsonb) from (select season, count(distinct wk) v from us where us.mon = mons.m group by 1) x)) order by mons.m) from mons),
    'items', (select coalesce(jsonb_agg(to_jsonb(x) order by x.g desc nulls last, x.works desc), '[]'::jsonb) from (select coalesce(item_type,'미정') item, round(sum(g)) g, count(distinct wk) works from us where created_at >= since group by 1) x),
    'yarns', (select coalesce(jsonb_agg(jsonb_strip_nulls(to_jsonb(yr) || jsonb_build_object('spark',
        (select jsonb_agg((select count(distinct u.wk) from us u where u.k = yr.k and u.mon = mons.m) order by mons.m) from mons)))
        order by yr.g desc nulls last, yr.bought desc nulls last), '[]'::jsonb) from yr)
  ) into out;
  return out;
end $$;
revoke all on function public.admin_yarn_overview(int) from public, anon;
grant execute on function public.admin_yarn_overview(int) to authenticated, service_role;
