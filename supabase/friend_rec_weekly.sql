-- 145. 추천 뜨친 주 1회 알림 (2026-11-18 대표 지시)
-- 매주 토요일 10:00(한국 시간). 최근 30일 안에 접속했고 지난 7일 동안 뜨친 신청을 보내지 않은 회원에게, 그날의 추천 뜨친 한 명을 알림으로 소개한다.
-- 추천을 끈 회원·정지·탈퇴 회원 제외. 소개할 이웃이 없으면 보내지 않는다. 링크는 그 사람의 프로필(옛 앱에서도 열림).
alter table public.friend_recs add column if not exists pushed_at timestamptz;

create or replace function public.friend_rec_weekly()
returns integer language plpgsql security definer set search_path to 'public', 'extensions' as $fn$
declare u record; r public.friend_recs; nick text; why text; n int := 0; d date := (now() at time zone 'Asia/Seoul')::date;
begin
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
      values (u.id, r.rec_id, 'remind', left('오늘의 추천 뜨친: ' || nick || ' 님 · ' || coalesce(r.near, '가까운 이웃') || coalesce(' · ' || why, ''), 120),
              jsonb_build_object('type', 'profile', 'id', r.rec_id));
    update public.friend_recs set pushed_at = now() where id = r.id;
    n := n + 1;
  end loop;
  return n;
end $fn$;
revoke all on function public.friend_rec_weekly() from public, anon, authenticated;
grant execute on function public.friend_rec_weekly() to service_role;
select cron.schedule('friend-rec-weekly', '0 1 * * 6', $$select public.friend_rec_weekly()$$);
