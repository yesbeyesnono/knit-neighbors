-- 143. 실 정보 되묻기 — 지기 채팅으로 묻고, 답을 받아 실 사전에 채운다 (2026-11-17 대표 지시: 화면·문구를 바꾸지 말고 대화로)
--   흐름: 완성작품 인증이 승인됨 → 그 인증에 쓴 실 가운데 사전에 '후보(auto)'로만 있고 필수 항목(브랜드·1볼 무게·1볼 길이·소재)이 빈 것이 있으면
--         지기 채팅으로 한 번 묻는다(yarn_ask_check) → 회원이 답하면 support_on_message 가 Edge `yarn-ask` 를 부른다(AI 는 답에서 값만 읽음)
--         → yarn_ask_apply 가 값의 범위를 검사해 ① 사전의 확정 실과 맞으면 그 실에 연결 ② 아니면 후보 실의 빈 칸만 채움(상태는 후보 그대로 — 확정은 대표가 콘솔에서) ③ 모르면 그대로 둠
--   지킬 것: 한 인증에 한 번 · 같은 회원에게는 cooldown(기본 7일)에 한 번 · 열린 질문이 있으면 새로 묻지 않음 · 되묻기는 한 번까지 · 14일 지나면 닫힘
--           AI 가 고치는 것은 '후보' 실의 빈 칸뿐(확정 실은 손대지 않음). 바꾼 내용은 yarn_asks.result 에 before/after 로 남김
--   스위치: jigi_config.yarn_ask = 'on' | 'off'(처음 값 off — 대표가 켜라고 할 때 켠다) · jigi_config.yarn_ask_cooldown_days
create table if not exists public.yarn_asks (
  id bigserial primary key,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  work_id uuid references public.works(id) on delete set null,
  items jsonb not null,                 -- [{entry_id, catalog_id, name, missing:[brand|ball_g|ball_m|fibers]}]
  status text not null default 'asked' check (status in ('asked','done','unknown','expired')),
  turns int not null default 0,
  asked_at timestamptz not null default now(),
  answered_at timestamptz,
  answer jsonb,                         -- AI 가 읽은 값(원문은 넣지 않음)
  result jsonb                          -- 적용 결과(before/after)
);
create index if not exists yarn_asks_profile on public.yarn_asks(profile_id, status);
alter table public.yarn_asks enable row level security;
revoke all on public.yarn_asks from anon, authenticated;
grant select on public.yarn_asks to authenticated;
grant all on public.yarn_asks to service_role;
grant usage, select on sequence public.yarn_asks_id_seq to service_role;
drop policy if exists yarn_asks_admin_select on public.yarn_asks;
create policy yarn_asks_admin_select on public.yarn_asks for select to authenticated using (public.is_admin());

insert into public.jigi_config(key, value) values ('yarn_ask', 'off') on conflict (key) do nothing;
insert into public.jigi_config(key, value) values ('yarn_ask_cooldown_days', '7') on conflict (key) do nothing;

-- 인증 하나를 살펴 물어볼 것이 있으면 지기 채팅으로 한 번 묻는다. p_force = 스위치·쉬는 기간을 무시(시험용)
create or replace function public.yarn_ask_check(p_work uuid, p_force boolean default false) returns bigint
language plpgsql security definer set search_path = public as $$
declare w public.works; v_items jsonb; v_names text; v_miss text[]; v_id bigint; v_cool int; sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e'; v_what text;
begin
  if not p_force and coalesce((select value from public.jigi_config where key = 'yarn_ask'), 'off') <> 'on' then return null; end if;
  select * into w from public.works where id = p_work;
  if w.id is null or w.review_status <> 'approved' or w.profile_id = sup then return null; end if;
  update public.yarn_asks set status = 'expired' where profile_id = w.profile_id and status = 'asked' and asked_at < now() - interval '14 days';
  if exists (select 1 from public.yarn_asks where work_id = p_work) then return null; end if;
  if exists (select 1 from public.yarn_asks where profile_id = w.profile_id and status = 'asked') then return null; end if;
  v_cool := coalesce(nullif((select value from public.jigi_config where key = 'yarn_ask_cooldown_days'), '')::int, 7);
  if not p_force and exists (select 1 from public.yarn_asks where profile_id = w.profile_id and asked_at > now() - make_interval(days => v_cool)) then return null; end if;
  -- 물어볼 실: 사전에 후보로만 있고 필수 항목이 빈 것(가장 많이 빈 것부터 2개까지)
  select jsonb_agg(jsonb_build_object('entry_id', x.id, 'catalog_id', x.cid, 'name', x.raw_name, 'missing', to_jsonb(x.miss)) order by cardinality(x.miss) desc, x.id),
         string_agg('「'||x.raw_name||'」', ', ' order by cardinality(x.miss) desc, x.id)
    into v_items, v_names
  from (
    select y.* from (
      select e.id, c.id cid, e.raw_name,
             array_remove(array[case when c.brand is null then 'brand' end, case when coalesce(c.ball_g, e.ball_g) is null then 'ball_g' end,
                                case when coalesce(c.ball_m, e.ball_m) is null then 'ball_m' end, case when coalesce(c.fibers, e.fibers) is null and c.fiber_main is null then 'fibers' end], null) miss
      from public.yarn_entries e join public.yarn_catalog c on c.id = e.catalog_id
      where e.work_id = p_work and c.status = 'auto' and c.merged_into is null
    ) y where cardinality(y.miss) > 0 order by cardinality(y.miss) desc, y.id limit 2
  ) x;
  if v_items is null then return null; end if;
  select array_agg(distinct m) into v_miss from jsonb_array_elements(v_items) it, jsonb_array_elements_text(it->'missing') m;
  v_what := array_to_string(array_remove(array[
      case when 'brand' = any(v_miss) then '브랜드(만든 곳)와 실 이름' end,
      case when 'ball_g' = any(v_miss) or 'ball_m' = any(v_miss) then '1볼의 무게(g)와 길이(m)' end,
      case when 'fibers' = any(v_miss) then '소재(혼용률)' end], null), ', ');
  insert into public.yarn_asks(profile_id, work_id, items) values (w.profile_id, p_work, v_items) returning id into v_id;
  perform public._jigi_say(w.profile_id,
    '「'||coalesce(nullif(btrim(w.title),''),'작품')||'」 인증 잘 봤어요. 쓰신 실 '||v_names||' 정보가 실 사전에 아직 없어서 여쭤봐요. '||v_what||
    ' 가운데 아시는 것만 이 채팅에 적어 주시겠어요? 볼밴드(띠지) 사진을 보내 주셔도 돼요. 같은 실을 찾는 분들께 도움이 돼요. 모르시면 "몰라요"라고만 답해 주세요.');
  return v_id;
end $$;
revoke all on function public.yarn_ask_check(uuid, boolean) from public, anon, authenticated;
grant execute on function public.yarn_ask_check(uuid, boolean) to service_role;

-- 인증이 승인되는 순간 살핀다(실패해도 승인은 그대로)
create or replace function public.works_yarn_ask() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  begin
    if new.review_status = 'approved' and old.review_status is distinct from 'approved' then perform public.yarn_ask_check(new.id, false); end if;
  exception when others then null;
  end;
  return null;
end $$;
revoke all on function public.works_yarn_ask() from public, anon, authenticated;
drop trigger if exists works_yarn_ask on public.works;
create trigger works_yarn_ask after update of review_status on public.works for each row execute function public.works_yarn_ask();

-- 답 적용(Edge yarn-ask 가 service_role 로 부름). p_answer = {related, unknown, items:[{i, brand, product, ball_g, ball_m, fibers}]}
-- 돌려줌: {status, applied, reply} — reply 는 고정 문구(모델이 쓴 글을 회원에게 보내지 않는다)
create or replace function public.yarn_ask_apply(p_ask bigint, p_answer jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.yarn_asks; it jsonb; an jsonb; i int; c public.yarn_catalog; e public.yarn_entries; v_brand text; v_prod text; v_g numeric; v_m numeric; v_f jsonb; v_fm text; v_sum numeric;
  v_match uuid; v_new uuid; n_link int := 0; n_fill int := 0; v_res jsonb := '[]'::jsonb; v_name text; v_linked text; v_reply text; v_status text; sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e'; v_others int; v_k text;
begin
  select * into a from public.yarn_asks where id = p_ask for update;
  if a.id is null or a.status <> 'asked' then return jsonb_build_object('status', 'closed'); end if;
  if coalesce((p_answer->>'unknown')::boolean, false) is not true then
    for an in select * from jsonb_array_elements(case when jsonb_typeof(p_answer->'items') = 'array' then p_answer->'items' else '[]'::jsonb end) loop
      i := coalesce(nullif(an->>'i','')::int, 0); it := a.items->i; if it is null then continue; end if;
      select * into e from public.yarn_entries where id = (it->>'entry_id')::bigint; if e.id is null then continue; end if;
      select * into c from public.yarn_catalog where id = e.catalog_id; if c.id is null or c.status <> 'auto' then continue; end if;   -- 확정 실은 손대지 않는다
      -- 값 검사(범위를 벗어나면 버림)
      v_brand := nullif(left(btrim(regexp_replace(coalesce(an->>'brand',''), '[<>{}\[\]\\]', '', 'g')), 30), '');
      v_prod  := nullif(left(btrim(regexp_replace(coalesce(an->>'product',''), '[<>{}\[\]\\]', '', 'g')), 50), '');
      v_g := case when (an->>'ball_g') ~ '^\d+(\.\d+)?$' and (an->>'ball_g')::numeric between 5 and 2000 then (an->>'ball_g')::numeric end;
      v_m := case when (an->>'ball_m') ~ '^\d+(\.\d+)?$' and (an->>'ball_m')::numeric between 5 and 5000 then (an->>'ball_m')::numeric end;
      v_f := null;
      if jsonb_typeof(an->'fibers') = 'object' then
        select jsonb_object_agg(left(k, 12), v::numeric), sum(v::numeric) into v_f, v_sum from jsonb_each_text(an->'fibers') t(k, v) where v ~ '^\d+(\.\d+)?$' and v::numeric > 0 and v::numeric <= 100 and length(btrim(k)) between 1 and 12;
        if v_f is null or v_sum < 95 or v_sum > 105 then v_f := null; end if;
      end if;
      if v_brand is null and v_prod is null and v_g is null and v_m is null and v_f is null then continue; end if;
      v_fm := case when v_f is not null then (select k from jsonb_each_text(v_f) t(k, v) order by v::numeric desc limit 1) end;
      -- ① 사전의 확정 실과 맞는지: 이름으로, 안 되면 규격으로
      v_match := null; v_name := btrim(coalesce(v_brand||' ','')||coalesce(v_prod, ''));
      if v_prod is not null and v_brand is not null then   -- 브랜드 없이 실 이름만으로는 맞추지 않는다(같은 이름의 다른 실일 수 있음)
        v_k := public.yarn_norm(v_name);
        select t.id into v_match from public.yarn_catalog t where t.merged_into is null and t.status = 'verified' and t.id <> c.id
          and (t.norm_keys @> array[v_k] or (t.norm_keys @> array[public.yarn_norm(v_prod)] and t.brand = v_brand)) order by t.uses desc limit 1;
      end if;
      if v_match is null and v_brand is not null and coalesce(v_g, c.ball_g, e.ball_g) is not null and coalesce(v_m, c.ball_m, e.ball_m) is not null then
        v_match := public.yarn_match_spec_one(v_brand, coalesce(v_g, c.ball_g, e.ball_g), coalesce(v_m, c.ball_m, e.ball_m), coalesce(v_f, c.fibers, e.fibers), null);
        if v_match = c.id or exists (select 1 from public.yarn_catalog t where t.id = v_match and t.status <> 'verified') then v_match := null; end if;
      end if;
      update public.yarn_entries set ball_g = coalesce(ball_g, v_g), ball_m = coalesce(ball_m, v_m), fibers = coalesce(fibers, v_f), fiber = coalesce(fiber, v_fm) where id = e.id;
      if v_match is not null then
        -- 이 기록만 옮긴다(같은 이름을 쓴 다른 회원의 기록은 다른 실일 수 있다)
        update public.yarn_entries set catalog_id = v_match where id = e.id;
        update public.yarn_catalog t set uses = (select count(*) from public.yarn_entries x where x.catalog_id = t.id), updated_at = now() where t.id in (c.id, v_match);
        if not exists (select 1 from public.yarn_entries x where x.catalog_id = c.id) and not exists (select 1 from public.yarn_stash s where s.catalog_id = c.id) then
          update public.yarn_catalog set merged_into = v_match where id = c.id; end if;
        select coalesce(t.brand||' ','')||t.product into v_linked from public.yarn_catalog t where t.id = v_match;
        n_link := n_link + 1;
        v_res := v_res || jsonb_build_object('entry_id', e.id, 'action', 'link', 'from', c.id, 'to', v_match);
      else
        select count(*) into v_others from public.yarn_entries x where x.catalog_id = c.id and x.id <> e.id;
        if v_others > 0 or exists (select 1 from public.yarn_stash s where s.catalog_id = c.id) then
          -- 같은 후보를 다른 기록도 쓰고 있으면 그 후보를 고치지 않고 새 후보를 만든다(브랜드나 실 이름을 새로 알았을 때만)
          if v_brand is null and v_prod is null then
            v_res := v_res || jsonb_build_object('entry_id', e.id, 'action', 'entry_only'); n_fill := n_fill + 1; continue;
          end if;
          v_k := public.yarn_norm(coalesce(v_brand||' ','')||coalesce(v_prod, c.product));
          insert into public.yarn_catalog(brand, product, aliases, norm_keys, ball_g, ball_m, fibers, fiber_main, uses)
            values (v_brand, coalesce(v_prod, c.product), array[left(e.raw_name, 60)], array_remove(array[v_k], null), coalesce(v_g, e.ball_g), coalesce(v_m, e.ball_m), coalesce(v_f, e.fibers), v_fm, 1) returning id into v_new;
          update public.yarn_entries set catalog_id = v_new where id = e.id;
          update public.yarn_catalog t set uses = (select count(*) from public.yarn_entries x where x.catalog_id = t.id) where t.id = c.id;
          v_res := v_res || jsonb_build_object('entry_id', e.id, 'action', 'new_candidate', 'from', c.id, 'to', v_new);
        else
          v_res := v_res || jsonb_build_object('entry_id', e.id, 'action', 'fill', 'catalog', c.id,
            'before', jsonb_build_object('brand', c.brand, 'product', c.product, 'ball_g', c.ball_g, 'ball_m', c.ball_m, 'fibers', c.fibers, 'fiber_main', c.fiber_main));
          v_k := public.yarn_norm(coalesce(coalesce(c.brand, v_brand)||' ','')||coalesce(v_prod, c.product));
          update public.yarn_catalog t set brand = coalesce(t.brand, v_brand),
              product = case when v_prod is not null and t.brand is null then v_prod else t.product end,
              aliases = case when v_prod is not null and not (t.product = any(t.aliases)) and cardinality(t.aliases) < 30 then t.aliases || t.product else t.aliases end,
              norm_keys = case when v_k is not null and not (t.norm_keys @> array[v_k]) then t.norm_keys || v_k else t.norm_keys end,
              ball_g = coalesce(t.ball_g, v_g), ball_m = coalesce(t.ball_m, v_m), fibers = coalesce(t.fibers, v_f), fiber_main = coalesce(t.fiber_main, v_fm), updated_at = now()
            where t.id = c.id;
        end if;
        n_fill := n_fill + 1;
      end if;
    end loop;
  end if;
  -- 굵기: 1볼 g·m 이 생긴 후보는 규격으로 정한다(schema 137 과 같은 기준)
  update public.yarn_catalog t set weight_class = case when t.m_per_100g >= 600 then '레이스·극세' when t.m_per_100g >= 350 then '합세(Fingering)' when t.m_per_100g >= 250 then '중세(Sport)'
      when t.m_per_100g >= 200 then '합태(DK)' when t.m_per_100g >= 120 then '병태(Worsted)' when t.m_per_100g >= 60 then '극태(Bulky)' else '초극태' end
    where t.status = 'auto' and t.weight_class is null and t.m_per_100g is not null
      and t.id in (select (r->>'catalog')::uuid from jsonb_array_elements(v_res) r where r ? 'catalog' union select (r->>'to')::uuid from jsonb_array_elements(v_res) r where r->>'action' = 'new_candidate');
  if n_link + n_fill > 0 then
    v_status := 'done';
    v_reply := case when n_link > 0 and n_fill = 0 then '고마워요! 「'||v_linked||'」(으)로 실 사전에 연결했어요. 덕분에 같은 실을 찾는 분들이 이 작품을 볼 수 있어요.'
                    else '고마워요! 알려 주신 내용을 실 사전에 적어 두었어요. 확인을 거쳐 정식으로 올라가요. 덕분에 같은 실을 찾는 분들께 도움이 돼요.' end;
  elsif coalesce((p_answer->>'unknown')::boolean, false) or a.turns >= 1 then
    v_status := 'unknown'; v_reply := '괜찮아요, 답해 주셔서 고마워요. 즐거운 뜨개 되세요.';
  else
    v_status := 'asked'; v_reply := '말씀해 주신 내용에서 실 정보를 찾지 못했어요. 브랜드와 실 이름을 한 번만 더 적어 주시겠어요? 모르시면 "몰라요"라고만 답해 주세요.';
  end if;
  update public.yarn_asks set status = v_status, turns = turns + 1, answered_at = now(), answer = p_answer - 'raw', result = v_res where id = a.id;
  insert into public.messages(room_id, sender_id, body, by_ai, support_seen) values (public._support_room(a.profile_id), sup, v_reply, true, true);
  return jsonb_build_object('status', v_status, 'linked', n_link, 'filled', n_fill, 'reply', v_reply);
end $$;
revoke all on function public.yarn_ask_apply(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.yarn_ask_apply(bigint, jsonb) to service_role;

-- 지기 채팅에 회원이 답했을 때: 열린 실 질문이 있으면 Edge yarn-ask 가 먼저 본다(실 이야기가 아니면 yarn-ask 가 1차 응대로 넘김). 없으면 지금처럼 1차 응대 + 신고 건 처리
create or replace function public.support_on_message()
returns trigger language plpgsql security definer set search_path = 'public'
as $$
declare sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e'; cid bigint; v_secret text; v_ask bigint;
begin
  begin
    if new.sender_id <> sup and exists (select 1 from public.room_members m where m.room_id = new.room_id and m.profile_id = sup)
       and exists (select 1 from public.rooms r where r.id = new.room_id and r.kind = 'direct') then
      select id into cid from public.report_cases where author_id = new.sender_id and status in ('ask','review','hidden') order by id desc limit 1;
      if cid is null then
        select id into v_ask from public.yarn_asks where profile_id = new.sender_id and status = 'asked' and asked_at > now() - interval '14 days' order by id desc limit 1;
      end if;
      if v_ask is not null then
        select value into v_secret from public.jigi_config where key = 'hook_secret';
        perform net.http_post(url := 'https://thfcrodfaitzrzlrxyir.supabase.co/functions/v1/yarn-ask',
          body := jsonb_build_object('ask', v_ask, 'msg', new.id),
          headers := jsonb_build_object('Content-Type','application/json','x-jigi-secret', v_secret), timeout_milliseconds := 30000);
      else
        perform public.jigi_call('support');
      end if;
      if cid is not null then
        update public.report_cases set replied_at = now(), reply_msg = new.id where id = cid;
        if new.photo_url is not null then
          select value into v_secret from public.jigi_config where key = 'hook_secret';
          perform net.http_post(url := 'https://thfcrodfaitzrzlrxyir.supabase.co/functions/v1/report-flow',
            body := jsonb_build_object('case', cid, 'msg', new.id),
            headers := jsonb_build_object('Content-Type','application/json','x-jigi-secret', v_secret), timeout_milliseconds := 30000);
        end if;
      end if;
    end if;
  exception when others then null;
  end;
  return null;
end $$;
