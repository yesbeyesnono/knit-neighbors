-- 173. 탈퇴할 때 이유 묻기 (2026-11-27 대표 확정 시안 leave_reason_v2 — 마이그레이션 leave_reason)
--   계정 삭제 창이 두 단계가 됨: ① 떠나는 이유(고르기 하나, 건너뛸 수 있음) → ② 삭제 확인(지금 그대로).
--   새 앱은 request_account_deletion_v2(이유, 한 줄) 를 부른다. 옛 앱은 지금처럼 request_account_deletion() — 이유 없이.
--   이유는 account_deletions 에 적고(복구하면 그 줄과 함께 없어짐), 콘솔에는 누가 적었는지 없이 이유별 건수와 '기타'에 적힌 글만 보여 준다.

alter table public.account_deletions add column if not exists reason text check (reason in ('no_neighbors','little_content','hard_to_use','location','too_many_notif','break','other'));
alter table public.account_deletions add column if not exists reason_text text check (reason_text is null or char_length(reason_text) <= 100);

create or replace function public.request_account_deletion_v2(p_reason text default null, p_text text default null)
 returns timestamp with time zone language plpgsql security definer set search_path to 'public' as $function$
declare uid uuid := auth.uid(); v_until timestamptz; v_r text := nullif(btrim(coalesce(p_reason, '')), ''); v_t text := nullif(left(btrim(regexp_replace(coalesce(p_text, ''), '\s+', ' ', 'g')), 100), '');
begin
  if uid is null then raise exception '로그인이 필요해요'; end if;
  v_until := public.request_account_deletion();
  if v_r is not null and v_r not in ('no_neighbors','little_content','hard_to_use','location','too_many_notif','break','other') then v_r := null; end if;
  if v_r is distinct from 'other' then v_t := null; end if;
  -- 적은 글에 링크·연락처·금칙어가 있으면 글만 버린다(탈퇴를 막지 않는다)
  if v_t is not null and (v_t ~* '(https?:|www\.|\.com|\.kr|@|[0-9]{3,4}[- .]?[0-9]{4})' or public.contains_banned(v_t)) then v_t := null; end if;
  if v_r is not null then
    begin update public.account_deletions set reason = v_r, reason_text = v_t where user_id = uid and reason is null; exception when others then null; end;
  end if;
  return v_until;
end $function$;
revoke all on function public.request_account_deletion_v2(text, text) from public, anon;
grant execute on function public.request_account_deletion_v2(text, text) to authenticated;

-- 콘솔 › 회원: 탈퇴 이유 모아 보기(누가 적었는지는 내보내지 않는다)
create or replace function public.admin_leave_reasons(p_days int default 30)
 returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare d int := greatest(1, least(coalesce(p_days, 30), 365));
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  return (with a as (select a.reason, a.reason_text, a.requested_at from public.account_deletions a join public.profiles p on p.id = a.user_id
                     where a.requested_at > now() - make_interval(days => d) and not coalesce(p.is_test, false))
    select jsonb_build_object('days', d, 'total', (select count(*) from a), 'answered', (select count(*) from a where reason is not null),
      'counts', coalesce((select jsonb_object_agg(reason, n) from (select reason, count(*) n from a where reason is not null group by reason) x), '{}'::jsonb),
      'texts', coalesce((select jsonb_agg(reason_text order by requested_at desc) from a where reason_text is not null), '[]'::jsonb)));
end $function$;
revoke all on function public.admin_leave_reasons(int) from public, anon;
grant execute on function public.admin_leave_reasons(int) to authenticated;
