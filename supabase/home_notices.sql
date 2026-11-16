-- schema 134 (2026-11-16 대표 확정 시안 notice_carousel_v2): 앱 시작 공지 — 좌우로 넘겨 보는 팝업(공지 여러 개)
-- app_config.home_notices = [{id, active, kicker, title, body, img, btn, link}] (새 앱 1.0.9 부터 읽음).
-- 옛 앱은 지금처럼 app_config.home_notice(하나)만 읽으므로 그 값은 그대로 둔다.
-- 규칙(앱): 처음 보이는 카드는 무작위 · ✕ 로 닫으면 그날은 쉼 · '이 공지 다시 보지 않기'는 그 공지만(기기에 id 로 기억)
insert into public.app_config(key, value) values ('home_notices', jsonb_build_array(
  jsonb_build_object('id','20261114-ddeuchin','active',true,'kicker','기간 한정 이벤트 · ~11/30','title','뜨친 생겼다 축하 이벤트',
    'body', E'뜨친과 만나 함께 뜨면,\n두 분 모두에게 커피 쿠폰을 드려요.', 'img','events/ddeuchin-highfive.webp','btn','참여 방법 보기','link', jsonb_build_object('type','view','view','ddeuchin')),
  jsonb_build_object('id','20261116-cert','active',true,'kicker','꼭 읽어 주세요','title','완성작품 인증이 달라졌어요',
    'body', E'단계 · 모임 · 작가 자격의 바탕이에요.\n하루 한 작품, 확인한 뒤 올려 드려요.', 'img','events/cert-hero.jpg','btn','자세히 보기','link', jsonb_build_object('type','view','view','certguide'))))
on conflict (key) do nothing;

-- 콘솔: 공지 하나를 켜고 끈다(문구·그림을 바꾸는 일은 아직 SQL 로)
create or replace function public.admin_home_notices_toggle(p_id text, p_active boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v jsonb; n jsonb;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  select value into v from public.app_config where key = 'home_notices' for update;
  if v is null or jsonb_typeof(v) <> 'array' or not exists (select 1 from jsonb_array_elements(v) e where e->>'id' = p_id) then raise exception '공지를 찾을 수 없어요'; end if;
  select jsonb_agg(case when e->>'id' = p_id then e || jsonb_build_object('active', coalesce(p_active, false)) else e end order by ord) into n
    from jsonb_array_elements(v) with ordinality as t(e, ord);
  update public.app_config set value = n, updated_at = now() where key = 'home_notices';
  perform public.admin_log('home_notices_toggle', 'app_config', 'home_notices', jsonb_build_object('id', p_id, 'active', coalesce(p_active, false)));
  return n;
end $$;
revoke all on function public.admin_home_notices_toggle(text, boolean) from public, anon;
grant execute on function public.admin_home_notices_toggle(text, boolean) to authenticated;
