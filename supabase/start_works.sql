-- 146. 앱 시작 카드에 회원의 완성작품 (2026-11-19 대표 확정 시안 start_works_v4)
-- 승인된 완성작품 인증을 앱 시작 카드(지금 공지 카드 틀)에서 소개한다. 카드 전체가 사진, 왼쪽 위에 닉네임.
-- 승인한 날과 다음 날 이틀 동안 돈다. 하루 12건까지(넘으면 다음 날 0시로), 같은 회원은 7일에 한 번. 올라간 회원에게 알림 한 번.
-- 끄기: 대표 = 콘솔 승인 화면의 '앱 첫 화면에 소개하기' 체크(works.feature) · 회원 = 마이 › 설정(profiles.feature_off)
-- 어떤 작품을 이미 봤는지는 기기에 적는다(공지와 같은 방식). 서버는 그날의 묶음만 준다.

alter table public.profiles add column if not exists feature_off boolean not null default false;
grant update (feature_off) on public.profiles to authenticated;
alter table public.works add column if not exists feature boolean not null default true;
alter table public.works add column if not exists featured_at timestamptz;
create index if not exists works_featured_at on public.works (featured_at) where featured_at is not null;

-- 승인되는 순간: 첫 화면 소개를 정하고 회원에게 알린다
create or replace function public.works_feature_on_approve()
returns trigger language plpgsql security definer set search_path to 'public' as $fn$
declare
  pr record; v_post uuid; v_at timestamptz; cnt int; d date := (now() at time zone 'Asia/Seoul')::date;
  sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e';
begin
  if new.review_status <> 'approved' or old.review_status not in ('pending','fix') or not new.feature or new.featured_at is not null then return null; end if;
  select p.deleted_at, p.suspended_at, p.feature_off into pr from public.profiles p where p.id = new.profile_id;
  if not found or pr.deleted_at is not null or pr.suspended_at is not null or pr.feature_off then return null; end if;
  if coalesce(new.photos[1], '') = '' then return null; end if;
  -- 같은 회원은 7일에 한 번
  if exists (select 1 from public.works w where w.profile_id = new.profile_id and w.id <> new.id and w.featured_at > now() - interval '7 days') then return null; end if;
  select id into v_post from public.posts where work_id = new.id and parent_id is null order by created_at limit 1;
  if v_post is null then return null; end if;
  -- 하루 12건까지. 넘으면 다음 날 0시(한국 시간)부터
  select count(*) into cnt from public.works w where w.featured_at is not null and (w.featured_at at time zone 'Asia/Seoul')::date = d;
  v_at := case when cnt >= 12 then ((d + 1)::timestamp at time zone 'Asia/Seoul') else now() end;
  update public.works set featured_at = v_at where id = new.id;
  insert into public.notifications(recipient_id, actor_id, kind, post_id, snippet, link)
    values (new.profile_id, sup, 'notice', v_post,
      left(case when cnt >= 12 then '내일의 완성작품에 올랐어요 🎉 ' else '오늘의 완성작품에 올랐어요 🎉 ' end
           || coalesce('「' || nullif(btrim(new.title), '') || '」 — ', '') || '앱 첫 화면에서 이웃들에게 소개돼요.', 300),
      jsonb_build_object('type', 'post', 'id', v_post));
  return null;
end $fn$;
revoke all on function public.works_feature_on_approve() from public, anon, authenticated;
drop trigger if exists works_feature_on_approve on public.works;
create trigger works_feature_on_approve after update of review_status on public.works
  for each row execute function public.works_feature_on_approve();

-- 콘솔: 승인하기 전에 '앱 첫 화면에 소개하기'를 끄거나 켠다
create or replace function public.admin_work_feature(p_work uuid, p_on boolean)
returns boolean language plpgsql security definer set search_path to 'public' as $fn$
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  update public.works set feature = coalesce(p_on, true) where id = p_work and review_status in ('pending','fix');
  return found;
end $fn$;
revoke all on function public.admin_work_feature(uuid, boolean) from public, anon;
grant execute on function public.admin_work_feature(uuid, boolean) to authenticated;

-- 앱: 지금 소개 중인 작품 묶음(승인한 날 + 다음 날). 3건이 안 되면 최근 7일에서 채운다
create or replace function public.start_works()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare me uuid := auth.uid(); mt boolean; d date := (now() at time zone 'Asia/Seoul')::date; res jsonb;
begin
  if me is null then return '[]'::jsonb; end if;
  select is_test into mt from public.profiles where id = me;
  if mt is null then return '[]'::jsonb; end if;
  with base as (
    select w.id, po.id as post, coalesce(w.photos[1], po.photos[1]) as photo, p.nickname, p.avatar_url, w.profile_id, w.featured_at,
           ((w.featured_at at time zone 'Asia/Seoul')::date >= d - 1) as fresh
      from public.works w
      join public.profiles p on p.id = w.profile_id
      join public.posts po on po.work_id = w.id and po.parent_id is null
     where w.featured_at is not null and w.featured_at <= now() and w.featured_at > now() - interval '7 days'
       and w.review_status = 'approved' and w.feature
       and not po.hidden and not coalesce(po.hidden_by_mod, false) and po.archived_at is null
       and p.deleted_at is null and p.suspended_at is null and not p.feature_off and p.is_test = mt
       and coalesce(w.photos[1], po.photos[1]) is not null
       and not exists (select 1 from public.friendships f where f.status = 'blocked'
                        and ((f.requester_id = me and f.addressee_id = w.profile_id) or (f.requester_id = w.profile_id and f.addressee_id = me)))
  ), pick as (
    (select * from base where fresh order by featured_at desc limit 12)
    union all
    (select * from base where not fresh order by featured_at desc
      limit greatest(0, 3 - (select count(*) from base where fresh)::int))
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'post', post, 'photo', photo, 'nickname', nickname, 'avatar_url', avatar_url, 'mine', profile_id = me) order by featured_at desc), '[]'::jsonb)
    into res from pick;
  return res;
end $fn$;
revoke all on function public.start_works() from public, anon;
grant execute on function public.start_works() to authenticated;
