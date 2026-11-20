-- 160. 보낸 뜨친 신청 취소 (2026-11-20 대표 확정 시안 friend_cancel_v1 — 문의 #20 "보낸 친구신청 취소하는 방법")
--   취소 자체는 원래 정책(friendships_delete_own_request: 내가 보낸 pending 만 삭제)으로 된다. 앱에 버튼이 없었을 뿐.
--   여기서는 취소(=pending 줄 삭제)될 때 상대에게 갔던 '뜨친 신청' 알림을 함께 지운다(상대에게 '취소했다'는 알림은 보내지 않는다).
create or replace function public.friend_request_cleanup()
returns trigger language plpgsql security definer set search_path to 'public' as $fn$
begin
  if old.status = 'pending' then
    delete from public.notifications
     where recipient_id = old.addressee_id and actor_id = old.requester_id and kind = 'friend_request';
  end if;
  return null;
end $fn$;
revoke all on function public.friend_request_cleanup() from public, anon, authenticated;
drop trigger if exists friendships_cancel_cleanup on public.friendships;
create trigger friendships_cancel_cleanup after delete on public.friendships
  for each row execute function public.friend_request_cleanup();
