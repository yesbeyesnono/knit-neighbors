-- 156. 뜨친 인증을 통과시키면 그 글에 지기가 축하 댓글을 단다 (2026-11-20 대표 확정 문구 2번 — 마이그레이션 ddeuchin_pass_comment)
--   콘솔 › 이벤트 › 뜨친 인증의 [통과] → 그 글에 지기 계정으로 댓글 한 번(글쓴이에게 댓글 알림이 감). 제외했다가 다시 통과해도 두 번 달지 않는다
--   문구의 날짜(12월 1~4일)는 이번 이벤트(~11-30) 것 — 다음 이벤트 때 고칠 것
create or replace function public.admin_ddeuchin_decide(p_id bigint, p_pass boolean, p_reason text default null::text)
 returns text
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v record; sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e';
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  select * into v from public.ddeuchin_claims where id = p_id for update;
  if v.id is null then raise exception '찾을 수 없어요'; end if;
  if v.status = 'sent' then raise exception '이미 쿠폰을 보낸 건이에요'; end if;
  if p_pass then
    if v.pair is null then raise exception '뜨친·기간 조건을 채우지 못한 글은 통과시킬 수 없어요'; end if;
    update public.ddeuchin_claims set status = 'ok', reason = null, decided_at = now() where id = p_id;
    if exists (select 1 from public.posts where id = v.post_id and parent_id is null)
       and not exists (select 1 from public.posts where parent_id = v.post_id and author_id = sup) then
      insert into public.posts(author_id, parent_id, body)
        values (sup, v.post_id, '뜨친 생기신 것 축하드려요 🎉 #뜨친인증 확인했어요. 커피 쿠폰은 이벤트가 끝난 뒤(12월 1~4일) 두 분께 지기 채팅으로 보내드릴게요 ☕');
    end if;
  else
    update public.ddeuchin_claims set status = 'excluded', reason = coalesce(nullif(trim(p_reason),''), '사진에서 함께 뜬 모습을 확인하지 못했어요'), decided_at = now() where id = p_id;
    insert into public.notifications(recipient_id, actor_id, kind, post_id, snippet, link)
      values (v.author_id, sup, 'notice', v.post_id, left('뜨친 인증 이벤트: 이번 글은 대상이 아니에요 — '||coalesce(nullif(trim(p_reason),''), '사진에서 함께 뜬 모습을 확인하지 못했어요')||'. 궁금한 점은 지기에게 말씀해 주세요.', 200),
              jsonb_build_object('type','view','view','support','push','0'));
  end if;
  perform public.admin_log('ddeuchin_decide', 'ddeuchin', p_id::text, jsonb_build_object('pass', p_pass, 'reason', p_reason));
  return (select status from public.ddeuchin_claims where id = p_id);
end $function$;
