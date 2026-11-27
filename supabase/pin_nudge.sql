-- 171. 인증을 올린 회원이 지도 핀을 꺼 두었으면 켜 보시라고 한 번 권한다 (2026-11-27 대표 지시 — 마이그레이션 pin_nudge)
--   완성작품 인증이 승인될 때, 그 회원의 '지도에 내 핀 보이기'가 꺼져 있으면 지기 채팅으로 감사 인사 + 핀을 켜는 곳(그림 한 장)을 보낸다.
--   본인이 끈 것이므로 회원마다 한 번만(pin_nudges). 그림은 저장소의 공개 그림(docs/guides/pin_on_v1.png — 회원 정보 없음)

create table if not exists public.pin_nudges (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  sent_at timestamptz not null default now(),
  msg_id bigint
);
alter table public.pin_nudges enable row level security;
revoke all on public.pin_nudges from anon, authenticated;
grant all on public.pin_nudges to service_role;
comment on table public.pin_nudges is '지도 핀을 켜 보시라는 안내를 보낸 회원(한 번만) — 쓰기는 pin_nudge_send 로만';

create or replace function public.pin_nudge_send(p_user uuid)
 returns boolean language plpgsql security definer set search_path to 'public' as $function$
declare sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e'; p public.profiles; rid uuid; mid bigint; nm text;
begin
  select * into p from public.profiles where id = p_user;
  if p.id is null or p.id = sup or p.deleted_at is not null or p.onboarded_at is null or coalesce(p.is_visible, true) or p.location is null then return false; end if;
  insert into public.pin_nudges(profile_id) values (p_user) on conflict do nothing;
  if not found then return false; end if;
  nm := coalesce(nullif(btrim(p.nickname), ''), '회원');
  rid := public._support_room(p_user);
  insert into public.messages(room_id, sender_id, body, by_ai, photo_url) values (rid, sup,
    nm || ' 님, 완성작품 인증을 올려 주셔서 감사해요.' || E'\n'
    || '올려 주신 작품을 가까운 이웃들도 볼 수 있도록, 지도의 내 핀을 켜 보시면 어떨까요? 핀을 켜면 동네 이웃이 지도에서 ' || nm || ' 님을 찾아 작품을 보고 먼저 인사할 수 있어요.' || E'\n'
    || '위치는 정확한 주소가 아니라 약 200m 흐리게 표시되니 안심하셔도 돼요.' || E'\n\n'
    || '켜는 곳: 마이 › 설정 › ''지도에 내 핀 보이기'' (아래 그림)',
    true, 'https://yesbeyesnono.github.io/knit-neighbors/guides/pin_on_v1.png') returning id into mid;
  insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
    values (p_user, sup, 'notice', '완성작품 인증을 올려 주셔서 감사해요. 가까운 이웃도 작품을 볼 수 있게 지도의 내 핀을 켜 보시면 어떨까요? 눌러서 켜는 곳을 확인해 보세요.', jsonb_build_object('type','view','view','support'));
  update public.pin_nudges set msg_id = mid where profile_id = p_user;
  return true;
end $function$;
revoke all on function public.pin_nudge_send(uuid) from public, anon, authenticated;
grant execute on function public.pin_nudge_send(uuid) to service_role;

create or replace function public.trg_pin_nudge()
 returns trigger language plpgsql security definer set search_path to 'public' as $function$
begin
  begin perform public.pin_nudge_send(new.profile_id); exception when others then null; end;   -- 안내 실패가 승인을 막으면 안 된다
  return null;
end $function$;
revoke all on function public.trg_pin_nudge() from public, anon, authenticated;

drop trigger if exists works_pin_nudge on public.works;
create trigger works_pin_nudge after update of review_status on public.works
  for each row when (new.review_status = 'approved' and old.review_status is distinct from 'approved')
  execute function public.trg_pin_nudge();
