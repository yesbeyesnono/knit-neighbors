-- 154. 기법이 추가돼도 뜨개 단계가 내려가지 않게 (2026-11-19 대표 결정 1번 — 마이그레이션 tech_extra)
--   배경: 새 기법 3개(걸러뜨기·아이코드·방안뜨기)를 넣으면 '한 단계 기법의 절반 이상' 기준이 올라가 회원 71명의 단계가 내려감
--   규칙: 나중에 추가하는 기법은 techniques.extra = true 로 넣는다. 추가 기법은 체크하면 '한 것'으로 세지만, 단계 기준(절반)의 모수에는 넣지 않는다
--         → 기법을 추가해도 누구의 단계도 내려가지 않고, 추가 기법을 체크하면 단계에 보탬이 된다
--   lv_stats 의 total = 기준이 되는 기법 수(추가 기법 제외), done = 체크한 수(추가 기법 포함, total 까지만)
--   지금은 extra 인 기법이 없어 결과가 그대로다. 앱은 다음 스토어 버전(1.0.10 빌드)부터 같은 규칙(lvStats). 새 기법 등록은 그 버전이 스토어에 나온 뒤에
alter table public.techniques add column if not exists extra boolean not null default false;
comment on column public.techniques.extra is '나중에 추가한 기법 — 체크하면 한 것으로 세지만 단계 기준(절반)의 모수에는 넣지 않는다';

create or replace function public.compute_skill_level(p_skills text[], p_craft text)
 returns smallint
 language sql
 immutable
 set search_path to 'public'
as $function$
  select coalesce(max(level), 0)::smallint from (
    select t.level, count(*) filter (where t.id = any(p_skills)) as done, count(*) filter (where not t.extra) as total
    from public.techniques t where t.craft = p_craft and not t.hidden
    group by t.level
  ) s where total > 0 and done * 2 >= total;
$function$;

create or replace function public.lv_stats(p_user uuid, p_craft text)
 returns table(level integer, total integer, done integer)
 language sql
 stable
 set search_path to 'public'
as $function$
  select t.level::int, (count(*) filter (where not t.extra))::int,
         least(count(*) filter (where t.id = any(coalesce(p.skills, '{}'))), count(*) filter (where not t.extra))::int
  from public.techniques t cross join (select skills from public.profiles where id = p_user) p
  where t.craft = p_craft and not coalesce(t.hidden, false) group by t.level order by t.level;
$function$;
