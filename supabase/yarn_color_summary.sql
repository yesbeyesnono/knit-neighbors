-- 141. 콘솔 › 실 사전 빠르게 열기 (2026-11-17 대표 지시: 실 데이터 불러오기가 너무 오래 걸림)
--   색이 3만 개를 넘어 콘솔이 색 전체를 1,000줄씩 33번 받아 오던 것을, 실마다 색 수·사진 수·첫 사진과 계열별 개수만 서버에서 세어 한 번에 돌려준다
--   admin_yarn_color_summary(): 관리자만. { tot, photos, fam_n, fam:[[계열,개수]...], per:[{c,n,p,f}...] }  (c=catalog_id, n=색 수, p=사진 있는 색 수, f=첫 사진)
--   색 전체 목록은 콘솔의 '색상' 탭을 열 때만 받는다
create or replace function public.admin_yarn_color_summary() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out jsonb;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  select jsonb_build_object(
    'tot', (select count(*) from public.yarn_colors),
    'photos', (select count(*) from public.yarn_colors where photo is not null),
    'fam_n', (select count(*) from public.yarn_colors where family is not null),
    'fam', coalesce((select jsonb_agg(jsonb_build_array(family, n) order by n desc) from (select family, count(*) n from public.yarn_colors where family is not null group by family) f), '[]'::jsonb),
    'per', coalesce((select jsonb_agg(jsonb_build_object('c', catalog_id, 'n', n, 'p', p, 'f', f)) from (
        select catalog_id, count(*) n, count(photo) p, (array_agg(photo order by id) filter (where photo is not null))[1] f
        from public.yarn_colors group by catalog_id) x), '[]'::jsonb)
  ) into out;
  return out;
end $$;
revoke all on function public.admin_yarn_color_summary() from public, anon;
grant execute on function public.admin_yarn_color_summary() to authenticated, service_role;
