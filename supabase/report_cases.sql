-- schema 124 (2026-11-15 대표 지시): "직접 뜬 것이 아님(fake)" 신고 자동 처리
-- 신고가 들어오면 ① 작성자에게 지기 채팅으로 확인 요청(다른 각도·뜨는 중 사진) ② 신고자에게 접수 안내
-- 작성자가 사진을 보내면 AI(Edge report-flow)가 원래 사진과 비교해 의견만 붙여 **대표에게 넘긴다**(대표: 처음엔 나한테 넘겨) → 콘솔 신고함의 글 상세에서 [그대로 두기]/[숨기기]
-- 3일 동안 답이 없으면 글을 임시로 숨기고(지기 AI 단독 권한 = 임시 숨김까지) 양쪽에 안내 + 텔레그램 보고. 경고·제한·정지·인증 취소·삭제는 여전히 대표만
create table if not exists public.report_cases (
  id bigint generated always as identity primary key,
  post_id uuid not null references public.posts(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'ask' check (status in ('ask','review','ok','hidden','closed')),
  asked_at timestamptz not null default now(),
  due_at timestamptz not null default now() + interval '3 days',
  replied_at timestamptz, reply_msg bigint, verdict jsonb,
  hidden_by_case boolean not null default false,
  decided_by text, closed_at timestamptz, created_at timestamptz not null default now()
);
create unique index if not exists report_cases_open_post on public.report_cases(post_id) where status in ('ask','review','hidden');
alter table public.report_cases enable row level security;
revoke all on public.report_cases from anon, authenticated;
grant select on public.report_cases to authenticated;
grant all on public.report_cases to service_role;
drop policy if exists report_cases_admin_select on public.report_cases;
create policy report_cases_admin_select on public.report_cases for select to authenticated using (public.is_admin());

-- 지기 채팅으로 자동 안내 한 줄('지기 AI'로 표시) + 🔔 알림(푸시)
create or replace function public._jigi_say(p_user uuid, p_body text)
returns void language plpgsql security definer set search_path = 'public'
as $$
declare sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e'; rid uuid;
begin
  if p_user is null or p_user = sup then return; end if;
  rid := public._support_room(p_user);
  insert into public.messages(room_id, sender_id, body, by_ai) values (rid, sup, p_body, true);
  insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
    values (p_user, sup, 'notice', left('지기가 메시지를 보냈어요: '||regexp_replace(p_body, '\s+', ' ', 'g'), 200), jsonb_build_object('type','view','view','support'));
end $$;
revoke all on function public._jigi_say(uuid, text) from public, anon, authenticated;

-- 신고가 들어오면 사건을 열고 양쪽에 안내
create or replace function public.report_case_on_report()
returns trigger language plpgsql security definer set search_path = 'public'
as $$
declare po record; cid bigint; ttl text;
begin
  begin
    if new.reason::text <> 'fake' then return null; end if;
    select p.id, p.author_id, p.parent_id, p.hidden, coalesce(nullif(w.title,''), nullif(left(regexp_replace(coalesce(p.body,''), '\s+', ' ', 'g'), 20), ''), '올리신 글') as title
      into po from public.posts p left join public.works w on w.id = p.work_id where p.id = new.post_id;
    if not found or po.parent_id is not null or po.author_id = new.reporter_id then return null; end if;
    select id into cid from public.report_cases where post_id = new.post_id and status in ('ask','review','hidden');
    if cid is null then
      insert into public.report_cases(post_id, author_id) values (new.post_id, po.author_id) returning id into cid;
      perform public._jigi_say(po.author_id, '안녕하세요, 뜨개동네 지기예요. 올려 주신 「'||po.title||'」 사진에 대해 확인 요청이 들어와 여쭤봐요. 직접 뜨신 작품이라면 다른 각도의 사진이나 뜨는 중에 찍은 사진을 한 장만 이 채팅으로 보여 주실 수 있을까요? 3일 안에 답이 없으면 글은 잠시 숨겨 둘게요.');
    end if;
    perform public._jigi_say(new.reporter_id, '신고해 주셔서 고마워요. 말씀하신 글은 지금 작성자에게 확인하고 있어요. 확인이 끝나면 결과를 다시 알려 드릴게요.');
  exception when others then null;
  end;
  return null;
end $$;
drop trigger if exists post_reports_case on public.post_reports;
create trigger post_reports_case after insert on public.post_reports for each row execute function public.report_case_on_report();

-- 작성자가 지기 채팅에 답하면: 열린 사건이 있을 때 Edge report-flow 를 부른다(사진 비교 → 대표에게 넘김). 지기 AI 1차 응대(support)는 그대로 함께 돈다
create or replace function public.support_on_message()
returns trigger language plpgsql security definer set search_path = 'public'
as $$
declare sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e'; cid bigint; v_secret text;
begin
  begin
    if new.sender_id <> sup and exists (select 1 from public.room_members m where m.room_id = new.room_id and m.profile_id = sup)
       and exists (select 1 from public.rooms r where r.id = new.room_id and r.kind = 'direct') then
      perform public.jigi_call('support');
      select id into cid from public.report_cases where author_id = new.sender_id and status in ('ask','review','hidden') order by id desc limit 1;
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

-- AI 의견 저장 + 대표에게 텔레그램 (Edge report-flow 가 service_role 로 부름)
create or replace function public.report_case_review(p_case bigint, p_verdict jsonb)
returns void language plpgsql security definer set search_path = 'public'
as $$
declare c record; ttl text; nick text;
begin
  select * into c from public.report_cases where id = p_case and status in ('ask','review','hidden'); if not found then return; end if;
  update public.report_cases set status = case when status = 'hidden' then 'hidden' else 'review' end, verdict = p_verdict where id = p_case;
  select coalesce(nullif(w.title,''), left(coalesce(p.body,''), 20)), pr.nickname into ttl, nick from public.posts p left join public.works w on w.id = p.work_id join public.profiles pr on pr.id = p.author_id where p.id = c.post_id;
  insert into public.jigi_reminders(due_at, text) values (now(), '[신고 건 · 대표 확인 필요] 「'||coalesce(ttl,'')||'」(작성자 '||coalesce(nick,'')||')에 "직접 뜬 것이 아님" 신고가 있었고, 작성자가 지기 채팅으로 사진을 보내 왔습니다.'||E'\n\n'||
    'AI 가 원래 올린 사진과 새로 보낸 사진을 비교한 의견(참고용, 틀릴 수 있음):'||E'\n'||
    '· 같은 작품인가: '||coalesce(p_verdict->>'same','판단 못 함')||E'\n'||'· 원래 사진이 AI·광고 사진처럼 보이는가: '||coalesce(p_verdict->>'ai_like','판단 못 함')||E'\n'||'· 이유: '||coalesce(p_verdict->>'reason','(없음)')||E'\n\n'||
    '대표님이 하실 일: 콘솔 › 오늘 › 신고함에서 이 글을 열면 맨 위에 [직접 뜬 것 확인 · 그대로 두기] / [숨기기] 버튼이 있습니다. 누르면 작성자와 신고자에게 결과 안내가 자동으로 가고 신고가 닫힙니다. 작성자가 보낸 사진은 콘솔 › 지기 문의함의 대화에서 볼 수 있습니다.'||E'\n'||'https://yesbeyesnono.github.io/knit-neighbors/admin.html#reports');
end $$;
revoke all on function public.report_case_review(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.report_case_review(bigint, jsonb) to service_role;

-- 결정 실행(공용): ok = 그대로 두기(숨겨져 있었으면 다시 보이게) / not ok = 숨기기. 양쪽에 안내하고 신고를 닫는다
create or replace function public._report_case_close(p_case bigint, p_ok boolean, p_by text, p_why text)
returns void language plpgsql security definer set search_path = 'public'
as $$
declare c record; r record; was boolean;
begin
  select * into c from public.report_cases where id = p_case and status in ('ask','review','hidden'); if not found then raise exception '이미 끝난 건이에요'; end if;
  select hidden into was from public.posts where id = c.post_id;
  if p_ok then
    if c.hidden_by_case and was then update public.posts set hidden = false where id = c.post_id; end if;
    perform public._jigi_say(c.author_id, '보내 주신 사진 잘 확인했어요. 직접 뜨신 작품으로 확인되어 글은 그대로 둘게요. 번거롭게 해 드려 죄송하고, 협조해 주셔서 고맙습니다.');
    for r in select distinct reporter_id from public.post_reports where post_id = c.post_id loop
      perform public._jigi_say(r.reporter_id, '신고해 주신 글은 확인을 마쳤어요. 작성자가 다른 사진을 보내 주어 직접 뜬 작품으로 확인했어요. 살펴 주셔서 고맙습니다.');
    end loop;
  else
    if not coalesce(was,false) then update public.posts set hidden = true where id = c.post_id; end if;
    if p_why = 'timeout' then
      perform public._jigi_say(c.author_id, '확인 요청에 답이 없어 글을 잠시 숨겨 두었어요. 다른 각도의 사진이나 뜨는 중 사진을 이 채팅으로 보내 주시면 확인하고 다시 보이게 할게요.');
    else
      perform public._jigi_say(c.author_id, '확인 결과 직접 뜬 작품으로 보기 어려워 글을 숨겨 두었어요. 뜨개동네의 완성작품 인증은 직접 뜬 작품만 올려 주세요. 다른 의견이 있으면 이 채팅으로 알려 주세요.');
    end if;
    for r in select distinct reporter_id from public.post_reports where post_id = c.post_id loop
      perform public._jigi_say(r.reporter_id, case when p_why = 'timeout' then '신고해 주신 글은 작성자의 답이 없어 우선 숨겨 두었어요. 덕분에 동네가 더 믿을 만해졌어요. 고맙습니다.' else '신고해 주신 글은 확인을 마치고 필요한 조치를 했어요. 덕분에 동네가 더 믿을 만해졌어요. 고맙습니다.' end);
    end loop;
    insert into public.mod_actions(actor, action, target, before, after) values (p_by, 'hide_post', c.post_id::text, jsonb_build_object('hidden', coalesce(was,false)), jsonb_build_object('hidden', true, 'case', p_case, 'why', p_why));
  end if;
  update public.post_reports set reviewed_at = now() where post_id = c.post_id and reviewed_at is null and (p_ok or p_why <> 'timeout');
  update public.report_cases set status = case when p_ok then 'ok' when p_why = 'timeout' then 'hidden' else 'closed' end,
         hidden_by_case = (not p_ok), decided_by = p_by, closed_at = case when p_why = 'timeout' and not p_ok then null else now() end where id = p_case;
end $$;
revoke all on function public._report_case_close(bigint, boolean, text, text) from public, anon, authenticated;

-- 콘솔 버튼(관리자)
create or replace function public.admin_report_case_decide(p_case bigint, p_ok boolean)
returns void language plpgsql security definer set search_path = 'public'
as $$
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  perform public._report_case_close(p_case, p_ok, 'admin', 'decided');
  perform public.admin_log(case when p_ok then 'report_case_ok' else 'report_case_hide' end, 'report_case', p_case::text, '{}'::jsonb);
end $$;
revoke all on function public.admin_report_case_decide(bigint, boolean) from public, anon;
grant execute on function public.admin_report_case_decide(bigint, boolean) to authenticated;

-- 3일 동안 답이 없으면 임시 숨김(매시)
create or replace function public.report_case_tick()
returns integer language plpgsql security definer set search_path = 'public'
as $$
declare c record; n int := 0; ttl text; nick text;
begin
  for c in select * from public.report_cases where status = 'ask' and replied_at is null and due_at < now() loop
    perform public._report_case_close(c.id, false, 'ai', 'timeout');   -- mod_actions.actor 는 'ai'|'admin' 만 n := n + 1;
    select coalesce(nullif(w.title,''), left(coalesce(p.body,''), 20)), pr.nickname into ttl, nick from public.posts p left join public.works w on w.id = p.work_id join public.profiles pr on pr.id = p.author_id where p.id = c.post_id;
    insert into public.jigi_reminders(due_at, text) values (now(), '[신고 건 · 자동 처리 보고] 「'||coalesce(ttl,'')||'」(작성자 '||coalesce(nick,'')||')에 "직접 뜬 것이 아님" 신고가 있어 작성자에게 사진을 요청했지만 3일 동안 답이 없어 **글을 임시로 숨겼습니다**. 작성자와 신고자에게 안내를 보냈습니다.'||E'\n\n'||'숨김은 임시 조치입니다. 작성자가 나중에 사진을 보내면 다시 알려 드리고, 콘솔 › 신고함의 글 상세에서 [직접 뜬 것 확인 · 그대로 두기]를 누르면 글이 다시 보입니다. 경고·인증 취소 같은 추가 조치가 필요하면 대표님이 직접 정해 주세요. 되돌리기: 콘솔 › 지기 AI 관리 › 기록.');
  end loop;
  -- 답은 왔는데(글자만) 사진이 없어 계속 열려 있는 건: 기한이 지나면 대표에게 한 번 알림
  for c in select * from public.report_cases where status = 'ask' and replied_at is not null and due_at < now() and coalesce(verdict->>'nudged','') = '' loop
    update public.report_cases set verdict = coalesce(verdict,'{}'::jsonb) || '{"nudged":"1"}'::jsonb where id = c.id;
    insert into public.jigi_reminders(due_at, text) values (now(), '[신고 건 · 대표 확인 필요] "직접 뜬 것이 아님" 신고 건에서 작성자가 지기 채팅에 답은 했지만 사진은 보내지 않은 채 3일이 지났습니다. 답 내용은 콘솔 › 지기 문의함에서 볼 수 있습니다. 콘솔 › 신고함의 글 상세에서 [그대로 두기] 또는 [숨기기]를 정해 주세요.'||E'\n'||'https://yesbeyesnono.github.io/knit-neighbors/admin.html#reports');
  end loop;
  return n;
end $$;
revoke all on function public.report_case_tick() from public, anon, authenticated;
select cron.unschedule('report-case-tick') where exists (select 1 from cron.job where jobname = 'report-case-tick');
select cron.schedule('report-case-tick', '7 * * * *', $$select public.report_case_tick()$$);

-- 오늘(11-15) 손으로 안내를 보낸 미피 인형 건을 사건으로 등록(안내는 이미 보냈으므로 다시 보내지 않음)
insert into public.report_cases(post_id, author_id, asked_at, due_at)
select 'da81f326-e4e8-407c-8c89-50de187dc87b', '4612d2c0-36ee-4667-bc20-64d607950806', '2026-11-15 11:35:30+09', '2026-11-18 11:35:30+09'
where exists (select 1 from public.posts where id = 'da81f326-e4e8-407c-8c89-50de187dc87b')
  and not exists (select 1 from public.report_cases where post_id = 'da81f326-e4e8-407c-8c89-50de187dc87b');
