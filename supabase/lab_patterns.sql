-- 170. Lab 도안 미리 보기 (2026-11-26 대표 확정 시안 lab_pattern_preview_v1)
--   Studio 가 도안을 저장할 때마다 자동으로 올리고(연결 열쇠), Lab 앱에서 관리자 계정만 본다. 공개 도안 목록(patterns)과는 따로.
--   lab_patterns(도안 꾸러미) · lab_keys(연결 열쇠의 해시만) · lab_key_new(관리자: 열쇠 새로 만들기 — 한 번만 보여 줌, 옛 열쇠는 끊김)
--   lab_pattern_put(열쇠, id, 제목, 요약, 꾸러미) · lab_pattern_drop(열쇠, id) — Studio 가 로그인 없이 부름(열쇠가 맞을 때만)

create table if not exists public.lab_patterns (
  id text primary key check (char_length(id) between 1 and 60),
  title text not null check (char_length(title) between 1 and 120),
  meta jsonb not null default '{}'::jsonb,
  cover text,
  pkg jsonb not null,
  bytes integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.lab_patterns enable row level security;
revoke all on public.lab_patterns from public, anon, authenticated;
grant select, delete on public.lab_patterns to authenticated;
grant all on public.lab_patterns to service_role;
drop policy if exists lab_patterns_admin_select on public.lab_patterns;
create policy lab_patterns_admin_select on public.lab_patterns for select to authenticated using (public.is_admin());
drop policy if exists lab_patterns_admin_delete on public.lab_patterns;
create policy lab_patterns_admin_delete on public.lab_patterns for delete to authenticated using (public.is_admin());

create table if not exists public.lab_keys (
  id uuid primary key default gen_random_uuid(),
  key_hash text not null unique,
  created_by uuid,
  created_at timestamptz not null default now(),
  last_used_at timestamptz,
  revoked_at timestamptz
);
alter table public.lab_keys enable row level security;
revoke all on public.lab_keys from public, anon, authenticated;
grant all on public.lab_keys to service_role;

-- 관리자: 연결 열쇠 새로 만들기(값은 이때 한 번만 돌려주고 서버에는 해시만 남김). 전에 만든 열쇠는 끊는다
create or replace function public.lab_key_new()
returns text language plpgsql security definer set search_path = public as $$
declare k text;
begin
  if not public.is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  k := 'lab_' || replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  update public.lab_keys set revoked_at = now() where revoked_at is null;
  insert into public.lab_keys(key_hash, created_by) values (encode(sha256(convert_to(k, 'UTF8')), 'hex'), auth.uid());
  return k;
end $$;
revoke all on function public.lab_key_new() from public, anon;
grant execute on function public.lab_key_new() to authenticated, service_role;

-- 관리자: 열쇠 상태(있는지 · 마지막으로 쓰인 때)
create or replace function public.lab_key_info()
returns jsonb language plpgsql security definer set search_path = public as $$
declare r record;
begin
  if not public.is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  select created_at, last_used_at into r from public.lab_keys where revoked_at is null order by created_at desc limit 1;
  if not found then return jsonb_build_object('has', false); end if;
  return jsonb_build_object('has', true, 'created_at', r.created_at, 'last_used_at', r.last_used_at);
end $$;
revoke all on function public.lab_key_info() from public, anon;
grant execute on function public.lab_key_info() to authenticated, service_role;

create or replace function public._lab_key_ok(p_key text)
returns boolean language plpgsql security definer set search_path = public as $$
declare kid uuid;
begin
  if p_key is null or char_length(p_key) < 40 or char_length(p_key) > 100 then return false; end if;
  select id into kid from public.lab_keys where key_hash = encode(sha256(convert_to(p_key, 'UTF8')), 'hex') and revoked_at is null;
  if kid is null then return false; end if;
  update public.lab_keys set last_used_at = now() where id = kid;
  return true;
end $$;
revoke all on function public._lab_key_ok(text) from public, anon, authenticated;
grant execute on function public._lab_key_ok(text) to service_role;

-- Studio: 도안 올리기(같은 id 면 새것으로 바꿈). 꾸러미 4MB · 200개까지
create or replace function public.lab_pattern_put(p_key text, p_id text, p_title text, p_meta jsonb, p_pkg jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare n integer; cv text; m jsonb;
begin
  if not public._lab_key_ok(p_key) then raise exception 'bad key' using errcode = '42501'; end if;
  if p_id is null or p_id !~ '^[A-Za-z0-9_-]{1,60}$' then raise exception 'bad id' using errcode = 'P0001'; end if;
  if p_pkg is null or jsonb_typeof(p_pkg) <> 'object' or coalesce(p_pkg->>'app', '') <> 'knitup-pattern-package' then raise exception 'bad package' using errcode = 'P0001'; end if;
  n := octet_length(p_pkg::text);
  if n > 4 * 1024 * 1024 then raise exception 'too big' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.lab_patterns where id = p_id) and (select count(*) from public.lab_patterns) >= 200 then raise exception 'too many' using errcode = 'P0001'; end if;
  m := coalesce(p_meta, '{}'::jsonb);
  if jsonb_typeof(m) <> 'object' then m := '{}'::jsonb; end if;
  -- 목록의 작은 사진: Studio 가 보낸 작은 그림(meta.thumb) → 없으면 표지 첫 장
  cv := m->>'thumb';
  if cv is null then
    select b->'imgs'->>0 into cv from jsonb_array_elements(case when jsonb_typeof(p_pkg->'doc'->'blocks') = 'array' then p_pkg->'doc'->'blocks' else '[]'::jsonb end) b where b->>'type' = 'cover' limit 1;
  end if;
  if cv is not null and (cv !~ '^data:image/(jpeg|png|webp);base64,' or char_length(cv) > 400000) then cv := null; end if;
  m := m - 'thumb';
  if octet_length(m::text) > 20000 then m := '{}'::jsonb; end if;
  insert into public.lab_patterns(id, title, meta, cover, pkg, bytes)
    values (p_id, left(coalesce(nullif(btrim(p_title), ''), p_pkg->>'title', '이름 없는 도안'), 120), m, cv, p_pkg, n)
  on conflict (id) do update set title = excluded.title, meta = excluded.meta, cover = excluded.cover, pkg = excluded.pkg, bytes = excluded.bytes, updated_at = now();
  return jsonb_build_object('ok', true, 'id', p_id, 'bytes', n);
end $$;
revoke all on function public.lab_pattern_put(text, text, text, jsonb, jsonb) from public;
grant execute on function public.lab_pattern_put(text, text, text, jsonb, jsonb) to anon, authenticated, service_role;

-- Studio: 도안 지우기(Studio 에서 지웠을 때)
create or replace function public.lab_pattern_drop(p_key text, p_id text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public._lab_key_ok(p_key) then raise exception 'bad key' using errcode = '42501'; end if;
  delete from public.lab_patterns where id = p_id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.lab_pattern_drop(text, text) from public;
grant execute on function public.lab_pattern_drop(text, text) to anon, authenticated, service_role;
