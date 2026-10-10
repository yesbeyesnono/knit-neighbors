-- ---------------------------------------------------------------
-- knitup Studio → 뜨개동네 앱(네이티브·다른 기기) 도안 전달함 — 2026-10-11 마이그레이션 `studio_inbox` 로 **적용됨**
--   흐름: 앱 마이 › 내 도안 › [Studio 에서 가져오기] → studio_claim_code()(로그인) 6자리 코드(10분) → Studio [뜨개동네에 등록] › 앱으로 보내기에 코드 입력
--         → studio_submit(code, title, meta, pkg)(anon, 코드·형식·3MB 검사) → 앱 [받았는지 확인] 또는 로그인 때 studio_inbox_take()(본인, 7일 이내 1건, 돌려주고 삭제)
--         → localStorage kn_studio_handoff 로 옮겨 웹과 같은 studioImportCheck → 등록 폼 자동 채움
--   테이블 studio_inbox: RLS 본인 select/delete, anon 직접 접근 없음(함수로만). 권한 점검: P1 other inbox 0 · P4 anon select blocked · studio_submit 잘못된 코드 false
-- ---------------------------------------------------------------
create table if not exists public.studio_inbox (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  code text not null,
  title text,
  meta jsonb,
  pkg jsonb,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '10 minutes',
  claimed_at timestamptz
);
create index if not exists studio_inbox_code_idx on public.studio_inbox(code) where pkg is null;
create index if not exists studio_inbox_profile_idx on public.studio_inbox(profile_id);
alter table public.studio_inbox enable row level security;
drop policy if exists studio_inbox_owner_select on public.studio_inbox;
create policy studio_inbox_owner_select on public.studio_inbox for select to authenticated using (profile_id = auth.uid());
drop policy if exists studio_inbox_owner_delete on public.studio_inbox;
create policy studio_inbox_owner_delete on public.studio_inbox for delete to authenticated using (profile_id = auth.uid());
revoke all on table public.studio_inbox from public, anon;
grant select, delete on table public.studio_inbox to authenticated;
grant all on table public.studio_inbox to service_role;

create or replace function public.studio_claim_code()
returns text language plpgsql security definer set search_path to 'public' as $$
declare c text; uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  delete from public.studio_inbox where expires_at < now() - interval '1 day';
  delete from public.studio_inbox where profile_id = uid and pkg is null;
  loop
    c := lpad((floor(random()*1000000))::int::text, 6, '0');
    exit when not exists (select 1 from public.studio_inbox where code = c and pkg is null and expires_at > now());
  end loop;
  insert into public.studio_inbox(profile_id, code) values (uid, c);
  return c;
end $$;

create or replace function public.studio_submit(p_code text, p_title text, p_meta jsonb, p_pkg jsonb)
returns boolean language plpgsql security definer set search_path to 'public' as $$
declare rid uuid;
begin
  if p_code !~ '^[0-9]{6}$' then return false; end if;
  if p_pkg is null or jsonb_typeof(p_pkg) <> 'object' or coalesce(p_pkg->>'app','') <> 'knitup-pattern-package' or jsonb_typeof(p_pkg->'charts') <> 'array' or jsonb_array_length(p_pkg->'charts') = 0 then return false; end if;
  if length(p_pkg::text) > 3*1024*1024 then return false; end if;
  select id into rid from public.studio_inbox where code = p_code and pkg is null and expires_at > now() order by created_at desc limit 1;
  if rid is null then return false; end if;
  update public.studio_inbox set title = left(coalesce(p_title,''), 80), meta = p_meta, pkg = p_pkg, claimed_at = now() where id = rid;
  return true;
end $$;

create or replace function public.studio_inbox_take()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r record; uid uuid := auth.uid();
begin
  if uid is null then return null; end if;
  select * into r from public.studio_inbox where profile_id = uid and pkg is not null and claimed_at > now() - interval '7 days' order by claimed_at desc limit 1;
  if r.id is null then return null; end if;
  delete from public.studio_inbox where id = r.id;
  return jsonb_build_object('title', r.title, 'meta', r.meta, 'pkg', r.pkg, 'at', r.claimed_at);
end $$;

revoke all on function public.studio_claim_code() from public;
revoke all on function public.studio_submit(text, text, jsonb, jsonb) from public;
revoke all on function public.studio_inbox_take() from public;
grant execute on function public.studio_claim_code() to authenticated, service_role;
grant execute on function public.studio_submit(text, text, jsonb, jsonb) to anon, authenticated, service_role;
grant execute on function public.studio_inbox_take() to authenticated, service_role;
