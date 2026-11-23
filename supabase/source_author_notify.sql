-- 168. 내 도안으로 뜬 작품이 올라오면 작가에게 알린다 (2026-11-23 대표 지시 — 마이그레이션 source_author_notify)
--   완성작품 인증이 승인되어 게시됐고, 그 인증의 도안(work_sources)이 앱 작가 계정과 묶여 있으면(maker_profile) 그 작가에게 지기 이름으로 알림 한 번.
--   "○○ 작가님, 반가운 소식이에요 🧶 △△ 님이 작가님 도안으로 「작품」 완성작품 인증을 올리셨어요. 한번 보시고 댓글로 한마디 남겨 주시면 △△ 님께 큰 힘이 될 거예요." (누르면 그 작품 글)
--   작품마다 한 번(works.maker_notified_at) · 올린 지 14일 안의 것만(묶기·합치기로 옛 작품이 한꺼번에 알려지지 않게) · 본인 작품 · 차단 사이 · 테스트 계정의 글은 보내지 않는다
--   나중에 도안이 작가와 묶인 경우(콘솔에서 잇기 · 이름 고치기)에도 아직 알리지 않은 최근 작품 3개까지 알린다

alter table public.works add column if not exists maker_notified_at timestamptz;

create or replace function public.source_author_notify(p_work uuid)
 returns void language plpgsql security definer set search_path to 'public' as $function$
declare w public.works; s public.work_sources; v_post uuid; v_nick text; v_test boolean; v_anick text; v_atest boolean;
begin
  select * into w from public.works where id = p_work for update;
  if w.id is null or w.review_status <> 'approved' or w.source_id is null or w.maker_notified_at is not null then return; end if;
  if coalesce(w.submitted_at, w.created_at) < now() - interval '14 days' then return; end if;
  select * into s from public.work_sources where id = w.source_id;
  if s.id is null or s.maker_profile is null or s.maker_profile = w.profile_id or s.status = 'excluded' then return; end if;
  select coalesce(nullif(btrim(nickname), ''), '회원'), coalesce(is_test, false) into v_nick, v_test from public.profiles where id = w.profile_id;
  select coalesce(nullif(btrim(nickname), ''), ''), coalesce(is_test, false) into v_anick, v_atest from public.profiles where id = s.maker_profile;
  if v_test and not v_atest then return; end if;
  if public.is_blocked(s.maker_profile, w.profile_id) then return; end if;
  select id into v_post from public.posts where work_id = w.id order by created_at limit 1;
  if v_post is null then return; end if;
  update public.works set maker_notified_at = now() where id = w.id;
  insert into public.notifications(recipient_id, actor_id, kind, post_id, link, snippet)
  values (s.maker_profile, 'e120eb67-b254-4008-92d8-08c95c821e9e'::uuid, 'notice', v_post, jsonb_build_object('type', 'post', 'id', v_post),
    btrim(v_anick || ' 작가님, 반가운 소식이에요 🧶 ') || ' ' || v_nick || ' 님이 작가님 도안으로 「' || coalesce(nullif(btrim(w.title), ''), '작품') || '」 완성작품 인증을 올리셨어요. 한번 보시고 댓글로 한마디 남겨 주시면 ' || v_nick || ' 님께 큰 힘이 될 거예요.');
exception when others then null;   -- 알림 실패가 승인·저장을 막으면 안 된다
end $function$;
revoke all on function public.source_author_notify(uuid) from public, anon, authenticated;
grant execute on function public.source_author_notify(uuid) to service_role;

create or replace function public.trg_source_author_notify()
 returns trigger language plpgsql security definer set search_path to 'public' as $function$
declare r record;
begin
  if tg_table_name = 'works' then
    perform public.source_author_notify(new.id);
  else   -- work_sources: 도안이 작가와 새로 묶였을 때
    for r in select id from public.works where source_id = new.id and review_status = 'approved' and maker_notified_at is null order by created_at desc limit 3 loop
      perform public.source_author_notify(r.id);
    end loop;
  end if;
  return null;
end $function$;
revoke all on function public.trg_source_author_notify() from public, anon, authenticated;

drop trigger if exists works_source_author_notify on public.works;
create trigger works_source_author_notify after update of review_status, source_id on public.works
  for each row when (new.review_status = 'approved' and new.source_id is not null and new.maker_notified_at is null)
  execute function public.trg_source_author_notify();
drop trigger if exists work_sources_author_notify on public.work_sources;
-- 칼럼 목록을 두지 않는다: maker_profile 은 BEFORE 트리거(이름으로 작가 찾기)가 채우므로 'update of maker_profile' 로는 걸리지 않는다
create trigger work_sources_author_notify after update on public.work_sources
  for each row when (new.maker_profile is not null and new.maker_profile is distinct from old.maker_profile)
  execute function public.trg_source_author_notify();
