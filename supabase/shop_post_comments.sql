-- schema 138 (2026-11-16 대표 확정 시안 activity_shopnews_v1): 가게 소식에 댓글·좋아요
-- 댓글은 '소식' 글에만(클래스 글은 신청 → 채팅방), 글만(사진 없음), 300자, 링크·계좌번호 금지. 쓰기는 함수로만.
-- 댓글이 달리면 가게 주인에게, 가게 주인이 댓글을 쓰면 그 글에 댓글을 쓴 분들에게 알림(notice, 누르면 가게 화면).
alter table public.shop_posts add column if not exists like_count integer not null default 0;
alter table public.shop_posts add column if not exists comment_count integer not null default 0;

create table if not exists public.shop_post_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.shop_posts(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 300),
  created_at timestamptz not null default now()
);
create index if not exists shop_post_comments_post_idx on public.shop_post_comments (post_id, created_at);
alter table public.shop_post_comments enable row level security;
revoke all on public.shop_post_comments from anon, authenticated;
grant select, delete on public.shop_post_comments to authenticated;
grant all on public.shop_post_comments to service_role;
drop policy if exists shop_post_comments_select on public.shop_post_comments;
create policy shop_post_comments_select on public.shop_post_comments for select to authenticated using (
  not public.is_blocked((select auth.uid()), author_id) and exists (select 1 from public.shop_posts sp where sp.id = post_id));
drop policy if exists shop_post_comments_delete on public.shop_post_comments;
create policy shop_post_comments_delete on public.shop_post_comments for delete to authenticated using (
  author_id = (select auth.uid()) or public.is_admin()
  or exists (select 1 from public.shop_posts sp left join public.shops s on s.id = sp.shop_id where sp.id = post_id and (s.owner_id = (select auth.uid()) or (sp.shop_id is null and sp.author_id = (select auth.uid())))));

create table if not exists public.shop_post_likes (
  post_id uuid not null references public.shop_posts(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, profile_id)
);
alter table public.shop_post_likes enable row level security;
revoke all on public.shop_post_likes from anon, authenticated;
grant select on public.shop_post_likes to authenticated;
grant all on public.shop_post_likes to service_role;
drop policy if exists shop_post_likes_select_own on public.shop_post_likes;
create policy shop_post_likes_select_own on public.shop_post_likes for select to authenticated using (profile_id = (select auth.uid()));

-- 개수는 서버가 센다
create or replace function public.shop_post_counts() returns trigger
language plpgsql security definer set search_path = public as $$
declare pid uuid := coalesce(new.post_id, old.post_id);
begin
  if tg_table_name = 'shop_post_comments' then
    update public.shop_posts set comment_count = (select count(*) from public.shop_post_comments c where c.post_id = pid) where id = pid;
  else
    update public.shop_posts set like_count = (select count(*) from public.shop_post_likes l where l.post_id = pid) where id = pid;
  end if;
  return null;
end $$;
revoke all on function public.shop_post_counts() from public, anon, authenticated;
drop trigger if exists shop_post_comments_count on public.shop_post_comments;
create trigger shop_post_comments_count after insert or delete on public.shop_post_comments for each row execute function public.shop_post_counts();
drop trigger if exists shop_post_likes_count on public.shop_post_likes;
create trigger shop_post_likes_count after insert or delete on public.shop_post_likes for each row execute function public.shop_post_counts();

create or replace function public.shop_post_comment(p_post uuid, p_body text) returns uuid
language plpgsql security definer set search_path = public as $$
declare sp public.shop_posts; v_owner uuid; v_shop text; v_nick text; v_body text := btrim(coalesce(p_body, '')); v_id uuid; v_until timestamptz; r record;
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  if not public.is_active_user() then raise exception '지금은 댓글을 쓸 수 없어요'; end if;
  select post_restricted_until into v_until from public.profiles where id = auth.uid();
  if v_until is not null and v_until > now() then raise exception '글쓰기가 제한된 동안에는 댓글을 쓸 수 없어요'; end if;
  select * into sp from public.shop_posts where id = p_post and not hidden;
  if not found then raise exception '소식을 찾을 수 없어요'; end if;
  if sp.kind = 'class' then raise exception '클래스 문의는 신청한 뒤 채팅방에서 해 주세요'; end if;
  if char_length(v_body) < 1 or char_length(v_body) > 300 then raise exception '댓글은 300자까지 쓸 수 있어요'; end if;
  if v_body ~* '(https?://|www\.|[a-z0-9-]+\.(com|co\.kr|kr|net|io|me|shop)(/|\s|$))' or v_body ~ '[0-9]{2,6}[- ][0-9]{2,6}[- ][0-9]{2,8}' then raise exception '댓글에는 링크나 계좌번호를 넣을 수 없어요'; end if;
  if public.contains_banned(v_body) then raise exception '커뮤니티 가이드라인에 맞지 않는 표현이 있어요'; end if;
  if (select count(*) from public.shop_post_comments where author_id = auth.uid() and created_at > now() - interval '1 day') >= 40 then raise exception '오늘은 댓글을 더 쓸 수 없어요. 내일 다시 해 주세요'; end if;
  select s.owner_id, s.name into v_owner, v_shop from public.shops s where s.id = sp.shop_id;
  v_owner := coalesce(v_owner, sp.author_id);
  if v_owner is not null and public.is_blocked(auth.uid(), v_owner) then raise exception '댓글을 쓸 수 없어요'; end if;
  insert into public.shop_post_comments(post_id, author_id, body) values (p_post, auth.uid(), v_body) returning id into v_id;
  select coalesce(nullif(btrim(nickname), ''), '이웃') into v_nick from public.profiles where id = auth.uid();
  if auth.uid() <> v_owner then
    insert into public.notifications(recipient_id, actor_id, kind, snippet, shop_id, link)
      values (v_owner, auth.uid(), 'notice', left(v_nick||' 님이 「'||sp.title||'」 소식에 댓글을 남겼어요: '||v_body, 200), sp.shop_id,
              case when sp.shop_id is not null then jsonb_build_object('type','shop','id', sp.shop_id) else jsonb_build_object('type','view','view','my') end);
  else
    for r in select distinct c.author_id from public.shop_post_comments c where c.post_id = p_post and c.author_id <> v_owner
               and not public.is_blocked(c.author_id, v_owner) limit 50 loop
      insert into public.notifications(recipient_id, actor_id, kind, snippet, shop_id, link)
        values (r.author_id, v_owner, 'notice', left(coalesce(v_shop, v_nick)||'에서 「'||sp.title||'」 소식에 댓글을 남겼어요: '||v_body, 200), sp.shop_id,
                case when sp.shop_id is not null then jsonb_build_object('type','shop','id', sp.shop_id) else jsonb_build_object('type','profile','id', v_owner) end);
    end loop;
  end if;
  return v_id;
end $$;
revoke all on function public.shop_post_comment(uuid, text) from public, anon;
grant execute on function public.shop_post_comment(uuid, text) to authenticated;

create or replace function public.shop_post_like(p_post uuid, p_on boolean) returns integer
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  if not public.is_active_user() then raise exception '지금은 할 수 없어요'; end if;
  if not exists (select 1 from public.shop_posts where id = p_post and not hidden) then raise exception '소식을 찾을 수 없어요'; end if;
  if coalesce(p_on, true) then insert into public.shop_post_likes(post_id, profile_id) values (p_post, auth.uid()) on conflict do nothing;
  else delete from public.shop_post_likes where post_id = p_post and profile_id = auth.uid(); end if;
  return (select like_count from public.shop_posts where id = p_post);
end $$;
revoke all on function public.shop_post_like(uuid, boolean) from public, anon;
grant execute on function public.shop_post_like(uuid, boolean) to authenticated;
