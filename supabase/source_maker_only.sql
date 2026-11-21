-- 166. 도안 찾기: 앱 작가를 누르면 그것으로 선택 끝 (2026-11-21 대표 확정 시안 cert_flow_v1 — 마이그레이션 source_maker_only)
--   "올드랭"처럼 앱에 있는 작가·공방이 나오면 그 줄을 누르는 것으로 선택이 끝난다(도안 이름은 알면 나중에 적음).
--   work_source_maker(p_kind, p_maker): 만든 곳만 있는 줄(title = '')을 만들거나 찾아 돌려준다. 앱 작가·공방과 이름이 맞을 때만(아무 이름으로나 빈 줄을 만들지 못하게).
--   이런 줄은 처음부터 'ok'(대표가 확인할 이름이 없음)이고, 도안 목록·AI 묶기의 견줄 대상에서는 뺀다.
create or replace function public.work_source_maker(p_kind text, p_maker text)
 returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_m text := left(btrim(regexp_replace(coalesce(p_maker,''), '\s+', ' ', 'g')), 40); mn text; s public.work_sources; f record;
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  if p_kind not in ('pattern','video','class') then raise exception '종류를 다시 골라 주세요'; end if;
  mn := public._src_norm(v_m);
  if length(mn) < 2 then raise exception '이름을 두 글자 이상 적어 주세요'; end if;
  select * into f from public._src_maker_find(mn);
  if f.o_profile is null then raise exception '도안 이름도 함께 적어 주세요'; end if;
  select * into s from public.work_sources where kind = p_kind and mnorm = mn and tnorm = '';
  if s.id is not null then
    if s.merged_into is not null then select * into s from public.work_sources where id = s.merged_into; end if;
    if s.id is null or s.status = 'excluded' then raise exception '쓸 수 없는 이름이에요. 다르게 적어 주세요'; end if;
    return jsonb_build_object('id', s.id, 'maker', s.maker, 'title', s.title);
  end if;
  insert into public.work_sources(kind, maker, title, mnorm, tnorm, status, decided_at, created_by) values (p_kind, v_m, '', mn, '', 'ok', now(), auth.uid()) returning * into s;
  return jsonb_build_object('id', s.id, 'maker', s.maker, 'title', s.title);
end $function$;
revoke all on function public.work_source_maker(text, text) from public, anon;
grant execute on function public.work_source_maker(text, text) to authenticated;

-- AI 묶기: 이름 없는 줄은 견줄 대상에서 뺀다(같은 작가의 다른 도안이 여기로 묶이지 않게)
create or replace function public.source_ai_pending(p_limit int default 4)
 returns jsonb language sql stable security definer set search_path to 'public' as $function$
  select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
    select s.id, s.kind, s.maker, s.title,
      (select coalesce(jsonb_agg(u), '[]'::jsonb) from (select unnest(w.photos[1:2]) u from public.works w where w.source_id = s.id and array_length(w.photos, 1) > 0 order by w.created_at desc limit 2) p) photos,
      (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'maker', o.maker, 'title', o.title,
          'alias', (select coalesce(jsonb_agg(btrim(a.maker || ' ' || a.title)), '[]'::jsonb) from public.work_sources a where a.merged_into = o.id))), '[]'::jsonb)
        from (select * from public.work_sources o where o.kind = s.kind and o.id <> s.id and o.merged_into is null and o.status <> 'excluded' and o.tnorm <> ''
                and (o.status = 'ok' or o.created_at < s.created_at or (o.created_at = s.created_at and o.id < s.id))
              order by (o.status = 'ok') desc, o.created_at desc limit 300) o) targets
    from public.work_sources s
    where s.status = 'candidate' and s.merged_into is null and s.ai_at is null and s.tnorm <> '' and s.created_at < now() - interval '2 minutes'
      and exists (select 1 from public.works w where w.source_id = s.id and array_length(w.photos, 1) > 0)
    order by s.created_at limit greatest(1, least(coalesce(p_limit, 4), 10))) x;
$function$;
revoke all on function public.source_ai_pending(int) from public, anon, authenticated;
grant execute on function public.source_ai_pending(int) to service_role;

-- 도안 찾기 목록(163)에서 이름 없는 줄을 뺀다
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
      where s.kind = p_kind and s.status <> 'excluded' and s.merged_into is null and s.tnorm <> ''
        and (not exists (select 1 from unnest(toks) k where position(k in s.mnorm || s.tnorm) = 0)
          or exists (select 1 from public.work_sources a where a.merged_into = s.id and not exists (select 1 from unnest(toks) k where position(k in a.mnorm || a.tnorm) = 0)))
      order by 4 desc, s.title limit 8) m;
  end if;
  return r;
end $function$;
revoke all on function public.work_source_search(text, text, boolean) from public, anon;
grant execute on function public.work_source_search(text, text, boolean) to authenticated;

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
        'sources', (select count(*) from public.work_sources s where s.maker_profile = m.pid and s.kind = 'pattern' and s.status <> 'excluded' and s.merged_into is null and s.tnorm <> ''),
        'works', (select count(*) from public.works w join public.work_sources s on s.id = w.source_id where s.maker_profile = m.pid and w.review_status = 'approved'),
        'rows', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'maker', t.maker, 'title', t.title, 'n', t.n, 'photo', public._src_photo(t.id)) order by t.n desc, t.title) from (
            select s.id, s.maker, s.title, (select count(*) from public.works w where w.source_id = s.id and w.review_status = 'approved') n
              from public.work_sources s
             where s.maker_profile = m.pid and s.kind = 'pattern' and s.status <> 'excluded' and s.merged_into is null and s.tnorm <> ''
               and (m.cut is null or length(qn) <= m.cut or position(substr(qn, m.cut + 1) in s.tnorm) > 0)
             order by 4 desc, s.title limit 8) t), '[]'::jsonb)) j
    from m join public.profiles p on p.id = m.pid
    order by m.exact desc, 3 desc, p.nickname limit 2) x;
  return r;
end $function$;
revoke all on function public.work_source_suggest(text) from public, anon;
grant execute on function public.work_source_suggest(text) to authenticated;
