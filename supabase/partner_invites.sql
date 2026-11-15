-- schema 128 (2026-11-15): 작가·공방 초대 기록 + 승인 순간 사용법 자동 안내 + 3일 뒤 사진 알림
-- 초대장은 회원이 아닌 분께 대표가 직접 보냄(기록만). 작가 지정·가게 공개 순간에는 지기 채팅 + 🔔 푸시가 자동.

create table if not exists public.partner_invites (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('author','shop')),
  name text not null check (char_length(name) between 1 and 40),
  memo text check (memo is null or char_length(memo) <= 300),
  sent_at timestamptz,
  profile_id uuid references public.profiles(id) on delete set null,
  created_by uuid,
  created_at timestamptz not null default now()
);
alter table public.partner_invites enable row level security;
revoke all on public.partner_invites from anon, authenticated;
grant all on public.partner_invites to service_role;

create table if not exists public.partner_guides (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('author','shop')),
  sent_at timestamptz,            -- 안내를 보낸 시각 (null = 이 기능 전부터 작가·가게였던 분: 보내지 않음)
  msg_id bigint,                  -- 지기 채팅 메시지 (읽음 확인용)
  nudged_at timestamptz,          -- 3일 뒤 확인한 시각
  nudge_sent boolean not null default false,
  seeded boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (profile_id, kind)
);
alter table public.partner_guides enable row level security;
revoke all on public.partner_guides from anon, authenticated;
grant all on public.partner_guides to service_role;

-- 이미 작가·가게인 분들은 '보내지 않음'으로 적어 둔다 (대표 지시: 기존 분들께는 보내지 않음)
insert into public.partner_guides(profile_id, kind, seeded)
  select id, 'author', true from public.profiles where is_author
  on conflict do nothing;
insert into public.partner_guides(profile_id, kind, seeded)
  select distinct owner_id, 'shop', true from public.shops where owner_id is not null and is_active
  on conflict do nothing;

-- 안내 보내기 (한 사람·종류당 한 번)
create or replace function public._partner_guide_send(p_user uuid, p_kind text) returns boolean
language plpgsql security definer set search_path = public as $$
declare sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e'; rid uuid; mid bigint; nm text; body text; card jsonb; snip text; dup boolean;
begin
  if p_user is null or p_user = sup or p_kind not in ('author','shop') then return false; end if;
  insert into public.partner_guides(profile_id, kind) values (p_user, p_kind) on conflict do nothing;
  if not found then return false; end if;
  if p_kind = 'author' then
    select nickname into nm from public.profiles where id = p_user;
    body := coalesce(nm,'작가')||' 님, knitup 작가가 되셨어요 ♛'||E'\n'
      ||'이제 지도에 황금색 작가 핀으로 보이고, 나만의 작가 페이지가 생겼어요.'||E'\n\n'
      ||'먼저 이 두 가지만 해 두시면 좋아요.'||E'\n'
      ||'1. 마이 › 설정 › 작가 화면 꾸미기에서 대표 사진과 링크 넣기'||E'\n'
      ||'2. 아래 ＋ 에서 모임이나 클래스 열기'||E'\n\n'
      ||'작가 안내: app.knitup.co.kr/authors.html';
    card := jsonb_build_object('type','guide','guide','author','label','작가 안내 보기','url','https://app.knitup.co.kr/authors.html');
    snip := coalesce(nm,'작가')||' 님, knitup 작가가 되셨어요 ♛ 작가 안내를 보내 드렸어요. 눌러서 확인해 보세요.';
    dup := exists (select 1 from public.notifications n where n.recipient_id = p_user and n.kind = 'notice' and n.snippet like '작가로 승인됐어요%' and n.created_at > now() - interval '2 minutes');
  else
    select s.name into nm from public.shops s where s.owner_id = p_user order by s.created_at limit 1;
    body := coalesce(nm,'')||' 사장님, knitup 가게 문이 열렸어요'||E'\n'
      ||'지도에 가게 핀과 가게 페이지가 생겼어요.'||E'\n\n'
      ||'먼저 이 두 가지만 해 두시면 좋아요.'||E'\n'
      ||'1. 마이 › 설정 › 내 가게 관리에서 로고와 매장 사진 넣기'||E'\n'
      ||'2. 아래 ＋ › 가게 소식으로 첫 소식 올리기'||E'\n\n'
      ||'가게 안내: app.knitup.co.kr/shop-guide.html';
    card := jsonb_build_object('type','guide','guide','shop','label','가게 안내 보기','url','https://app.knitup.co.kr/shop-guide.html');
    snip := 'knitup 가게 문이 열렸어요. 가게 안내를 보내 드렸어요. 눌러서 확인해 보세요.';
    dup := exists (select 1 from public.notifications n where n.recipient_id = p_user and n.kind = 'notice' and n.snippet like '가게 등록이 승인됐어요%' and n.created_at > now() - interval '2 minutes');
  end if;
  rid := public._support_room(p_user);
  insert into public.messages(room_id, sender_id, body, by_ai, card) values (rid, sup, body, true, card) returning id into mid;
  if not dup then   -- 승인 알림이 방금 갔으면 푸시를 한 번 더 보내지 않는다
    insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
      values (p_user, sup, 'notice', snip, jsonb_build_object('type','view','view','support'));
  end if;
  update public.partner_guides set sent_at = now(), msg_id = mid where profile_id = p_user and kind = p_kind;
  return true;
end $$;
revoke all on function public._partner_guide_send(uuid, text) from public, anon, authenticated;

-- 작가가 되는 순간 / 가게가 공개되는 순간 (커밋 때 실행 → 승인 알림과 겹치는지 볼 수 있음)
create or replace function public.partner_guide_trg() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  begin
    if tg_table_name = 'profiles' then
      if new.is_author and new.deleted_at is null then perform public._partner_guide_send(new.id, 'author'); end if;
    else
      if new.owner_id is not null and new.is_active then perform public._partner_guide_send(new.owner_id, 'shop'); end if;
    end if;
  exception when others then null;   -- 안내 실패가 승인을 막지 않게
  end;
  return null;
end $$;
revoke all on function public.partner_guide_trg() from public, anon, authenticated;

drop trigger if exists profiles_partner_guide on public.profiles;
create constraint trigger profiles_partner_guide after update of is_author on public.profiles
  deferrable initially deferred for each row when (new.is_author) execute function public.partner_guide_trg();
drop trigger if exists shops_partner_guide on public.shops;
create constraint trigger shops_partner_guide after insert or update of is_active, owner_id on public.shops
  deferrable initially deferred for each row execute function public.partner_guide_trg();

-- 3일 뒤: 대표 사진(가게는 매장 사진)이 아직 없으면 한 번만 알림
create or replace function public.partner_guide_nudge() returns int
language plpgsql security definer set search_path = public as $$
declare sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e'; g record; need boolean; n int := 0;
begin
  for g in select * from public.partner_guides where sent_at is not null and nudged_at is null and sent_at <= now() - interval '3 days' loop
    if g.kind = 'author' then
      need := exists (select 1 from public.profiles p where p.id = g.profile_id and p.is_author and p.deleted_at is null and p.cover_url is null);
      if need then insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
        values (g.profile_id, sup, 'remind', '작가 페이지에 대표 사진을 넣어 보세요. 사진 한 장만 넣어도 작가 페이지가 훨씬 살아나요.', jsonb_build_object('type','view','view','author_page')); end if;
    else
      need := exists (select 1 from public.shops s where s.owner_id = g.profile_id and s.is_active and s.cover_url is null);
      if need then insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
        values (g.profile_id, sup, 'remind', '가게 페이지에 매장 사진을 넣어 보세요. 사진이 있으면 이웃이 가게를 훨씬 쉽게 알아봐요.', jsonb_build_object('type','view','view','shop_edit')); end if;
    end if;
    update public.partner_guides set nudged_at = now(), nudge_sent = need where profile_id = g.profile_id and kind = g.kind;
    if need then n := n + 1; end if;
  end loop;
  return n;
end $$;
revoke all on function public.partner_guide_nudge() from public, anon, authenticated;
select cron.unschedule('partner-guide-nudge') where exists (select 1 from cron.job where jobname = 'partner-guide-nudge');
select cron.schedule('partner-guide-nudge', '0 1 * * *', $$select public.partner_guide_nudge()$$);   -- 매일 10:00 KST

-- 콘솔: 초대·안내 현황
create or replace function public.admin_partner_list() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  with base as (
    select i.id, i.kind, i.name, i.memo, i.sent_at, i.created_at, i.profile_id from public.partner_invites i
    union all
    select null, g.kind, null, null, null, coalesce(g.sent_at, g.created_at), g.profile_id from public.partner_guides g
      where not exists (select 1 from public.partner_invites i where i.profile_id = g.profile_id and i.kind = g.kind)
  )
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb) into r from (
    select b.id, b.kind, b.name, b.memo, b.sent_at, b.created_at, b.profile_id,
      p.nickname, p.created_at as joined_at, coalesce(p.is_author, false) as is_author, p.author_since,
      (p.cover_url is not null) as a_cover,
      coalesce(jsonb_array_length(case when jsonb_typeof(p.author_links) = 'array' then p.author_links else '[]'::jsonb end), 0) as a_links,
      s.id as shop_id, s.name as shop_name, coalesce(s.is_active, false) as shop_active, s.created_at as shop_at,
      (s.cover_url is not null) as s_cover, (s.logo_url is not null) as s_logo,
      (select count(*) from jsonb_each(case when jsonb_typeof(s.links) = 'object' then s.links else '{}'::jsonb end) e where coalesce(e.value #>> '{}', '') <> '') as s_links,
      (select c.status from public.shop_claims c where c.profile_id = b.profile_id order by c.created_at desc limit 1) as claim_status,
      g.sent_at as guide_at, coalesce(g.seeded, false) as seeded, g.nudged_at, coalesce(g.nudge_sent, false) as nudge_sent,
      (g.msg_id is not null and exists (select 1 from public.messages m join public.room_members rm on rm.room_id = m.room_id and rm.profile_id = b.profile_id where m.id = g.msg_id and rm.last_read_at >= m.created_at)) as guide_read
    from base b
      left join public.profiles p on p.id = b.profile_id
      left join lateral (select * from public.shops s where s.owner_id = b.profile_id order by s.created_at limit 1) s on b.kind = 'shop'
      left join public.partner_guides g on g.profile_id = b.profile_id and g.kind = b.kind
  ) x;
  return r;
end $$;
revoke all on function public.admin_partner_list() from public, anon;
grant execute on function public.admin_partner_list() to authenticated;

create or replace function public.admin_partner_invite(p_kind text, p_name text, p_memo text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare i uuid; nm text := btrim(regexp_replace(coalesce(p_name,''), '[<>#]', '', 'g'));
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  if p_kind not in ('author','shop') then raise exception '종류를 골라 주세요'; end if;
  if char_length(nm) < 1 or char_length(nm) > 40 then raise exception '이름을 1~40자로 적어 주세요'; end if;
  insert into public.partner_invites(kind, name, memo, created_by) values (p_kind, nm, nullif(btrim(coalesce(p_memo,'')), ''), auth.uid()) returning id into i;
  perform public.admin_log('partner_invite', 'partner_invite', i::text, jsonb_build_object('kind', p_kind, 'name', nm));
  return i;
end $$;
revoke all on function public.admin_partner_invite(text, text, text) from public, anon;
grant execute on function public.admin_partner_invite(text, text, text) to authenticated;

-- p_op: sent(보냄으로 기록) · unsent · link(닉네임 연결, p_val=닉네임) · unlink · memo(p_val) · delete
create or replace function public.admin_partner_invite_set(p_id uuid, p_op text, p_val text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v public.partner_invites; pid uuid; k int; key text;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  select * into v from public.partner_invites where id = p_id for update;
  if v.id is null then raise exception '초대 기록을 찾을 수 없습니다'; end if;
  if p_op = 'sent' then update public.partner_invites set sent_at = coalesce(sent_at, now()) where id = p_id;
  elsif p_op = 'unsent' then update public.partner_invites set sent_at = null where id = p_id;
  elsif p_op = 'link' then
    key := lower(regexp_replace(coalesce(p_val,''), '\s+', '', 'g'));
    if key = '' then raise exception '닉네임을 적어 주세요'; end if;
    select count(*), (array_agg(id))[1] into k, pid from public.profiles
      where deleted_at is null and lower(regexp_replace(coalesce(nickname,''), '\s+', '', 'g')) = key;
    if k = 0 then raise exception '그 닉네임의 회원을 찾지 못했어요'; end if;
    if k > 1 then raise exception '같은 닉네임의 회원이 %명이에요. 회원 화면에서 확인해 주세요', k; end if;
    update public.partner_invites set profile_id = pid where id = p_id;
  elsif p_op = 'unlink' then update public.partner_invites set profile_id = null where id = p_id;
  elsif p_op = 'memo' then update public.partner_invites set memo = nullif(left(btrim(coalesce(p_val,'')), 300), '') where id = p_id;
  elsif p_op = 'delete' then delete from public.partner_invites where id = p_id;
  else raise exception '알 수 없는 동작입니다'; end if;
  perform public.admin_log('partner_invite_'||p_op, 'partner_invite', p_id::text, jsonb_build_object('name', v.name, 'profile', pid));
  return jsonb_build_object('ok', true, 'profile_id', pid);
end $$;
revoke all on function public.admin_partner_invite_set(uuid, text, text) from public, anon;
grant execute on function public.admin_partner_invite_set(uuid, text, text) to authenticated;
