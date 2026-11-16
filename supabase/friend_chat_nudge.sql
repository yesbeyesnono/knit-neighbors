-- schema 135 (2026-11-16 대표 지시): 뜨친이 된 뒤 하루가 지나도 한마디도 없으면 양쪽에 한 번 알림
-- 매일 10:00 KST(밤에는 보내지 않음). 한 쌍에 한 번(friendships.chat_nudged_at), 한 사람에게는 하루 한 건(여러 명이면 '○○ 님 외 N명'으로 묶음).
-- 문구는 '가볍게'(대표 선택), 이벤트 안내는 넣지 않는다. 이미 맺어진 쌍(60일 안)에도 첫 실행 때 한 번 간다.
-- 누르면 상대 프로필(채팅 버튼이 있음)이 열린다 — 옛 앱에도 있는 링크 종류. 여러 명이면 채팅 목록.
alter table public.friendships add column if not exists chat_nudged_at timestamptz;

create or replace function public.friend_chat_nudge() returns int
language plpgsql security definer set search_path = public as $$
declare r record; n int := 0; sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e';
begin
  create temp table _fcn on commit drop as
    select f.requester_id as a, f.addressee_id as b, coalesce(f.responded_at, f.created_at) as acc
      from public.friendships f join public.profiles pa on pa.id = f.requester_id join public.profiles pb on pb.id = f.addressee_id
     where f.status = 'accepted' and f.chat_nudged_at is null
       and coalesce(f.responded_at, f.created_at) < now() - interval '24 hours' and coalesce(f.responded_at, f.created_at) > now() - interval '60 days'
       and pa.deleted_at is null and pa.suspended_at is null and pb.deleted_at is null and pb.suspended_at is null
       and f.requester_id <> sup and f.addressee_id <> sup
       and not public.is_blocked(f.requester_id, f.addressee_id) and not public.is_blocked(f.addressee_id, f.requester_id)
       and not exists (select 1 from public.rooms ro
                         join public.room_members x on x.room_id = ro.id and x.profile_id = f.requester_id
                         join public.room_members y on y.room_id = ro.id and y.profile_id = f.addressee_id
                         join public.messages m on m.room_id = ro.id
                        where ro.kind = 'direct');
  for r in
    select u.uid, count(*) as k, (array_agg(u.partner order by u.acc desc))[1] as p1, (array_agg(coalesce(nullif(btrim(pp.nickname),''),'이웃') order by u.acc desc))[1] as nick, max(u.acc) as acc
      from (select a as uid, b as partner, acc from _fcn union all select b, a, acc from _fcn) u join public.profiles pp on pp.id = u.partner
     group by u.uid
  loop
    insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
      values (r.uid, r.p1, 'remind',
        left(case when r.k > 1 then r.nick||' 님 외 '||(r.k - 1)||'명과 뜨친이 됐어요. 아직 인사 전이에요. 먼저 인사해 볼까요? 👋'
                  when r.acc > now() - interval '48 hours' then r.nick||' 님과 뜨친이 된 지 하루 됐어요. 먼저 인사해 볼까요? 👋'
                  else r.nick||' 님과 뜨친이 됐어요. 아직 인사 전이에요. 먼저 인사해 볼까요? 👋' end, 120),
        case when r.k > 1 then jsonb_build_object('type','view','view','chats') else jsonb_build_object('type','profile','id', r.p1) end);
    n := n + 1;
  end loop;
  update public.friendships f set chat_nudged_at = now() from _fcn c where f.requester_id = c.a and f.addressee_id = c.b;
  return n;
end $$;
revoke all on function public.friend_chat_nudge() from public, anon, authenticated;

select cron.unschedule('friend-chat-nudge') where exists (select 1 from cron.job where jobname = 'friend-chat-nudge');
select cron.schedule('friend-chat-nudge', '0 1 * * *', $$select public.friend_chat_nudge()$$);   -- 매일 10:00 KST
