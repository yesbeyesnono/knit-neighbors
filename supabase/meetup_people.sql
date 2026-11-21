-- 167. 모임에 누가 참여하는지 보이게 (2026-11-21 대표 확정 시안 meet_people_v1 — 마이그레이션 meetup_people)
--   지금까지는 "참여 2명"처럼 숫자만 보이고, 누가 오는지는 단체 채팅방에 들어가야 알 수 있었다.
--   meetup_people(p_ids, p_limit): 모임마다 참여자 수와 앞의 몇 명(주최자 먼저, 그다음 참여한 순서).
--   공개 모임은 로그인한 회원 누구에게나, '초대만' 모임은 참여한 사람에게만. 신청제 모임은 확정되어 채팅방에 들어온 분만(대기 중인 신청자는 room_members 에 없음).
--   정지·삭제 유예 회원, 서로 차단한 회원, 테스트 계정(테스트 계정끼리만)은 뺀다. 내보내는 것은 프로필에 이미 보이는 것(닉네임·사진·동네 이름·단계)뿐.
create or replace function public.meetup_people(p_ids uuid[], p_limit int default 5)
 returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare v_test boolean; v_lim int := least(greatest(coalesce(p_limit, 5), 1), 50); r jsonb;
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  select coalesce(is_test, false) into v_test from public.profiles where id = auth.uid();
  select coalesce(jsonb_object_agg(m.id, jsonb_build_object('n', x.n, 'rows', x.rows)), '{}'::jsonb) into r
    from public.meetups m
    cross join lateral (
      select count(*) n,
             coalesce(jsonb_agg(jsonb_build_object('id', q.id, 'nickname', q.nickname, 'avatar_url', q.avatar_url, 'dong_name', q.dong_name,
                 'level_crochet', q.level_crochet, 'level_knit', q.level_knit, 'host', q.host) order by q.rn) filter (where q.rn <= v_lim), '[]'::jsonb) rows
        from (select p.id, p.nickname, p.avatar_url, p.dong_name, p.level_crochet, p.level_knit, (p.id = m.created_by) host,
                     row_number() over (order by (p.id = m.created_by) desc, rm.joined_at) rn
                from public.room_members rm join public.profiles p on p.id = rm.profile_id
               where rm.room_id = m.room_id and rm.left_at is null
                 and p.suspended_at is null and p.deleted_at is null
                 and (not coalesce(p.is_test, false) or v_test)
                 and not public.is_blocked(auth.uid(), p.id)) q) x
   where m.id = any(p_ids[1:40])
     and (m.is_public or exists (select 1 from public.room_members me where me.room_id = m.room_id and me.profile_id = auth.uid() and me.left_at is null));
  return r;
end $function$;
revoke all on function public.meetup_people(uuid[], int) from public, anon;
grant execute on function public.meetup_people(uuid[], int) to authenticated;
