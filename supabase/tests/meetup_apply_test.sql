-- schema 109 (참가비 모임: 신청 → 개설자 확정) 동작 테스트. 끝에서 raise exception 으로 전부 롤백 — 아무것도 남지 않는다.
-- demo1 = 개설자, demo2 = 확정될 신청자, demo3 = 취소·거절될 신청자, demo4 = 남. 결과는 'RESULT(rolled back): …' 줄을 읽는다.
do $do$ declare d1 uuid; d2 uuid; d3 uuid; d4 uuid; rid uuid; mid uuid; rid2 uuid; mid2 uuid; o text := ''; n int;
begin
  execute $f$create function pg_temp.t(q text) returns text language plpgsql as $b$ declare r text; begin begin execute q into r; return coalesce(r,'null'); exception when others then return 'ERR '||sqlerrm; end; end $b$$f$;
  select id into d1 from auth.users where email='demo1@knit.local'; select id into d2 from auth.users where email='demo2@knit.local';
  select id into d3 from auth.users where email='demo3@knit.local'; select id into d4 from auth.users where email='demo4@knit.local';
  insert into public.rooms(kind, created_by) values ('group', d1) returning id into rid;
  insert into public.meetups(room_id, created_by, title, starts_at, is_public, capacity, place_name, location) values (rid, d1, 'apply-test', now()+interval '3 days', true, 5, 'test', st_setsrid(st_makepoint(126.77,37.67),4326)) returning id into mid;  insert into public.room_members(room_id, profile_id) values (rid, d1);
  insert into public.rooms(kind, created_by) values ('group', d1) returning id into rid2; insert into public.room_members(room_id, profile_id) values (rid2, d1);
  insert into public.meetups(room_id, created_by, title, starts_at, is_public, capacity, place_name, location) values (rid2, d1, 'open-test', now()+interval '3 days', true, 5, 'test', st_setsrid(st_makepoint(126.77,37.67),4326)) returning id into mid2;

  -- 개설자: 조건 정하기
  perform set_config('request.jwt.claims', json_build_object('sub',d1,'role','authenticated')::text, true); set local role authenticated;
  o := o || E'\n01 terms link(ERR)=' || pg_temp.t(format('select public.meetup_set_terms(%L,%L,%L,%L)', mid, 'http://a.com 참고', 'apply', null));
  o := o || E'\n02 terms acct(ERR)=' || pg_temp.t(format('select public.meetup_set_terms(%L,%L,%L,%L)', mid, '국민 123-456-7890', 'apply', null));
  o := o || E'\n03 terms ok=' || pg_temp.t(format('select public.meetup_set_terms(%L,%L,%L,%L)', mid, '대관비를 나눠 내요', 'apply', '이틀 전까지 전액'));
  o := o || E'\n04 terms saved=' || pg_temp.t(format('select join_mode||''/''||fee_note||''/''||refund_note from public.meetups where id=%L', mid));
  -- 신청자 demo2
  perform set_config('request.jwt.claims', json_build_object('sub',d2,'role','authenticated')::text, true);
  o := o || E'\n05 other set_terms(ERR)=' || pg_temp.t(format('select public.meetup_set_terms(%L,%L,%L,%L)', mid, 'x', 'open', null));
  o := o || E'\n06 old join_meetup(ERR)=' || pg_temp.t(format('select public.join_meetup(%L)', mid));
  o := o || E'\n07 direct room insert(ERR)=' || pg_temp.t(format('insert into public.room_members(room_id, profile_id) values (%L,%L)', rid, d2));
  o := o || E'\n08 apply=' || pg_temp.t(format('select public.meetup_apply(%L,%L)', mid, '안녕하세요'));
  o := o || E'\n09 apply again=' || pg_temp.t(format('select public.meetup_apply(%L,null)', mid));
  o := o || E'\n10 self accept by update(ERR)=' || pg_temp.t(format('update public.meetup_applications set status=''accepted'' where meetup_id=%L', mid));
  o := o || E'\n11 self decide(ERR)=' || pg_temp.t(format('select public.meetup_decide(%L,%L,true)', mid, d2));
  o := o || E'\n12 summary mine=' || pg_temp.t(format('select public.meetup_app_summary(%L)', mid));
  -- 남 demo4
  perform set_config('request.jwt.claims', json_build_object('sub',d4,'role','authenticated')::text, true);
  o := o || E'\n13 outsider rows(0)=' || pg_temp.t(format('select count(*) from public.meetup_applications where meetup_id=%L', mid));
  o := o || E'\n14 outsider applicants(ERR)=' || pg_temp.t(format('select count(*) from public.meetup_applicants(%L)', mid));
  o := o || E'\n15 outsider decide(ERR)=' || pg_temp.t(format('select public.meetup_decide(%L,%L,true)', mid, d2));
  reset role; update public.meetups set starts_at = now() - interval '1 day' where id = mid;
  perform set_config('request.jwt.claims', json_build_object('sub',d3,'role','authenticated')::text, true); set local role authenticated;
  o := o || E'\n16 past meetup apply(ERR)=' || pg_temp.t(format('select public.meetup_apply(%L,null)', mid));
  reset role; update public.meetups set starts_at = now() + interval '3 days', participant_count = 5 where id = mid;
  select count(*) into n from public.notifications where recipient_id = d1 and link->>'id' = mid::text; o := o || E'\n17 host notified(1)=' || n;
  -- 개설자: 정원·확정
  perform set_config('request.jwt.claims', json_build_object('sub',d1,'role','authenticated')::text, true); set local role authenticated;
  o := o || E'\n18 host summary=' || pg_temp.t(format('select public.meetup_app_summary(%L)', mid));
  o := o || E'\n19 applicants(1)=' || pg_temp.t(format('select count(*) from public.meetup_applicants(%L)', mid));
  o := o || E'\n20 accept when full(ERR)=' || pg_temp.t(format('select public.meetup_decide(%L,%L,true)', mid, d2));
  reset role; update public.meetups set participant_count = 1 where id = mid;
  perform set_config('request.jwt.claims', json_build_object('sub',d1,'role','authenticated')::text, true); set local role authenticated;
  o := o || E'\n21 accept=' || pg_temp.t(format('select public.meetup_decide(%L,%L,true)', mid, d2));
  o := o || E'\n22 accept twice(ERR)=' || pg_temp.t(format('select public.meetup_decide(%L,%L,true)', mid, d2));
  reset role;
  select count(*) into n from public.room_members where room_id = rid and profile_id = d2; o := o || E'\n23 in room(1)=' || n;
  select participant_count into n from public.meetups where id = mid; o := o || E'\n24 participant_count(2)=' || n;
  select count(*) into n from public.notifications where recipient_id = d2 and link->>'id' = mid::text; o := o || E'\n25 applicant notified(1)=' || n;
  -- 확정된 demo2: 취소 함수는 확정을 못 바꿈, 다시 신청 불가
  perform set_config('request.jwt.claims', json_build_object('sub',d2,'role','authenticated')::text, true); set local role authenticated;
  o := o || E'\n26 cancel after accept=' || pg_temp.t(format('select public.meetup_cancel_apply(%L)', mid));
  o := o || E'\n27 still accepted=' || pg_temp.t(format('select status from public.meetup_applications where meetup_id=%L and profile_id=%L', mid, d2));
  o := o || E'\n28 apply when member(ERR)=' || pg_temp.t(format('select public.meetup_apply(%L,null)', mid));
  o := o || E'\n29 open meetup apply(ERR)=' || pg_temp.t(format('select public.meetup_apply(%L,null)', mid2));
  o := o || E'\n30 open meetup join(uuid)=' || pg_temp.t(format('select public.join_meetup(%L)', mid2));
  -- demo3: 거절
  perform set_config('request.jwt.claims', json_build_object('sub',d3,'role','authenticated')::text, true);
  o := o || E'\n35 d3 apply=' || pg_temp.t(format('select public.meetup_apply(%L,null)', mid));
  o := o || E'\n36 d3 cancel=' || pg_temp.t(format('select public.meetup_cancel_apply(%L)', mid));
  o := o || E'\n37 d3 status=' || pg_temp.t(format('select status from public.meetup_applications where meetup_id=%L and profile_id=%L', mid, d3));
  o := o || E'\n38 d3 re-apply=' || pg_temp.t(format('select public.meetup_apply(%L,null)', mid));
  o := o || E'\n31 d3 apply=' || pg_temp.t(format('select public.meetup_apply(%L,null)', mid));
  perform set_config('request.jwt.claims', json_build_object('sub',d1,'role','authenticated')::text, true);
  o := o || E'\n32 reject=' || pg_temp.t(format('select public.meetup_decide(%L,%L,false)', mid, d3));
  perform set_config('request.jwt.claims', json_build_object('sub',d3,'role','authenticated')::text, true);
  o := o || E'\n33 rejected re-apply(ERR)=' || pg_temp.t(format('select public.meetup_apply(%L,null)', mid));
  o := o || E'\n34 rejected join_meetup(ERR)=' || pg_temp.t(format('select public.join_meetup(%L)', mid));
  -- 비로그인
  reset role; perform set_config('request.jwt.claims', '{"role":"anon"}', true); set local role anon;
  o := o || E'\n39 anon apply(ERR)=' || pg_temp.t(format('select public.meetup_apply(%L,null)', mid));
  o := o || E'\n40 anon rows(ERR)=' || pg_temp.t('select count(*) from public.meetup_applications');
  o := o || E'\n41 anon summary(ERR)=' || pg_temp.t(format('select public.meetup_app_summary(%L)', mid));
  reset role;
  raise exception 'RESULT(rolled back): %', o;
end $do$;
