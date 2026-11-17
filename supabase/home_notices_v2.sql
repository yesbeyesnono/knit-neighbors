-- schema 139 (2026-11-17 대표 확정): 시작 공지 v2 — 1.0.10 부터 읽는 목록(바깥 그림 허용). 1.0.9 는 home_notices 를 계속 읽는다.
insert into public.app_config(key, value)
select 'home_notices_v2', (select value from public.app_config where key = 'home_notices') || jsonb_build_array(
  jsonb_build_object('id','20261117-mimisalon','active',true,'kicker','우리 동네 공방 소식 · 미미살롱 연희점','title','겨울에 뭐뜨지',
    'body', E'미미살롱 시그니처 실로 뜨는 겨울 머플러.\n이번 겨울, 같이 만들어 보아요.', 'img','https://app.knitup.co.kr/images/notice-mimisalon.jpg','btn','소식 보러 가기',
    'link', jsonb_build_object('type','shop','id','a3006154-45db-4d8a-b0fe-73d20d0077c4','post','9c810d6f-c84a-43ce-88a1-8feec8fad92f')))
on conflict (key) do nothing;

-- 켜고 끄기는 두 목록 모두에(같은 id 가 있는 쪽만 바뀜)
create or replace function public.admin_home_notices_toggle(p_id text, p_active boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v jsonb; n jsonb; k text; hit boolean := false; last jsonb;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  foreach k in array array['home_notices','home_notices_v2'] loop
    select value into v from public.app_config where key = k for update;
    if v is null or jsonb_typeof(v) <> 'array' or not exists (select 1 from jsonb_array_elements(v) e where e->>'id' = p_id) then continue; end if;
    select jsonb_agg(case when e->>'id' = p_id then e || jsonb_build_object('active', coalesce(p_active, false)) else e end order by ord) into n
      from jsonb_array_elements(v) with ordinality as t(e, ord);
    update public.app_config set value = n, updated_at = now() where key = k;
    hit := true; last := n;
  end loop;
  if not hit then raise exception '공지를 찾을 수 없어요'; end if;
  perform public.admin_log('home_notices_toggle', 'app_config', 'home_notices', jsonb_build_object('id', p_id, 'active', coalesce(p_active, false)));
  return last;
end $$;
revoke all on function public.admin_home_notices_toggle(text, boolean) from public, anon;
grant execute on function public.admin_home_notices_toggle(text, boolean) to authenticated;
