-- 157. 완성작품 인증 — "어떻게 뜬 작품인가요?" (2026-11-20 대표 확정 시안 cert_pattern_v3 · v4 B안 — 마이그레이션 work_source)
--   인증의 뜨개 이야기 맨 위에서 도안 · 영상 · 수업 · 창작 중 하나를 고른다(선택). 도안·영상·수업은 '만든 곳(브랜드·채널·가르친 곳) + 이름' 한 쌍으로
--   work_sources 에 모으고(같은 표기는 한 줄), 새로 적힌 것은 후보(candidate) → 대표가 콘솔 › 도안 후보에서 확인 · 합치기 · 제외
--   이번에는 '묻고 모으기'까지. 글에 도안 줄을 보여 주고 도안별로 모아 보는 화면은 도안이 쌓인 뒤(다음 단계)
--   옛 앱은 work_set_story 에 how 를 보내지 않으므로 아무것도 바뀌지 않는다

create table if not exists public.work_sources (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('pattern','video','class')),
  maker text not null default '',          -- 브랜드(작가) · 채널 · 가르친 곳
  title text not null,                     -- 도안 이름 · 영상에서 뜬 작품 · 배운 작품
  mnorm text not null default '',          -- 비교용: 공백·기호를 뺀 소문자
  tnorm text not null,
  status text not null default 'candidate' check (status in ('candidate','ok','excluded')),
  merged_into uuid references public.work_sources(id) on delete set null,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  decided_at timestamptz
);
create unique index if not exists work_sources_key on public.work_sources(kind, mnorm, tnorm);
alter table public.work_sources enable row level security;
revoke all on public.work_sources from anon, authenticated;
grant all on public.work_sources to service_role;
comment on table public.work_sources is '완성작품을 무엇을 보고 떴는지(도안·영상·수업) 사전 — 읽기·쓰기는 함수로만(work_source_search · work_source_add · admin_source_*)';

alter table public.works add column if not exists made_how text check (made_how in ('pattern','video','class','original'));
alter table public.works add column if not exists source_id uuid references public.work_sources(id) on delete set null;
alter table public.works add column if not exists source_note text;
create index if not exists works_source_id on public.works(source_id) where source_id is not null;

create or replace function public._src_norm(t text) returns text language sql immutable set search_path to 'public' as $f$
  select regexp_replace(lower(coalesce(t,'')), '[^0-9a-z가-힣]', '', 'g');
$f$;
revoke all on function public._src_norm(text) from public, anon, authenticated;

-- 찾기: 적은 낱말이 모두 들어 있는 것(만든 곳 + 이름). p_makers = true 면 만든 곳 이름만(영상 채널 · 가르친 곳 추천)
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
    select coalesce(jsonb_agg(jsonb_build_object('id', id, 'maker', maker, 'title', title, 'n', n) order by n desc, title), '[]'::jsonb) into r from (
      select s.id, s.maker, s.title, (select count(*) from public.works w where w.source_id = s.id and w.review_status = 'approved') n
      from public.work_sources s
      where s.kind = p_kind and s.status <> 'excluded' and s.merged_into is null
        and not exists (select 1 from unnest(toks) k where position(k in s.mnorm || s.tnorm) = 0)
      order by 4 desc, s.title limit 8) m;
  end if;
  return r;
end $function$;
revoke all on function public.work_source_search(text, text, boolean) from public, anon;
grant execute on function public.work_source_search(text, text, boolean) to authenticated;

-- 새로 적기: 같은 표기가 이미 있으면 그것을 돌려준다. 링크·연락처·금칙어는 막는다. 하루 10개까지
create or replace function public.work_source_add(p_kind text, p_maker text, p_title text)
 returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_m text := left(btrim(regexp_replace(coalesce(p_maker,''), '\s+', ' ', 'g')), 40); v_t text := left(btrim(regexp_replace(coalesce(p_title,''), '\s+', ' ', 'g')), 40);
  mn text; tn text; s public.work_sources;
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  if p_kind not in ('pattern','video','class') then raise exception '종류를 다시 골라 주세요'; end if;
  mn := public._src_norm(v_m); tn := public._src_norm(v_t);
  if length(tn) < 2 then raise exception '이름을 두 글자 이상 적어 주세요'; end if;
  if (v_m || ' ' || v_t) ~* '(https?:|www\.|\.com|\.kr|\.net|@|[0-9]{3,4}[- .]?[0-9]{4})' then raise exception '링크나 연락처는 적을 수 없어요'; end if;
  if public.contains_banned(v_m || ' ' || v_t) then raise exception '커뮤니티 가이드라인에 맞지 않는 표현이 있어요'; end if;
  select * into s from public.work_sources where kind = p_kind and mnorm = mn and tnorm = tn;
  if s.id is not null then
    if s.merged_into is not null then select * into s from public.work_sources where id = s.merged_into; end if;
    if s.id is null or s.status = 'excluded' then raise exception '쓸 수 없는 이름이에요. 다르게 적어 주세요'; end if;
    return jsonb_build_object('id', s.id, 'maker', s.maker, 'title', s.title);
  end if;
  if (select count(*) from public.work_sources where created_by = auth.uid() and created_at > now() - interval '1 day') >= 10 then raise exception '오늘은 더 적을 수 없어요. 내일 다시 해 주세요'; end if;
  insert into public.work_sources(kind, maker, title, mnorm, tnorm, created_by) values (p_kind, v_m, v_t, mn, tn, auth.uid()) returning * into s;
  return jsonb_build_object('id', s.id, 'maker', s.maker, 'title', s.title);
end $function$;
revoke all on function public.work_source_add(text, text, text) from public, anon;
grant execute on function public.work_source_add(text, text, text) to authenticated;

-- 뜨개 이야기 저장: p_story 에 how 가 있을 때만 '어떻게 떴는지'를 함께 저장(옛 앱은 how 를 보내지 않음)
create or replace function public.work_set_story(p_post uuid, p_story jsonb)
 returns void language plpgsql security definer set search_path to 'public' as $function$
declare v_work uuid; v_took text := nullif(btrim(coalesce(p_story->>'took','')), '');
  v_know text := nullif(left(btrim(coalesce(p_story->>'knowhow','')), 500), ''); v_reg text := nullif(left(btrim(coalesce(p_story->>'regret','')), 300), '');
  v_how text; v_note text; s public.work_sources;
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  select w.id into v_work from public.posts po join public.works w on w.id = po.work_id where po.id = p_post and w.profile_id = auth.uid();
  if v_work is null then raise exception '내 완성작품 인증이 아니에요'; end if;
  if v_took is not null and v_took not in ('1d','3d','1w','2w','1m','long') then v_took := null; end if;
  if public.contains_banned(coalesce(v_know,'')||' '||coalesce(v_reg,'')) then raise exception '커뮤니티 가이드라인에 맞지 않는 표현이 있어요'; end if;
  update public.works set took = v_took, knowhow = v_know, regret = v_reg where id = v_work;
  if p_story ? 'how' then
    v_how := nullif(btrim(coalesce(p_story->>'how','')), '');
    if v_how is not null and v_how not in ('pattern','video','class','original') then v_how := null; end if;
    if v_how in ('pattern','video','class') then
      begin select * into s from public.work_sources where id = (p_story->>'src')::uuid; exception when others then s := null; end;
      if s.id is not null and s.merged_into is not null then select * into s from public.work_sources where id = s.merged_into; end if;
      if s.id is null or s.kind <> v_how or s.status = 'excluded' then v_how := null; s := null; end if;   -- 고르지 않았으면 비워 둔다
    elsif v_how = 'original' then
      v_note := nullif(left(btrim(coalesce(p_story->>'note','')), 60), '');
      if v_note is not null and (public.contains_banned(v_note) or v_note ~* '(https?:|www\.|@)') then raise exception '한 줄 설명에 쓸 수 없는 표현이 있어요'; end if;
    end if;
    update public.works set made_how = v_how, source_id = case when v_how in ('pattern','video','class') then s.id end, source_note = case when v_how = 'original' then v_note end,
      pattern_source = case when v_how in ('pattern','video','class') then nullif(btrim(s.maker || ' · ' || s.title, ' ·'), '') when v_how = 'original' then '창작' end
    where id = v_work;
  end if;
end $function$;

-- 콘솔 › 도안 후보
create or replace function public.admin_source_list()
 returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  return jsonb_build_object(
    'rows', coalesce((select jsonb_agg(to_jsonb(x) order by (x.status = 'candidate') desc, x.n desc, x.created_at desc) from (
      select s.id, s.kind, s.maker, s.title, s.status, s.created_at,
        (select nickname from public.profiles p where p.id = s.created_by) by_nick,
        (select count(*) from public.works w where w.source_id = s.id) n,
        (select (array_agg(w.photos[1] order by w.created_at desc))[1:3] from public.works w where w.source_id = s.id and array_length(w.photos,1) > 0) photos,
        (select jsonb_build_object('id', o.id, 'maker', o.maker, 'title', o.title, 'status', o.status) from public.work_sources o
          where s.status = 'candidate' and o.id <> s.id and o.kind = s.kind and o.merged_into is null and o.status <> 'excluded'
            and (o.status = 'ok' or o.created_at < s.created_at)
            and (o.tnorm = s.tnorm or (length(s.tnorm) >= 3 and length(o.tnorm) >= 3 and (position(s.tnorm in o.tnorm) > 0 or position(o.tnorm in s.tnorm) > 0)))
          order by (o.mnorm = s.mnorm) desc, (o.status = 'ok') desc, o.created_at limit 1) sim
      from public.work_sources s where s.merged_into is null) x), '[]'::jsonb),
    'originals', (select count(*) from public.works where made_how = 'original'),
    'top_original', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'nick', nickname, 'n', n) order by n desc) from (
      select p.id, p.nickname, count(*) n from public.works w join public.profiles p on p.id = w.profile_id where w.made_how = 'original' and not coalesce(p.is_test,false) group by p.id, p.nickname order by count(*) desc limit 10) t), '[]'::jsonb));
end $function$;
revoke all on function public.admin_source_list() from public, anon;
grant execute on function public.admin_source_list() to authenticated;

create or replace function public.admin_source_decide(p_id uuid, p_action text, p_into uuid default null, p_maker text default null, p_title text default null)
 returns text language plpgsql security definer set search_path to 'public' as $function$
declare s public.work_sources; t public.work_sources; v_m text; v_t text;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  select * into s from public.work_sources where id = p_id for update;
  if s.id is null then raise exception '찾을 수 없어요'; end if;
  if p_action = 'ok' then
    v_m := left(btrim(coalesce(p_maker, s.maker)), 40); v_t := left(btrim(coalesce(p_title, s.title)), 40);
    if length(public._src_norm(v_t)) < 2 then raise exception '이름을 두 글자 이상 적어 주세요'; end if;
    if exists (select 1 from public.work_sources o where o.id <> s.id and o.kind = s.kind and o.mnorm = public._src_norm(v_m) and o.tnorm = public._src_norm(v_t)) then raise exception '같은 이름이 이미 있어요 — 합치기를 써 주세요'; end if;
    update public.work_sources set maker = v_m, title = v_t, mnorm = public._src_norm(v_m), tnorm = public._src_norm(v_t), status = 'ok', decided_at = now() where id = p_id;
    update public.works set pattern_source = nullif(btrim(v_m || ' · ' || v_t, ' ·'), '') where source_id = p_id;
  elsif p_action = 'merge' then
    select * into t from public.work_sources where id = p_into;
    if t.id is null or t.id = s.id or t.kind <> s.kind or t.merged_into is not null or t.status = 'excluded' then raise exception '합칠 곳을 다시 골라 주세요'; end if;
    update public.works set source_id = t.id, pattern_source = nullif(btrim(t.maker || ' · ' || t.title, ' ·'), '') where source_id = s.id;
    update public.work_sources set merged_into = t.id where merged_into = s.id;
    update public.work_sources set merged_into = t.id, decided_at = now() where id = s.id;
  elsif p_action = 'exclude' then
    update public.works set source_id = null, pattern_source = null where source_id = s.id;
    update public.work_sources set status = 'excluded', decided_at = now() where id = s.id;
  elsif p_action = 'reopen' then
    update public.work_sources set status = 'candidate', decided_at = null where id = s.id;
  else raise exception '알 수 없는 처리예요';
  end if;
  perform public.admin_log('source_decide', 'work_source', p_id::text, jsonb_build_object('action', p_action, 'into', p_into, 'maker', p_maker, 'title', p_title));
  return p_action;
end $function$;
revoke all on function public.admin_source_decide(uuid, text, uuid, text, text) from public, anon;
grant execute on function public.admin_source_decide(uuid, text, uuid, text, text) to authenticated;
