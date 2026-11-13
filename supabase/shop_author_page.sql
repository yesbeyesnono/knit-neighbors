-- 108. 공방·작가 화면 개편: 맨 위 사진 · 작가 팔로우 · 문의 대화 · 작가 링크 여러 개 (2026-11-13 대표 확정 시안)
alter table public.shops    add column if not exists cover_url text;
alter table public.profiles add column if not exists cover_url text, add column if not exists author_links jsonb;
alter table public.rooms    add column if not exists inquiry boolean not null default false;

create or replace function public._own_storage_url(u text) returns boolean language sql immutable
as $$ select u is null or u ~ '^https://(api\.knitup\.co\.kr|thfcrodfaitzrzlrxyir\.supabase\.co)/storage/v1/object/public/(avatars|shops)/[A-Za-z0-9/_.-]+$' $$;
revoke all on function public._own_storage_url(text) from public, anon;
grant execute on function public._own_storage_url(text) to authenticated, service_role;
alter table public.shops drop constraint if exists shops_cover_url_own;
alter table public.shops add constraint shops_cover_url_own check (public._own_storage_url(cover_url));

-- 작가: 맨 위 사진
create or replace function public.set_author_cover(p_url text) returns void language plpgsql security definer set search_path to 'public' as $$
declare v text := nullif(btrim(coalesce(p_url,'')), '');
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and is_author and suspended_at is null) then raise exception '작가만 넣을 수 있어요'; end if;
  if not public._own_storage_url(v) then raise exception '사진을 다시 올려 주세요'; end if;
  update public.profiles set cover_url = v where id = auth.uid();
end $$;
revoke all on function public.set_author_cover(text) from public, anon;
grant execute on function public.set_author_cover(text) to authenticated;

-- 작가: 링크 최대 3개(첫 번째는 옛 앱이 보는 author_link 에도)
create or replace function public.set_author_links(p_links jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v text; arr text[] := '{}';
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and is_author and suspended_at is null) then raise exception '작가만 링크를 넣을 수 있어요'; end if;
  if p_links is not null and jsonb_typeof(p_links) <> 'array' then raise exception '링크 형식이 맞지 않아요'; end if;
  for v in select btrim(x) from jsonb_array_elements_text(coalesce(p_links,'[]'::jsonb)) x loop
    if v = '' then continue; end if;
    if length(v) > 300 or v !~* '^https?://[^\s<>"'']+$' then raise exception '링크는 https://로 시작해야 해요'; end if;
    if exists (select 1 from public.banned_words b where lower(v) like '%'||lower(b.word)||'%') then raise exception '사용할 수 없는 표현이 들어 있어요'; end if;
    if not (v = any(arr)) then arr := arr || v; end if;
  end loop;
  if coalesce(array_length(arr,1),0) > 3 then raise exception '링크는 3개까지 넣을 수 있어요'; end if;
  update public.profiles set author_links = case when array_length(arr,1) is null then null else to_jsonb(arr) end, author_link = arr[1] where id = auth.uid();
  return to_jsonb(arr);
end $$;
revoke all on function public.set_author_links(jsonb) from public, anon;
grant execute on function public.set_author_links(jsonb) to authenticated;

-- 작가 팔로우
create table if not exists public.author_follows(
  profile_id uuid not null references public.profiles(id) on delete cascade,
  author_id  uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (profile_id, author_id),
  check (profile_id <> author_id)
);
create index if not exists author_follows_author on public.author_follows(author_id);
alter table public.author_follows enable row level security;
revoke all on public.author_follows from anon, authenticated;
grant select, insert, delete on public.author_follows to authenticated;
grant all on public.author_follows to service_role;
drop policy if exists author_follows_own_select on public.author_follows;
drop policy if exists author_follows_own_insert on public.author_follows;
drop policy if exists author_follows_own_delete on public.author_follows;
create policy author_follows_own_select on public.author_follows for select using (profile_id = (select auth.uid()) or author_id = (select auth.uid()) or public.is_admin());
create policy author_follows_own_insert on public.author_follows for insert with check (
  profile_id = (select auth.uid()) and public.is_active_user()
  and exists (select 1 from public.profiles p where p.id = author_id and p.is_author and p.suspended_at is null and p.deleted_at is null)
  and not public.is_blocked(profile_id, author_id));
create policy author_follows_own_delete on public.author_follows for delete using (profile_id = (select auth.uid()));

create or replace function public.follower_count(p_kind text, p_id uuid) returns integer language sql stable security definer set search_path to 'public' as $$
  select case when auth.uid() is null then 0
    when p_kind = 'shop' then (select count(*)::int from public.shop_follows where shop_id = p_id)
    when p_kind = 'author' then (select count(*)::int from public.author_follows where author_id = p_id)
    else 0 end $$;
revoke all on function public.follower_count(text, uuid) from public, anon;
grant execute on function public.follower_count(text, uuid) to authenticated;

-- 문의 대화: 작가·공방(주인)에게는 뜨친이 아니어도 1:1 대화를 열 수 있다
create or replace function public.open_inquiry_room(p_kind text, p_id uuid) returns uuid language plpgsql security definer set search_path to 'public' as $$
declare v_me uuid := auth.uid(); v_to uuid; v_room uuid;
begin
  if v_me is null or not public.is_active_user() then raise exception '지금은 문의할 수 없어요'; end if;
  if p_kind = 'shop' then select owner_id into v_to from public.shops where id = p_id and is_active;
  elsif p_kind = 'author' then select id into v_to from public.profiles where id = p_id and is_author;
  end if;
  if v_to is null or exists (select 1 from public.profiles where id = v_to and (suspended_at is not null or deleted_at is not null)) then raise exception '지금은 문의를 받지 않는 곳이에요'; end if;
  if v_to = v_me then raise exception '내 화면이에요'; end if;
  if exists (select 1 from public.friendships where status = 'blocked' and ((requester_id = v_me and addressee_id = v_to) or (requester_id = v_to and addressee_id = v_me))) then raise exception '문의할 수 없어요'; end if;
  select r.id into v_room from public.rooms r
    join public.room_members a on a.room_id = r.id and a.profile_id = v_me
    join public.room_members b on b.room_id = r.id and b.profile_id = v_to
   where r.kind = 'direct' limit 1;
  if v_room is null then
    if (select count(*) from public.rooms where created_by = v_me and inquiry and created_at > now() - interval '1 day') >= 10 then raise exception '오늘은 문의를 더 열 수 없어요. 내일 다시 해 주세요'; end if;
    insert into public.rooms(kind, created_by, inquiry) values ('direct', v_me, true) returning id into v_room;
    insert into public.room_members(room_id, profile_id) values (v_room, v_me), (v_room, v_to);
  else
    update public.room_members set left_at = null, archived_at = null where room_id = v_room and profile_id = v_me;
  end if;
  return v_room;
end $$;
revoke all on function public.open_inquiry_room(text, uuid) from public, anon;
grant execute on function public.open_inquiry_room(text, uuid) to authenticated;

-- 작가가 클래스를 열면 팔로워에게도 알림(뜨친은 기존 알림이 있어 제외)
create or replace function public.notify_on_shop_post() returns trigger language plpgsql security definer set search_path to 'public' as $function$
begin
  if new.shop_id is not null then
    insert into public.notifications(recipient_id, actor_id, kind, shop_id, snippet)
      select f.profile_id, new.author_id, 'shop_post', new.shop_id, left(new.title, 80) from public.shop_follows f where f.shop_id = new.shop_id and f.profile_id is distinct from new.author_id;
  elsif new.kind = 'class' and new.author_id is not null then
    insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
      select case when fr.requester_id = new.author_id then fr.addressee_id else fr.requester_id end, new.author_id, 'notice', '작가 친구가 클래스를 열었어요: ' || left(new.title, 60), jsonb_build_object('type','profile','id',new.author_id,'tab','classes')
      from public.friendships fr where fr.status = 'accepted' and (fr.requester_id = new.author_id or fr.addressee_id = new.author_id);
    insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
      select f.profile_id, new.author_id, 'notice', '팔로우한 작가가 클래스를 열었어요: ' || left(new.title, 60), jsonb_build_object('type','profile','id',new.author_id,'tab','classes')
      from public.author_follows f where f.author_id = new.author_id
        and not exists (select 1 from public.friendships fr where fr.status in ('accepted','blocked') and ((fr.requester_id = new.author_id and fr.addressee_id = f.profile_id) or (fr.requester_id = f.profile_id and fr.addressee_id = new.author_id)));
  end if;
  return new;
end $function$;

-- 작가가 공개 모임을 열면 팔로워에게 알림
create or replace function public.notify_followers_on_meetup() returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  if new.is_public and not coalesce(new.hidden,false) and exists (select 1 from public.profiles where id = new.created_by and is_author) then
    insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
      select f.profile_id, new.created_by, 'notice', '팔로우한 작가가 모임을 열었어요: ' || left(new.title, 60), jsonb_build_object('type','meetup','id',new.id)
      from public.author_follows f where f.author_id = new.created_by
        and not exists (select 1 from public.friendships fr where fr.status = 'blocked' and ((fr.requester_id = new.created_by and fr.addressee_id = f.profile_id) or (fr.requester_id = f.profile_id and fr.addressee_id = new.created_by)));
  end if;
  return null;
end $$;
revoke all on function public.notify_followers_on_meetup() from public, anon, authenticated;
drop trigger if exists meetups_notify_followers on public.meetups;
create trigger meetups_notify_followers after insert on public.meetups for each row execute function public.notify_followers_on_meetup();
