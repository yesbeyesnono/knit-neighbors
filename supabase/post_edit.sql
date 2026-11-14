-- schema 110 (2026-11-14) 글·작품 인증 수정
-- 회원이 올린 글을 고칠 수 있게. posts/works 에는 회원용 UPDATE 정책이 없으므로 함수로만 고친다.
-- 고칠 수 없는 것: 댓글, 모임 안내 글(모임 화면에서), 이벤트 인증·#뜨친인증으로 접수된 글(심사한 내용이 바뀌지 않게).
-- 작품 인증의 기법은 추가만(빼기 불가 — 뜨개 단계·레벨 계산이 흔들리지 않게). 실·바늘은 이번에는 고치지 않음.
alter table public.posts add column if not exists edited_at timestamptz;

create or replace function public._post_photo_ok(p_new text[], p_old text[]) returns boolean
language sql immutable set search_path to 'public' as $$
  select not exists (select 1 from unnest(coalesce(p_new,'{}')) u
    where not (u = any(coalesce(p_old,'{}')))
      and u !~ '^https://(api\.knitup\.co\.kr|thfcrodfaitzrzlrxyir\.supabase\.co)/storage/v1/object/public/[A-Za-z0-9/_.%-]+$');
$$;
revoke all on function public._post_photo_ok(text[], text[]) from public, anon, authenticated;

create or replace function public.edit_post(p_post uuid, p_body text, p_photos text[], p_mentions uuid[] default null)
returns void language plpgsql security definer set search_path to 'public' as $$
declare r public.posts; v_body text := nullif(btrim(coalesce(p_body,'')),''); v_photos text[] := coalesce(p_photos,'{}'); v_until timestamptz;
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  if not public.is_active_user() then raise exception '지금은 글을 고칠 수 없어요'; end if;
  select post_restricted_until into v_until from public.profiles where id = auth.uid();
  if v_until is not null and v_until > now() then raise exception '글쓰기가 제한된 동안에는 고칠 수 없어요'; end if;
  select * into r from public.posts where id = p_post and author_id = auth.uid() for update;
  if not found then raise exception '내 글만 고칠 수 있어요'; end if;
  if r.parent_id is not null then raise exception '댓글은 고칠 수 없어요'; end if;
  if r.meetup_id is not null then raise exception '모임 글은 모임 화면에서 고쳐 주세요'; end if;
  if r.work_id is not null then raise exception '작품 인증은 작품 인증 수정에서 고쳐 주세요'; end if;
  if exists (select 1 from public.ddeuchin_claims c where c.post_id = p_post) then raise exception '이벤트에 접수된 글은 고칠 수 없어요'; end if;
  if cardinality(v_photos) > 4 then raise exception '사진은 4장까지예요'; end if;
  if v_body is null and cardinality(v_photos) = 0 then raise exception '내용이나 사진을 넣어 주세요'; end if;
  if not public._post_photo_ok(v_photos, r.photos) then raise exception '사진을 다시 올려 주세요'; end if;
  update public.posts set body = v_body, photos = v_photos,
      mentions = case when p_mentions is null then mentions else array(select distinct m from unnest(p_mentions) m where m is not null limit 20) end,
      edited_at = now(), mod_scanned_at = null
    where id = p_post;
  begin perform public.jigi_call('scan'); exception when others then null; end;
end $$;
revoke all on function public.edit_post(uuid, text, text[], uuid[]) from public, anon;
grant execute on function public.edit_post(uuid, text, text[], uuid[]) to authenticated;

create or replace function public.edit_work(p_post uuid, p_title text, p_note text, p_photos text[], p_add_techniques text[] default '{}', p_add_custom text[] default '{}')
returns void language plpgsql security definer set search_path to 'public' as $$
declare r public.posts; w public.works; v_title text := nullif(btrim(coalesce(p_title,'')),''); v_note text := nullif(btrim(coalesce(p_note,'')),'');
  v_photos text[] := coalesce(p_photos,'{}'); v_known text[]; v_custom text[]; v_until timestamptz;
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  if not public.is_active_user() then raise exception '지금은 글을 고칠 수 없어요'; end if;
  select post_restricted_until into v_until from public.profiles where id = auth.uid();
  if v_until is not null and v_until > now() then raise exception '글쓰기가 제한된 동안에는 고칠 수 없어요'; end if;
  select * into r from public.posts where id = p_post and author_id = auth.uid() for update;
  if not found or r.work_id is null then raise exception '내 작품 인증만 고칠 수 있어요'; end if;
  select * into w from public.works where id = r.work_id and profile_id = auth.uid() for update;
  if not found then raise exception '내 작품 인증만 고칠 수 있어요'; end if;
  if w.event_id is not null or exists (select 1 from public.ddeuchin_claims c where c.post_id = p_post) then raise exception '이벤트에 접수된 글은 고칠 수 없어요'; end if;
  if v_title is null then raise exception '작품 이름을 적어 주세요'; end if;
  if cardinality(v_photos) = 0 then raise exception '작품 사진이 필요해요'; end if;
  if cardinality(v_photos) > 4 then raise exception '사진은 4장까지예요'; end if;
  if not public._post_photo_ok(v_photos, r.photos || coalesce(w.photos,'{}')) then raise exception '사진을 다시 올려 주세요'; end if;
  v_custom := array(select distinct x from (select unnest(coalesce(w.custom_techniques,'{}')) x union all
               select left(btrim(x),30) from unnest(coalesce(p_add_custom,'{}')) x where btrim(x) <> '') q limit 20);
  if public.contains_banned(v_title) or public.contains_banned(array_to_string(v_custom,' ')) then raise exception '커뮤니티 가이드라인에 맞지 않는 표현이 있어요'; end if;
  -- 기법: 이미 넣은 것은 그대로 두고, 새로 고른 것만 더한다
  v_known := array(select t.id from public.techniques t where t.id = any(coalesce(w.techniques,'{}') || coalesce(p_add_techniques,'{}')) order by t.sort);
  update public.works set title = v_title, note = v_note, photos = v_photos, photo_url = v_photos[1], techniques = v_known, custom_techniques = v_custom where id = w.id;
  update public.posts set body = coalesce(v_note, v_title), photos = v_photos, edited_at = now(), mod_scanned_at = null where id = p_post;
  begin perform public.jigi_call('scan'); exception when others then null; end;
end $$;
revoke all on function public.edit_work(uuid, text, text, text[], text[], text[]) from public, anon;
grant execute on function public.edit_work(uuid, text, text, text[], text[], text[]) to authenticated;
