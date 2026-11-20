-- 163. 도안 찾기: 맞는 앱 작가 한 줄 + 그 작가의 도안 + 도안마다 작품 사진 (2026-11-20 대표 확정 시안 cert_maker_suggest_v2 ② — 마이그레이션 source_suggest)
--   인증 › 도안 찾기에 글자를 적으면(예: "올드") 이름이 맞는 앱 작가·공방을 맨 위에 두 줄까지 보여 주고, 그 작가의 도안을 사진과 함께 보여 준다.
--   사진 = 그 도안으로 승인된 완성작품 가운데 좋아요가 가장 많은 작품의 첫 사진(같으면 최근 것). 숨긴 글·보관한 글·테스트 계정 작품(테스트 계정끼리만)은 뺀다.
--   작가의 다른 이름(work_maker_aliases — 본명이 들어갈 수 있음)은 끝까지 똑같이 적었을 때만 맞춘다(몇 글자로 본명 ↔ 닉네임을 알아낼 수 없게).
--   일반 도안 목록(work_source_search)에도 같은 사진(photo)을 더한다. 옛 화면은 photo 를 안 쓸 뿐 그대로 동작.

create or replace function public._src_photo(p_source uuid)
 returns text language sql stable security definer set search_path to 'public' as $f$
  select w.photos[1]
    from public.works w join public.profiles p on p.id = w.profile_id left join public.posts po on po.work_id = w.id and po.parent_id is null
   where w.source_id = p_source and w.review_status = 'approved' and array_length(w.photos, 1) > 0
     and not coalesce(po.hidden, false) and not coalesce(po.hidden_by_mod, false) and po.archived_at is null
     and (not coalesce(p.is_test, false) or coalesce((select is_test from public.profiles where id = auth.uid()), false))
   order by coalesce(po.like_count, 0) desc, w.created_at desc limit 1;
$f$;
revoke all on function public._src_photo(uuid) from public, anon, authenticated;

create or replace function public.work_source_search(p_kind text, p_q text, p_makers boolean default false)
 returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare toks text[]; r jsonb;
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  if p_kind not in ('pattern','video','class') then return '[]'::jsonb; end if;
  select coalesce(array_agg(x), '{}') into toks from (select public._src_norm(t) x from unnest(string_to_array(left(coalesce(p_q,''), 60), ' ')) t) s where x <> '';
  if array_length(toks, 1) is null then return '[]'::jsonb; end if;
  if p_makers then
    select coalesce(jsonb_agg(jsonb_build_object('maker', maker, 'n', n) order by n desc, maker), '[]'::jsonb) into r from (
      select min(s.maker) maker, count(w.id) n from public.work_sources s left join public.works w on w.source_id = s.id and w.review_status = 'approved'
      where s.kind = p_kind and s.status <> 'excluded' and s.merged_into is null and s.mnorm <> ''
        and not exists (select 1 from unnest(toks) k where position(k in s.mnorm) = 0)
      group by s.mnorm order by count(w.id) desc limit 5) m;
  else
    select coalesce(jsonb_agg(jsonb_build_object('id', id, 'maker', maker, 'title', title, 'n', n, 'photo', public._src_photo(id)) order by n desc, title), '[]'::jsonb) into r from (
      select s.id, s.maker, s.title, (select count(*) from public.works w where w.source_id = s.id and w.review_status = 'approved') n
      from public.work_sources s
      where s.kind = p_kind and s.status <> 'excluded' and s.merged_into is null
        and (not exists (select 1 from unnest(toks) k where position(k in s.mnorm || s.tnorm) = 0)
          or exists (select 1 from public.work_sources a where a.merged_into = s.id and not exists (select 1 from unnest(toks) k where position(k in a.mnorm || a.tnorm) = 0)))
      order by 4 desc, s.title limit 8) m;
  end if;
  return r;
end $function$;
revoke all on function public.work_source_search(text, text, boolean) from public, anon;
grant execute on function public.work_source_search(text, text, boolean) to authenticated;

-- 적은 글자와 맞는 앱 작가·공방(두 곳까지)과 그 작가의 도안(여덟 개까지)
create or replace function public.work_source_suggest(p_q text)
 returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare q text := left(btrim(coalesce(p_q, '')), 60); qn text; q1 text; r jsonb;
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  qn := public._src_norm(q); q1 := public._src_norm(split_part(q, ' ', 1));
  if length(qn) < 2 then return '[]'::jsonb; end if;
  with c as (   -- 닉네임·공방 이름: 앞에서부터 겹치면 / 다른 이름: 똑같이 적었을 때만
    select p.id pid, public._src_norm(split_part(p.nickname, '@', 1)) nn, false al
      from public.profiles p where coalesce(p.is_author, false) and not coalesce(p.is_test, false)
    union all
    select s.owner_id, public._src_norm(s.name), false
      from public.shops s left join public.profiles p on p.id = s.owner_id
     where s.owner_id is not null and coalesce(s.is_active, true) and not coalesce(p.is_test, false) and s.name not ilike '%테스트%'
    union all
    select a.profile_id, a.anorm, true from public.work_maker_aliases a
  ), m as (
    select pid, max(length(nn)) filter (where left(qn, length(nn)) = nn) cut, bool_or(nn = qn or nn = q1) exact
      from c
     where length(nn) >= 2 and ((not al and (left(nn, length(qn)) = qn or left(qn, length(nn)) = nn))
        or (al and (nn = qn or nn = q1 or nn = regexp_replace(qn, '(작가님|작가|선생님|쌤|님)$', ''))))
     group by pid
  )
  select coalesce(jsonb_agg(x.j order by x.exact desc, x.wn desc, x.nick), '[]'::jsonb) into r from (
    select m.exact, p.nickname nick,
      (select count(*) from public.works w join public.work_sources s on s.id = w.source_id where s.maker_profile = m.pid and w.review_status = 'approved') wn,
      jsonb_build_object('id', p.id, 'nickname', p.nickname, 'avatar_url', p.avatar_url, 'author', coalesce(p.is_author, false),
        'fill', btrim(split_part(p.nickname, '@', 1)),
        'sources', (select count(*) from public.work_sources s where s.maker_profile = m.pid and s.kind = 'pattern' and s.status <> 'excluded' and s.merged_into is null),
        'works', (select count(*) from public.works w join public.work_sources s on s.id = w.source_id where s.maker_profile = m.pid and w.review_status = 'approved'),
        'rows', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'maker', t.maker, 'title', t.title, 'n', t.n, 'photo', public._src_photo(t.id)) order by t.n desc, t.title) from (
            select s.id, s.maker, s.title, (select count(*) from public.works w where w.source_id = s.id and w.review_status = 'approved') n
              from public.work_sources s
             where s.maker_profile = m.pid and s.kind = 'pattern' and s.status <> 'excluded' and s.merged_into is null
               and (m.cut is null or length(qn) <= m.cut or position(substr(qn, m.cut + 1) in s.tnorm) > 0)
             order by 4 desc, s.title limit 8) t), '[]'::jsonb)) j
    from m join public.profiles p on p.id = m.pid
    order by m.exact desc, 3 desc, p.nickname limit 2) x;
  return r;
end $function$;
revoke all on function public.work_source_suggest(text) from public, anon;
grant execute on function public.work_source_suggest(text) to authenticated;
