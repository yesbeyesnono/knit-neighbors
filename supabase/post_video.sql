-- 150. 일반 글에 짧은 영상 (2026-11-19 대표 확정 시안 post_video_v1 · A안: 30초까지 한 개, 지금 저장소에 그대로)
-- 영상 파일은 새 보관함 videos(공개, 50MB, mp4·mov·webm)에, 첫 장면 사진은 지금처럼 posts 에. 글에는 posts.video = {url, poster, dur, w, h}.
-- 옛 앱은 video 를 모르므로 첫 장면 사진(photos 의 첫 장)만 보인다. 댓글·모임 글·완성작품 인증에는 넣지 않는다(일반 글만).

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('videos', 'videos', true, 52428800, array['video/mp4','video/quicktime','video/webm'])
on conflict (id) do nothing;

drop policy if exists storage_videos_read on storage.objects;
create policy storage_videos_read on storage.objects for select using (bucket_id = 'videos');
drop policy if exists storage_videos_insert_own on storage.objects;
create policy storage_videos_insert_own on storage.objects for insert to authenticated
  with check (bucket_id = 'videos' and (storage.foldername(name))[1] = ((select auth.uid()))::text);
drop policy if exists storage_videos_delete_own on storage.objects;
create policy storage_videos_delete_own on storage.objects for delete to authenticated
  using (bucket_id = 'videos' and (storage.foldername(name))[1] = ((select auth.uid()))::text);

alter table public.posts add column if not exists video jsonb;

-- 글에 붙는 영상 정보는 서버가 확인한다: 내 폴더의 우리 저장소 주소만 · 30초까지 · 일반 글만 · 하루 10개까지
create or replace function public.posts_video_guard()
returns trigger language plpgsql security definer set search_path to 'public' as $fn$
declare u text; ps text; d numeric;
begin
  if new.video is null then return new; end if;
  if tg_op = 'UPDATE' and new.video is not distinct from old.video then return new; end if;
  if jsonb_typeof(new.video) <> 'object' then raise exception '영상 정보가 올바르지 않아요'; end if;
  if new.parent_id is not null or new.meetup_id is not null or new.work_id is not null or new.review_of is not null then
    raise exception '영상은 일반 글에만 올릴 수 있어요'; end if;
  u := new.video->>'url'; ps := new.video->>'poster';
  if u is null or u !~ ('^https://api\.knitup\.co\.kr/storage/v1/object/public/videos/' || new.author_id::text || '/[A-Za-z0-9._-]+\.(mp4|mov|webm)$') then
    raise exception '영상 주소가 올바르지 않아요'; end if;
  if ps is not null and ps !~ ('^https://api\.knitup\.co\.kr/storage/v1/object/public/posts/' || new.author_id::text || '/[A-Za-z0-9._-]+\.jpg$') then
    raise exception '영상 첫 장면 주소가 올바르지 않아요'; end if;
  begin d := (new.video->>'dur')::numeric; exception when others then d := null; end;
  if d is null or d <= 0 or d > 31 then raise exception '영상은 30초까지 올릴 수 있어요'; end if;
  if (select count(*) from public.posts p where p.author_id = new.author_id and p.video is not null and p.created_at > now() - interval '1 day') >= 10 then
    raise exception '영상은 하루에 10개까지 올릴 수 있어요'; end if;
  -- 정해진 칸만 남긴다
  new.video := jsonb_strip_nulls(jsonb_build_object('url', u, 'poster', ps, 'dur', round(d, 1),
                 'w', nullif(greatest(0, least(8000, coalesce((new.video->>'w')::int, 0))), 0),
                 'h', nullif(greatest(0, least(8000, coalesce((new.video->>'h')::int, 0))), 0)));
  return new;
end $fn$;
revoke all on function public.posts_video_guard() from public, anon, authenticated;
drop trigger if exists posts_video_guard on public.posts;
create trigger posts_video_guard before insert or update of video on public.posts
  for each row execute function public.posts_video_guard();
