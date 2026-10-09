-- 권한 전수 점검 (2026-09-30, schema 66). 각 블록은 raise exception 'RESULT(rolled back): ...' 로 끝나 아무것도 남기지 않는다.
-- 실행: MCP execute_sql / SQL 에디터에 블록 하나씩(각 블록이 자기 헬퍼를 pg_temp 에 만든다). 통과 = RESULT 에 FAIL 이 없음.
-- demo1 = 공격자, demo2 = 피해자. 새 마이그레이션마다 다시 돌리고, 새 테이블·함수를 만들면 여기 한 줄씩 추가.

-- [P1] 회원(demo1)이 남(demo2)의 1급·2급 데이터를 읽을 수 없는가 + 회사 자산(실 사전) 직접 조회 불가 + 함수 경유는 가능
do $do$ declare d1 uuid; d2 uuid; ev uuid; app uuid; rid uuid; n int; out text := '';
begin
  execute $f$create function pg_temp.chk(o text, label text, got int, want int) returns text language sql as 'select $1 || '' | '' || case when $3 = $4 then $2||'' ok'' else ''FAIL ''||$2||'' got=''||$3 end'$f$;
  select id into d1 from auth.users where email='demo1@knit.local'; select id into d2 from auth.users where email='demo2@knit.local';
  -- 피해자 데이터 심기(postgres 권한)
  insert into public.events(title, kind, status, needs_shipping, apply_from, apply_until) values ('perm-test', 'sample', 'open', true, now()-interval '1 day', now()+interval '1 day') returning id into ev;
  insert into public.event_applications(event_id, profile_id, status) values (ev, d2, 'selected') returning id into app;
  insert into public.event_shipping(application_id, profile_id, name, phone, zip, addr) values (app, d2, '홍길동', '010-0000-0000', '00000', '테스트 주소');
  insert into public.yarn_stash(owner_id, raw_name, bought_balls, left_balls) values (d2, 'perm-test yarn', 1, 1);
  insert into public.rooms(kind, created_by) values ('group', d2) returning id into rid;
  insert into public.room_members(room_id, profile_id) values (rid, d2);
  insert into public.messages(room_id, sender_id, body) values (rid, d2, 'secret');
  insert into public.notifications(recipient_id, actor_id, kind, snippet) values (d2, d2, 'notice', 'secret');
  insert into public.support_tickets(room_id, profile_id, summary) values (rid, d2, 'secret');
  -- demo1 로
  perform set_config('request.jwt.claims', json_build_object('sub',d1,'role','authenticated')::text, true); set local role authenticated;
  select count(*) into n from public.event_shipping where profile_id = d2; out := pg_temp.chk(out, 'shipping', n, 0);
  select count(*) into n from public.yarn_stash where owner_id = d2; out := pg_temp.chk(out, 'stash', n, 0);
  select count(*) into n from public.messages where room_id = rid; out := pg_temp.chk(out, 'messages', n, 0);
  select count(*) into n from public.room_members where room_id = rid; out := pg_temp.chk(out, 'room_members', n, 0);
  select count(*) into n from public.notifications where recipient_id = d2; out := pg_temp.chk(out, 'notifications', n, 0);
  select count(*) into n from public.support_tickets; out := pg_temp.chk(out, 'support_tickets', n, 0);
  select count(*) into n from public.admin_logs; out := pg_temp.chk(out, 'admin_logs', n, 0);
  select count(*) into n from public.admins; out := pg_temp.chk(out, 'admins', n, 0);
  select count(*) into n from public.yarn_entries; out := pg_temp.chk(out, 'yarn_entries', n, 0);
  select count(*) into n from public.device_tokens where profile_id = d2; out := pg_temp.chk(out, 'device_tokens', n, 0);
  select count(*) into n from public.point_events where user_id = d2; out := pg_temp.chk(out, 'point_events', n, 0);
  select count(*) into n from public.shop_claims where profile_id = d2; out := pg_temp.chk(out, 'shop_claims', n, 0);
  select count(*) into n from public.feedback_reports where user_id = d2; out := pg_temp.chk(out, 'feedback', n, 0);
  select count(*) into n from public.event_applications where profile_id = d2; out := pg_temp.chk(out, 'event_apps', n, 0);
  select count(*) into n from public.class_applications where profile_id = d2; out := pg_temp.chk(out, 'class_apps', n, 0);
  select count(*) into n from public.referrals where invitee_user_id = d2; out := pg_temp.chk(out, 'referrals', n, 0);
  select count(*) into n from public.survey_responses where user_id = d2; out := pg_temp.chk(out, 'survey', n, 0);
  select count(*) into n from public.mod_items; out := pg_temp.chk(out, 'mod_items', n, 0);
  select count(*) into n from public.jigi_reminders; out := pg_temp.chk(out, 'jigi_reminders', n, 0);
  select count(*) into n from public.yarn_catalog; out := pg_temp.chk(out, 'yarn_catalog(asset)', n, 0);
  select count(*) into n from public.yarn_colors; out := pg_temp.chk(out, 'yarn_colors(asset)', n, 0);
  select count(*) into n from public.yarn_sellers; out := pg_temp.chk(out, 'yarn_sellers(asset)', n, 0);
  select count(*) into n from public.yarn_suggest('낙양'); out := pg_temp.chk(out, 'yarn_suggest>0', least(n,1), 1);
  select count(*) into n from public.yarn_popular(); out := pg_temp.chk(out, 'yarn_popular>0', least(n,1), 1);
  select count(*) into n from public.yarn_colors_of((select id from public.yarn_suggest('낙양') limit 1)); out := pg_temp.chk(out, 'yarn_colors_of>0', least(n,1), 1);
  select case when public.yarn_spec((select id from public.yarn_suggest('아임울2') limit 1)) ? 'gauge_knit' then 1 else 0 end into n; out := pg_temp.chk(out, 'yarn_spec gauge', n, 1);   -- schema 68
  reset role;
  raise exception 'RESULT(rolled back): %', out;
end $do$;

-- [P2] 회원(demo1)이 남의 데이터·서버 계산값을 고치거나 지울 수 없는가
do $do$ declare d1 uuid; d2 uuid; p2 uuid; w2 uuid; s2 uuid; r2 uuid; n int; out text := '';
begin
  execute $f$create function pg_temp.chk(o text, label text, got int, want int) returns text language sql as 'select $1 || '' | '' || case when $3 = $4 then $2||'' ok'' else ''FAIL ''||$2||'' got=''||$3 end'$f$;
  execute $f$create function pg_temp.must_fail(o text, label text, q text) returns text language plpgsql as $b$ begin begin execute q; return o || ' | FAIL '||label||' (allowed)'; exception when others then return o || ' | '||label||' blocked('||sqlstate||')'; end; end $b$$f$;
  select id into d1 from auth.users where email='demo1@knit.local'; select id into d2 from auth.users where email='demo2@knit.local';
  insert into public.posts(author_id, body) values (d2, 'victim post') returning id into p2;
  insert into public.works(profile_id, photo_url, title) values (d2, 'x', 'victim work') returning id into w2;
  insert into public.yarn_stash(owner_id, raw_name, bought_balls, left_balls) values (d2, 'victim yarn', 1, 1) returning id into s2;
  insert into public.rooms(kind, created_by) values ('group', d2) returning id into r2; insert into public.room_members(room_id, profile_id) values (r2, d2);
  perform set_config('request.jwt.claims', json_build_object('sub',d1,'role','authenticated')::text, true); set local role authenticated;
  update public.profiles set nickname = 'hacked' where id = d2; get diagnostics n = row_count; out := pg_temp.chk(out, 'upd other profile', n, 0);
  delete from public.posts where id = p2; get diagnostics n = row_count; out := pg_temp.chk(out, 'del other post', n, 0);
  delete from public.works where id = w2; get diagnostics n = row_count; out := pg_temp.chk(out, 'del other work', n, 0);
  delete from public.yarn_stash where id = s2; get diagnostics n = row_count; out := pg_temp.chk(out, 'del other stash', n, 0);
  update public.yarn_stash set left_balls = 0 where id = s2; get diagnostics n = row_count; out := pg_temp.chk(out, 'upd other stash', n, 0);
  update public.posts set body = 'x' where id = p2; get diagnostics n = row_count; out := pg_temp.chk(out, 'upd other post', n, 0);
  update public.yarn_colors set name = 'x' where id = (select min(id) from public.yarn_colors); get diagnostics n = row_count; out := pg_temp.chk(out, 'upd yarn_colors', n, 0);
  out := pg_temp.must_fail(out, 'own is_author', format('update public.profiles set is_author = true where id = %L', d1));
  out := pg_temp.must_fail(out, 'own act_level', format('update public.profiles set act_level = 99 where id = %L', d1));
  out := pg_temp.must_fail(out, 'own level_crochet', format('update public.profiles set level_crochet = 5 where id = %L', d1));
  out := pg_temp.must_fail(out, 'own suspended_at', format('update public.profiles set suspended_at = null where id = %L', d1));
  out := pg_temp.must_fail(out, 'insert post as other', format('insert into public.posts(author_id, body) values (%L, ''spoof'')', d2));
  out := pg_temp.must_fail(out, 'insert admins', format('insert into public.admins(profile_id) values (%L)', d1));
  out := pg_temp.must_fail(out, 'insert notification to other', format('insert into public.notifications(recipient_id, actor_id, kind, snippet) values (%L, %L, ''notice'', ''spam'')', d2, d1));
  out := pg_temp.must_fail(out, 'update yarn_catalog', 'update public.yarn_catalog set product = ''x'' where false');
  out := pg_temp.must_fail(out, 'insert event_shipping', format('insert into public.event_shipping(application_id, profile_id, name, phone, zip, addr) values (gen_random_uuid(), %L, ''a'', ''b'', ''c'', ''d'')', d1));
  out := pg_temp.must_fail(out, 'insert admin_logs', 'insert into public.admin_logs(admin_id, action, target_type, target_id) values (null, ''x'', ''y'', ''z'')');
  out := pg_temp.must_fail(out, 'insert point_events', format('insert into public.point_events(supporter_id, user_id, kind, points, ref_table, ref_id, kst_date, segment) values (1, %L, ''hack'', 100, ''x'', ''y'', current_date, 1)', d1));
  out := pg_temp.must_fail(out, 'insert messages to other room', format('insert into public.messages(room_id, sender_id, body) values (%L, %L, ''x'')', r2, d1));
  reset role;
  raise exception 'RESULT(rolled back): %', out;
end $do$;

-- [P3] 회원(demo1)이 관리자 함수·권한 상승 함수를 부를 수 없는가
do $do$ declare d1 uuid; d2 uuid; out text := ''; v jsonb; n int;
begin
  execute $f$create function pg_temp.must_fail(o text, label text, q text) returns text language plpgsql as $b$ begin begin execute q; return o || ' | FAIL '||label||' (allowed)'; exception when others then return o || ' | '||label||' blocked'; end; end $b$$f$;
  select id into d1 from auth.users where email='demo1@knit.local'; select id into d2 from auth.users where email='demo2@knit.local';
  perform set_config('request.jwt.claims', json_build_object('sub',d1,'role','authenticated')::text, true); set local role authenticated;
  begin select count(*) into n from public.admin_find_users('demo', 5); out := out || ' | ' || case when n = 0 then 'admin_find_users empty' else 'FAIL admin_find_users rows='||n end; exception when others then out := out || ' | admin_find_users blocked'; end;
  out := pg_temp.must_fail(out, 'admin_set_admin', format('select public.admin_set_admin(%L, true)', d1));
  out := pg_temp.must_fail(out, 'admin_suspend_user', format('select public.admin_suspend_user(%L, true, ''x'')', d2));
  out := pg_temp.must_fail(out, 'admin_stats', 'select public.admin_stats()');
  out := pg_temp.must_fail(out, 'admin_broadcast_send', 'select public.admin_broadcast_send(''{}''::jsonb)');
  out := pg_temp.must_fail(out, 'admin_yarn_update', 'select public.admin_yarn_update(''{}''::jsonb)');
  out := pg_temp.must_fail(out, 'admin_yarn_set_gauge', 'select public.admin_yarn_set_gauge(gen_random_uuid(), null, null, true)');   -- schema 68
  out := pg_temp.must_fail(out, 'admin_event_apps', 'select * from public.admin_event_apps(gen_random_uuid())');
  begin v := public.admin_stash_search('a', 0); out := out || ' | ' || case when v is null then 'admin_stash_search hidden' else 'FAIL admin_stash_search visible' end; exception when others then out := out || ' | admin_stash_search blocked'; end;
  out := pg_temp.must_fail(out, 'admin_jigi_tool', 'select public.admin_jigi_tool(''get_item'', ''{}''::jsonb)');
  out := pg_temp.must_fail(out, 'admin_set_author', format('select public.admin_set_author(%L, true)', d1));
  out := pg_temp.must_fail(out, 'admin_yarn_bulk_upsert', 'select public.admin_yarn_bulk_upsert(''{}''::jsonb)');
  out := pg_temp.must_fail(out, 'admin_delete_post', 'select public.admin_delete_post(gen_random_uuid(), ''x'')');
  out := pg_temp.must_fail(out, 'open_support_room(other member)', format('select public.open_support_room(%L)', d2));
  out := pg_temp.must_fail(out, 'jigi_on_shop_claim', 'select public.jigi_on_shop_claim()');
  out := pg_temp.must_fail(out, 'yarn_add_alias', 'select public.yarn_add_alias(gen_random_uuid(), ''x'')');
  out := pg_temp.must_fail(out, 'set_pattern_pkg(any)', 'select public.set_pattern_pkg((select id from public.patterns limit 1), null)');
  v := public.supporter_stats(); out := out || ' | ' || case when v is null then 'supporter_stats hidden' else 'FAIL supporter_stats visible' end;
  reset role;
  raise exception 'RESULT(rolled back): %', out;
end $do$;

-- [P4] 비로그인(anon)은 아무것도 못 읽는가 (app_config 만 허용)
do $do$ declare n int; out text := '';
begin
  execute $f$create function pg_temp.cnt(o text, label text, q text, want int) returns text language plpgsql as $b$ declare k int; begin begin execute q into k; return o || ' | ' || case when k = want then label||' ok' else 'FAIL '||label||' got='||k end; exception when others then return o || ' | '||label||' blocked'; end; end $b$$f$;
  perform set_config('request.jwt.claims', '{"role":"anon"}', true); set local role anon;
  out := pg_temp.cnt(out, 'profiles', 'select count(*) from public.profiles', 0);
  out := pg_temp.cnt(out, 'posts', 'select count(*) from public.posts', 0);
  out := pg_temp.cnt(out, 'works', 'select count(*) from public.works', 0);
  out := pg_temp.cnt(out, 'messages', 'select count(*) from public.messages', 0);
  out := pg_temp.cnt(out, 'meetups', 'select count(*) from public.meetups', 0);
  out := pg_temp.cnt(out, 'shops', 'select count(*) from public.shops', 0);
  out := pg_temp.cnt(out, 'techniques', 'select count(*) from public.techniques', 0);
  out := pg_temp.cnt(out, 'yarn_catalog', 'select count(*) from public.yarn_catalog', 0);
  out := pg_temp.cnt(out, 'app_config>0', 'select least(count(*),1) from public.app_config', 1);
  out := pg_temp.cnt(out, 'yarn_suggest(anon)', 'select count(*) from public.yarn_suggest(''낙양'')', 0);
  out := pg_temp.cnt(out, 'yarn_gauge_search(anon)', 'select jsonb_array_length(public.yarn_gauge_search(''낙양'', ''crochet''))', 0);   -- schema 69
  out := pg_temp.cnt(out, 'pattern_gauge_ctx(anon)', 'select case when public.pattern_gauge_ctx((select id from public.patterns limit 1)) is null then 0 else 1 end', 0);
  out := pg_temp.cnt(out, 'my_patterns_in_progress(anon)', 'select jsonb_array_length(public.my_patterns_in_progress())', 0);   -- schema 71
  out := pg_temp.cnt(out, 'my_pattern_stats(anon)', 'select case when public.my_pattern_stats() = ''{}''::jsonb then 0 else 1 end', 0);
  out := pg_temp.cnt(out, 'yarn_spec(anon)', 'select case when public.yarn_spec(gen_random_uuid()) is null then 0 else 1 end', 0);   -- schema 68
  reset role;
  raise exception 'RESULT(rolled back): %', out;
end $do$;
