-- schema 133 (2026-11-16 대표 확정 시안 cert_review_v3): 완성작품 인증 — 확인 뒤 게시 · 하루 1개 · 뜨개 이야기
-- 올리면 '확인 중'(pending): 글은 숨김(hidden) 상태라 본인만 보이고, 인증 개수·기법·자격에 들어가지 않는다.
-- 대표가 콘솔에서 승인하면 그때 커뮤니티에 올라가고 반영된다. 보완 요청(fix)·반려(rejected)는 사유와 함께 알림.
-- 이미 올라와 있던 인증은 모두 approved(칼럼 기본값)로 그대로 둔다. 옛 앱은 create_work 를 그대로 부르므로 서버가 pending 으로 받는다.

alter table public.works
  add column if not exists review_status text not null default 'approved',
  add column if not exists review_note text,
  add column if not exists reviewed_at timestamptz,
  add column if not exists reviewed_by uuid,
  add column if not exists submitted_at timestamptz,
  add column if not exists review_alerted_at timestamptz,
  add column if not exists fix_reminded_at timestamptz,
  add column if not exists took text,
  add column if not exists knowhow text,
  add column if not exists regret text;
alter table public.works drop constraint if exists works_review_status_chk;
alter table public.works add constraint works_review_status_chk check (review_status in ('pending','fix','approved','rejected'));
alter table public.works drop constraint if exists works_story_chk;
alter table public.works add constraint works_story_chk check (
  (took is null or took in ('1d','3d','1w','2w','1m','long'))
  and (knowhow is null or char_length(knowhow) <= 500)
  and (regret is null or char_length(regret) <= 300)
  and (review_note is null or char_length(review_note) <= 300));
create index if not exists works_review_idx on public.works (review_status, submitted_at) where review_status in ('pending','fix');

-- 다른 회원은 승인된 인증만 읽는다(본인은 자기 것 모두, 관리자는 works_admin_select)
alter policy "works_select" on public.works using (
  (not is_blocked((select auth.uid()), profile_id)) and (review_status = 'approved' or profile_id = (select auth.uid())));

-- 있던 함수는 정의를 그대로 가져와 필요한 줄만 바꾼다(바꿀 자리가 정확히 그 수만큼 있어야 진행)
create or replace function pg_temp.swap(p_def text, p_from text, p_to text, p_n int) returns text language plpgsql as $$
begin
  if (length(p_def) - length(replace(p_def, p_from, ''))) / length(p_from) <> p_n then raise exception 'swap: expected % of [%]', p_n, left(p_from, 60); end if;
  return replace(p_def, p_from, p_to);
end $$;

do $do$
declare d text;
begin
  -- create_work: 하루 1개 · 확인 중으로 받기 · 글은 숨김 · 접수 알림
  d := pg_get_functiondef('public.create_work(text, text[], text[], text, text, text[], jsonb)'::regprocedure);
  d := pg_temp.swap(d, $a$  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;$a$,
    $b$  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  if not coalesce((select pr.is_test from public.profiles pr where pr.id = auth.uid()), false)
     and exists (select 1 from public.works w0 where w0.profile_id = auth.uid() and public.kst_date(w0.created_at) = public.kst_date(now())) then
    raise exception '완성작품 인증은 하루에 하나씩 올릴 수 있어요. 내일 다시 올려 주세요';
  end if;$b$, 1);
  d := pg_temp.swap(d, $a$insert into public.works (profile_id, photo_url,$a$, $b$insert into public.works (review_status, submitted_at, profile_id, photo_url,$b$, 1);
  d := pg_temp.swap(d, $a$values (auth.uid(), p_photos[1], p_photos, p_title,$a$, $b$values ('pending', now(), auth.uid(), p_photos[1], p_photos, p_title,$b$, 1);
  d := pg_temp.swap(d, $a$insert into public.posts (author_id, body, photos, work_id)$a$, $b$insert into public.posts (author_id, body, photos, work_id, hidden)$b$, 1);
  d := pg_temp.swap(d, $a$p_photos, v_work) returning id into v_post;$a$, $b$p_photos, v_work, true) returning id into v_post;
  insert into public.notifications(recipient_id, actor_id, kind, post_id, snippet, link)
    values (auth.uid(), 'e120eb67-b254-4008-92d8-08c95c821e9e', 'notice', v_post,
      left('「'||coalesce(nullif(btrim(p_title),''),'작품')||'」 완성작품 인증을 잘 받았어요. knitup 이 사진과 기법을 확인한 뒤 커뮤니티에 올려 드려요. 확인이 끝나면 알려 드릴게요.', 300),
      jsonb_build_object('type','post','id',v_post,'push','0'));$b$, 1);
  execute d;

  -- 인증 개수·인증된 기법·활동 레벨: 승인된 것만
  d := pg_get_functiondef('public.works_apply_cert()'::regprocedure);
  d := pg_temp.swap(d, $a$where w.profile_id = pid;$a$, $b$where w.profile_id = pid and w.review_status = 'approved';$b$, 2);
  execute d;

  -- 작가 자격(전문 기법 인증 3개): 승인된 것만
  d := pg_get_functiondef('public.author_adv_count(uuid)'::regprocedure);
  d := pg_temp.swap(d, $a$where w.profile_id = p_user$a$, $b$where w.profile_id = p_user and w.review_status = 'approved'$b$, 1);
  execute d;
  d := pg_get_functiondef('public.my_author_eligibility()'::regprocedure);
  d := pg_temp.swap(d, $a$(select count(*) from public.works where profile_id = auth.uid())$a$, $b$(select count(*) from public.works where profile_id = auth.uid() and review_status = 'approved')$b$, 1);
  execute d;

  -- 모임 열기 자격(인증 1회): 승인된 것만
  d := pg_get_functiondef((select p.oid from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'create_meetup' order by p.oid desc limit 1)::regprocedure);
  d := pg_temp.swap(d, $a$if not exists (select 1 from public.works where profile_id = auth.uid()) then raise exception '모임을 열려면 완성작품 인증이 1회 이상 필요해요'; end if;$a$,
    $b$if not exists (select 1 from public.works where profile_id = auth.uid() and review_status = 'approved') then raise exception '모임을 열려면 확인이 끝난 완성작품 인증이 1회 이상 필요해요'; end if;$b$, 1);
  execute d;

  -- 첫 인증 축하·작가 신청 안내: 승인되는 순간에
  d := pg_get_functiondef('public.cheer_on_work()'::regprocedure);
  d := pg_temp.swap(d, $a$  select * into p from public.profiles where id = new.profile_id;$a$,
    $b$  if new.review_status <> 'approved' then return null; end if;
  if tg_op = 'UPDATE' then if old.review_status = 'approved' then return null; end if; end if;
  select * into p from public.profiles where id = new.profile_id;$b$, 1);
  d := pg_temp.swap(d, $a$(select count(*) from public.works where profile_id = new.profile_id) = 1$a$, $b$(select count(*) from public.works where profile_id = new.profile_id and review_status = 'approved') = 1$b$, 1);
  execute d;
end $do$;

drop trigger if exists works_apply_cert on public.works;
create trigger works_apply_cert after insert or delete or update of techniques, review_status on public.works for each row execute function public.works_apply_cert();
drop trigger if exists cheer_work_approved on public.works;
create trigger cheer_work_approved after update of review_status on public.works for each row execute function public.cheer_on_work();

-- 보완 요청을 받은 인증을 본인이 고치면 다시 '확인 중'으로
create or replace function public.works_resubmit() returns trigger
language plpgsql set search_path = public as $$
begin
  if old.review_status = 'fix' and new.review_status = 'fix' and auth.uid() = old.profile_id
     and (new.title, new.note, new.photos, new.techniques, new.custom_techniques, new.tech_photos, new.took, new.knowhow, new.regret)
         is distinct from (old.title, old.note, old.photos, old.techniques, old.custom_techniques, old.tech_photos, old.took, old.knowhow, old.regret) then
    new.review_status := 'pending'; new.submitted_at := now(); new.review_alerted_at := null;
  end if;
  return new;
end $$;
revoke all on function public.works_resubmit() from public, anon, authenticated;
drop trigger if exists works_resubmit on public.works;
create trigger works_resubmit before update on public.works for each row execute function public.works_resubmit();

-- 뜨개 이야기 저장(본인 인증만): took = 걸린 시간, knowhow = 뜨기 노하우, regret = 아쉬운 점
create or replace function public.work_set_story(p_post uuid, p_story jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare v_work uuid; v_took text := nullif(btrim(coalesce(p_story->>'took','')), '');
  v_know text := nullif(left(btrim(coalesce(p_story->>'knowhow','')), 500), ''); v_reg text := nullif(left(btrim(coalesce(p_story->>'regret','')), 300), '');
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  select w.id into v_work from public.posts po join public.works w on w.id = po.work_id where po.id = p_post and w.profile_id = auth.uid();
  if v_work is null then raise exception '내 완성작품 인증이 아니에요'; end if;
  if v_took is not null and v_took not in ('1d','3d','1w','2w','1m','long') then v_took := null; end if;
  if public.contains_banned(coalesce(v_know,'')||' '||coalesce(v_reg,'')) then raise exception '커뮤니티 가이드라인에 맞지 않는 표현이 있어요'; end if;
  update public.works set took = v_took, knowhow = v_know, regret = v_reg where id = v_work;
end $$;
revoke all on function public.work_set_story(uuid, jsonb) from public, anon;
grant execute on function public.work_set_story(uuid, jsonb) to authenticated;

-- 콘솔: 인증 확인 목록 (p_tab: pending | fix | done)
create or replace function public.admin_work_queue(p_tab text default 'pending') returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  select jsonb_build_object(
    'counts', (select jsonb_build_object('pending', count(*) filter (where w.review_status = 'pending'), 'fix', count(*) filter (where w.review_status = 'fix')) from public.works w),
    'items', coalesce((select jsonb_agg(to_jsonb(x)) from (
      select w.id, po.id as post_id, w.title, w.review_status as status, w.review_note as note, w.created_at, w.submitted_at, w.reviewed_at,
        coalesce(po.photos, w.photos) as photos, w.tech_photos, w.custom_techniques as custom, w.took, w.knowhow, w.regret, w.note as memo, w.yarn_info, w.needles, w.gauge, w.finished_size, w.sponsored,
        (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name_ko, 'level', t.level) order by t.sort), '[]'::jsonb) from public.techniques t where t.id = any(w.techniques)) as techs,
        exists (select 1 from public.techniques t where t.id = any(w.techniques) and t.level >= 5) as has5,
        (w.took is null and w.knowhow is null) as no_story, (w.tech_photos is null) as no_tech_photo,
        p.id as profile_id, p.nickname, p.level_crochet, p.level_knit, p.cert_count, coalesce(p.is_test, false) as is_test, coalesce(p.is_author, false) as is_author
      from public.works w join public.profiles p on p.id = w.profile_id
        left join lateral (select q.id, q.photos from public.posts q where q.work_id = w.id and q.parent_id is null order by q.created_at limit 1) po on true
      where case p_tab when 'fix' then w.review_status = 'fix'
                       when 'done' then w.review_status in ('approved','rejected') and w.reviewed_at is not null
                       else w.review_status = 'pending' end
      order by case when p_tab = 'done' then w.reviewed_at end desc nulls last, w.submitted_at asc nulls last
      limit 100) x), '[]'::jsonb)) into r;
  return r;
end $$;
revoke all on function public.admin_work_queue(text) from public, anon;
grant execute on function public.admin_work_queue(text) to authenticated;

-- 콘솔: 승인(approve) · 보완 요청(fix) · 반려(reject). 승인은 대표(관리자)만 — 지기 AI 는 하지 않는다
create or replace function public.admin_work_review(p_work uuid, p_action text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare w public.works; v_post uuid; v_note text := nullif(left(btrim(coalesce(p_note,'')), 300), ''); v_title text; sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e';
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  select * into w from public.works where id = p_work for update;
  if not found then raise exception '인증을 찾을 수 없어요'; end if;
  select q.id into v_post from public.posts q where q.work_id = w.id and q.parent_id is null order by q.created_at limit 1;
  v_title := '「'||coalesce(nullif(btrim(w.title),''),'작품')||'」';
  if p_action = 'approve' then
    if w.review_status = 'approved' then raise exception '이미 승인된 인증이에요'; end if;
    update public.works set review_status = 'approved', reviewed_at = now(), reviewed_by = auth.uid() where id = w.id;
    update public.posts set hidden = false, created_at = now() where id = v_post and hidden and not coalesce(hidden_by_mod, false) and archived_at is null;
    insert into public.notifications(recipient_id, actor_id, kind, post_id, snippet, link)
      values (w.profile_id, sup, 'notice', v_post, left(v_title||' 완성작품 인증이 커뮤니티에 올라갔어요. 적어 주신 이야기가 같은 작품을 뜨는 분께 큰 도움이 될 거예요.', 300),
              case when v_post is not null then jsonb_build_object('type','post','id',v_post) else jsonb_build_object('type','view','view','my') end);
  elsif p_action = 'fix' then
    if w.review_status not in ('pending','fix') then raise exception '확인 중인 인증만 보완을 요청할 수 있어요'; end if;
    if v_note is null then raise exception '무엇을 채워야 하는지 적어 주세요'; end if;
    update public.works set review_status = 'fix', review_note = v_note, reviewed_at = now(), reviewed_by = auth.uid(), fix_reminded_at = null where id = w.id;
    insert into public.notifications(recipient_id, actor_id, kind, post_id, snippet, link)
      values (w.profile_id, sup, 'notice', v_post, left(v_title||' 인증을 올리기 전에 하나만 부탁드려요. '||v_note||' 글을 눌러 고친 뒤 저장하면 다시 확인해 드려요.', 400),
              case when v_post is not null then jsonb_build_object('type','post','id',v_post) else jsonb_build_object('type','view','view','my') end);
  elsif p_action = 'reject' then
    if w.review_status not in ('pending','fix') then raise exception '확인 중인 인증만 반려할 수 있어요'; end if;
    if v_note is null then raise exception '사유를 적어 주세요'; end if;
    update public.works set review_status = 'rejected', review_note = v_note, reviewed_at = now(), reviewed_by = auth.uid() where id = w.id;
    insert into public.notifications(recipient_id, actor_id, kind, post_id, snippet, link)
      values (w.profile_id, sup, 'notice', v_post, left(v_title||' 인증은 커뮤니티에 올리지 못했어요. 사유: '||v_note||' 궁금한 점은 마이 › 설정 › 지기에게 말하기로 물어봐 주세요.', 400),
              jsonb_build_object('type','view','view','support'));
  else raise exception '알 수 없는 동작입니다'; end if;
  perform public.admin_log('work_'||p_action, 'work', w.id::text, jsonb_build_object('title', w.title, 'profile', w.profile_id, 'note', v_note));
  return jsonb_build_object('ok', true, 'status', (select review_status from public.works where id = w.id));
end $$;
revoke all on function public.admin_work_review(uuid, text, text) from public, anon;
grant execute on function public.admin_work_review(uuid, text, text) to authenticated;

-- 대표에게 텔레그램: 새로 들어온 확인 대기(15분마다, 올린 지 3분 지난 것부터 — 기법 사진·이야기 저장이 끝난 뒤)
create or replace function public.work_review_alert() returns int
language plpgsql security definer set search_path = public as $$
declare ids uuid[]; lines text; n int; tot int; oldest int;
begin
  select array_agg(w.id), string_agg('· '||coalesce(p.nickname,'회원')||' 「'||coalesce(nullif(btrim(w.title),''),'작품')||'」'
      ||case when exists (select 1 from public.techniques t where t.id = any(w.techniques) and t.level >= 5) then ' — 전문(5단계) 기법 포함' else '' end
      ||case when w.took is null and w.knowhow is null then ' — 옛 버전 앱(뜨개 이야기 없음)' else '' end, E'\n' order by w.submitted_at)
    into ids, lines
    from public.works w join public.profiles p on p.id = w.profile_id
   where w.review_status = 'pending' and w.review_alerted_at is null and not coalesce(p.is_test, false) and coalesce(w.submitted_at, w.created_at) < now() - interval '3 minutes';
  n := coalesce(array_length(ids, 1), 0);
  if n = 0 then return 0; end if;
  select count(*), coalesce(max(extract(epoch from now() - coalesce(w.submitted_at, w.created_at)) / 3600)::int, 0) into tot, oldest
    from public.works w join public.profiles p on p.id = w.profile_id where w.review_status = 'pending' and not coalesce(p.is_test, false);
  update public.works set review_alerted_at = now() where id = any(ids);
  insert into public.jigi_reminders(due_at, text) values (now(),
    '🧶 완성작품 인증 확인 대기 '||n||'건이 새로 들어왔어요'||E'\n\n'||lines||E'\n\n'||
    '지금 확인을 기다리는 인증은 모두 '||tot||'건이고, 가장 오래 기다린 것은 약 '||oldest||'시간 됐어요.'||E'\n\n'||
    '왜 알려 드리나요: 완성작품 인증은 대표님이 승인해야 커뮤니티에 올라가요. 승인 전에는 올린 분에게만 보이고, 인증 개수·기법·모임·작가 자격에도 들어가지 않아요.'||E'\n\n'||
    '지금 하실 수 있는 일:'||E'\n'||
    '① 콘솔 › 인증 확인(https://yesbeyesnono.github.io/knit-neighbors/admin.html#certs)에서 사진과 고른 기법, 뜨개 이야기를 보고 [승인 · 게시]를 눌러 주세요.'||E'\n'||
    '② 사진이 흐리거나 기법 표시가 맞지 않으면 [보완 요청] — 사유를 고르면 회원에게 보낼 문구가 만들어져요. 회원이 고쳐서 저장하면 다시 확인 대기로 돌아와요.'||E'\n'||
    '③ 완성작이 아니거나 가이드라인에 맞지 않으면 [반려] — 글은 올라가지 않고 사유가 회원에게 전달돼요.');
  return n;
end $$;
revoke all on function public.work_review_alert() from public, anon, authenticated;

-- 매일 09:00 KST: 하루 넘게 기다리는 인증을 대표에게 · 보완 요청 뒤 3일 지난 회원에게 한 번 더
create or replace function public.work_review_daily() returns int
language plpgsql security definer set search_path = public as $$
declare n int; r record; k int := 0; sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e';
begin
  select count(*) into n from public.works w join public.profiles p on p.id = w.profile_id
   where w.review_status = 'pending' and not coalesce(p.is_test, false) and coalesce(w.submitted_at, w.created_at) < now() - interval '24 hours';
  if n > 0 then
    insert into public.jigi_reminders(due_at, text) values (now(),
      '⏰ 하루 넘게 확인을 기다리는 완성작품 인증이 '||n||'건 있어요'||E'\n\n'||
      '올린 분들은 "확인 중"이라는 안내만 받고 기다리고 있어요. 승인 전에는 커뮤니티에 보이지 않고 인증 개수에도 들어가지 않아요.'||E'\n\n'||
      '콘솔 › 인증 확인(https://yesbeyesnono.github.io/knit-neighbors/admin.html#certs)에서 [승인 · 게시], [보완 요청], [반려] 중 하나를 눌러 주세요.');
  end if;
  for r in select w.id, w.profile_id, w.title, w.review_note,
             (select q.id from public.posts q where q.work_id = w.id and q.parent_id is null order by q.created_at limit 1) as post_id
           from public.works w where w.review_status = 'fix' and w.fix_reminded_at is null and w.reviewed_at < now() - interval '3 days' loop
    update public.works set fix_reminded_at = now() where id = r.id;
    insert into public.notifications(recipient_id, actor_id, kind, post_id, snippet, link)
      values (r.profile_id, sup, 'remind', r.post_id, left('「'||coalesce(nullif(btrim(r.title),''),'작품')||'」 인증이 아직 기다리고 있어요. '||coalesce(r.review_note,'')||' 글을 눌러 고친 뒤 저장하면 다시 확인해 드려요.', 400),
              case when r.post_id is not null then jsonb_build_object('type','post','id',r.post_id) else jsonb_build_object('type','view','view','my') end);
    k := k + 1;
  end loop;
  return k;
end $$;
revoke all on function public.work_review_daily() from public, anon, authenticated;

select cron.unschedule('work-review-alert') where exists (select 1 from cron.job where jobname = 'work-review-alert');
select cron.schedule('work-review-alert', '*/15 * * * *', $$select public.work_review_alert()$$);
select cron.unschedule('work-review-daily') where exists (select 1 from cron.job where jobname = 'work-review-daily');
select cron.schedule('work-review-daily', '0 0 * * *', $$select public.work_review_daily()$$);   -- 09:00 KST
