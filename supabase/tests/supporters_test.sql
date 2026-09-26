-- 서포터즈 자동 테스트 (supporters_spec.md §4). 각 블록은 마지막에 raise exception 'RESULT(rolled back): ...' 로 끝나 아무것도 남기지 않는다.
-- 실행: Supabase SQL 에디터 또는 MCP execute_sql 에 블록 하나씩. 통과 = RESULT 문자열에 FAIL 이 없음. 사용자는 demo1~6@knit.local 만 쓴다.

-- [T1] 정원·중복 신청·마감: capacity 2 로 줄이고 demo1·2·3 신청
do $$ declare d1 uuid; d2 uuid; d3 uuid; r1 jsonb; r1b jsonb; r2 jsonb; r3 jsonb; n int; op boolean; out text := '';
begin
  select id into d1 from auth.users where email='demo1@knit.local'; select id into d2 from auth.users where email='demo2@knit.local'; select id into d3 from auth.users where email='demo3@knit.local';
  update supporter_cohorts set capacity = 2, is_open = true;
  perform set_config('request.jwt.claims', json_build_object('sub',d1,'role','authenticated')::text, true); set local role authenticated;
  r1 := join_supporters(); r1b := join_supporters();
  reset role; perform set_config('request.jwt.claims', json_build_object('sub',d2,'role','authenticated')::text, true); set local role authenticated;
  r2 := join_supporters();
  reset role; perform set_config('request.jwt.claims', json_build_object('sub',d3,'role','authenticated')::text, true); set local role authenticated;
  r3 := join_supporters();
  reset role;
  select count(*) into n from supporters where user_id = d1; select is_open into op from supporter_cohorts order by id desc limit 1;
  out := out || case when (r1->>'supporter')='true' then 'join1 ok' else 'FAIL join1 '||r1::text end;
  out := out || ' | ' || case when n = 1 and (r1b->>'id') = (r1->>'id') then 'dup ok(1 row)' else 'FAIL dup n='||n end;
  out := out || ' | ' || case when (r2->>'supporter')='true' then 'join2 ok' else 'FAIL join2' end;
  out := out || ' | ' || case when r3->>'error' = 'FULL' and op = false then '3rd FULL + closed ok' else 'FAIL 3rd '||r3::text||' open='||op end;
  raise exception 'RESULT(rolled back): %', out;
end $$;

-- [T2] 출석 1일 1점 · 글 3점/일 · 댓글 2점/일 · 본인 글 댓글 0 · 작품 10점/일 · 삭제 차감 · 비서포터 0
do $$ declare d1 uuid; d2 uuid; sid bigint; p1 uuid; p2 uuid; c1 uuid; c2 uuid; c3 uuid; cs uuid; w1 uuid; w2 uuid; pts int; out text := ''; a1 int; a2 int;
  f_sum int; begin
  select id into d1 from auth.users where email='demo1@knit.local'; select id into d2 from auth.users where email='demo2@knit.local';
  perform set_config('request.jwt.claims', json_build_object('sub',d1,'role','authenticated')::text, true); set local role authenticated;
  perform join_supporters(); perform check_in(); perform check_in();
  reset role; select id into sid from supporters where user_id = d1;
  select coalesce(sum(points),0) into a1 from point_events where supporter_id = sid and kind='attendance';
  out := out || case when a1 = 1 then 'attendance 1 ok' else 'FAIL attendance '||a1 end;
  -- 글 2개 → 3점만
  insert into posts(author_id, body) values (d1, 'T2 글1') returning id into p1; insert into posts(author_id, body) values (d1, 'T2 글2') returning id into p2;
  select coalesce(sum(points),0) into pts from point_events where supporter_id = sid and kind='post';
  out := out || ' | ' || case when pts = 3 then 'post cap 3 ok' else 'FAIL post '||pts end;
  -- demo2 글에 댓글 3개 → 2점, 본인 글 댓글 → 0
  insert into posts(author_id, body) values (d2, 'T2 남의 글') returning id into c1;
  insert into posts(author_id, parent_id, body) values (d1, c1, '댓1'), (d1, c1, '댓2'), (d1, c1, '댓3');
  insert into posts(author_id, parent_id, body) values (d1, p1, '본인 글 댓글') returning id into cs;
  select coalesce(sum(points),0) into pts from point_events where supporter_id = sid and kind='comment';
  out := out || ' | ' || case when pts = 2 then 'comment cap 2 ok' else 'FAIL comment '||pts end;
  out := out || ' | ' || case when not exists (select 1 from point_events where ref_id = cs::text) then 'self-comment 0 ok' else 'FAIL self-comment' end;
  -- 작품 2개 같은 날 → 10점
  insert into works(profile_id, photo_url, photos, title, techniques) values (d1, 'x', array['x'], 'w1', array['C01']) returning id into w1;
  insert into works(profile_id, photo_url, photos, title, techniques) values (d1, 'x', array['x'], 'w2', array['C01']) returning id into w2;
  select coalesce(sum(points),0) into pts from point_events where supporter_id = sid and kind='work_verified';
  out := out || ' | ' || case when pts = 10 then 'work 10/day ok' else 'FAIL work '||pts end;
  -- 글 삭제 → -3
  delete from posts where id = p1;
  select coalesce(sum(points),0) into pts from point_events where supporter_id = sid and kind in ('post','post_revoke');
  out := out || ' | ' || case when pts = 0 and exists (select 1 from point_events where kind='post_revoke' and ref_id=p1::text) then 'delete revoke ok' else 'FAIL revoke '||pts end;
  -- 비서포터(demo2) 활동은 적립 없음
  out := out || ' | ' || case when not exists (select 1 from point_events where user_id = d2) then 'non-supporter 0 ok' else 'FAIL non-supporter' end;
  raise exception 'RESULT(rolled back): %', out;
end $$;

-- [T3] 설문 회차당 1번 · 버그 채택 10/반려 0 · 초대(다음 날 접속) · 자기추천/기존계정 차단
do $$ declare d1 uuid; d2 uuid; d3 uuid; sid bigint; sv int; r jsonb; pts int; fid1 bigint; fid2 bigint; out text := ''; code text; ref jsonb; ref2 jsonb; ref3 jsonb;
begin
  select id into d1 from auth.users where email='demo1@knit.local'; select id into d2 from auth.users where email='demo2@knit.local'; select id into d3 from auth.users where email='demo3@knit.local';
  perform set_config('request.jwt.claims', json_build_object('sub',d1,'role','authenticated')::text, true); set local role authenticated;
  perform join_supporters(); reset role;
  select id, ref_code into sid, code from supporters where user_id = d1;
  insert into surveys(cohort_id, round, title, questions) values ((select id from supporter_cohorts order by id desc limit 1), 1, 'T3', '[]') returning id into sv;
  perform set_config('request.jwt.claims', json_build_object('sub',d1,'role','authenticated')::text, true); set local role authenticated;
  perform submit_survey(sv, '{"q1":"a"}'); perform submit_survey(sv, '{"q1":"b"}');
  reset role;
  select coalesce(sum(points),0) into pts from point_events where supporter_id = sid and kind='survey';
  out := out || case when pts = 10 then 'survey once 10 ok' else 'FAIL survey '||pts end;
  -- 버그 제보 2건: 채택 / 반려
  insert into feedback_reports(user_id, body) values (d1, 'T3 버그 채택용') returning id into fid1;
  insert into feedback_reports(user_id, body) values (d1, 'T3 버그 반려용') returning id into fid2;
  perform set_config('request.jwt.claims', json_build_object('sub','e120eb67-b254-4008-92d8-08c95c821e9e','role','authenticated')::text, true); set local role authenticated;
  perform admin_feedback_decide(fid1, true, null); perform admin_feedback_decide(fid2, false, null); reset role;
  select coalesce(sum(points),0) into pts from point_events where supporter_id = sid and kind='bug_accepted';
  out := out || ' | ' || case when pts = 10 then 'bug accept 10/reject 0 ok' else 'FAIL bug '||pts end;
  -- 초대: demo2 를 '새 계정'으로(가입 오늘 → 같은 날 접속 0점, 어제 가입으로 바꾸면 +20)
  update profiles set referred_by = null, created_at = now() where id = d2; delete from referrals where invitee_user_id = d2;
  perform set_config('request.jwt.claims', json_build_object('sub',d2,'role','authenticated')::text, true); set local role authenticated;
  ref := set_referrer(code, null); perform check_in();
  reset role;
  select coalesce(sum(points),0) into pts from point_events where supporter_id = sid and kind='referral';
  out := out || ' | ' || case when (ref->>'ok')='true' and pts = 0 then 'referral same-day 0 ok' else 'FAIL ref same-day '||ref::text||' pts='||pts end;
  update profiles set created_at = now() - interval '1 day' where id = d2;
  perform set_config('request.jwt.claims', json_build_object('sub',d2,'role','authenticated')::text, true); set local role authenticated;
  perform check_in(); ref2 := set_referrer(null, 'demo3');   -- 추천인 변경 시도
  reset role;
  select coalesce(sum(points),0) into pts from point_events where supporter_id = sid and kind='referral';
  out := out || ' | ' || case when pts = 20 then 'referral next-day +20 ok' else 'FAIL ref next-day '||pts end;
  out := out || ' | ' || case when ref2->>'error' = 'ALREADY' then 'change blocked ok' else 'FAIL change '||ref2::text end;
  -- 자기 추천 · 기존 계정
  update profiles set referred_by = null, created_at = now() where id = d1;
  perform set_config('request.jwt.claims', json_build_object('sub',d1,'role','authenticated')::text, true); set local role authenticated;
  ref3 := set_referrer(code, null); reset role;
  out := out || ' | ' || case when ref3->>'error' = 'SELF' then 'self blocked ok' else 'FAIL self '||ref3::text end;
  update profiles set referred_by = null, created_at = now() - interval '3 days' where id = d3;
  perform set_config('request.jwt.claims', json_build_object('sub',d3,'role','authenticated')::text, true); set local role authenticated;
  ref3 := set_referrer(code, null); reset role;
  out := out || ' | ' || case when ref3->>'error' = 'NOT_NEW' then 'old account blocked ok' else 'FAIL old '||ref3::text end;
  raise exception 'RESULT(rolled back): %', out;
end $$;

-- [T4] 구간 경계(29일차=1구간, 30일차=2구간) · 60일 이후 0 · tier 판정 · MVP · 응원 알림 1회
do $$ declare d1 uuid; d2 uuid; d3 uuid; s1 bigint; s2 bigint; s3 bigint; seg29 int; seg30 int; p60 int; out text := ''; fin jsonb; t1 text; t2 text; t3 text; nn int; i int;
begin
  select id into d1 from auth.users where email='demo1@knit.local'; select id into d2 from auth.users where email='demo2@knit.local'; select id into d3 from auth.users where email='demo3@knit.local';
  update supporter_cohorts set capacity = 100, is_open = true;
  insert into supporters(user_id, cohort_id, started_at, ends_at, ref_code) values
    (d1, (select id from supporter_cohorts order by id desc limit 1), now() - interval '61 days', now() - interval '1 day', 'T4AAAA'),
    (d2, (select id from supporter_cohorts order by id desc limit 1), now() - interval '61 days', now() - interval '1 day', 'T4BBBB'),
    (d3, (select id from supporter_cohorts order by id desc limit 1), now() - interval '61 days', now() - interval '1 day', 'T4CCCC');
  select id into s1 from supporters where user_id = d1; select id into s2 from supporters where user_id = d2; select id into s3 from supporters where user_id = d3;
  -- 구간 경계: 시작일 +29일 / +30일 시점의 이벤트
  perform award_points(d1, 'post', 'test', 'seg29', (select started_at from supporters where id = s1) + interval '29 days' + interval '1 hour');
  perform award_points(d1, 'post', 'test', 'seg30', (select started_at from supporters where id = s1) + interval '30 days' + interval '1 hour');
  select segment into seg29 from point_events where ref_id='seg29'; select segment into seg30 from point_events where ref_id='seg30';
  out := out || case when seg29 = 1 and seg30 = 2 then 'segment boundary ok' else format('FAIL segment %s/%s', seg29, seg30) end;
  p60 := award_points(d1, 'post', 'test', 'day60', (select started_at from supporters where id = s1) + interval '60 days' + interval '1 hour');
  out := out || ' | ' || case when p60 = 0 then 'after 60d 0 ok' else 'FAIL after60 '||p60 end;
  delete from point_events where supporter_id = s1;
  -- 점수 만들기: d1 (120, 90) → none, d2 (100,100) → basic, d3 (150,160) → excellent
  for i in 1..12 loop perform award_points(d1, 'bug_accepted', 'test', 'a'||i, (select started_at from supporters where id=s1) + interval '5 days'); end loop;
  for i in 1..9 loop perform award_points(d1, 'bug_accepted', 'test', 'b'||i, (select started_at from supporters where id=s1) + interval '40 days'); end loop;
  for i in 1..10 loop perform award_points(d2, 'bug_accepted', 'test', 'c'||i, (select started_at from supporters where id=s2) + interval '5 days'); end loop;
  for i in 1..10 loop perform award_points(d2, 'bug_accepted', 'test', 'd'||i, (select started_at from supporters where id=s2) + interval '40 days'); end loop;
  for i in 1..15 loop perform award_points(d3, 'bug_accepted', 'test', 'e'||i, (select started_at from supporters where id=s3) + interval '5 days'); end loop;
  for i in 1..16 loop perform award_points(d3, 'bug_accepted', 'test', 'f'||i, (select started_at from supporters where id=s3) + interval '40 days'); end loop;
  -- 응원 알림: d3 는 1구간 30·60·90 각 1회만
  select count(*) into nn from supporter_notices where supporter_id = s3 and notice_key like 'seg1_%';
  out := out || ' | ' || case when nn = 3 then 'cheer once each ok' else 'FAIL cheer '||nn end;
  -- 다른 active 서포터가 없어야 MVP 확정되므로 실제 운영 서포터는 이 트랜잭션 안에서만 잠시 withdrawn 처리
  update supporters set status = 'withdrawn' where status = 'active' and id not in (s1, s2, s3);
  fin := finalize_supporters();
  select tier into t1 from supporters where id = s1; select tier into t2 from supporters where id = s2; select tier into t3 from supporters where id = s3;
  out := out || ' | ' || case when t1 = 'none' and t2 = 'basic' and t3 = 'mvp' then 'tier none/basic/excellent→mvp ok' else format('FAIL tier %s/%s/%s', t1, t2, t3) end;
  out := out || ' | ' || case when (select supporter_badge from profiles where id = d2) = '1기 서포터' and (select supporter_badge from profiles where id = d1) is null then 'badge ok' else 'FAIL badge' end;
  raise exception 'RESULT(rolled back): %', out;
end $$;

-- [T5] RLS: 남의 point_events 조회 불가, 클라이언트 직접 insert 불가
do $$ declare d1 uuid; d2 uuid; sid bigint; n int; ins text := 'FAIL insert allowed';
begin
  select id into d1 from auth.users where email='demo1@knit.local'; select id into d2 from auth.users where email='demo2@knit.local';
  perform set_config('request.jwt.claims', json_build_object('sub',d1,'role','authenticated')::text, true); set local role authenticated;
  perform join_supporters(); perform check_in(); reset role;
  select id into sid from supporters where user_id = d1;
  perform set_config('request.jwt.claims', json_build_object('sub',d2,'role','authenticated')::text, true); set local role authenticated;
  select count(*) into n from point_events where user_id = d1;
  begin insert into point_events(supporter_id, user_id, kind, points, ref_table, ref_id, kst_date, segment) values (sid, d2, 'post', 3, 'x', 'y', current_date, 1); exception when others then ins := 'insert blocked ok ('||sqlstate||')'; end;
  reset role;
  raise exception 'RESULT(rolled back): others-select=% (0 ok) | %', n, ins;
end $$;
