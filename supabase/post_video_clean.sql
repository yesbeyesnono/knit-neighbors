-- 151. 글의 영상: 지울 때 파일도 지우기 · 글 고치기에서 영상 바꾸기 (2026-11-19 대표 지시)
-- 글이 지워지거나 영상이 바뀌면 옛 영상 파일과 첫 장면 사진을 '지울 파일' 목록(storage_trash)에 적고,
-- 매시 10분에 Edge Function jigi-remind 의 sweep 이 Storage API 로 실제 파일을 지운다(SQL 로는 파일을 지울 수 없어서).
-- 실수로 지워지지 않게 목록에 오른 지 10분이 지난 것만, 지금 어떤 글에서도 쓰지 않는 파일만 지운다.

create table if not exists public.storage_trash (
  id         bigint generated always as identity primary key,
  bucket     text not null,
  path       text not null,
  reason     text,
  created_at timestamptz not null default now(),
  done_at    timestamptz,
  tries      int not null default 0,
  unique (bucket, path)
);
alter table public.storage_trash enable row level security;
revoke all on public.storage_trash from anon, authenticated;
grant all on public.storage_trash to service_role;

create or replace function public.posts_video_trash()
returns trigger language plpgsql security definer set search_path to 'public' as $fn$
declare u text; ps text;
begin
  if old.video is null then return null; end if;
  if tg_op = 'UPDATE' and new.video is not distinct from old.video then return null; end if;
  u := old.video->>'url'; ps := old.video->>'poster';
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
drop trigger if exists posts_video_trash on public.posts;
create trigger posts_video_trash after delete or update of video on public.posts
  for each row execute function public.posts_video_trash();

-- sweep 이 부른다: 지울 파일 목록(10분 지난 것, 지금 어떤 글에서도 쓰지 않는 것)
create or replace function public.storage_trash_due(p_limit int default 50)
returns table (id bigint, bucket text, path text) language sql security definer set search_path to 'public' as $fn$
  select t.id, t.bucket, t.path from public.storage_trash t
   where t.done_at is null and t.tries < 5 and t.created_at < now() - interval '10 minutes'
     and not exists (select 1 from public.posts p where p.video is not null
                       and (p.video->>'url' like '%/' || t.bucket || '/' || t.path or p.video->>'poster' like '%/' || t.bucket || '/' || t.path))
     and not exists (select 1 from public.posts p where t.bucket = 'posts' and p.photos is not null
                       and exists (select 1 from unnest(p.photos) ph where ph like '%/posts/' || t.path)
                       and (p.video is null or p.video->>'poster' not like '%/posts/' || t.path))
   order by t.id limit greatest(1, least(coalesce(p_limit, 50), 200));
$fn$;
revoke all on function public.storage_trash_due(int) from public, anon, authenticated;
grant execute on function public.storage_trash_due(int) to service_role;

-- 글 고치기: 내 일반 글의 영상을 바꾸거나(새 영상) 뺀다(null). 주소·길이는 posts_video_guard 가 확인
create or replace function public.post_video_set(p_post uuid, p_video jsonb)
returns boolean language plpgsql security definer set search_path to 'public' as $fn$
declare me uuid := auth.uid(); po public.posts;
begin
  if me is null then raise exception '로그인이 필요해요'; end if;
  select * into po from public.posts where id = p_post;
  if po.id is null or po.author_id <> me then raise exception '내 글만 고칠 수 있어요'; end if;
  if po.parent_id is not null or po.meetup_id is not null or po.work_id is not null or po.review_of is not null then
    raise exception '영상은 일반 글에만 올릴 수 있어요'; end if;
  update public.posts set video = case when p_video is null or jsonb_typeof(p_video) = 'null' then null else p_video end where id = p_post;
  return true;
end $fn$;
revoke all on function public.post_video_set(uuid, jsonb) from public, anon;
grant execute on function public.post_video_set(uuid, jsonb) to authenticated;

select cron.schedule('storage-sweep', '10 * * * *', $$select public.jigi_remind_call('sweep')$$);
