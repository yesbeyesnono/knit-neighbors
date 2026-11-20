-- 161. 도안의 '만든 곳'을 앱 작가·공방과 자동으로 잇기 (2026-11-20 대표 지시 — 마이그레이션 source_maker)
--   회원이 인증에서 만든 곳을 "올드랭"처럼 적기만 해도, 앱에 있는 작가(profiles.is_author)·공방(shops)과 이름이 맞으면 서버가 그 계정과 묶어 둔다.
--   앱 화면은 바뀌지 않는다(목록에 앱 작가를 따로 보여 주지 않음 — 대표: 많아질 테니). 묶어 두기만 하고, 작가 화면에 모아 보여 주는 것은 다음 단계.
--   맞는 기준: 공백·기호를 뺀 이름이 같거나, 세 글자 이상이 앞에서부터 겹칠 때(예: "민이네" ↔ "민이네 코바늘 작업소"). 닉네임의 '@아이디' 뒤는 보지 않는다.
--   맞는 계정이 둘 이상이면 묶지 않는다. 작가가 새로 지정되거나 닉네임·공방 이름이 바뀌면 다시 맞춘다.
--   대표가 콘솔 › 도안 후보에서 [끊기]한 것은 자동이 다시 묶지 않는다(maker_fixed).

alter table public.work_sources add column if not exists maker_profile uuid references public.profiles(id) on delete set null;   -- 앱 작가(또는 공방 주인)
alter table public.work_sources add column if not exists maker_shop uuid references public.shops(id) on delete set null;         -- 공방 이름으로 맞았을 때
alter table public.work_sources add column if not exists maker_fixed boolean not null default false;                            -- 대표가 손으로 끊은 것
create index if not exists work_sources_maker_profile on public.work_sources(maker_profile) where maker_profile is not null;

create or replace function public._src_maker_find(p_mn text, out o_profile uuid, out o_shop uuid)
 language plpgsql stable security definer set search_path to 'public' as $fn$
declare n int;
begin
  if coalesce(p_mn, '') = '' or length(p_mn) < 2 then return; end if;
  with c as (
    select p.id pid, null::uuid sid, public._src_norm(split_part(p.nickname, '@', 1)) nn
      from public.profiles p where coalesce(p.is_author, false) and not coalesce(p.is_test, false)
    union all
    select s.owner_id, s.id, public._src_norm(s.name)
      from public.shops s left join public.profiles p on p.id = s.owner_id
     where coalesce(s.is_active, true) and not coalesce(p.is_test, false) and s.name not ilike '%테스트%'
  ), m as (
    select pid, sid, (nn = p_mn) exact from c
     where length(nn) >= 2 and (nn = p_mn or (length(p_mn) >= 3 and left(nn, length(p_mn)) = p_mn) or (length(nn) >= 3 and left(p_mn, length(nn)) = nn))
  ), k as (
    select * from m where exact or not exists (select 1 from m where exact)
  )
  select count(distinct coalesce(pid::text, sid::text)), (array_agg(pid) filter (where pid is not null))[1], (array_agg(sid) filter (where sid is not null))[1]
    into n, o_profile, o_shop from k;
  if n is distinct from 1 then o_profile := null; o_shop := null; end if;
end $fn$;
revoke all on function public._src_maker_find(text) from public, anon, authenticated;

-- 새로 적히거나 만든 곳 이름이 바뀔 때
create or replace function public.work_source_maker_trg()
 returns trigger language plpgsql security definer set search_path to 'public' as $fn$
begin
  if not new.maker_fixed then
    select o_profile, o_shop into new.maker_profile, new.maker_shop from public._src_maker_find(new.mnorm);
  end if;
  return new;
end $fn$;
revoke all on function public.work_source_maker_trg() from public, anon, authenticated;
drop trigger if exists work_sources_maker on public.work_sources;
create trigger work_sources_maker before insert or update of mnorm, maker_fixed on public.work_sources
  for each row execute function public.work_source_maker_trg();

-- 작가 지정·닉네임·공방 이름이 바뀌면 전부 다시 맞춘다(손으로 끊은 것은 그대로)
create or replace function public.work_source_relink()
 returns int language plpgsql security definer set search_path to 'public' as $fn$
declare n int;
begin
  update public.work_sources s set maker_profile = f.o_profile, maker_shop = f.o_shop
    from (select id, (public._src_maker_find(mnorm)).* from public.work_sources where not maker_fixed) f
   where s.id = f.id and (s.maker_profile is distinct from f.o_profile or s.maker_shop is distinct from f.o_shop);
  get diagnostics n = row_count;
  return n;
end $fn$;
revoke all on function public.work_source_relink() from public, anon, authenticated;
grant execute on function public.work_source_relink() to service_role;

create or replace function public.work_source_relink_trg()
 returns trigger language plpgsql security definer set search_path to 'public' as $fn$
begin
  perform public.work_source_relink();
  return null;
end $fn$;
revoke all on function public.work_source_relink_trg() from public, anon, authenticated;
drop trigger if exists profiles_source_relink on public.profiles;
create trigger profiles_source_relink after update of is_author, nickname on public.profiles
  for each row when ((coalesce(new.is_author, false) or coalesce(old.is_author, false))
                     and (new.is_author is distinct from old.is_author or new.nickname is distinct from old.nickname))
  execute function public.work_source_relink_trg();
drop trigger if exists shops_source_relink on public.shops;
create trigger shops_source_relink after insert or update of name, is_active on public.shops
  for each row execute function public.work_source_relink_trg();

-- 콘솔 › 도안 후보: 어느 앱 작가·공방과 묶였는지
create or replace function public.admin_source_makers()
 returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  return coalesce((select jsonb_object_agg(s.id, jsonb_build_object('profile', s.maker_profile, 'fixed', s.maker_fixed,
      'nick', (select nickname from public.profiles p where p.id = s.maker_profile),
      'shop', (select name from public.shops h where h.id = s.maker_shop)))
    from public.work_sources s where s.maker_profile is not null or s.maker_shop is not null or s.maker_fixed), '{}'::jsonb);
end $fn$;
revoke all on function public.admin_source_makers() from public, anon;
grant execute on function public.admin_source_makers() to authenticated;

-- [끊기] = 묶음을 풀고 자동이 다시 묶지 않게 · [다시 맞추기] = 자동에 맡김
create or replace function public.admin_source_maker_set(p_id uuid, p_off boolean)
 returns text language plpgsql security definer set search_path to 'public' as $fn$
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  if p_off then
    update public.work_sources set maker_profile = null, maker_shop = null, maker_fixed = true where id = p_id;
  else
    update public.work_sources set maker_fixed = false where id = p_id;   -- 트리거가 다시 맞춘다
  end if;
  if not found then raise exception '찾을 수 없어요'; end if;
  perform public.admin_log('source_maker', 'work_source', p_id::text, jsonb_build_object('off', p_off));
  return case when p_off then 'off' else 'auto' end;
end $fn$;
revoke all on function public.admin_source_maker_set(uuid, boolean) from public, anon;
grant execute on function public.admin_source_maker_set(uuid, boolean) to authenticated;

select public.work_source_relink();
