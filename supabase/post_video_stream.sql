-- 152. 글의 영상을 Cloudflare Stream 으로(서버가 자동으로 줄임) (2026-11-19 대표: 큰 영상도 자동 압축 · 쓰레드처럼)
-- 새 영상은 posts.video = {cf: <Stream 영상 id>, poster, dur, w, h}. 옛 방식({url: 우리 저장소 주소})도 그대로 받는다.
-- 누가 올린 영상인지는 Edge Function video-upload 가 video_uploads 에 적는다 — 글에 붙일 때 그 표로 주인을 확인한다.
-- 글이 지워지거나 영상이 바뀌면 storage_trash 에 bucket='cf' 로 올리고, jigi-remind 의 sweep 이 Cloudflare 에서 지운다.

create table if not exists public.video_uploads (
  uid        text primary key,
  owner      uuid,
  created_at timestamptz not null default now(),
  ready_at   timestamptz,
  duration   numeric
);
create index if not exists video_uploads_owner on public.video_uploads (owner, created_at);
alter table public.video_uploads enable row level security;
revoke all on public.video_uploads from anon, authenticated;
grant all on public.video_uploads to service_role;

create or replace function public.posts_video_guard()
returns trigger language plpgsql security definer set search_path to 'public' as $fn$
declare u text; ps text; d numeric; c text; v jsonb;
begin
  if new.video is null then return new; end if;
  if tg_op = 'UPDATE' and new.video is not distinct from old.video then return new; end if;
  if jsonb_typeof(new.video) <> 'object' then raise exception '영상 정보가 올바르지 않아요'; end if;
  if new.parent_id is not null or new.meetup_id is not null or new.work_id is not null or new.review_of is not null then
    raise exception '영상은 일반 글에만 올릴 수 있어요'; end if;
  u := new.video->>'url'; ps := new.video->>'poster'; c := new.video->>'cf';
  if c is not null then
    if c !~ '^[0-9a-f]{32}$' or not exists (select 1 from public.video_uploads vu where vu.uid = c and vu.owner = new.author_id) then
      raise exception '영상 정보가 올바르지 않아요'; end if;
    u := null;
  elsif u is null or u !~ ('^https://api\.knitup\.co\.kr/storage/v1/object/public/videos/' || new.author_id::text || '/[A-Za-z0-9._-]+\.(mp4|mov|webm)$') then
    raise exception '영상 주소가 올바르지 않아요';
  end if;
  if ps is not null and ps !~ ('^https://api\.knitup\.co\.kr/storage/v1/object/public/posts/' || new.author_id::text || '/[A-Za-z0-9._-]+\.jpg$') then
    raise exception '영상 첫 장면 주소가 올바르지 않아요'; end if;
  begin d := (new.video->>'dur')::numeric; exception when others then d := null; end;
  if d is null or d <= 0 or d > 37 then raise exception '영상은 30초까지 올릴 수 있어요'; end if;
  if (select count(*) from public.posts p where p.author_id = new.author_id and p.video is not null and p.created_at > now() - interval '1 day' and p.id <> new.id) >= 10 then
    raise exception '영상은 하루에 10개까지 올릴 수 있어요'; end if;
  v := jsonb_build_object('poster', ps, 'dur', round(d, 1),
         'w', nullif(greatest(0, least(8000, coalesce((new.video->>'w')::int, 0))), 0),
         'h', nullif(greatest(0, least(8000, coalesce((new.video->>'h')::int, 0))), 0));
  new.video := jsonb_strip_nulls(case when c is not null then jsonb_build_object('cf', c) else jsonb_build_object('url', u) end || v);
  return new;
end $fn$;
revoke all on function public.posts_video_guard() from public, anon, authenticated;

create or replace function public.posts_video_trash()
returns trigger language plpgsql security definer set search_path to 'public' as $fn$
declare u text; ps text; c text;
begin
  if old.video is null then return null; end if;
  if tg_op = 'UPDATE' and new.video is not distinct from old.video then return null; end if;
  u := old.video->>'url'; ps := old.video->>'poster'; c := old.video->>'cf';
  if c ~ '^[0-9a-f]{32}$' and (tg_op = 'DELETE' or c is distinct from (new.video->>'cf')) then
    insert into public.storage_trash(bucket, path, reason) values ('cf', c, lower(tg_op)) on conflict (bucket, path) do nothing;
  end if;
  if u ~ '/storage/v1/object/public/videos/' and (tg_op = 'DELETE' or u is distinct from (new.video->>'url')) then
    insert into public.storage_trash(bucket, path, reason) values ('videos', split_part(u, '/storage/v1/object/public/videos/', 2), lower(tg_op))
      on conflict (bucket, path) do nothing;
  end if;
  if ps ~ '/storage/v1/object/public/posts/' and (tg_op = 'DELETE' or ps is distinct from (new.video->>'poster')) then
    insert into public.storage_trash(bucket, path, reason) values ('posts', split_part(ps, '/storage/v1/object/public/posts/', 2), lower(tg_op))
      on conflict (bucket, path) do nothing;
  end if;
  return null;
end $fn$;
revoke all on function public.posts_video_trash() from public, anon, authenticated;

create or replace function public.storage_trash_due(p_limit int default 50)
returns table (id bigint, bucket text, path text) language sql security definer set search_path to 'public' as $fn$
  select t.id, t.bucket, t.path from public.storage_trash t
   where t.done_at is null and t.tries < 5 and t.created_at < now() - interval '10 minutes'
     and not exists (select 1 from public.posts p where p.video is not null
                       and ((t.bucket = 'cf' and p.video->>'cf' = t.path)
                         or (t.bucket <> 'cf' and (p.video->>'url' like '%/' || t.bucket || '/' || t.path or p.video->>'poster' like '%/' || t.bucket || '/' || t.path))))
     and not exists (select 1 from public.posts p where t.bucket = 'posts' and p.photos is not null
                       and exists (select 1 from unnest(p.photos) ph where ph like '%/posts/' || t.path)
                       and (p.video is null or p.video->>'poster' not like '%/posts/' || t.path))
   order by t.id limit greatest(1, least(coalesce(p_limit, 50), 200));
$fn$;
revoke all on function public.storage_trash_due(int) from public, anon, authenticated;
grant execute on function public.storage_trash_due(int) to service_role;

-- 올리다 만 영상(글에 붙지 않은 채 하루 지난 것)도 지울 목록에 올린다
create or replace function public.video_uploads_orphans()
returns integer language plpgsql security definer set search_path to 'public' as $fn$
declare n int;
begin
  with o as (
    select vu.uid from public.video_uploads vu
     where vu.created_at < now() - interval '1 day'
       and not exists (select 1 from public.posts p where p.video->>'cf' = vu.uid)
       and not exists (select 1 from public.storage_trash t where t.bucket = 'cf' and t.path = vu.uid)
     limit 200)
  insert into public.storage_trash(bucket, path, reason) select 'cf', uid, 'orphan' from o on conflict (bucket, path) do nothing;
  get diagnostics n = row_count;
  return n;
end $fn$;
revoke all on function public.video_uploads_orphans() from public, anon, authenticated;
grant execute on function public.video_uploads_orphans() to service_role;
