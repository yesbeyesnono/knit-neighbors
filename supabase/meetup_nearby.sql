-- 153. 모임이 열리면 가까운 회원에게 알리기 (2026-11-19 대표 확정 문구 A안 · 5km)
-- 지기 점검을 통과한 공개 모임을, 모임 장소에서 5km 안에 사는 회원(최근 30일 접속)에게 한 번 알린다.
-- 밤(22시~8시)에는 보내지 않고 아침에 보낸다. 한 사람은 하루에 모임 알림 2건까지. 알린 뒤 모임을 연 회원에게도 몇 명에게 알렸는지 알려 준다.
alter table public.meetups add column if not exists nearby_notified_at timestamptz;

create or replace function public.meetup_nearby_notify()
returns integer language plpgsql security definer set search_path to 'public', 'extensions' as $fn$
declare
  m record; n int; total int := 0; t timestamp; txt text; whn text; h int; mi int;
  kst timestamp := now() at time zone 'Asia/Seoul';
  sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e';
begin
  if extract(hour from kst) < 8 or extract(hour from kst) >= 22 then return 0; end if;
  for m in
    select mt.id, mt.title, mt.place_name, mt.location, mt.starts_at, mt.created_by, hp.is_test
      from public.meetups mt join public.profiles hp on hp.id = mt.created_by
     where mt.nearby_notified_at is null and mt.is_public and not coalesce(mt.hidden, false) and mt.mod_scanned_at is not null
       and mt.location is not null and mt.starts_at > now() and mt.created_at > now() - interval '3 days'
       and hp.deleted_at is null and hp.suspended_at is null
     order by mt.created_at limit 10
  loop
    t := m.starts_at at time zone 'Asia/Seoul'; h := extract(hour from t)::int; mi := extract(minute from t)::int;
    whn := extract(month from t)::int || '월 ' || extract(day from t)::int || '일(' || (array['일','월','화','수','목','금','토'])[extract(dow from t)::int + 1] || ') '
        || case when h = 12 then '낮 12시' when h = 0 then '밤 12시' when h < 12 then '오전 ' || h || '시' else '오후 ' || (h - 12) || '시' end
        || case when mi > 0 then ' ' || mi || '분' else '' end;
    txt := left('가까운 곳에 뜨개 모임이 열렸어요 🧶 「' || coalesce(nullif(btrim(m.title), ''), '뜨개 모임') || '」 ' || whn
        || coalesce(' · ' || nullif(btrim(m.place_name), ''), ''), 200);
    with r as (
      select p.id from public.profiles p
       where p.id <> m.created_by and p.is_test = m.is_test and p.onboarded_at is not null and p.deleted_at is null and p.suspended_at is null
         and p.location is not null and p.last_seen_at > now() - interval '30 days' and ST_DWithin(p.location, m.location, 5000)
         and not exists (select 1 from public.friendships f where f.status = 'blocked'
                          and ((f.requester_id = p.id and f.addressee_id = m.created_by) or (f.requester_id = m.created_by and f.addressee_id = p.id)))
         and (select count(*) from public.notifications x where x.recipient_id = p.id and x.meetup_id is not null and x.kind = 'remind'
                and x.snippet like '가까운 곳에 뜨개 모임이 열렸어요%' and x.created_at > now() - interval '20 hours') < 2
    ), ins as (
      insert into public.notifications(recipient_id, actor_id, kind, meetup_id, snippet, link)
      select r.id, m.created_by, 'remind', m.id, txt, jsonb_build_object('type', 'meetup', 'id', m.id) from r returning 1
    ) select count(*) into n from ins;
    update public.meetups set nearby_notified_at = now() where id = m.id;
    insert into public.notifications(recipient_id, actor_id, kind, meetup_id, snippet, link)
      values (m.created_by, sup, 'notice', m.id,
        left(case when n > 0
          then '「' || coalesce(nullif(btrim(m.title), ''), '모임') || '」 모임을 가까운 이웃 ' || n || '명에게 알렸어요. 모임 장소에서 5km 안에 사는 분들께 "가까운 곳에 뜨개 모임이 열렸어요" 알림을 보냈어요. 모임 글에 사진을 한 장 넣으면 더 눈에 띄어요.'
          else '「' || coalesce(nullif(btrim(m.title), ''), '모임') || '」 모임이 지도와 모임 탭에 올라갔어요. 아직 5km 안에 사는 이웃이 없어 알림은 보내지 못했어요. 모임 글에 사진을 한 장 넣으면 더 눈에 띄어요.' end, 300),
        jsonb_build_object('type', 'meetup', 'id', m.id));
    total := total + n;
  end loop;
  return total;
end $fn$;
revoke all on function public.meetup_nearby_notify() from public, anon, authenticated;
grant execute on function public.meetup_nearby_notify() to service_role;
select cron.schedule('meetup-nearby', '*/10 * * * *', $$select public.meetup_nearby_notify()$$);
