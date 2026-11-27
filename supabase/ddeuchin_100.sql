-- 172. 뜨친 100쌍 기념 (2026-11-27 대표 확정 시안 ddeuchin_100_v3)
--   friend_request_remind_100(): 3일 넘게 답하지 않은 받은 신청이 있는 회원에게 한 번 더(회원마다 알림 한 개). 한 번만 돌리는 함수
--   friend_rec_weekly(): app_config.friend_rec_prefix {text, until} 가 있고 기한 안이면 토요일 추천 알림 앞에 한마디(기한이 지나면 원래 문구)

create or replace function public.friend_request_remind_100()
returns integer language plpgsql security definer set search_path = public, extensions as $$
declare r record; n int := 0; nick text;
begin
  for r in
    select f.addressee_id, count(*) cnt, (array_agg(f.requester_id order by f.created_at desc))[1] last_req
      from public.friendships f
      join public.profiles p on p.id = f.requester_id join public.profiles a on a.id = f.addressee_id
     where f.status = 'pending' and f.created_at < now() - interval '3 days' and f.created_at > now() - interval '60 days'
       and p.deleted_at is null and p.suspended_at is null and a.deleted_at is null and a.suspended_at is null
       and coalesce(p.is_test, false) = false and coalesce(a.is_test, false) = false
       and not exists (select 1 from public.friendships b where b.status = 'blocked'
                        and ((b.requester_id = f.requester_id and b.addressee_id = f.addressee_id) or (b.requester_id = f.addressee_id and b.addressee_id = f.requester_id)))
     group by f.addressee_id
  loop
    -- 이미 이 알림을 받은 회원은 건너뜀(두 번 돌아도 한 번만)
    continue when exists (select 1 from public.notifications x where x.recipient_id = r.addressee_id and x.kind = 'remind' and x.snippet like '뜨친이 100쌍을 넘었어요%');
    select coalesce(nullif(btrim(nickname), ''), '이웃') into nick from public.profiles where id = r.last_req;
    insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
      values (r.addressee_id, r.last_req, 'remind',
        left('뜨친이 100쌍을 넘었어요 🎉 ' || nick || ' 님' || case when r.cnt > 1 then ' 외 ' || (r.cnt - 1) || '명' else '' end || '이 아직 인사를 기다리고 있어요', 120),
        jsonb_build_object('type', 'profile', 'id', r.last_req));
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.friend_request_remind_100() from public, anon, authenticated;
grant execute on function public.friend_request_remind_100() to service_role;

create or replace function public.friend_rec_weekly()
returns integer language plpgsql security definer set search_path = public, extensions as $$
declare u record; r public.friend_recs; nick text; why text; n int := 0; d date := (now() at time zone 'Asia/Seoul')::date; pre text; head text := '오늘의 추천 뜨친: ';
begin
  -- 한때만 붙이는 앞말(schema 172): 기한 안일 때만
  select nullif(btrim(value->>'text'), '') into pre from public.app_config where key = 'friend_rec_prefix' and (value->>'until')::timestamptz > now();
  if pre is not null then head := left(pre, 40) || ' 오늘의 추천: '; end if;
  for u in
    select p.id from public.profiles p
     where p.onboarded_at is not null and p.deleted_at is null and p.suspended_at is null and not p.rec_off
       and p.last_seen_at > now() - interval '30 days'
       and not exists (select 1 from public.friendships f where f.requester_id = p.id and f.created_at > now() - interval '7 days')
     order by p.last_seen_at desc limit 2000
  loop
    perform public._friend_rec_make(u.id, d);
    select * into r from public.friend_recs where profile_id = u.id and day = d;
    continue when r.id is null or r.rec_id is null or r.pushed_at is not null;
    continue when exists (select 1 from public.friendships f where (f.requester_id = u.id and f.addressee_id = r.rec_id) or (f.requester_id = r.rec_id and f.addressee_id = u.id));
    select coalesce(nullif(btrim(nickname), ''), '이웃') into nick from public.profiles where id = r.rec_id and deleted_at is null and suspended_at is null;
    continue when nick is null;
    select x->>'t' into why from jsonb_array_elements(r.reasons) x limit 1;
    insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
      values (u.id, r.rec_id, 'remind', left(head || nick || ' 님 · ' || coalesce(r.near, '가까운 이웃') || coalesce(' · ' || why, ''), 120),
              jsonb_build_object('type', 'profile', 'id', r.rec_id));
    update public.friend_recs set pushed_at = now() where id = r.id;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.friend_rec_weekly() from public, anon, authenticated;
grant execute on function public.friend_rec_weekly() to service_role;
