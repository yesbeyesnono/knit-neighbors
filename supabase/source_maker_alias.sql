-- 162. 만든 곳 ↔ 앱 작가: 다른 이름(별칭) · '같아 보여요'는 대표 확인 (2026-11-20 대표 지시 — 마이그레이션 source_maker_alias)
--   한 작가를 여러 이름으로 적는다(브랜드 이름 · 풀어 쓴 이름 · 본명 + '작가'). 작가마다 '다른 이름'을 두고 모두 같은 계정으로 묶는다.
--   끝의 '작가 · 작가님 · 선생님 · 쌤 · 님'은 떼고 견준다.
--   확실하지 않은 것(두 글자만 겹침 · 이름 가운데에 들어 있음)은 묶지 않고 콘솔에 '같아 보여요'로만(maker_guess) → 대표가 [맞아요]/[아니에요].
--   [맞아요] · 손으로 잇기를 하면 그 표기가 그 작가의 다른 이름으로 들어가, 다음부터는 자동으로 묶인다.
--   다른 이름에는 본명이 들어갈 수 있으므로 표는 회원에게 열지 않는다(관리자 함수로만).

create table if not exists public.work_maker_aliases (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  alias text not null,
  anorm text not null unique,
  created_at timestamptz not null default now()
);
alter table public.work_maker_aliases enable row level security;
revoke all on public.work_maker_aliases from anon, authenticated;
grant all on public.work_maker_aliases to service_role;
comment on table public.work_maker_aliases is '앱 작가·공방의 다른 이름(도안 만든 곳 맞추기용) — 본명이 들어갈 수 있어 관리자 함수로만 읽고 쓴다';

alter table public.work_sources add column if not exists maker_guess uuid references public.profiles(id) on delete set null;   -- 같아 보이지만 확인이 필요한 작가

drop function if exists public._src_maker_find(text);
create function public._src_maker_find(p_mn text, out o_profile uuid, out o_shop uuid, out o_guess uuid)
 language plpgsql stable security definer set search_path to 'public' as $fn$
declare n int; gn int; mn text := coalesce(p_mn, ''); m2 text;
begin
  m2 := regexp_replace(mn, '(작가님|작가|선생님|쌤|님)$', '');
  if length(m2) >= 2 then mn := m2; end if;
  if length(mn) < 2 then return; end if;
  with c as (
    select * from (
      select p.id pid, null::uuid sid, public._src_norm(split_part(p.nickname, '@', 1)) nn
        from public.profiles p where coalesce(p.is_author, false) and not coalesce(p.is_test, false)
      union all
      select s.owner_id, s.id, public._src_norm(s.name)
        from public.shops s left join public.profiles p on p.id = s.owner_id
       where coalesce(s.is_active, true) and not coalesce(p.is_test, false) and s.name not ilike '%테스트%'
      union all
      select a.profile_id, null::uuid, a.anorm from public.work_maker_aliases a) x where length(nn) >= 2
  ), m as (   -- 확실: 같거나, 세 글자 이상이 앞에서부터 겹침
    select pid, sid, (nn = mn) exact from c
     where nn = mn or (length(mn) >= 3 and left(nn, length(mn)) = mn) or (length(nn) >= 3 and left(mn, length(nn)) = nn)
  ), k as (select * from m where exact or not exists (select 1 from m where exact)
  ), sure as (
    select count(distinct coalesce(pid::text, sid::text)) n, (array_agg(pid) filter (where pid is not null))[1] p, (array_agg(sid) filter (where sid is not null))[1] s from k
  ), g as (   -- 확인 필요: 두 글자만 앞에서 겹치거나, 세 글자 이상이 이름 가운데에 들어 있음
    select count(distinct pid) n, (array_agg(pid))[1] p from c
     where pid is not null and (left(nn, length(mn)) = mn or left(mn, length(nn)) = nn
        or (length(mn) >= 3 and position(mn in nn) > 0) or (length(nn) >= 3 and position(nn in mn) > 0))
  )
  select sure.n, sure.p, sure.s, g.n, g.p into n, o_profile, o_shop, gn, o_guess from sure, g;
  if n = 1 then o_guess := null; return; end if;
  o_profile := null; o_shop := null;
  if n > 1 or gn is distinct from 1 then o_guess := null; end if;
end $fn$;
revoke all on function public._src_maker_find(text) from public, anon, authenticated;

create or replace function public.work_source_maker_trg()
 returns trigger language plpgsql security definer set search_path to 'public' as $fn$
begin
  if not new.maker_fixed then
    select o_profile, o_shop, o_guess into new.maker_profile, new.maker_shop, new.maker_guess from public._src_maker_find(new.mnorm);
  else
    new.maker_guess := null;
  end if;
  return new;
end $fn$;
revoke all on function public.work_source_maker_trg() from public, anon, authenticated;

create or replace function public.work_source_relink()
 returns int language plpgsql security definer set search_path to 'public' as $fn$
declare n int := 0; r record; f record;
begin
  for r in select id, mnorm, maker_profile, maker_shop, maker_guess from public.work_sources where not maker_fixed loop
    select * into f from public._src_maker_find(r.mnorm);
    if r.maker_profile is distinct from f.o_profile or r.maker_shop is distinct from f.o_shop or r.maker_guess is distinct from f.o_guess then
      update public.work_sources set maker_profile = f.o_profile, maker_shop = f.o_shop, maker_guess = f.o_guess where id = r.id;
      n := n + 1;
    end if;
  end loop;
  return n;
end $fn$;
revoke all on function public.work_source_relink() from public, anon, authenticated;
grant execute on function public.work_source_relink() to service_role;

-- 콘솔 › 도안 후보: 묶인 곳 · 같아 보이는 곳 · 고를 수 있는 작가·공방 · 다른 이름 목록
drop function if exists public.admin_source_makers();
create function public.admin_source_makers()
 returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  return jsonb_build_object(
    'rows', coalesce((select jsonb_object_agg(s.id, jsonb_build_object('profile', s.maker_profile, 'fixed', s.maker_fixed, 'guess', s.maker_guess,
        'nick', (select nickname from public.profiles p where p.id = s.maker_profile),
        'shop', (select name from public.shops h where h.id = s.maker_shop),
        'guess_nick', (select nickname from public.profiles p where p.id = s.maker_guess)))
      from public.work_sources s where s.maker_profile is not null or s.maker_guess is not null or s.maker_fixed), '{}'::jsonb),
    'makers', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name) order by name) from (
        select p.id, p.nickname name from public.profiles p where coalesce(p.is_author, false) and not coalesce(p.is_test, false)
        union select s.owner_id, s.name from public.shops s left join public.profiles p on p.id = s.owner_id
          where s.owner_id is not null and coalesce(s.is_active, true) and not coalesce(p.is_test, false) and s.name not ilike '%테스트%'
            and not coalesce(p.is_author, false)) x), '[]'::jsonb),
    'aliases', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'alias', a.alias, 'profile', a.profile_id,
        'nick', (select nickname from public.profiles p where p.id = a.profile_id)) order by a.created_at desc) from public.work_maker_aliases a), '[]'::jsonb));
end $fn$;
revoke all on function public.admin_source_makers() from public, anon;
grant execute on function public.admin_source_makers() to authenticated;

-- 다른 이름 넣기(p_profile 이 null 이면 지우기). 넣거나 지운 뒤 전부 다시 맞춘다
create or replace function public.admin_maker_alias(p_profile uuid, p_alias text)
 returns int language plpgsql security definer set search_path to 'public' as $fn$
declare v text := left(btrim(regexp_replace(coalesce(p_alias, ''), '\s+', ' ', 'g')), 40); an text;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  an := regexp_replace(public._src_norm(v), '(작가님|작가|선생님|쌤|님)$', '');
  if length(an) < 2 then an := public._src_norm(v); end if;
  if length(an) < 2 then raise exception '이름을 두 글자 이상 적어 주세요'; end if;
  if p_profile is null then
    delete from public.work_maker_aliases where anorm = an;
  else
    if not exists (select 1 from public.profiles where id = p_profile) then raise exception '회원을 찾을 수 없어요'; end if;
    insert into public.work_maker_aliases(profile_id, alias, anorm) values (p_profile, v, an)
      on conflict (anorm) do update set profile_id = excluded.profile_id, alias = excluded.alias;
  end if;
  perform public.admin_log('maker_alias', 'profile', coalesce(p_profile::text, ''), jsonb_build_object('alias', v, 'remove', p_profile is null));
  return public.work_source_relink();
end $fn$;
revoke all on function public.admin_maker_alias(uuid, text) from public, anon;
grant execute on function public.admin_maker_alias(uuid, text) to authenticated;

-- 도안 후보 한 줄을 작가와 잇기([맞아요] · 손으로 고르기): 그 표기를 작가의 다른 이름으로 넣는다 → 같은 표기는 모두 묶인다
create or replace function public.admin_source_maker_link(p_id uuid, p_profile uuid)
 returns int language plpgsql security definer set search_path to 'public' as $fn$
declare s public.work_sources;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  select * into s from public.work_sources where id = p_id;
  if s.id is null then raise exception '찾을 수 없어요'; end if;
  if coalesce(s.mnorm, '') = '' then raise exception '만든 곳이 비어 있어요'; end if;
  update public.work_sources set maker_fixed = false where id = p_id and maker_fixed;
  return public.admin_maker_alias(p_profile, s.maker);
end $fn$;
revoke all on function public.admin_source_maker_link(uuid, uuid) from public, anon;
grant execute on function public.admin_source_maker_link(uuid, uuid) to authenticated;

select public.work_source_relink();
