-- 159. 도안 후보를 AI 가 자동으로 묶기 (2026-11-20 대표 지시 — 마이그레이션 source_ai · Edge supabase/functions/source-match)
--   새로 적힌 후보(도안·영상·수업)를 이미 있는 것과 견준다: 이름이 같은 것으로 보이고(한글·영문·띄어쓰기·줄임 표기가 달라도) 실제 올라온 작품 사진도 같은 디자인이면 AI 가 바로 합친다.
--   이름만 같아 보이고 사진으로 확인하지 못하면 합치지 않고 콘솔에 '같아 보여요'로만 알린다. 합친 것은 콘솔 › 도안 후보 › 'AI 가 묶은 것'에서 [되돌리기].
--   AI 는 후보 하나를 한 번만 본다(ai_at). 무엇을 합칠지는 이 파일의 함수가 검사해서 정한다(같은 종류 · 제외되지 않은 것 · 양쪽에 사진이 있을 때만).
--   끄기: update jigi_config set value = 'off' where key = 'source_ai'

alter table public.work_sources add column if not exists ai_at timestamptz;      -- AI 가 본 때(한 번만 본다)
alter table public.work_sources add column if not exists ai_result jsonb;        -- {same, sure, why, into, merged, works[], kids[], undone, tries}
alter table public.work_sources add column if not exists merged_by text;         -- 'ai' | 'admin'
insert into public.jigi_config(key, value) values ('source_ai', 'on') on conflict (key) do nothing;

-- AI 가 볼 후보: 아직 안 본 후보 가운데 사진 있는 작품이 붙은 것. 견줄 대상 = 같은 종류의 확인된 것 + 먼저 적힌 후보
create or replace function public.source_ai_pending(p_limit int default 4)
 returns jsonb language sql stable security definer set search_path to 'public' as $function$
  select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
    select s.id, s.kind, s.maker, s.title,
      (select coalesce(jsonb_agg(u), '[]'::jsonb) from (select unnest(w.photos[1:2]) u from public.works w where w.source_id = s.id and array_length(w.photos, 1) > 0 order by w.created_at desc limit 2) p) photos,
      (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'maker', o.maker, 'title', o.title,
          'alias', (select coalesce(jsonb_agg(btrim(a.maker || ' ' || a.title)), '[]'::jsonb) from public.work_sources a where a.merged_into = o.id))), '[]'::jsonb)
        from (select * from public.work_sources o where o.kind = s.kind and o.id <> s.id and o.merged_into is null and o.status <> 'excluded'
                and (o.status = 'ok' or o.created_at < s.created_at or (o.created_at = s.created_at and o.id < s.id))
              order by (o.status = 'ok') desc, o.created_at desc limit 300) o) targets
    from public.work_sources s
    where s.status = 'candidate' and s.merged_into is null and s.ai_at is null and s.created_at < now() - interval '2 minutes'
      and exists (select 1 from public.works w where w.source_id = s.id and array_length(w.photos, 1) > 0)
    order by s.created_at limit greatest(1, least(coalesce(p_limit, 4), 10))) x;
$function$;
revoke all on function public.source_ai_pending(int) from public, anon, authenticated;
grant execute on function public.source_ai_pending(int) to service_role;

-- AI 의 판단을 받아 적는다. 합치는 것은 이름도 사진도 같다고 한 때(same + sure)이고 양쪽에 사진 있는 작품이 있을 때만
create or replace function public.source_ai_apply(p_id uuid, p_result jsonb)
 returns text language plpgsql security definer set search_path to 'public' as $function$
declare s public.work_sources; t public.work_sources; v_into uuid; v_same boolean := (p_result->>'same') = 'true'; v_sure boolean := (p_result->>'sure') = 'true';
  v_why text := left(btrim(coalesce(p_result->>'why', '')), 200); v_works jsonb; v_kids jsonb; v_tries int;
begin
  select * into s from public.work_sources where id = p_id for update;
  if s.id is null or s.merged_into is not null or s.status <> 'candidate' or s.ai_at is not null then return 'skip'; end if;
  if (p_result->>'error') = 'true' then   -- AI 호출 실패: 세 번까지 다시 본다
    v_tries := coalesce((s.ai_result->>'tries')::int, 0) + 1;
    update public.work_sources set ai_result = jsonb_build_object('tries', v_tries), ai_at = case when v_tries >= 3 then now() end where id = s.id;
    return 'retry';
  end if;
  begin v_into := (p_result->>'into')::uuid; exception when others then v_into := null; end;
  if v_into is not null then
    select * into t from public.work_sources where id = v_into;
    if t.id is null or t.id = s.id or t.kind <> s.kind or t.merged_into is not null or t.status = 'excluded' then v_into := null; end if;
  end if;
  if v_into is null or not v_same then
    update public.work_sources set ai_at = now(), ai_result = jsonb_build_object('same', false, 'why', v_why) where id = s.id;
    return 'none';
  end if;
  if v_sure and coalesce((select value from public.jigi_config where key = 'source_ai'), 'off') = 'on'
     and exists (select 1 from public.works w where w.source_id = s.id and array_length(w.photos, 1) > 0)
     and exists (select 1 from public.works w where w.source_id = t.id and array_length(w.photos, 1) > 0) then
    select coalesce(jsonb_agg(id), '[]'::jsonb) into v_works from public.works where source_id = s.id;
    select coalesce(jsonb_agg(id), '[]'::jsonb) into v_kids from public.work_sources where merged_into = s.id;
    update public.works set source_id = t.id, pattern_source = nullif(btrim(t.maker || ' · ' || t.title, ' ·'), '') where source_id = s.id;
    update public.work_sources set merged_into = t.id where merged_into = s.id;
    update public.work_sources set merged_into = t.id, merged_by = 'ai', decided_at = now(), ai_at = now(),
      ai_result = jsonb_build_object('same', true, 'sure', true, 'merged', true, 'why', v_why, 'into', t.id, 'works', v_works, 'kids', v_kids) where id = s.id;
    return 'merged';
  end if;
  update public.work_sources set ai_at = now(), ai_result = jsonb_build_object('same', true, 'sure', false, 'why', v_why, 'into', t.id) where id = s.id;
  return 'suggest';
end $function$;
revoke all on function public.source_ai_apply(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.source_ai_apply(uuid, jsonb) to service_role;

-- 10분마다: 볼 후보가 있을 때만 Edge Function 을 부른다
create or replace function public.source_ai_tick()
 returns void language plpgsql security definer set search_path to 'public' as $function$
declare v_secret text;
begin
  if coalesce((select value from public.jigi_config where key = 'source_ai'), 'off') <> 'on' then return; end if;
  if public.source_ai_pending(1) = '[]'::jsonb then return; end if;
  select value into v_secret from public.jigi_config where key = 'hook_secret';
  perform net.http_post(url := 'https://thfcrodfaitzrzlrxyir.supabase.co/functions/v1/source-match', body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json','x-jigi-secret', v_secret), timeout_milliseconds := 5000);
exception when others then null;
end $function$;
revoke all on function public.source_ai_tick() from public, anon, authenticated;
grant execute on function public.source_ai_tick() to service_role;
select cron.schedule('source-ai', '4-59/10 * * * *', $cron$select public.source_ai_tick()$cron$);

-- 찾기: 합쳐진 다른 표기(영문·줄임)로 쳐도 합친 쪽이 나오게
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
        and (not exists (select 1 from unnest(toks) k where position(k in s.mnorm || s.tnorm) = 0)
          or exists (select 1 from public.work_sources a where a.merged_into = s.id and not exists (select 1 from unnest(toks) k where position(k in a.mnorm || a.tnorm) = 0)))
      order by 4 desc, s.title limit 8) m;
  end if;
  return r;
end $function$;
revoke all on function public.work_source_search(text, text, boolean) from public, anon;
grant execute on function public.work_source_search(text, text, boolean) to authenticated;

-- 콘솔 › 도안 후보: AI 가 같아 보인다고 한 것(ai_sim) · AI 가 묶은 것(ai_merged)
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
          order by (o.mnorm = s.mnorm) desc, (o.status = 'ok') desc, o.created_at limit 1) sim,
        (select jsonb_build_object('id', o.id, 'maker', o.maker, 'title', o.title, 'status', o.status, 'why', s.ai_result->>'why') from public.work_sources o
          where s.status = 'candidate' and (s.ai_result->>'same') = 'true' and coalesce(s.ai_result->>'undone', '') <> 'true'
            and o.id::text = s.ai_result->>'into' and o.merged_into is null and o.status <> 'excluded') ai_sim,
        (s.ai_at is not null) ai_seen
      from public.work_sources s where s.merged_into is null) x), '[]'::jsonb),
    'ai_merged', coalesce((select jsonb_agg(to_jsonb(m) order by m.at desc) from (
      select s.id, s.kind, s.maker, s.title, s.decided_at at, s.ai_result->>'why' why, jsonb_array_length(coalesce(s.ai_result->'works', '[]'::jsonb)) n,
        (select (array_agg(w.photos[1] order by w.created_at desc))[1:3] from public.works w
          where w.id in (select (jsonb_array_elements_text(coalesce(s.ai_result->'works', '[]'::jsonb)))::uuid) and array_length(w.photos,1) > 0) photos,
        jsonb_build_object('id', o.id, 'maker', o.maker, 'title', o.title) "into",
        (select (array_agg(w.photos[1] order by w.created_at desc))[1:3] from public.works w
          where w.source_id = o.id and array_length(w.photos,1) > 0 and not (to_jsonb(w.id::text) <@ coalesce(s.ai_result->'works', '[]'::jsonb))) into_photos
      from public.work_sources s join public.work_sources o on o.id = s.merged_into
      where s.merged_by = 'ai' order by s.decided_at desc limit 100) m), '[]'::jsonb),
    'originals', (select count(*) from public.works where made_how = 'original'),
    'top_original', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'nick', nickname, 'n', n) order by n desc) from (
      select p.id, p.nickname, count(*) n from public.works w join public.profiles p on p.id = w.profile_id where w.made_how = 'original' and not coalesce(p.is_test,false) group by p.id, p.nickname order by count(*) desc limit 10) t), '[]'::jsonb));
end $function$;
revoke all on function public.admin_source_list() from public, anon;
grant execute on function public.admin_source_list() to authenticated;

-- 콘솔 처리: unmerge(AI 가 묶은 것 되돌리기)를 더하고, 사람이 합친 것은 merged_by = 'admin'
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
    update public.work_sources set merged_into = t.id, merged_by = 'admin', decided_at = now() where id = s.id;
  elsif p_action = 'unmerge' then
    if s.merged_into is null or s.merged_by is distinct from 'ai' then raise exception 'AI 가 묶은 것만 되돌릴 수 있어요'; end if;
    update public.works set source_id = s.id, pattern_source = nullif(btrim(s.maker || ' · ' || s.title, ' ·'), '')
      where source_id = s.merged_into and id in (select (jsonb_array_elements_text(coalesce(s.ai_result->'works', '[]'::jsonb)))::uuid);
    update public.work_sources set merged_into = s.id
      where merged_into = s.merged_into and id in (select (jsonb_array_elements_text(coalesce(s.ai_result->'kids', '[]'::jsonb)))::uuid);
    update public.work_sources set merged_into = null, merged_by = null, decided_at = null, status = 'candidate',
      ai_result = coalesce(ai_result, '{}'::jsonb) || jsonb_build_object('undone', true, 'merged', false) where id = s.id;   -- ai_at 은 그대로: AI 가 다시 묶지 않는다
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
