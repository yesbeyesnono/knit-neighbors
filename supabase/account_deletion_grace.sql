-- 77. 계정 삭제 유예 20일 (마이그레이션 account_deletion_grace, 2026-11-04 대표 지시)
--   삭제 요청 → 다른 회원에게 안 보이게(글 숨김·지도 핀 끔·친구 관계 보관 후 제거) + profiles.deleted_at
--   → 20일 안에 같은 계정으로 로그인하면 restore_my_account() 로 그대로 복구
--   → 20일 지나면 크론 account-purge → Edge Function jigi-remind(route purge) 가 Storage 파일 정리 + auth.users 삭제(cascade)
alter table public.profiles add column if not exists deleted_at timestamptz;

create table if not exists public.account_deletions(
  user_id uuid primary key references auth.users(id) on delete cascade,
  requested_at timestamptz not null default now(),
  purge_after timestamptz not null,
  hidden_post_ids uuid[] not null default '{}',
  friendships jsonb not null default '[]',
  was_visible boolean not null default false,
  wave_until timestamptz,
  purged_at timestamptz
);
alter table public.account_deletions enable row level security;
revoke all on public.account_deletions from anon, authenticated;
grant select on public.account_deletions to authenticated;
grant all on public.account_deletions to service_role;
drop policy if exists account_deletions_own on public.account_deletions;
create policy account_deletions_own on public.account_deletions for select to authenticated using (user_id = auth.uid());

create or replace function public.request_account_deletion() returns timestamptz
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_ids uuid[]; v_fr jsonb; v_vis boolean; v_wave timestamptz; v_until timestamptz := now() + interval '20 days';
begin
  if uid is null then raise exception '로그인이 필요해요'; end if;
  if exists (select 1 from public.account_deletions where user_id = uid) then
    return (select purge_after from public.account_deletions where user_id = uid);
  end if;
  select coalesce(array_agg(id), '{}') into v_ids from public.posts where author_id = uid and coalesce(hidden, false) = false;
  update public.posts set hidden = true where id = any(v_ids);
  select coalesce(jsonb_agg(to_jsonb(f)), '[]') into v_fr from public.friendships f where f.requester_id = uid or f.addressee_id = uid;
  delete from public.friendships where requester_id = uid or addressee_id = uid;
  select is_visible, wave_until into v_vis, v_wave from public.profiles where id = uid;
  update public.profiles set deleted_at = now(), is_visible = false, wave_until = null where id = uid;
  insert into public.account_deletions(user_id, purge_after, hidden_post_ids, friendships, was_visible, wave_until)
    values (uid, v_until, v_ids, v_fr, coalesce(v_vis, false), v_wave);
  return v_until;
end $$;
revoke all on function public.request_account_deletion() from public, anon;
grant execute on function public.request_account_deletion() to authenticated;

create or replace function public.restore_my_account() returns boolean
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r public.account_deletions;
begin
  if uid is null then raise exception '로그인이 필요해요'; end if;
  select * into r from public.account_deletions where user_id = uid;
  if not found then update public.profiles set deleted_at = null where id = uid; return false; end if;
  update public.posts set hidden = false where id = any(r.hidden_post_ids) and author_id = uid;
  insert into public.friendships select * from jsonb_populate_recordset(null::public.friendships, r.friendships) on conflict do nothing;
  update public.profiles set deleted_at = null, is_visible = r.was_visible, wave_until = r.wave_until where id = uid;
  delete from public.account_deletions where user_id = uid;
  return true;
end $$;
revoke all on function public.restore_my_account() from public, anon;
grant execute on function public.restore_my_account() to authenticated;

-- 매일 03:30 KST: 유예가 끝난 계정이 있을 때만 Edge Function 호출
select cron.unschedule('account-purge') where exists (select 1 from cron.job where jobname = 'account-purge');
select cron.schedule('account-purge', '30 18 * * *',
  $$select public.jigi_remind_call('purge') where exists (select 1 from public.account_deletions where purged_at is null and purge_after <= now())$$);
