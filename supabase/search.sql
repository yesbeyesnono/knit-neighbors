-- 165. 검색 — 글 + 회원 (2026-11-21 대표 확정 시안 search_v1 — 마이그레이션 search)
--   홈 맨 윗줄의 돋보기 → 검색 화면. 글은 본문과 #태그에서, 회원은 닉네임에서 찾는다(두 글자부터).
--   search_posts: 호출한 회원의 권한으로 읽는다(SECURITY DEFINER 아님 → posts 의 RLS 그대로: 숨긴 글·정지 회원·테스트 계정 글은 안 나옴). 개수와 글 id 만 돌려주고, 글은 앱이 읽는다.
--   search_members: 닉네임으로. 테스트 계정(테스트 계정끼리만)·정지·삭제 유예·가입 미완료는 뺀다. 내보내는 것은 프로필에 이미 보이는 것뿐(닉네임·사진·동네 이름·단계·작가 여부).
create or replace function public.search_posts(p_q text, p_before timestamptz default null, p_limit int default 20)
 returns jsonb language plpgsql stable set search_path to 'public' as $function$
declare q text := left(btrim(regexp_replace(coalesce(p_q, ''), '\s+', ' ', 'g')), 40); pat text; tg text; v_n int; v_ids jsonb;
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  if length(replace(q, ' ', '')) < 2 then return jsonb_build_object('n', 0, 'ids', '[]'::jsonb); end if;
  pat := '%' || replace(replace(replace(q, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  tg := lower(regexp_replace(q, '[^가-힣a-zA-Z0-9_]', '', 'g'));
  select count(*) into v_n from public.posts po
   where po.parent_id is null and not coalesce(po.hidden, false) and po.archived_at is null
     and (po.body ilike pat or (tg <> '' and po.tags @> array[tg]));
  select coalesce(jsonb_agg(y.id order by y.created_at desc), '[]'::jsonb) into v_ids from (
    select po.id, po.created_at from public.posts po
     where po.parent_id is null and not coalesce(po.hidden, false) and po.archived_at is null
       and (po.body ilike pat or (tg <> '' and po.tags @> array[tg]))
       and (p_before is null or po.created_at < p_before)
     order by po.created_at desc limit least(greatest(coalesce(p_limit, 20), 1), 30)) y;
  return jsonb_build_object('n', v_n, 'ids', v_ids);
end $function$;
revoke all on function public.search_posts(text, timestamptz, int) from public, anon;
grant execute on function public.search_posts(text, timestamptz, int) to authenticated;

create or replace function public.search_members(p_q text, p_limit int default 3)
 returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare q text := left(btrim(regexp_replace(coalesce(p_q, ''), '\s+', ' ', 'g')), 30); pat text; v_test boolean; v_n int; v_rows jsonb;
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  if length(replace(q, ' ', '')) < 2 then return jsonb_build_object('n', 0, 'rows', '[]'::jsonb); end if;
  pat := '%' || replace(replace(replace(q, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  select coalesce(is_test, false) into v_test from public.profiles where id = auth.uid();
  select count(*) into v_n from public.profiles p
   where p.nickname ilike pat and p.onboarded_at is not null and p.suspended_at is null and p.deleted_at is null and (not coalesce(p.is_test, false) or v_test);
  select coalesce(jsonb_agg(to_jsonb(x) order by x.pre desc, x.cert_count desc, x.nickname), '[]'::jsonb) into v_rows from (
    select p.id, p.nickname, p.avatar_url, p.dong_name, p.level_crochet, p.level_knit, coalesce(p.is_author, false) is_author,
           coalesce(p.cert_count, 0) cert_count, (lower(p.nickname) like lower(q) || '%') pre
      from public.profiles p
     where p.nickname ilike pat and p.onboarded_at is not null and p.suspended_at is null and p.deleted_at is null and (not coalesce(p.is_test, false) or v_test)
     order by (lower(p.nickname) like lower(q) || '%') desc, coalesce(p.cert_count, 0) desc, p.nickname
     limit least(greatest(coalesce(p_limit, 3), 1), 30)) x;
  return jsonb_build_object('n', v_n, 'rows', v_rows);
end $function$;
revoke all on function public.search_members(text, int) from public, anon;
grant execute on function public.search_members(text, int) to authenticated;
