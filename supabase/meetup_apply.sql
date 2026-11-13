-- 109. 참가비가 있는 모임: 쓰임새·환불 안내 + '신청 → 개설자 확정' (2026-11-13 대표 확정 시안)
--   ※ 2026-11-13 작성 시점에 DB 연결이 끊겨 아직 적용하지 못함. 적용 뒤 supabase_schema.sql · permissions_test.sql 에 옮겨 적을 것.
--   앱은 meetups.join_mode 칸이 있는지 먼저 확인하고(없으면 새 칸을 숨김) 이 기능을 쓴다.
alter table public.meetups add column if not exists fee_note text, add column if not exists refund_note text, add column if not exists join_mode text not null default 'open';
alter table public.meetups drop constraint if exists meetups_join_mode_chk;
alter table public.meetups add constraint meetups_join_mode_chk check (join_mode in ('open','apply'));
create index if not exists meetups_room_id_idx on public.meetups(room_id);

create table if not exists public.meetup_applications(
  meetup_id  uuid not null references public.meetups(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  status     text not null default 'applied' check (status in ('applied','accepted','rejected','cancelled')),
  note       text,
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  primary key (meetup_id, profile_id)
);
alter table public.meetup_applications enable row level security;
revoke all on public.meetup_applications from anon, authenticated;
grant select on public.meetup_applications to authenticated;   -- 쓰기는 함수로만
grant all on public.meetup_applications to service_role;
drop policy if exists meetup_applications_select on public.meetup_applications;
create policy meetup_applications_select on public.meetup_applications for select using (
  profile_id = (select auth.uid()) or public.is_admin()
  or exists (select 1 from public.meetups m where m.id = meetup_id and m.created_by = (select auth.uid())));

-- 개설자: 참가비 쓰임새 · 참여 방식 · 취소·환불 안내
create or replace function public.meetup_set_terms(p_meetup uuid, p_fee_note text, p_mode text, p_refund text) returns void language plpgsql security definer set search_path to 'public' as $$
declare m public.meetups; v_note text := nullif(btrim(coalesce(p_fee_note,'')), ''); v_ref text := nullif(btrim(coalesce(p_refund,'')), ''); v_mode text := coalesce(p_mode,'open'); t text;
begin
  select * into m from public.meetups where id = p_meetup;
  if m.id is null or m.created_by is distinct from auth.uid() then raise exception '개설자만 정할 수 있어요'; end if;
  if v_mode not in ('open','apply') then raise exception '참여 방식을 확인해 주세요'; end if;
  if length(coalesce(v_note,'')) > 80 or length(coalesce(v_ref,'')) > 80 then raise exception '한 줄(80자)로 적어 주세요'; end if;
  foreach t in array array[coalesce(v_note,''), coalesce(v_ref,'')] loop
    if t ~* 'https?://|www\.' then raise exception '링크는 넣을 수 없어요'; end if;
    if t ~ '\d{2,6}[- ]\d{2,6}[- ]\d{2,8}' then raise exception '계좌번호는 적을 수 없어요. 확정 뒤 채팅방에서 안내해 주세요'; end if;
    if exists (select 1 from public.banned_words b where lower(t) like '%'||lower(b.word)||'%') then raise exception '사용할 수 없는 표현이 들어 있어요'; end if;
  end loop;
  update public.meetups set fee_note = v_note, refund_note = v_ref, join_mode = v_mode where id = p_meetup;
end $$;
revoke all on function public.meetup_set_terms(uuid, text, text, text) from public, anon;
grant execute on function public.meetup_set_terms(uuid, text, text, text) to authenticated;

-- 회원: 참여 신청 / 신청 취소
create or replace function public.meetup_apply(p_meetup uuid, p_note text default null) returns text language plpgsql security definer set search_path to 'public' as $$
declare m public.meetups; v_me uuid := auth.uid(); v_note text := nullif(btrim(coalesce(p_note,'')), ''); cur text; nick text;
begin
  if v_me is null or not public.is_active_user() then raise exception '지금은 신청할 수 없어요'; end if;
  select * into m from public.meetups where id = p_meetup;
  if m.id is null or coalesce(m.hidden,false) then raise exception '모임을 찾을 수 없어요'; end if;
  if m.join_mode <> 'apply' then raise exception '바로 참여할 수 있는 모임이에요'; end if;
  if m.created_by = v_me then raise exception '내가 연 모임이에요'; end if;
  if coalesce(m.repeat,'once') = 'once' and m.starts_at < now() then raise exception '이미 지난 모임이에요'; end if;
  if exists (select 1 from public.friendships where status = 'blocked' and ((requester_id = v_me and addressee_id = m.created_by) or (requester_id = m.created_by and addressee_id = v_me))) then raise exception '신청할 수 없어요'; end if;
  if exists (select 1 from public.room_members where room_id = m.room_id and profile_id = v_me) then raise exception '이미 참여하고 있어요'; end if;
  if length(coalesce(v_note,'')) > 200 then raise exception '한마디는 200자까지예요'; end if;
  if v_note is not null and exists (select 1 from public.banned_words b where lower(v_note) like '%'||lower(b.word)||'%') then raise exception '사용할 수 없는 표현이 들어 있어요'; end if;
  select status into cur from public.meetup_applications where meetup_id = p_meetup and profile_id = v_me;
  if cur = 'applied' then return 'applied'; end if;
  if cur = 'rejected' then raise exception '이번 모임은 참여가 어려워요'; end if;
  insert into public.meetup_applications(meetup_id, profile_id, status, note) values (p_meetup, v_me, 'applied', v_note)
    on conflict (meetup_id, profile_id) do update set status = 'applied', note = excluded.note, created_at = now(), decided_at = null;
  select nickname into nick from public.profiles where id = v_me;
  insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
    values (m.created_by, v_me, 'notice', coalesce(nick,'이웃') || '님이 모임 참여를 신청했어요: ' || left(m.title, 50), jsonb_build_object('type','meetup','id',m.id));
  return 'applied';
end $$;
revoke all on function public.meetup_apply(uuid, text) from public, anon;
grant execute on function public.meetup_apply(uuid, text) to authenticated;

create or replace function public.meetup_cancel_apply(p_meetup uuid) returns void language sql security definer set search_path to 'public' as $$
  update public.meetup_applications set status = 'cancelled', decided_at = now() where meetup_id = p_meetup and profile_id = auth.uid() and status = 'applied' $$;
revoke all on function public.meetup_cancel_apply(uuid) from public, anon;
grant execute on function public.meetup_cancel_apply(uuid) to authenticated;

-- 화면용 요약: 내 상태 + (개설자에게만) 기다리는 신청 수
create or replace function public.meetup_app_summary(p_meetup uuid) returns jsonb language sql stable security definer set search_path to 'public' as $$
  select jsonb_build_object(
    'mine', (select status from public.meetup_applications where meetup_id = p_meetup and profile_id = auth.uid()),
    'waiting', case when exists (select 1 from public.meetups where id = p_meetup and created_by = auth.uid())
                    then (select count(*) from public.meetup_applications where meetup_id = p_meetup and status = 'applied') else null end) $$;
revoke all on function public.meetup_app_summary(uuid) from public, anon;
grant execute on function public.meetup_app_summary(uuid) to authenticated;

-- 개설자: 신청자 목록 / 확정·거절
create or replace function public.meetup_applicants(p_meetup uuid) returns table(profile_id uuid, nickname text, avatar_url text, status text, note text, created_at timestamptz)
language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not exists (select 1 from public.meetups where id = p_meetup and created_by = auth.uid()) and not public.is_admin() then raise exception '개설자만 볼 수 있어요'; end if;
  return query select a.profile_id, p.nickname, p.avatar_url, a.status, a.note, a.created_at
    from public.meetup_applications a join public.profiles p on p.id = a.profile_id
    where a.meetup_id = p_meetup and a.status in ('applied','accepted') order by (a.status = 'applied') desc, a.created_at;
end $$;
revoke all on function public.meetup_applicants(uuid) from public, anon;
grant execute on function public.meetup_applicants(uuid) to authenticated;

create or replace function public.meetup_decide(p_meetup uuid, p_profile uuid, p_accept boolean) returns text language plpgsql security definer set search_path to 'public' as $$
declare m public.meetups; cur text;
begin
  select * into m from public.meetups where id = p_meetup;
  if m.id is null or m.created_by is distinct from auth.uid() then raise exception '개설자만 정할 수 있어요'; end if;
  select status into cur from public.meetup_applications where meetup_id = p_meetup and profile_id = p_profile for update;
  if cur is distinct from 'applied' then raise exception '기다리는 신청이 아니에요'; end if;
  if p_accept then
    if m.capacity is not null and coalesce(m.participant_count,0) >= m.capacity then raise exception '정원이 찼어요'; end if;
    update public.meetup_applications set status = 'accepted', decided_at = now() where meetup_id = p_meetup and profile_id = p_profile;
    insert into public.room_members(room_id, profile_id) values (m.room_id, p_profile) on conflict do nothing;
    insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
      values (p_profile, m.created_by, 'notice', '모임 참여가 확정됐어요: ' || left(m.title, 60), jsonb_build_object('type','meetup','id',m.id));
    return 'accepted';
  end if;
  update public.meetup_applications set status = 'rejected', decided_at = now() where meetup_id = p_meetup and profile_id = p_profile;
  insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
    values (p_profile, m.created_by, 'notice', '이번 모임은 함께하기 어렵게 됐어요: ' || left(m.title, 60), jsonb_build_object('type','meetup','id',m.id));
  return 'rejected';
end $$;
revoke all on function public.meetup_decide(uuid, uuid, boolean) from public, anon;
grant execute on function public.meetup_decide(uuid, uuid, boolean) to authenticated;

-- 문지기: '신청 → 확정' 모임의 채팅방에는 개설자와 확정된 사람만 들어온다(옛 앱의 join_meetup·친구 초대도 여기서 막힘)
create or replace function public.room_members_meetup_gate() returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  if exists (select 1 from public.meetups m where m.room_id = new.room_id and m.join_mode = 'apply' and m.created_by <> new.profile_id)
     and not exists (select 1 from public.meetups m join public.meetup_applications a on a.meetup_id = m.id
                      where m.room_id = new.room_id and a.profile_id = new.profile_id and a.status = 'accepted') then
    raise exception '이 모임은 참여 신청 뒤 개설자가 확정하면 들어올 수 있어요. 앱을 최신 버전으로 업데이트해 주세요';
  end if;
  return new;
end $$;
revoke all on function public.room_members_meetup_gate() from public, anon, authenticated;
drop trigger if exists room_members_meetup_gate on public.room_members;
create trigger room_members_meetup_gate before insert on public.room_members for each row execute function public.room_members_meetup_gate();
