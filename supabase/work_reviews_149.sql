-- 149. 승인할 때도 회원에게 한마디 (2026-11-19 대표: "이번에는 승인하지만 다음에는 이렇게 찍어 달라"는 말을 승인과 함께 보내고 싶다)
--   admin_work_review(p_work, 'approve', p_note): p_note 가 있으면 승인 알림의 둘째 문장 자리에 그 글이 들어간다(없으면 지금 문구 그대로). 인자·다른 동작은 그대로
--   work_reviews.note 에 승인 때 보낸 글도 남긴다
create or replace function public.admin_work_review(p_work uuid, p_action text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare w public.works; v_post uuid; v_note text := nullif(left(btrim(coalesce(p_note,'')), 300), ''); v_title text; sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e';
  v_snap jsonb; v_rev bigint;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  select * into w from public.works where id = p_work for update;
  if not found then raise exception '인증을 찾을 수 없어요'; end if;
  v_snap := public._work_review_snap(w.id);
  select q.id into v_post from public.posts q where q.work_id = w.id and q.parent_id is null order by q.created_at limit 1;
  v_title := '「'||coalesce(nullif(btrim(w.title),''),'작품')||'」';
  if p_action = 'approve' then
    if w.review_status = 'approved' then raise exception '이미 승인된 인증이에요'; end if;
    update public.works set review_status = 'approved', reviewed_at = now(), reviewed_by = auth.uid() where id = w.id;
    update public.posts set hidden = false, created_at = now() where id = v_post and hidden and not coalesce(hidden_by_mod, false) and archived_at is null;
    insert into public.notifications(recipient_id, actor_id, kind, post_id, snippet, link)
      values (w.profile_id, sup, 'notice', v_post, left(v_title||' 완성작품 인증이 커뮤니티에 올라갔어요. '||coalesce(v_note, '적어 주신 이야기가 같은 작품을 뜨는 분께 큰 도움이 될 거예요.'), 400),
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
  insert into public.work_reviews(work_id, profile_id, admin_id, action, round, note, snapshot)
    values (w.id, w.profile_id, auth.uid(), p_action, (select count(*) + 1 from public.work_reviews r where r.work_id = w.id), v_note, coalesce(v_snap, '{}'::jsonb))
    returning id into v_rev;
  return jsonb_build_object('ok', true, 'status', (select review_status from public.works where id = w.id), 'review', v_rev);
end $function$;
