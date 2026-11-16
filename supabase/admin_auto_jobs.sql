-- schema 136 (2026-11-16): 콘솔 '자동 메시지' 화면 — 예약 작업이 켜져 있는지·마지막으로 언제 돌았는지
create or replace function public.admin_auto_jobs() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('name', j.jobname, 'schedule', j.schedule, 'active', j.active, 'last_at', d.start_time, 'last_status', d.status) order by j.jobname), '[]'::jsonb) into r
    from cron.job j left join lateral (select x.start_time, x.status from cron.job_run_details x where x.jobid = j.jobid order by x.start_time desc limit 1) d on true;
  return r;
end $$;
revoke all on function public.admin_auto_jobs() from public, anon;
grant execute on function public.admin_auto_jobs() to authenticated;
