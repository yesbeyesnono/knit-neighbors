-- 148. 판단 기록에 '지기가 제안한 처리' 칸 (2026-11-19 대표: 인증 확인 창에서 말로 시키면 지기가 처리 방법과 글을 제안 → 대표가 확인하고 실행)
--   work_reviews.ai_action: 지기 AI 가 제안한 처리(fix·reject·approve). 실제로 한 처리는 action — 둘이 다르면 대표가 제안을 고친 것
--   raw_note 에는 대표가 지기에게 적은 말이 그대로 들어간다(자동 집행을 만들 때의 재료)
alter table public.work_reviews add column if not exists ai_action text;

create or replace function public.admin_work_review_meta(p_review bigint, p_meta jsonb) returns boolean
language plpgsql security definer set search_path to 'public' as $$
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  update public.work_reviews set
      raw_note  = nullif(left(btrim(coalesce(p_meta->>'raw','')), 800), ''),
      reason    = nullif(left(btrim(coalesce(p_meta->>'reason','')), 40), ''),
      ai_used   = coalesce((p_meta->>'ai')::boolean, false),
      ai_action = case when p_meta->>'ai_action' in ('fix','reject','approve') then p_meta->>'ai_action' end
    where id = p_review and admin_id = auth.uid() and created_at > now() - interval '10 minutes';
  return found;
end $$;
revoke all on function public.admin_work_review_meta(bigint, jsonb) from public, anon;
grant execute on function public.admin_work_review_meta(bigint, jsonb) to authenticated, service_role;
