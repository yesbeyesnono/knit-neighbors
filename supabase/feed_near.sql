-- 164. 커뮤니티 '동네' 탭을 핀 위치 기준으로 (2026-11-21 대표 확정 시안 dong_tab_near_v1 A안 · v2 — 마이그레이션 feed_near)
--   지금까지는 동네 이름(dong_code 글자)이 똑같은 글만 보였다 → 한 동에 회원이 평균 1.2명이고 이름 형식도 제각각이라 대부분 비어 있었음.
--   내 핀(profiles.location)에서 3km 안의 글을 찾고, 글이 5개가 안 되면 5km → 10km → 30km 로 넓힌다. 기준은 글쓴이의 핀.
--   돌려주는 것은 범위(km)와 글 id 뿐(위치·거리는 내보내지 않는다). 글 자체는 앱이 지금처럼 posts 를 읽어 온다(RLS 그대로).
--   옛 앱은 이 함수를 부르지 않으므로 지금처럼 동작.
create or replace function public.feed_near_ids(p_before timestamptz default null, p_limit int default 30)
 returns jsonb language plpgsql stable security definer set search_path to 'public', 'extensions' as $function$
declare v_loc geography; v_dong text; v_test boolean; r int; n int; v_ids jsonb;
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  select location, dong_name, coalesce(is_test, false) into v_loc, v_dong, v_test from public.profiles where id = auth.uid();
  if v_loc is null then return jsonb_build_object('noloc', true, 'ids', '[]'::jsonb); end if;
  foreach r in array array[3, 5, 10, 30] loop
    select count(*) into n from (
      select 1 from public.posts po join public.profiles a on a.id = po.author_id
       where po.parent_id is null and not coalesce(po.hidden, false) and not coalesce(po.hidden_by_mod, false) and po.archived_at is null
         and a.suspended_at is null and (not coalesce(a.is_test, false) or v_test)
         and a.location is not null and st_dwithin(a.location, v_loc, r * 1000)
       limit 5) x;
    exit when n >= 5;
  end loop;
  select coalesce(jsonb_agg(y.id order by y.created_at desc), '[]'::jsonb) into v_ids from (
    select po.id, po.created_at from public.posts po join public.profiles a on a.id = po.author_id
     where po.parent_id is null and not coalesce(po.hidden, false) and not coalesce(po.hidden_by_mod, false) and po.archived_at is null
       and a.suspended_at is null and (not coalesce(a.is_test, false) or v_test)
       and a.location is not null and st_dwithin(a.location, v_loc, r * 1000)
       and (p_before is null or po.created_at < p_before)
     order by po.created_at desc limit least(greatest(coalesce(p_limit, 30), 1), 50)) y;
  return jsonb_build_object('km', r, 'dong', v_dong, 'ids', v_ids);
end $function$;
revoke all on function public.feed_near_ids(timestamptz, int) from public, anon;
grant execute on function public.feed_near_ids(timestamptz, int) to authenticated;
