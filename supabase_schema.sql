-- 뜨개동네(가칭) MVP 스키마
-- 대상: Supabase (Postgres 17 + PostGIS)
-- 원칙: 정확한 위치는 저장하지 않는다. 흐려진 좌표(location)만 저장한다.

-- ---------------------------------------------------------------
-- 0. 확장
-- ---------------------------------------------------------------
create extension if not exists postgis with schema extensions;

-- ---------------------------------------------------------------
-- 1. 열거형
-- ---------------------------------------------------------------
create type public.craft_type as enum ('knit', 'crochet', 'both');
create type public.experience_level as enum ('new', 'under_1y', '1_3y', 'over_3y');
create type public.friendship_status as enum ('pending', 'accepted', 'declined', 'blocked');
create type public.room_kind as enum ('direct', 'group');
create type public.report_reason as enum ('spam', 'harassment', 'inappropriate', 'fake', 'other');

-- ---------------------------------------------------------------
-- 2. 테이블
-- ---------------------------------------------------------------

-- 프로필 (auth.users 1:1)
create table public.profiles (
  id                uuid primary key references auth.users(id) on delete cascade,
  nickname          text not null check (char_length(nickname) between 1 and 20),
  avatar_url        text,
  dong_code         text,                         -- 행정동 코드 (예: 1168010100)
  dong_name         text,                         -- "역삼1동"
  location          extensions.geography(point, 4326),   -- 흐려진 좌표. 지도 핀에 쓰임
  dong_verified_at  timestamptz,                  -- GPS 동네 인증 시각 (선택)
  mbti              char(4) check (mbti is null or mbti ~ '^[EI][NS][TF][JP]$'),
  craft             public.craft_type,
  experience        public.experience_level,
  now_making        text check (now_making is null or char_length(now_making) <= 40),
  now_making_photo  text,
  stuck_on          text check (stuck_on is null or char_length(stuck_on) <= 100),
  bio               text check (bio is null or char_length(bio) <= 300),
  available         text[] not null default '{}', -- {'weekday_day','weekday_evening','weekend'}
  beginner_ok       boolean not null default false,
  is_visible        boolean not null default true, -- 지도 노출 여부 (사용자가 끌 수 있음)
  suspended_at      timestamptz,                   -- 신고 누적 시 자동 정지
  onboarded_at      timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index profiles_location_gix on public.profiles using gist (location);
create index profiles_dong_code_idx on public.profiles (dong_code);

-- 완성작 자랑
create table public.works (
  id              uuid primary key default gen_random_uuid(),
  profile_id      uuid not null references public.profiles(id) on delete cascade,
  photo_url       text not null,
  title           text check (title is null or char_length(title) <= 60),
  yarn_info       text,     -- "산네스 가른 알파카 실크, 4ply, 색번 2032"
  pattern_source  text,     -- 도안 출처
  created_at      timestamptz not null default now()
);
create index works_profile_idx on public.works (profile_id, created_at desc);

-- 친구 관계 (신청자 → 수신자, 방향 있음)
create table public.friendships (
  requester_id  uuid not null references public.profiles(id) on delete cascade,
  addressee_id  uuid not null references public.profiles(id) on delete cascade,
  status        public.friendship_status not null default 'pending',
  message       text check (message is null or char_length(message) <= 100),
  created_at    timestamptz not null default now(),
  responded_at  timestamptz,
  primary key (requester_id, addressee_id),
  check (requester_id <> addressee_id)
);
create index friendships_addressee_idx on public.friendships (addressee_id, status);

-- 채팅방
create table public.rooms (
  id          uuid primary key default gen_random_uuid(),
  kind        public.room_kind not null,
  title       text check (title is null or char_length(title) <= 40),
  created_by  uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now()
);
create index rooms_created_by_idx on public.rooms (created_by);

create table public.room_members (
  room_id       uuid not null references public.rooms(id) on delete cascade,
  profile_id    uuid not null references public.profiles(id) on delete cascade,
  joined_at     timestamptz not null default now(),
  last_read_at  timestamptz not null default now(),
  primary key (room_id, profile_id)
);
create index room_members_profile_idx on public.room_members (profile_id);

-- 메시지
create table public.messages (
  id          bigint generated always as identity primary key,
  room_id     uuid not null references public.rooms(id) on delete cascade,
  sender_id   uuid not null references public.profiles(id) on delete cascade,
  body        text check (body is null or char_length(body) <= 2000),
  photo_url   text,
  place       jsonb,        -- {"name":"카페 코바늘","lat":..,"lng":..,"address":".."}
  created_at  timestamptz not null default now(),
  check (body is not null or photo_url is not null or place is not null)
);
create index messages_room_idx on public.messages (room_id, created_at desc);
create index messages_sender_idx on public.messages (sender_id);

-- 모임 (단체 채팅에서 생성)
create table public.meetups (
  id          uuid primary key default gen_random_uuid(),
  room_id     uuid not null references public.rooms(id) on delete cascade,
  created_by  uuid references public.profiles(id) on delete set null,
  title       text not null check (char_length(title) <= 60),
  place_name  text not null,
  location    extensions.geography(point, 4326),
  starts_at   timestamptz not null,
  is_public   boolean not null default false,
  created_at  timestamptz not null default now()
);
create index meetups_location_gix on public.meetups using gist (location);
create index meetups_public_idx on public.meetups (is_public, starts_at);
create index meetups_room_idx on public.meetups (room_id);
create index meetups_created_by_idx on public.meetups (created_by);

-- 신고
create table public.reports (
  id           bigint generated always as identity primary key,
  reporter_id  uuid not null references public.profiles(id) on delete cascade,
  reported_id  uuid not null references public.profiles(id) on delete cascade,
  reason       public.report_reason not null,
  detail       text check (detail is null or char_length(detail) <= 500),
  message_id   bigint references public.messages(id) on delete set null,
  created_at   timestamptz not null default now(),
  reviewed_at  timestamptz,
  unique (reporter_id, reported_id)
);
create index reports_reported_idx on public.reports (reported_id);
create index reports_message_idx on public.reports (message_id);

-- 푸시 토큰
create table public.push_tokens (
  profile_id  uuid not null references public.profiles(id) on delete cascade,
  token       text not null,
  platform    text not null check (platform in ('ios', 'android')),
  updated_at  timestamptz not null default now(),
  primary key (profile_id, token)
);

-- ---------------------------------------------------------------
-- 3. 공용 함수
-- ---------------------------------------------------------------

-- updated_at 자동 갱신
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- 카카오 로그인 직후 프로필 자동 생성
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, nickname, avatar_url)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data ->> 'name',
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'preferred_username',
      '뜨개인'
    ),
    new.raw_user_meta_data ->> 'avatar_url'
  )
  on conflict (id) do nothing;
  return new;
end $$;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 두 사용자가 서로 차단 관계인지
create or replace function public.is_blocked(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select (a = auth.uid() or b = auth.uid()) and exists (
    select 1 from public.friendships
    where status = 'blocked'
      and ((requester_id = a and addressee_id = b) or (requester_id = b and addressee_id = a))
  );
$$;

-- 두 사용자가 친구인지
create or replace function public.is_friend(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select (a = auth.uid() or b = auth.uid()) and exists (
    select 1 from public.friendships
    where status = 'accepted'
      and ((requester_id = a and addressee_id = b) or (requester_id = b and addressee_id = a))
  );
$$;

-- 내가 속한 방인지 (RLS 재귀 방지용)
create or replace function public.is_room_member(p_room_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.room_members
    where room_id = p_room_id and profile_id = auth.uid()
  );
$$;

-- 내가 만든 방인지 (방 생성 직후 첫 멤버 등록용 — rooms select 정책을 우회)
create or replace function public.is_room_creator(p_room_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.rooms where id = p_room_id and created_by = auth.uid());
$$;

-- 근처 뜨개인 조회 (지도 홈)
create or replace function public.nearby_profiles(
  p_lat double precision,
  p_lng double precision,
  p_radius_m integer default 3000,
  p_craft public.craft_type default null,
  p_beginner_ok boolean default null
)
returns table (
  id uuid, nickname text, avatar_url text, dong_name text,
  lat double precision, lng double precision,
  craft public.craft_type, experience public.experience_level,
  now_making text, beginner_ok boolean, distance_m double precision,
  level_crochet smallint, level_knit smallint
)
language sql stable security invoker set search_path = public, extensions as $$
  select
    p.id, p.nickname, p.avatar_url, p.dong_name,
    st_y(p.location::geometry), st_x(p.location::geometry),
    p.craft, p.experience, p.now_making, p.beginner_ok,
    st_distance(p.location, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography),
    p.level_crochet, p.level_knit
  from public.profiles p
  where p.location is not null
    and p.is_visible
    and p.suspended_at is null
    and p.onboarded_at is not null
    and p.id <> auth.uid()
    and not public.is_blocked(auth.uid(), p.id)
    and (p_craft is null or p.craft = p_craft or p.craft = 'both')
    and (p_beginner_ok is null or p.beginner_ok = p_beginner_ok)
    and st_dwithin(p.location, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography, p_radius_m)
  order by 11
  limit 200;
$$;

-- 흐려진 위치 저장: 약 500m 격자로 스냅한 뒤 무작위 오프셋. 정확 좌표는 저장되지 않는다.
create or replace function public.set_fuzzy_location(p_lat double precision, p_lng double precision)
returns void language plpgsql security invoker set search_path = public, extensions as $$
declare
  cell constant double precision := 0.0045;   -- 위도 기준 약 500m
  snapped_lat double precision;
  snapped_lng double precision;
begin
  snapped_lat := floor(p_lat / cell) * cell + cell / 2 + (random() - 0.5) * cell * 0.6;
  snapped_lng := floor(p_lng / cell) * cell + cell / 2 + (random() - 0.5) * cell * 0.6;
  update public.profiles
     set location = st_setsrid(st_makepoint(snapped_lng, snapped_lat), 4326)::geography
   where id = auth.uid();
end $$;

-- 친구 수락 시 1:1 채팅방 자동 생성
create or replace function public.handle_friendship_accepted()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_room uuid;
begin
  if new.status = 'accepted' and (old.status is distinct from 'accepted') then
    select r.id into v_room
      from public.rooms r
      join public.room_members a on a.room_id = r.id and a.profile_id = new.requester_id
      join public.room_members b on b.room_id = r.id and b.profile_id = new.addressee_id
     where r.kind = 'direct'
     limit 1;
    if v_room is null then
      insert into public.rooms (kind, created_by) values ('direct', new.addressee_id) returning id into v_room;
      insert into public.room_members (room_id, profile_id)
        values (v_room, new.requester_id), (v_room, new.addressee_id);
    end if;
  end if;
  if new.status is distinct from old.status then
    new.responded_at := now();
  end if;
  return new;
end $$;
create trigger friendships_on_accept
  before update on public.friendships
  for each row execute function public.handle_friendship_accepted();

-- 하루 친구 신청 10건 제한 + 차단 관계 금지 + 거절 후 30일 재신청 금지
create or replace function public.guard_friend_request()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.friendships
       where requester_id = new.requester_id and created_at > now() - interval '1 day') >= 10 then
    raise exception '하루에 보낼 수 있는 친구 신청은 10건입니다.' using errcode = 'P0001';
  end if;
  if public.is_blocked(new.requester_id, new.addressee_id) then
    raise exception '신청할 수 없는 사용자입니다.' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.friendships
              where requester_id = new.requester_id and addressee_id = new.addressee_id
                and status = 'declined' and responded_at > now() - interval '30 days') then
    raise exception '거절된 신청은 30일 후에 다시 보낼 수 있습니다.' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.friendships
              where requester_id = new.addressee_id and addressee_id = new.requester_id
                and status in ('pending','accepted')) then
    raise exception '상대가 이미 보낸 신청이 있거나 친구입니다.' using errcode = 'P0001';
  end if;
  -- 30일 지난 거절 기록은 지우고 새 신청을 받는다
  delete from public.friendships
   where requester_id = new.requester_id and addressee_id = new.addressee_id and status = 'declined';
  return new;
end $$;
create trigger friendships_guard_insert
  before insert on public.friendships
  for each row execute function public.guard_friend_request();

-- 신고 3건 누적 시 자동 정지
create or replace function public.handle_report()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.reports where reported_id = new.reported_id) >= 3 then
    update public.profiles set suspended_at = coalesce(suspended_at, now()) where id = new.reported_id;
  end if;
  return new;
end $$;
create trigger reports_after_insert
  after insert on public.reports
  for each row execute function public.handle_report();

-- ---------------------------------------------------------------
-- 4. RLS
-- ---------------------------------------------------------------
alter table public.profiles     enable row level security;
alter table public.works        enable row level security;
alter table public.friendships  enable row level security;
alter table public.rooms        enable row level security;
alter table public.room_members enable row level security;
alter table public.messages     enable row level security;
alter table public.meetups      enable row level security;
alter table public.reports      enable row level security;
alter table public.push_tokens  enable row level security;

-- profiles: 로그인 사용자는 정지되지 않은 프로필을 볼 수 있고(차단 제외), 본인만 수정
create policy "profiles_select" on public.profiles for select to authenticated
  using (id = auth.uid() or (suspended_at is null and not public.is_blocked(auth.uid(), id)));
create policy "profiles_update_own" on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- works: 프로필과 같은 가시성, 본인만 쓰기
create policy "works_select" on public.works for select to authenticated
  using (not public.is_blocked(auth.uid(), profile_id));
create policy "works_insert_own" on public.works for insert to authenticated
  with check (profile_id = auth.uid());
create policy "works_update_own" on public.works for update to authenticated
  using (profile_id = auth.uid());
create policy "works_delete_own" on public.works for delete to authenticated
  using (profile_id = auth.uid());

-- friendships: 당사자만 조회. 신청은 본인 명의로만. 응답(수락/거절/차단)은 수신자만, 차단은 신청자도 가능
create policy "friendships_select" on public.friendships for select to authenticated
  using (requester_id = auth.uid() or addressee_id = auth.uid());
create policy "friendships_insert" on public.friendships for insert to authenticated
  with check (requester_id = auth.uid() and status = 'pending');
create policy "friendships_update" on public.friendships for update to authenticated
  using (addressee_id = auth.uid() or requester_id = auth.uid())
  with check (
    (addressee_id = auth.uid() and status in ('accepted','declined','blocked'))
    or (requester_id = auth.uid() and status = 'blocked')
  );
create policy "friendships_delete_own_request" on public.friendships for delete to authenticated
  using (requester_id = auth.uid() and status = 'pending');

-- rooms / room_members: 멤버만
create policy "rooms_select" on public.rooms for select to authenticated
  using (public.is_room_member(id));
create policy "rooms_insert_group" on public.rooms for insert to authenticated
  with check (kind = 'group' and created_by = auth.uid());
create policy "rooms_update_creator" on public.rooms for update to authenticated
  using (created_by = auth.uid());

create policy "room_members_select" on public.room_members for select to authenticated
  using (public.is_room_member(room_id));
-- 단체방 초대: 내가 멤버인 방에, 내 친구만 초대 가능. 본인 추가도 허용(방 생성 직후)
create policy "room_members_insert" on public.room_members for insert to authenticated
  with check (
    (profile_id = auth.uid() and public.is_room_creator(room_id))
    or (public.is_room_member(room_id) and public.is_friend(auth.uid(), profile_id))
  );
create policy "room_members_update_own" on public.room_members for update to authenticated
  using (profile_id = auth.uid());
create policy "room_members_leave" on public.room_members for delete to authenticated
  using (profile_id = auth.uid());

-- messages: 멤버만 읽고, 본인 명의로만 쓰기
create policy "messages_select" on public.messages for select to authenticated
  using (public.is_room_member(room_id));
create policy "messages_insert" on public.messages for insert to authenticated
  with check (sender_id = auth.uid() and public.is_room_member(room_id));

-- meetups: 공개 모임은 누구나, 비공개는 방 멤버만
create policy "meetups_select" on public.meetups for select to authenticated
  using (is_public or public.is_room_member(room_id));
create policy "meetups_insert" on public.meetups for insert to authenticated
  with check (created_by = auth.uid() and public.is_room_member(room_id));
create policy "meetups_update_creator" on public.meetups for update to authenticated
  using (created_by = auth.uid());
create policy "meetups_delete_creator" on public.meetups for delete to authenticated
  using (created_by = auth.uid());

-- reports: 쓰기만. 조회는 관리자(service role)만
create policy "reports_insert" on public.reports for insert to authenticated
  with check (reporter_id = auth.uid() and reporter_id <> reported_id);

-- push_tokens: 본인 것만
create policy "push_tokens_all_own" on public.push_tokens for all to authenticated
  using (profile_id = auth.uid()) with check (profile_id = auth.uid());

-- ---------------------------------------------------------------
-- 5. Realtime (채팅 구독)
-- ---------------------------------------------------------------
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.friendships;

-- ---------------------------------------------------------------
-- 6. Storage 버킷
-- ---------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars',     'avatars',     true,  2097152, array['image/jpeg','image/png','image/webp']),
  ('works',       'works',       true,  5242880, array['image/jpeg','image/png','image/webp']),
  ('chat-photos', 'chat-photos', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

-- 파일 경로 규칙: <bucket>/<auth.uid()>/<파일명>
create policy "storage_public_read" on storage.objects for select to public
  using (bucket_id in ('avatars', 'works'));
create policy "storage_insert_own_folder" on storage.objects for insert to authenticated
  with check (bucket_id in ('avatars','works','chat-photos') and (storage.foldername(name))[1] = auth.uid()::text);
create policy "storage_update_own_folder" on storage.objects for update to authenticated
  using ((storage.foldername(name))[1] = auth.uid()::text);
create policy "storage_delete_own_folder" on storage.objects for delete to authenticated
  using ((storage.foldername(name))[1] = auth.uid()::text);
-- chat-photos 읽기: 경로 <uid>/<room_id>/<파일명> 의 room 멤버만
create policy "storage_chat_photos_read" on storage.objects for select to authenticated
  using (bucket_id = 'chat-photos' and public.is_room_member(((storage.foldername(name))[2])::uuid));

-- ---------------------------------------------------------------
-- 7. 함수 실행 권한
-- ---------------------------------------------------------------
-- 트리거 전용 함수는 API로 호출 불가
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.handle_friendship_accepted() from public, anon, authenticated;
revoke execute on function public.guard_friend_request() from public, anon, authenticated;
revoke execute on function public.handle_report() from public, anon, authenticated;
revoke execute on function public.set_updated_at() from public, anon, authenticated;
-- 로그인 사용자만 호출 가능 (RLS 정책에서 쓰이므로 authenticated 권한은 유지)
revoke execute on function public.is_blocked(uuid, uuid) from public, anon;
revoke execute on function public.is_friend(uuid, uuid) from public, anon;
revoke execute on function public.is_room_member(uuid) from public, anon;
revoke execute on function public.is_room_creator(uuid) from public, anon;
revoke execute on function public.nearby_profiles(double precision, double precision, integer, public.craft_type, boolean) from public, anon;
revoke execute on function public.set_fuzzy_location(double precision, double precision) from public, anon;

-- ---------------------------------------------------------------
-- 8. 기법 사전 + 뜨개 단계 자가진단 (2026-09-12)
-- ---------------------------------------------------------------
create table public.techniques (
  id        text primary key,               -- C01~C30, K01~K30
  craft     text not null check (craft in ('crochet','knitting')),
  name_ko   text not null,
  level     smallint not null check (level between 1 and 5),
  category  text not null,
  prereq    text[] not null default '{}',
  descr     text,
  symbol    text,
  sort      smallint generated always as (level * 100 + (substr(id, 2))::int) stored
);
comment on table public.techniques is '기법사전 v1.3. level 1입문·2초급·3중급·4상급·5전문. prereq는 직접 선행만';
alter table public.techniques enable row level security;
create policy "techniques_read" on public.techniques for select to authenticated using (true);

insert into public.techniques (id, craft, name_ko, level, category, prereq, descr, symbol) values
('C01','crochet','사슬뜨기',1,'기초','{}'::text[],'기초코와 기둥코를 만드는 모든 코바늘 뜨기의 출발점','○'),
('C02','crochet','짧은뜨기',1,'기초',array['C01']::text[],'가장 기본이 되는 낮은 코. 촘촘하고 단단한 편물을 만든다','×'),
('C03','crochet','빼뜨기',1,'기초',array['C01']::text[],'높이 없이 코를 이동하거나 단을 닫을 때 쓰는 코','•'),
('C04','crochet','기둥코·왕복뜨기',1,'구성',array['C01','C02']::text[],'단 시작에 기둥코를 세우고 편물을 뒤집어 평면으로 뜨는 방법','–'),
('C05','crochet','매직링',2,'기초',array['C01']::text[],'중심에 구멍이 생기지 않는 원형 시작코','◎'),
('C06','crochet','원형뜨기',2,'구성',array['C02','C05']::text[],'중심에서 바깥으로 나선 또는 단 단위로 돌려 뜨는 구조','–'),
('C07','crochet','코 늘리기',2,'성형',array['C02']::text[],'한 코에 2코 이상 떠서 코 수를 늘리는 성형 기법','V'),
('C08','crochet','코 줄이기',2,'성형',array['C02']::text[],'2코를 하나로 모아 떠 코 수를 줄이는 성형 기법','∧'),
('C09','crochet','줄무늬 배색',2,'배색',array['C02']::text[],'단이 바뀔 때 실 색을 교체해 가로 줄무늬를 만드는 기법','–'),
('C10','crochet','이랑뜨기',2,'질감',array['C02']::text[],'코의 뒤쪽 반 코에만 떠서 이랑 무늬를 내는 기법','×̲'),
('C11','crochet','파트 조립·꿰매기',2,'구성',array['C02','C03']::text[],'완성된 조각들을 돗바늘이나 빼뜨기로 잇는 마무리','–'),
('C12','crochet','중간긴뜨기',3,'코높이',array['C02','C04']::text[],'짧은뜨기와 긴뜨기의 중간 높이 코','T'),
('C13','crochet','긴뜨기',3,'코높이',array['C02','C04']::text[],'실을 한 번 감아 뜨는 표준 높은 코. 가방·모자의 주력 기법','T̷'),
('C14','crochet','피코뜨기',3,'장식',array['C01','C02']::text[],'사슬 3코를 작은 고리로 만들어 가장자리를 장식하는 기법','○₃'),
('C15','crochet','셸뜨기',3,'질감',array['C13']::text[],'한 코에 긴뜨기 여러 개를 떠 부채(조개) 모양을 만드는 무늬','조합'),
('C16','crochet','네트뜨기',3,'질감',array['C01','C02']::text[],'사슬 아치를 반복해 그물 조직을 만드는 기법','조합'),
('C17','crochet','모티프 이어뜨기',3,'구성',array['C03','C06']::text[],'모티프를 뜨면서 또는 뜬 뒤 서로 연결하는 기법','조합'),
('C18','crochet','두길긴뜨기',4,'코높이',array['C13']::text[],'실을 두 번 감아 뜨는 더 높은 코','T⃫'),
('C19','crochet','구슬뜨기',4,'질감',array['C13']::text[],'미완성 긴뜨기 여러 개를 한 번에 묶어 볼록한 구슬을 만드는 기법','⬯'),
('C20','crochet','팝콘뜨기',4,'질감',array['C19']::text[],'완성된 긴뜨기 묶음을 접어 고정해 구슬뜨기보다 더 돌출시키는 기법','⬮'),
('C21','crochet','교차뜨기',4,'질감',array['C13']::text[],'긴뜨기 두 코를 서로 엇갈려 떠 X자 무늬를 만드는 기법','✕'),
('C22','crochet','배색뜨기',4,'배색',array['C09']::text[],'한 단 안에서 여러 색을 바꿔 가며 무늬를 그리는 기법','■□'),
('C23','crochet','의류 구성',4,'구성',array['C07','C08','C11']::text[],'몸판·소매를 성형하고 봉제해 의류로 완성하는 종합 기술','–'),
('C24','crochet','걸어뜨기',5,'질감',array['C13']::text[],'코가 아닌 기둥(post)에 바늘을 걸어 입체 골을 세우는 기법','T̷ʃ'),
('C25','crochet','바구니뜨기',5,'질감',array['C24']::text[],'앞·뒤 걸어뜨기를 블록으로 교대해 격자 짜임을 만드는 기법','조합'),
('C26','crochet','스타크로셰',5,'특수',array['C12']::text[],'여러 코에서 실을 끌어와 한 번에 묶어 별 모양을 만드는 특수 기법','조합'),
('C27','crochet','코일뜨기',5,'특수',array['C13']::text[],'바늘에 실을 여러 번 감아 코일째 빼내는 특수 기법','∿'),
('C28','crochet','한붓뜨기',5,'특수',array['C06','C17']::text[],'실을 끊지 않고 작품 전체를 한 번에 완성하는 구성 기법','–'),
('C29','crochet','브레이드',5,'특수',array['C11','C13']::text[],'띠 형태로 뜬 편물을 엮어 조립하는 구조 기법','–'),
('C30','crochet','링 짧은뜨기',3,'질감',array['C02']::text[],'손가락에 실을 걸어 편물 뒷면에 고리(링)를 남기며 뜨는 짧은뜨기 — 모프·러그·털 질감(AMO-030 등 하마나카 도안)','⌓×'),
('K01','knitting','기본 코잡기',1,'기초','{}'::text[],'바늘에 첫 코들을 만드는 뜨개의 시작','–'),
('K02','knitting','겉뜨기',1,'기초',array['K01']::text[],'가장 기본 스티치. 앞면에 V자 결이 생긴다','│'),
('K03','knitting','안뜨기',1,'기초',array['K02']::text[],'겉뜨기의 반대면 스티치. 가로 돌기가 생긴다','─'),
('K04','knitting','코 막기',1,'기초',array['K02']::text[],'코를 차례로 덮어 편물을 마무리하는 기법','●'),
('K05','knitting','가터뜨기',1,'조직',array['K02']::text[],'매단 겉뜨기만 반복해 가로 이랑이 지는 조직','–'),
('K06','knitting','롱테일 캐스트온',2,'기초',array['K01']::text[],'실꼬리를 함께 사용해 만드는 신축성 있는 표준 시작코','–'),
('K07','knitting','메리야스뜨기',2,'조직',array['K02','K03']::text[],'겉뜨기 단과 안뜨기 단을 교대해 매끈한 V결을 만드는 기본 조직','–'),
('K08','knitting','고무뜨기',2,'조직',array['K02','K03']::text[],'겉·안뜨기를 세로로 교대(1×1, 2×2)해 신축성을 내는 조직','–'),
('K09','knitting','멍석뜨기',2,'조직',array['K02','K03']::text[],'겉·안뜨기를 엇갈리게 배치해 오톨도톨한 질감을 만드는 조직','–'),
('K10','knitting','실 잇기',2,'구성',array['K02']::text[],'실이 끝났을 때 새 실을 이어 붙이는 기법','–'),
('K11','knitting','줄무늬 배색',2,'배색',array['K02','K10']::text[],'단 교체 시 실 색을 바꿔 가로 줄무늬를 만드는 기법','–'),
('K12','knitting','걸기코',2,'성형',array['K02']::text[],'실을 바늘에 걸어 새 코와 비침(구멍)을 만드는 늘림코','○'),
('K13','knitting','왼코 모아뜨기',2,'성형',array['K02']::text[],'두 코를 한 번에 겉뜨기해 오른쪽으로 기우는 줄임코','人'),
('K14','knitting','오른코 모아뜨기',2,'성형',array['K13']::text[],'두 코를 옮겨 잡은 뒤 함께 떠 왼쪽으로 기우는 줄임코','入'),
('K15','knitting','코 늘리기',2,'성형',array['K02','K03']::text[],'코 사이 실이나 한 코에서 새 코를 만들어 늘리는 기법','M'),
('K16','knitting','원형뜨기',3,'구성',array['K01','K02']::text[],'원형바늘·장갑바늘로 이음매 없이 통으로 뜨는 구조','–'),
('K17','knitting','꼬아뜨기',3,'질감',array['K02']::text[],'코 뒤쪽 고리에 떠서 코를 꼬아 또렷한 선을 만드는 기법','Ω'),
('K18','knitting','케이블뜨기',3,'질감',array['K07']::text[],'코 순서를 바꿔 떠 꽈배기 무늬를 만드는 교차 기법','＞＜'),
('K19','knitting','돗바늘 잇기',3,'구성',array['K04','K07']::text[],'완성 조각을 돗바늘로 티 나지 않게 잇는 솔기 기법','–'),
('K20','knitting','코 줍기',3,'구성',array['K02']::text[],'편물 가장자리에서 새 코를 주워 이어 뜨는 기법(목둘레·밴드)','–'),
('K21','knitting','레이스뜨기 기초',3,'질감',array['K12','K13','K14']::text[],'걸기코와 줄임코를 짝지어 비침무늬를 만드는 기법','○人'),
('K22','knitting','중심 3코 모아뜨기',3,'성형',array['K13','K14']::text[],'3코를 가운데 코가 위로 오도록 모아 뜨는 대칭 줄임코','个'),
('K23','knitting','숏로우',4,'성형',array['K07']::text[],'단을 끝까지 뜨지 않고 되돌아와 입체 굴곡을 만드는 기법','–'),
('K24','knitting','페어아일',4,'배색',array['K11','K16']::text[],'쉬는 실을 뒤로 건너뛰며 두 색 이상으로 무늬를 짜는 배색 기법','■□'),
('K25','knitting','인타르시아',4,'배색',array['K11']::text[],'색 구역마다 실을 따로 준비해 큰 그림을 짜는 배색 기법','▧'),
('K26','knitting','아란무늬',4,'질감',array['K17','K18']::text[],'여러 케이블·꼬아뜨기를 조합한 복합 입체 무늬','–'),
('K27','knitting','도미노뜨기',4,'구성',array['K20','K22']::text[],'중심 줄임코로 사각 모듈을 떠서 이어 붙이는 구성 기법','–'),
('K28','knitting','의류 구성',4,'구성',array['K13','K14','K15','K19']::text[],'래글런·세트인 등 성형과 조립로 의류를 완성하는 종합 기술','–'),
('K29','knitting','브리오슈',5,'특수',array['K08','K12']::text[],'걸기코와 걸러뜨기를 결합해 도톰한 양면 골을 만드는 특수 기법','–'),
('K30','knitting','스틱',5,'특수',array['K24']::text[],'통으로 뜬 편물을 잘라 열어 카디건 등을 만드는 특수 기법','–');

alter table public.profiles
  add column skills text[] not null default '{}',
  add column level_crochet smallint not null default 0,
  add column level_knit smallint not null default 0,
  add column skills_updated_at timestamptz;

-- 단계 규칙: 그 단계 기법의 절반 이상을 체크한 가장 높은 단계
create or replace function public.compute_skill_level(p_skills text[], p_craft text)
returns smallint language sql immutable as $$
  select coalesce(max(level), 0)::smallint from (
    select t.level,
           count(*) filter (where t.id = any(p_skills)) as done,
           count(*) as total
    from public.techniques t where t.craft = p_craft
    group by t.level
  ) s where done * 2 >= total;
$$;

create or replace function public.profiles_apply_skills()
returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'INSERT' or new.skills is distinct from old.skills then
    new.skills := array(select t.id from public.techniques t where t.id = any(new.skills) order by t.sort);
    new.level_crochet := public.compute_skill_level(new.skills, 'crochet');
    new.level_knit := public.compute_skill_level(new.skills, 'knitting');
    if tg_op = 'UPDATE' then new.skills_updated_at := now(); end if;
  end if;
  return new;
end $$;
create trigger profiles_apply_skills
  before insert or update of skills on public.profiles
  for each row execute function public.profiles_apply_skills();

-- 선행 기법 재귀 확장 (시드·서버측 보정용)
create or replace function public.expand_prereqs(p_ids text[])
returns text[] language sql stable set search_path = public as $$
  with recursive r(id) as (
    select unnest(p_ids)
    union
    select unnest(t.prereq) from public.techniques t join r on t.id = r.id
  ) select array(select id from r);
$$;

-- nearby_profiles 반환 컬럼에 level_crochet, level_knit 추가 (본문은 3절과 동일 + 두 컬럼)
revoke execute on function public.compute_skill_level(text[], text) from public, anon;
revoke execute on function public.expand_prereqs(text[]) from public, anon;
revoke execute on function public.profiles_apply_skills() from public, anon, authenticated;

-- ---------------------------------------------------------------
-- 9. 커뮤니티 (Threads 스타일) — 2026-09-13
-- ---------------------------------------------------------------
create table public.posts (
  id           uuid primary key default gen_random_uuid(),
  author_id    uuid not null references public.profiles(id) on delete cascade,
  parent_id    uuid references public.posts(id) on delete cascade,   -- null=원글, 값=답글
  body         text check (body is null or char_length(body) <= 500),
  photos       text[] not null default '{}',                          -- storage 'posts' 버킷 URL, 최대 4장
  dong_code    text,                                                  -- 작성 시점 작성자 동네 (우리 동네 피드용)
  reply_count  integer not null default 0,
  like_count   integer not null default 0,
  created_at   timestamptz not null default now(),
  check (body is not null or cardinality(photos) > 0),
  check (cardinality(photos) <= 4)
);
create index posts_feed_idx on public.posts (created_at desc) where parent_id is null;
create index posts_parent_idx on public.posts (parent_id, created_at);
create index posts_author_idx on public.posts (author_id, created_at desc);
create index posts_dong_idx on public.posts (dong_code, created_at desc) where parent_id is null;

create table public.post_likes (
  post_id     uuid not null references public.posts(id) on delete cascade,
  profile_id  uuid not null references public.profiles(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (post_id, profile_id)
);
create index post_likes_profile_idx on public.post_likes (profile_id);

create or replace function public.posts_before_insert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.dong_code is null then
    select dong_code into new.dong_code from public.profiles where id = new.author_id;
  end if;
  return new;
end $$;
create trigger posts_before_insert before insert on public.posts
  for each row execute function public.posts_before_insert();

create or replace function public.posts_reply_count()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' and new.parent_id is not null then
    update public.posts set reply_count = reply_count + 1 where id = new.parent_id;
  elsif tg_op = 'DELETE' and old.parent_id is not null then
    update public.posts set reply_count = greatest(reply_count - 1, 0) where id = old.parent_id;
  end if;
  return null;
end $$;
create trigger posts_reply_count after insert or delete on public.posts
  for each row execute function public.posts_reply_count();

create or replace function public.post_like_count()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    update public.posts set like_count = like_count + 1 where id = new.post_id;
  else
    update public.posts set like_count = greatest(like_count - 1, 0) where id = old.post_id;
  end if;
  return null;
end $$;
create trigger post_like_count after insert or delete on public.post_likes
  for each row execute function public.post_like_count();

revoke execute on function public.posts_before_insert() from public, anon, authenticated;
revoke execute on function public.posts_reply_count() from public, anon, authenticated;
revoke execute on function public.post_like_count() from public, anon, authenticated;

alter table public.posts enable row level security;
alter table public.post_likes enable row level security;
create policy "posts_select" on public.posts for select to authenticated
  using (not public.is_blocked(auth.uid(), author_id)
         and exists (select 1 from public.profiles p where p.id = author_id and p.suspended_at is null));
create policy "posts_insert_own" on public.posts for insert to authenticated with check (author_id = auth.uid());
create policy "posts_delete_own" on public.posts for delete to authenticated using (author_id = auth.uid());
create policy "post_likes_select" on public.post_likes for select to authenticated using (true);
create policy "post_likes_insert_own" on public.post_likes for insert to authenticated with check (profile_id = auth.uid());
create policy "post_likes_delete_own" on public.post_likes for delete to authenticated using (profile_id = auth.uid());

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('posts', 'posts', true, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;
create policy "storage_posts_read" on storage.objects for select to public using (bucket_id = 'posts');
create policy "storage_posts_insert_own" on storage.objects for insert to authenticated
  with check (bucket_id = 'posts' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "storage_posts_delete_own" on storage.objects for delete to authenticated
  using (bucket_id = 'posts' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------
-- 10. 추천 피드 — 2026-09-13
-- 점수 = (1+좋아요+답글×2) × 거리(같은 동네 2.0 / 3km 1.5 / 10km 1.0 / 그 외 0.5)
--        × 친구 1.5 × 단계 비슷(±1) 1.2 × 같은 종목 1.1 × 질문 글 1.3 ÷ (경과시간h+2)^1.3
--        작성자당 3번째 글부터 ×0.3 (다양성)
-- ---------------------------------------------------------------
create or replace function public.feed_ranked(p_limit integer default 30, p_offset integer default 0)
returns table (
  id uuid, author_id uuid, body text, photos text[], dong_code text,
  reply_count integer, like_count integer, created_at timestamptz,
  author jsonb, score double precision
)
language sql stable security invoker set search_path = public, extensions as $$
  with me as (
    select p.id, p.dong_code, p.location, p.craft, p.level_crochet, p.level_knit
    from public.profiles p where p.id = auth.uid()
  ),
  friends as (
    select case when f.requester_id = auth.uid() then f.addressee_id else f.requester_id end as fid
    from public.friendships f
    where f.status = 'accepted' and (f.requester_id = auth.uid() or f.addressee_id = auth.uid())
  ),
  scored as (
    select
      po.id, po.author_id, po.body, po.photos, po.dong_code, po.reply_count, po.like_count, po.created_at,
      jsonb_build_object('id', a.id, 'nickname', a.nickname, 'avatar_url', a.avatar_url, 'dong_name', a.dong_name,
                         'craft', a.craft, 'level_crochet', a.level_crochet, 'level_knit', a.level_knit) as author,
      (1 + po.like_count + 2 * po.reply_count)::double precision
      * case
          when po.dong_code is not null and po.dong_code = me.dong_code then 2.0
          when a.location is null or me.location is null then 1.0
          when st_dwithin(a.location, me.location, 3000) then 1.5
          when st_dwithin(a.location, me.location, 10000) then 1.0
          else 0.5 end
      * case when exists (select 1 from friends f where f.fid = po.author_id) then 1.5 else 1.0 end
      * case when (me.level_crochet > 0 and a.level_crochet > 0 and abs(me.level_crochet - a.level_crochet) <= 1)
              or (me.level_knit > 0 and a.level_knit > 0 and abs(me.level_knit - a.level_knit) <= 1) then 1.2 else 1.0 end
      * case when me.craft is not null and a.craft is not null
              and (me.craft = a.craft or me.craft = 'both' or a.craft = 'both') then 1.1 else 1.0 end
      * case when po.body ~ '(\?|막히|어떻게|도와|질문|팁|방법|알려)' then 1.3 else 1.0 end
      / power(extract(epoch from (now() - po.created_at)) / 3600.0 + 2, 1.3) as base
    from public.posts po
    join public.profiles a on a.id = po.author_id
    left join me on true
    where po.parent_id is null
  ),
  ranked as (
    select s.*, row_number() over (partition by s.author_id order by s.base desc) as rn from scored s
  )
  select id, author_id, body, photos, dong_code, reply_count, like_count, created_at, author,
         case when rn > 2 then base * 0.3 else base end as score
  from ranked
  order by score desc, created_at desc
  limit p_limit offset p_offset;
$$;
revoke execute on function public.feed_ranked(integer, integer) from public, anon;

-- ---------------------------------------------------------------
-- 11. 모임 개설·참여 (2026-09-13) — ＋ 버튼 '모임' 탭
-- 글(posts.meetup_id) ↔ 모임 연결, 참여자 수 트리거, create_meetup / join_meetup / leave_meetup
-- ---------------------------------------------------------------
alter table public.posts add column meetup_id uuid references public.meetups(id) on delete set null;
create index posts_meetup_idx on public.posts (meetup_id) where meetup_id is not null;
alter table public.meetups add column participant_count integer not null default 0;
alter table public.meetups add column descr text check (descr is null or char_length(descr) <= 300);

create or replace function public.meetup_count_sync()
returns trigger language plpgsql security definer set search_path = public as $$
declare rid uuid := coalesce(new.room_id, old.room_id);
begin
  update public.meetups m set participant_count = (select count(*) from public.room_members rm where rm.room_id = rid) where m.room_id = rid;
  return null;
end $$;
create trigger room_members_meetup_count after insert or delete on public.room_members
  for each row execute function public.meetup_count_sync();

-- 모임 개설: 단체방 + 모임 + 커뮤니티 글 (모임 행을 먼저 만들고 주최자를 방에 넣어야 카운트가 맞음)
create or replace function public.create_meetup(
  p_title text, p_place text, p_starts_at timestamptz, p_is_public boolean,
  p_body text default null, p_lat double precision default null, p_lng double precision default null, p_photos text[] default '{}'
)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare v_room uuid; v_meetup uuid; v_post uuid; v_loc geography;
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  if p_lat is not null and p_lng is not null then v_loc := st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography;
  else select location into v_loc from public.profiles where id = auth.uid(); end if;
  insert into public.rooms (kind, title, created_by) values ('group', left(p_title, 40), auth.uid()) returning id into v_room;
  insert into public.meetups (room_id, created_by, title, place_name, location, starts_at, is_public, descr)
    values (v_room, auth.uid(), p_title, p_place, v_loc, p_starts_at, p_is_public, p_body) returning id into v_meetup;
  insert into public.room_members (room_id, profile_id) values (v_room, auth.uid());
  insert into public.posts (author_id, body, photos, meetup_id)
    values (auth.uid(), coalesce(nullif(p_body,''), p_title), coalesce(p_photos,'{}'), v_meetup) returning id into v_post;
  return v_post;
end $$;

create or replace function public.join_meetup(p_meetup_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_room uuid; v_public boolean;
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  select room_id, is_public into v_room, v_public from public.meetups where id = p_meetup_id;
  if v_room is null then raise exception '모임을 찾을 수 없어요'; end if;
  if not v_public and not exists (select 1 from public.room_members where room_id = v_room and profile_id = auth.uid()) then
    raise exception '초대된 사람만 참여할 수 있어요';
  end if;
  insert into public.room_members (room_id, profile_id) values (v_room, auth.uid()) on conflict do nothing;
  return v_room;
end $$;

create or replace function public.leave_meetup(p_meetup_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_room uuid;
begin
  select room_id into v_room from public.meetups where id = p_meetup_id;
  delete from public.room_members where room_id = v_room and profile_id = auth.uid();
end $$;

revoke execute on function public.meetup_count_sync() from public, anon, authenticated;
revoke execute on function public.create_meetup(text, text, timestamptz, boolean, text, double precision, double precision, text[]) from public, anon;
revoke execute on function public.join_meetup(uuid) from public, anon;
revoke execute on function public.leave_meetup(uuid) from public, anon;
-- feed_ranked: 반환 컬럼에 meetup_id 추가, 모임 글 ×1.4 부스트 (10절 함수에 반영)

-- ---------------------------------------------------------------
-- 12. 모임 상세 항목 (2026-09-13) — 온라인 뜨개 모임(Meetup·소모임·당근·공방 워크숍) 공통 항목 + 뜨개동네 고유 항목
--   공통: 유형(자유/워크숍/프로젝트/나눔)·종목·정원·참가비·준비물·소요 시간·반복
--   고유: 권장 뜨개 단계(level_min~max) → 참여자에게 '내 단계에 맞아요/조금 높아요', 배울 기법(technique_id, 기법사전 연결)
-- ---------------------------------------------------------------
alter table public.meetups
  add column kind text not null default 'free' check (kind in ('free','workshop','project','swap')),
  add column craft text check (craft is null or craft in ('knit','crochet','both')),
  add column level_min smallint check (level_min is null or level_min between 1 and 5),
  add column level_max smallint check (level_max is null or level_max between 1 and 5),
  add column technique_id text references public.techniques(id),
  add column capacity smallint check (capacity is null or capacity between 2 and 100),
  add column fee text check (fee is null or char_length(fee) <= 40),
  add column bring text check (bring is null or char_length(bring) <= 120),
  add column duration_min smallint check (duration_min is null or duration_min between 30 and 480),
  add column repeat text not null default 'once' check (repeat in ('once','weekly','biweekly','monthly'));
-- create_meetup(…, p_extra jsonb): kind/craft/level_min/level_max/technique_id/capacity/fee/bring/duration_min/repeat 를 jsonb로 받음
-- join_meetup: 정원(capacity) 초과 시 '정원이 찼어요' 예외
-- profiles_apply_skills: skills에서 craft 자동 판정 (C*만 → crochet, K*만 → knit, 둘 다 → both)

-- ---------------------------------------------------------------
-- 13. 작품 인증 (2026-09-13) — 모임 개설 조건
--   works: photos[]·techniques[]·note 추가. posts.work_id 로 커뮤니티 '작품' 탭에 노출
--   profiles: verified_skills(인증된 기법 합집합)·cert_count — works 트리거가 유지, skills에 선행 포함 자동 체크
--   create_work(title, photos, techniques, yarn, note) → 글 id.  create_meetup 은 works 1건 이상 없으면 예외
-- ---------------------------------------------------------------
alter table public.works
  add column photos text[] not null default '{}',
  add column techniques text[] not null default '{}',
  add column note text check (note is null or char_length(note) <= 300);
alter table public.posts add column work_id uuid references public.works(id) on delete set null;
create index posts_work_idx on public.posts (work_id) where work_id is not null;
alter table public.profiles
  add column verified_skills text[] not null default '{}',
  add column cert_count integer not null default 0;
-- works_apply_cert 트리거 / create_work 함수 / create_meetup 조건: 적용된 마이그레이션 'work_certification' 참조
-- works.custom_techniques text[]: 목록(60종)에 없는 기법 자유 입력 (기법사전 확장 후보). 집계 뷰 custom_technique_stats
-- create_work(..., p_custom text[]) : 알려진 기법 0개여도 자유 입력이 있으면 인증 가능

-- ---------------------------------------------------------------
-- 14. 모임 후기 (2026-09-13) — 종료된 모임의 참여자가 글+사진으로 남김
--   posts.review_of → meetups.id, meetups.review_count(트리거), create_review(meetup_id, body, photos): 종료+참여자+1인1회
-- ---------------------------------------------------------------
alter table public.posts add column review_of uuid references public.meetups(id) on delete set null;
create index posts_review_idx on public.posts (review_of, created_at desc) where review_of is not null;
alter table public.meetups add column review_count integer not null default 0;

-- ---------------------------------------------------------------
-- 15. 보안 강화·주최자 취소 (2026-09-14 전체 검토)
--   custom_technique_stats 뷰 security_invoker + authenticated 접근 차단
--   profiles: level_crochet/level_knit/verified_skills/cert_count/suspended_at 컬럼 UPDATE 권한 회수 (서버 계산값 위조 방지)
--   works: 직접 insert/update 정책 제거 (create_work 함수로만)
--   posts_insert_own: meetup_id/work_id/review_of 는 클라이언트가 못 붙임 + 정지 계정 차단(is_active_user)
--   meetups: 직접 insert 정책 제거 (create_meetup으로만), room_id/created_by/카운트 컬럼 UPDATE 회수
--   create_meetup(p_extra.room_id): 기존 단체방에 모임 붙이기 (멤버만)
--   cancel_meetup(meetup_id): 주최자만, 시작 전만. 모임·안내 글 삭제, 방·채팅은 유지 + 취소 메시지
-- ---------------------------------------------------------------

-- ---------------------------------------------------------------
-- 16. 스토어 심사 대응 (2026-09-14)
--   profiles.terms_agreed_at(약관 동의) · delete_my_account()(계정 삭제, auth.users cascade; 파일은 클라이언트가 Storage API로 정리)
--   posts.hidden + post_reports(신고 3건 → 자동 숨김, 작성자에게만 보임) · banned_words + contains_banned() + 글/메시지/프로필 금칙어 트리거
--   법적 문서: docs/privacy.html · terms.html · guidelines.html · delete-account.html
-- ---------------------------------------------------------------

-- ---------------------------------------------------------------
-- 17. 🙋 뜨친구 구해요(손 들기) — 2026-09-15
--   profiles.wave_until: 마이에서 토글 시 now()+14일. 지도 핀에 손 배지, '손 든 이웃' 필터
--   nearby_profiles 반환에 waving boolean 추가 (wave_until > now())
-- ---------------------------------------------------------------
alter table public.profiles add column if not exists wave_until timestamptz;
-- nearby_profiles 재정의: 기존 select 목록 끝에 (p.wave_until is not null and p.wave_until > now()) as waving 추가 (drop function 후 create)

-- ---------------------------------------------------------------
-- 18. @멘션 + 활동(알림) — 2026-09-15 (마이그레이션 mentions_and_notifications)
--   posts.mentions uuid[] (답글 저장 시 클라이언트가 @선택한 사용자 id 배열 전달)
--   notifications(recipient_id, actor_id, kind[mention|reply|like|friend_request|friend_accept|meetup_join|review], post_id, root_post_id, meetup_id, snippet, read_at)
--   RLS: 본인 것만 select/update/delete, insert는 트리거(security definer push_notification)만
--   트리거: posts_notify(답글→원글 작성자, 멘션→언급된 사람, 후기→모임 개설자) · post_likes_notify(취소 시 삭제) · friendships_notify · room_members_notify(모임 참여→개설자)
--   realtime publication에 notifications 추가 (마이 탭 배지·토스트)
-- ---------------------------------------------------------------

-- ---------------------------------------------------------------
-- 19. 뜨개동네 지기(운영진) 채팅 — 2026-09-15 (마이그레이션 support_room)
--   open_support_room(p_support uuid) security definer: 친구가 아니어도 지기와 1:1 방 생성/조회
--   지기 계정 = knitup.official@gmail.com 프로필(e120eb67-…), 닉네임 '뜨개동네 지기'. 앱 SUPPORT_ID 상수
-- ---------------------------------------------------------------

-- ---------------------------------------------------------------
-- 20. 위치 흐리기 변경 — 2026-09-16 (마이그레이션 fuzzy_location_200m_center)
--   set_fuzzy_location: 200m 격자(0.0018°) 중심에 고정, 무작위 오프셋 제거. 기존 좌표 재정렬.
--   앱: 같은 지점 핀은 화면상 26px 원으로 분산(fetchPins spread), 하루 1회 조용히 위치 갱신(refreshLocationDaily)
--   문서: privacy.html · terms.html · 앱 문구 '200m 격자'
-- ---------------------------------------------------------------

-- ---------------------------------------------------------------
-- 21. 데이터 수집 3종 — 2026-09-16 (마이그레이션 data_collection_skill_events_yarn_solved)
--   a) skill_events(profile_id, kind add|remove|level, technique_id, craft, level, source manual|cert|backfill): profiles 트리거 profiles_log_skills. RLS 정책 없음(서버 분석 전용)
--   b) works.yarn_name / yarn_weight / needle_size + create_work(..., p_yarn_meta jsonb)
--   c) posts.solved_reply_id + mark_solved(p_post, p_reply) (원글 작성자만, 알림 kind 'solved')
--   개인정보처리방침: 가명·익명 처리 후 통계·연구·서비스 개선 활용 문구 추가
-- ---------------------------------------------------------------

-- ---------------------------------------------------------------
-- 22. 관리자 콘솔 docs/admin.html — 2026-09-16 (마이그레이션 admin_console, admin_manage_admins)
--   admins(profile_id) + is_admin() · 관리자 열람 정책(*_admin_select) 14개 테이블 · banned_words 관리자 쓰기
--   admin_logs(모든 관리자 행위 기록, 삭제 불가) · RPC: admin_hide_post / admin_delete_post / admin_suspend_user /
--   admin_resolve_report / admin_banned_word / admin_broadcast(알림 kind 'notice') / admin_stats / admin_set_admin / admin_find_users(이메일 포함)
--   초기 관리자: knitup.official, yesbeyesnono, cocos.jay
-- ---------------------------------------------------------------
--   + admin_reply_support(p_room, p_body): 관리자가 콘솔에서 지기 이름(sender=지기 계정)으로 답장, admin_logs 'reply_support' 기록

-- ---------------------------------------------------------------
-- 23. 파트너(가게) 계정 — 2026-09-16 (마이그레이션 partner_shops)
--   shops(owner_id, name, kind yarn|studio|cafe|other, address, location(정확 좌표), links, radius_m, is_active)
--   shop_posts(kind sale|new|meetup|class|notice, title, body, photos, ends_at, hidden) · shop_reads(사용자별 마지막 열람) · shop_follows
--   nearby_shops(lat,lng,radius): 반경 안 가게 + unread(열람 후 새 글) + following · 팔로워 알림 kind 'shop_post'(notifications.shop_id)
--   관리자: admin_upsert_shop(jsonb) / admin_shop_post(jsonb). 오너 계정은 앱 ＋ › 가게 소식 탭으로 직접 작성
--   등록: 쎄비하우스(성수, 연무장5가길 28, 37.5431317/127.0555276, 반경 8km)
-- ---------------------------------------------------------------
--   + admin_reply_support(p_room, p_body, p_photo): 사진 답장(경로 = <관리자 uid>/<room>/<ts>.jpg, 방 참여자 읽기 가능) · storage_chat_photos_admin_read 정책
--   + admin_dong_map(): 동네별 사용자 수·평균 좌표·친구 찾는 중 수, 예정 모임, 파트너 가게 → 관리자 동네 분포 지도(Leaflet)

-- ---------------------------------------------------------------
-- 24. 함수 실행 권한 정리 — 2026-09-18 (마이그레이션 harden_function_grants)
--   트리거 함수(log_skill_events, notify_on_*)는 직접 호출 불가. RPC(admin_*, is_admin, mark_solved, nearby_shops, open_support_room, create_work)는 authenticated만.
--   default privileges: 새 함수는 PUBLIC 실행 불가(필요 시 grant execute ... to authenticated 명시)
-- ---------------------------------------------------------------

-- ---------------------------------------------------------------
-- 25. 가게 등록 신청 — 2026-09-18 (마이그레이션 shop_claims)
--   흐름: 개인 가입 → 설정 › 우리 가게 등록 신청(또는 오너 없는 가게 화면 › 이 가게 주인이에요) → 관리자 콘솔 › 파트너 가게에서 승인/반려
--   shop_claims(profile_id, shop_id(기존 가게 오너 신청 시), name, kind, address, phone, biz_no, doc_path, note, status pending|approved|rejected, reject_reason, decided_by/at)
--     RLS: 본인 select/insert(pending만)/delete(pending만), 관리자 select. 계정당 pending 1건(unique partial index)
--   storage 'shop-docs'(비공개, 5MB, jpeg/png): <uid>/<ts>.jpg · 본인+관리자만 읽기/삭제. 처리 후 콘솔이 서류 삭제
--   admin_decide_shop_claim(p_id, p_approve, p_reason): 승인 → 새 가게(is_active=false, 좌표는 콘솔에서 입력) 또는 기존 가게 owner_id 연결,
--     신청자에게 지기 명의 notice 알림(승인 시 shop_id 포함 → 앱에서 가게로 이동), admin_logs approve_shop_claim/reject_shop_claim
-- ---------------------------------------------------------------

-- ---------------------------------------------------------------
-- 26. 도안 + 단계 기반 추천 — 2026-09-18 (마이그레이션 patterns_recommend)
--   patterns(author_id, title, descr, craft crochet|knitting, level 1~5, techniques text[], photos text[], yarn_weight, needle_size,
--            price(0=무료), buy_url(외부 판매 링크, http(s)만), is_published, hidden)
--     RLS: select = 공개(is_published and not hidden) 또는 본인·관리자. insert/update/delete는 authenticated에서 회수(쓰기는 RPC만, 3단계에서 작가에게 개방)
--   pattern_saves(profile_id, pattern_id): 찜. 본인 것만
--   admin_upsert_pattern(jsonb): 관리자 등록/수정, author_id 미지정 시 지기 계정. admin_logs 'upsert_pattern'
--   recommend_patterns(p_limit): 내 종목의 (내 단계~내 단계+1, 단계 0이면 1~1) 도안 중
--     아직 체크 안 한 기법 1~2개 → 0개 → 3개 이상 순, 같은 순위 안에서는 날짜별로 섞음. 내 도안·차단 상대 제외
--     반환: new_count/new_techniques(새로 배우는 기법 이름), step_up(한 단계 위), saved
--   앱 노출: 커뮤니티 피드 6번째 글 뒤(이후 8개마다) '다음에 떠보면 좋아요' · 작품 인증 직후 시트 · 내 뜨개 단계 화면 아래 · 설정 › 찜한 도안
--   결제는 앱에서 하지 않음(외부 링크만)
-- ---------------------------------------------------------------

-- ---------------------------------------------------------------
-- 27. 작가 — 2026-09-18 (마이그레이션 authors)
--   profiles.is_author, author_since
--   ★ profiles 쓰기 권한 재정의: authenticated의 테이블 단위 INSERT/UPDATE 회수 후 사용자 편집 컬럼만 grant update
--     (nickname, avatar_url, dong_*, location, mbti, craft, experience, now_making(_photo), stuck_on, bio, available, beginner_ok,
--      is_visible, onboarded_at, skills, terms_agreed_at, wave_until). 19절의 컬럼 회수는 테이블 단위 grant 때문에 실제로는 무효였음
--     → cert_count/verified_skills/suspended_at/level_*/is_author 는 이제 클라이언트가 못 바꿈. profiles에 컬럼을 추가하면 필요한 것만 grant 할 것
--   author_applications(profile_id, real_name, link, note, status, reject_reason, decided_by/at): 본인 select/delete(pending), 관리자 select. insert는 RPC만
--   apply_author(name, link, note): 작품 인증(cert_count) 3개 이상, 정지 아님, 계정당 pending 1건
--   admin_decide_author(id, approve, reason): is_author 설정 + 지기 명의 notice 알림 + admin_logs approve_author/reject_author
--   admin_set_author(profile, on): 수동 지정/해제
--   author_upsert_pattern(jsonb): 작가 본인 도안 등록/수정(금칙어, 사진 4장, 하루 20건 제한). 삭제는 RLS patterns_delete_own
--   nearby_profiles: is_author, pattern_count 반환 추가 → 지도 작가 핀(.upin.author, #8a6d1a)·'작가' 필터
-- ---------------------------------------------------------------

-- ---------------------------------------------------------------
-- 28. 리포스트 + 도안 찜 수 — 2026-09-18 (마이그레이션 reposts_pattern_save_count)
--   post_reposts(post_id, profile_id): 저장 겸 프로필 공개. select 전체(authenticated), insert 본인·정지 아님·원글만·내 글 제외, delete 본인
--   posts.repost_count (트리거 post_repost_apply: 카운트 + 알림 kind 'repost', 취소 시 알림 삭제). notifications_kind_check 에 'repost' 추가
--   patterns.save_count (트리거 pattern_save_count) → 프로필 도안 탭 '인기' 정렬
--   앱: 글 카드의 외부 공유 버튼 자리에 리포스트 버튼(공유는 ··· 메뉴로), 남의 프로필 탭 = 글/리포스트/인증/(도안), 마이 = 글/리포스트/인증/모임(답글 탭은 2026-09-20 제거)
--        프로필 도안 탭 정렬: 최신·인기(찜)·쉬운 순(단계별 구분선)·가격 낮은 순. 데모 계정끼리 리포스트 18건 시드
-- ---------------------------------------------------------------

-- ---------------------------------------------------------------
-- 29. knitup 도안 패키지(앱 안 뷰어) + 진도 — 2026-09-19 (마이그레이션 pattern_contents_viewer)
--   patterns.has_viewer
--   pattern_contents(pattern_id, pkg jsonb = knitup 에디터의 .knitup-pkg.json, app='knitup-pattern-package')
--     RLS select: 작가 본인·관리자, 또는 공개된 무료(price=0) 도안. ★ 유료 도안은 구매 테이블(IAP) 도입 시 정책에 구매자 조건 추가
--     쓰기는 set_pattern_pkg(p_id, p_pkg) 만(작가 본인 또는 관리자, 형식 검사, 3MB 이하, null이면 첨부 삭제)
--   pattern_progress(profile_id, pattern_id, prog): 단별 진도, 본인 것만
--   앱: 도안 상세 '도안 열기' → docs/viewer.html 을 sandbox(allow-scripts) + srcdoc iframe 으로 열고 postMessage 로 pkg·진도·닉네임(워터마크) 전달,
--        뷰어 → 앱: kn-prog(진도 저장), kn-close. viewer.html 은 tools/build-viewer.js 가 knitup/docs/app_v9.html 의 VIEWER_SIZE_HTML 에서 생성
--   데모: '동글동글 코스터 3종'(원형)·'첫 코바늘 수세미'(왕복) 에 패키지 첨부
--   사업 방향(2026-09-19 대표 확정): 회사가 판매자, 작가에게는 3.3% 원천징수 후 정산(Apple 수수료 제외 → 플랫폼 15% → 작가). 가격은 티어 중 선택(IAP 티어 상품)
-- ---------------------------------------------------------------

-- ---------------------------------------------------------------
-- 30. 작가 외부 링크 + 앱 설정 — 2026-09-19 (마이그레이션 author_link_app_config, recommend_patterns_has_viewer)
--   profiles.author_link(http(s), 300자): 클라이언트 직접 수정 불가 → set_author_link(p_link) (작가만, 금칙어 검사, 빈 값이면 삭제)
--   admin_decide_author: 승인 시 신청서 link 를 author_link 로 복사(비어 있을 때만)
--   app_config(key, value jsonb): anon·authenticated 읽기만. 'min_version' = {"ios","android","message"} → 네이티브 앱이 시작 때 확인, 낮으면 업데이트 안내 화면
--   recommend_patterns: has_viewer 반환 추가
-- ---------------------------------------------------------------

-- ---------------------------------------------------------------
-- 31. 모임 장소 위치 — 2026-09-20 (마이그레이션 meetup_address_location)
--   meetups.address 추가. create_meetup: p_extra.address 저장, p_lat/p_lng = 모임 장소 좌표(앱이 주소·장소 검색으로 고른 값. 예전에는 주최자 프로필 위치를 넣었음)
--   set_meetup_location(p_meetup, p_lat, p_lng, p_address, p_place): 주최자가 기존 모임의 핀 위치·주소·장소 이름 수정(국내 좌표 범위 검사)
--   앱: 모임 만들기(＋ › 모임, 단체방 › 모임 만들기)에서 '장소 위치' 검색 필수 — Google Geocoder, 실패 시 Nominatim(띄어쓰기 제거 재시도)
--        모임 상세에 주소·길찾기, 주최자에게 '장소 위치 수정'. 활동 알림은 누르면 삭제(notif_delete 정책 사용)
-- ---------------------------------------------------------------

-- ---------------------------------------------------------------
-- 32. 모임 참여·참여 취소·모임 취소 과정 — 2026-09-20 (마이그레이션 meetup_join_leave_flow)
--   notifications.kind 에 'meetup_leave', 'meetup_cancel' 추가
--   join_meetup(p_meetup_id, p_note default null): 정지·종료·정원·금칙어 검사 → room_members 추가 + 채팅방에 '🙋 모임에 참여했어요(+한마디)'. 주최자 알림은 기존 room_members 트리거(meetup_join)
--   leave_meetup(p_meetup_id, p_note default null): 주최자는 불가(취소 이용) → 채팅방에 '👋 모임 참여를 취소했어요(+사유)' + 주최자에게 meetup_leave 알림
--   cancel_meetup(p_meetup_id, p_note default null): 참여자 전원에게 meetup_cancel 알림(제목·사유) + 채팅방 '❌ … 취소됐어요'
--   (세 함수 모두 예전 시그니처를 같은 이름·기본값 인자로 대체 → 옛 앱 버전의 호출도 그대로 동작)
--   앱: 참여/참여 취소/모임 취소 모두 확인 시트(요약·안내·한마디) 거친 뒤 실행
-- ---------------------------------------------------------------

-- ---------------------------------------------------------------
-- 33. 작품 인증의 실·바늘 상세 — 2026-09-20 (마이그레이션 works_yarns_needles)
--   works.yarns jsonb[] = {name, color, amount, unit(볼|g), ball_g, ball_m, weight, fiber} 최대 6 · works.needles jsonb[] = {type(코바늘|대바늘|줄바늘|레이스 바늘), size} 최대 4
--   works.gauge, works.finished_size 추가, needle_size 는 text 로 확장. 기존 yarn_name/yarn_weight/needle_size 에는 첫 번째 실·바늘을 그대로 넣음(옛 데이터·통계 호환)
--   create_work: 시그니처 그대로, p_yarn_meta 의 yarns/needles/gauge/size 를 검증해 저장(알려진 키만, 길이·숫자 검사)
--   yarn_suggest(p_q): 회원들이 적은 실 이름 자동완성 + 가장 흔한 1볼 중량·길이·굵기·소재(집계값만 반환)
--   앱: 굵기는 고르게 하지 않고 1볼 중량(g)·길이(m) → 100g당 길이로 추정(600↑레이스·극세 / 350↑합세 / 250↑중세 / 200↑합태 / 120↑병태 / 60↑극태 / 그 아래 초극태), 길이를 모르면 바늘 mm로 추정, 직접 고르기도 가능
-- ---------------------------------------------------------------

-- ---------------------------------------------------------------
-- 34. 실 빅데이터·표준화 — 2026-09-20 (마이그레이션 yarn_catalog_entries, yarn_catalog_functions)
--   목표: 회원이 적는 실 정보를 전부 쌓고(원문), 같은 실끼리 묶어(표준 사전), 나중에 "이 실 대신 쓸 수 있는 다른 브랜드 실"을 자동 추천
--   yarn_norm(text): 소문자·공백/기호 제거·'3합/4ply/40g' 꼬리 제거 → 매칭 키
--   yarn_catalog(brand, product, aliases[], norm_keys[], ball_g, ball_m, m_per_100g(생성 컬럼), weight_class, fiber_main, fibers{소재:%}, status auto|verified, merged_into, uses)
--     RLS: authenticated 읽기만. 쓰기는 함수로만
--   yarn_entries(catalog_id, work_id(set null), raw_name, norm_name, color, amount, unit, ball_g, ball_m, weight, fiber, fibers, rating(-1/0/1), rating_reason,
--                needles, gauge, techniques, craft, item_type, maker_level): **회원 식별자 없음** — 작품·계정이 지워져도 남는 익명 로그. 관리자만 조회
--   works.item_type(작품 종류, 앱에서 필수) 추가. works.yarns 원소에 rating/rating_reason/fibers 추가
--   yarn_log_entry(...): create_work 가 실마다 호출 — 키로 사전 매칭(합쳐진 실이면 대표 실로), 없으면 후보(auto) 생성, 로그 1건, 후보 상태면 규격·굵기·소재를 회원 입력 최빈값으로 갱신. 직접 호출 불가
--   yarn_suggest(q): 사전(별칭 포함)에서 자동완성 — 표준 이름·규격·혼용률·확정 여부
--   yarn_similar(p_catalog | p_name, limit): 호환 실 = 100g당 길이 ±15%, 같은 소재 우선, 차이%·사용 수·만족도 수 반환 (앱에서는 아직 FULL 전용 화면)
--   admin_yarn_update(jsonb)(브랜드·제품명·별칭·규격·확정) / admin_yarn_merge(from, into)(같은 실 합치기: 로그·별칭 이동) — admin_logs yarn_update/yarn_merge
--   관리자 콘솔 › 실 사전(표준화): 새 실 후보/확정 목록, 합치기, 호환 실·회원 입력 원문 보기
-- ---------------------------------------------------------------

-- ---------------------------------------------------------------
-- 35. 실 색상 표준화 — 2026-09-20 (마이그레이션 yarn_colors_lexicon, yarn_color_family_logging)
--   yarn_catalog 에 shop, source_url, season(여름|겨울|사계절), needle_knit, needle_crochet, gauge, put_up, product_en 추가
--   yarn_colors(catalog_id, no, name, family): 실별 색 목록(쇼핑몰 표기 그대로). authenticated 읽기만
--   color_lexicon(token, family, canonical_ko): 한글·영어 색 낱말 → 표준 색 계열 17종
--     (화이트·아이보리 / 베이지·크림 / 브라운 / 그레이 / 블랙 / 레드 / 와인·버건디 / 핑크 / 오렌지 / 옐로·머스터드 / 그린 / 카키·올리브 / 민트·청록 / 블루·스카이 / 네이비 / 퍼플·라벤더 / 멀티·믹스)
--   color_norm(text), color_family(text): 이름 안에서 **가장 오른쪽에 끝나는 낱말**을 기준색으로 판정("그레이베이지"→베이지, "Dusty Rose"→핑크, "곤색"·"Navy Blue"→네이비)
--   yarn_entries.color_family, yarn_colors.family 는 트리거로 자동 채움 → 회원이 어떻게 적어도 색 계열 단위로 집계·매칭 가능
--   앱: 사전의 실을 고르면 그 실의 색 목록이 색 입력칸 자동완성으로 뜸(직접 입력도 가능)
-- ---------------------------------------------------------------

-- ---------------------------------------------------------------
-- 36. 실 사전 초기 데이터 — 2026-09-20 (마이그레이션 yarn_catalog_import_fn, yarn_norm_keep_ply, color_lexicon_food_nature)
--   yarn_catalog_import(jsonb): 압축 JSON 배열로 확정(verified) 실 + 색 목록 일괄 등록(관리자·운영 도구, 같은 키는 건너뜀)
--   yarn_norm: 합/ply 는 키에서 떼지 않음("뉴하이소프트" ≠ "뉴하이소프트 4ply"). 무게·볼 표기만 제거
--   color_lexicon: 음식·자연 이름 등 보강 → 약 430 낱말
--   등록 데이터(공개 상품 페이지의 볼밴드 규격·색 이름만, 설명문·사진 없음. source_url 에 출처):
--     바늘이야기 39 · 쎄비하우스(sevy.co.kr) 39 · 앵콜스 38 · 청송뜨개실(tgesil.com) 39 = 155종, 색 2,888개(색 계열 자동 판정 97%)
--     계절: 여름 45 · 겨울 73 · 사계절 37. 1볼 중량·길이 모두 있는 실 132종(호환 실 계산 가능)
--     조사 원본·가공 스크립트는 세션 scratchpad(yarns_*.json, yarn_pack.py) — 저장소에는 넣지 않음
-- ---------------------------------------------------------------

-- ---------------------------------------------------------------
-- 37. 실 호환 기준 재정의 — 2026-09-20 대표 지시 (마이그레이션 yarn_texture_use_tags)
--   원칙: 호환에서 제일 중요한 것은 **촉감·재질과 "어떤 작품에 맞는 실인가"**. 굵기·색이 조금 달라도 비슷한 느낌의 결과물이 나와야 함(수세미실로 스웨터를 뜰 수는 없다)
--   yarn_catalog.texture(촉감·구조 8종: 일반사 / 모헤어·헤일로 / 부클·퍼 / 셔닐·벨벳·수면사 / 테이프·라피아·페이퍼 / 패브릭얀·코드 / 수세미사 / 메탈릭)
--   yarn_catalog.use_tags(맞는 작품: 의류 / 방한 소품 / 여름 의류·소품 / 가방·바구니 / 인형 / 블랭킷·쿠션 / 코스터·매트 / 수세미 / 아기용품) — 155종은 제품명·소재·굵기로 1차 자동 분류, 콘솔에서 수정(admin_yarn_set_kind)
--   yarn_similar 재작성: texture 같음 + use_tags 겹침이 **필수 조건**. 점수 = 소재 유사도(혼용률 겹침) 0.5 + 용도 겹침 0.2 + 굵기 근접(±30%까지) 0.3.
--     반환에 texture, use_tags, shared_uses, fiber_sim, score, verdict('거의 같은 느낌' / '비슷한 느낌' / '재질은 맞아요 · 굵기 확인 필요' …) 추가
--   다음 단계: 회원 작품 종류(yarn_entries.item_type)·만족도가 쌓이면 use_tags 를 실제 사용 데이터로 보정
-- ---------------------------------------------------------------

-- ---------------------------------------------------------------
-- 38. 활동 레벨(Lv.) — 2026-09-20 대표 지시 (마이그레이션 activity_level)
--   profiles.act_level = 작품 인증을 올린 **날 수**(한국 시간, 하루 1개만 인정 — 몰아 올리기 방지). works_apply_cert 트리거가 cert_count 와 함께 유지.
--   서버 계산값: UPDATE grant 없음(위조 불가). 인증을 지우면 내려감. '뜨개 단계'(level_crochet/knit = 실력)와는 별개로 '활동량'
-- 39. 이벤트 (마이그레이션 events)
--   events(kind: invite 초대 모임 / sample 샘플 체험단 / general, min_level, capacity, select_mode: admin 직접·first 선착순·lottery 추첨, apply_from~until, cert_due, needs_shipping, catalog_id=연결 실, status draft/open/closed, announced_at)
--   event_applications(status applied/selected/rejected/cancelled/done, level_at, work_id) · event_shipping(선정자만 입력, 본인·관리자만 열람, 발송 30일 뒤 admin_event_apps 호출 때 자동 삭제)
--   works.event_id / works.sponsored(샘플 체험단 인증 = '샘플 제공' 표시, 표시광고법) · notifications.event_id + kind event_open/event_selected/event_rejected
--   회원 RPC: apply_event(레벨·기간·정지 검사, 선착순은 즉시 선정) · cancel_event_application · set_event_shipping(선정자만, 발송 전까지 수정) · link_work_event(p_post, p_event: 작품 인증 직후 앱이 호출 → sponsored 표시 + 신청 done)
--   관리자 RPC: admin_upsert_event(처음 open 될 때 act_level >= min_level 회원 전원에게 event_open 알림 1회) · admin_decide_event_app · admin_event_lottery · admin_event_mark_shipped · admin_event_apps(지난 이벤트 선정/완료 수 포함)
--   테이블은 전부 RLS + 쓰기 grant 없음(함수로만 변경)
-- ---------------------------------------------------------------

-- ---------------------------------------------------------------
-- 40. 서버 함수 호출 제한 (마이그레이션 api_rate_limit) — 2026-09-20 작업지시서 Phase 1
--   api_rate(profile_id, key, win, n): RLS + grant 없음. rate_hit(p_key, p_limit, p_window_sec=60) → boolean (authenticated)
--   (Edge Function place-search 는 카카오 검색용으로 만들었다가 2026-09-20 대표 지시로 폐기 — 앱은 호출하지 않음, 배포본은 빈 응답만. rate_hit 은 Phase 2·3 서버 함수에서 사용)
--   참고: 작업지시서의 yarn_entries.amount_num 은 만들지 않음 — 기존 amount 가 이미 numeric 이라 1.5볼이 그대로 저장됨
-- ---------------------------------------------------------------

-- ---------------------------------------------------------------
-- 41. 내 실함 (마이그레이션 yarn_stash) — 작업지시서 Phase 2 + 2026-09-20 대표 수정 지시
--   yarn_stash(owner_id, catalog_id, raw_name, color, color_family(트리거), ball_g/m, fiber(s), weight, bought_balls, left_balls, band_photo, read_status pending|done|failed|manual, read_json, edited[] = 회원이 고친 항목)
--     RLS: 본인 전부 + **관리자 열람**(지시서의 '본인만'에서 변경). 남은 볼은 본인이 직접 수정 가능(분실 등). 1인 500개
--   yarn_stash_log(stash_id, work_id, delta) — 차감 내역(중복 방지·복원용) · 버킷 bands(비공개, <uid>/ 폴더만, 관리자 읽기)
--   works.yarns[].stash_id → create_work 가 보존하고 저장 직후 stash_consume(work) 호출: 볼 단위 그대로, g 는 ÷1볼 중량, 남은 만큼만 차감
--   works BEFORE DELETE 트리거 → stash_restore(work): 차감분 복원
--   stash_apply_read(id, json, ok) [service_role 전용]: Edge Function read-band 결과 반영(edited 항목은 덮지 않음) → yarn_log_entry 로 실 사전 매칭 + yarn_entries.source='stash'
--   stash_link_catalog(id): 직접 입력한 실도 실 사전에 연결
--   Edge Function `read-band`(supabase/functions/read-band): AI_PROVIDER=anthropic|openrouter, ANTHROPIC_API_KEY / OPENROUTER_API_KEY, AI_MODEL_FAST. 키 없으면 read_status=failed(직접 입력 유도). 1인 하루 30장(rate_hit 'band')
-- ---------------------------------------------------------------

-- ---------------------------------------------------------------
-- 42~44. 지기 AI (마이그레이션 jigi_ai_tables / jigi_ai_tools / jigi_ai_hooks / jigi_on_change_fix) — 작업지시서 Phase 3
--   테이블(전부 RLS, 관리자 열람만, 변경은 함수로만): bad_words(1단계 감지 사전 — banned_words 는 '글쓰기 차단', 이것은 '감지') · mod_items(검토 대기열) · mod_actions(모든 조치 before/after, 되돌리기)
--     · ai_rules(위임 규칙 level 0 보고만/1 제안/2 자동) · ai_briefings · feedback_groups · technique_aliases · technique_candidates · mod_pending(버튼 1회용 토큰) · jigi_chat(대화 기억 30일) · jigi_config(hook_secret)
--   추가 컬럼: posts.hidden_by_mod / mod_scanned_at, meetups.mod_scanned_at, post_reports.mod_seen, reports.mod_seen, works.tech_scanned_at, profiles.post_restricted_until(posts_before_insert 가 검사)
--   jigi_tool(name, args, actor 'ai'|'admin', approved): **AI 가 쓸 수 있는 행동의 전부**. service_role 전용.
--     읽기: get_item, list_open_items, get_post_thread, get_user_summary(연락처·배송지 없음), get_stats, list_feedback_groups, list_technique_candidates, list_rules, list_auto_actions
--     단독 가능: hide_temp, add_to_feedback_group
--     승인 필요(approved=true): unhide, send_warning, restrict_posting(≤30일), dismiss_item, reply_as_jigi, notify_reporter, link_technique_alias, exclude_candidate, save_rule, delete_rule, set_rule_enabled, revert_action
--     없음(불가): 영구 정지, 계정·글 삭제, 개인정보 조회·내보내기, 이벤트 당첨 확정, 결제
--   admin_jigi_tool(name, args): 콘솔용(is_admin → actor admin, approved) · admin_bad_word
--   호출: pg_net + pg_cron. jigi_call(route) → Edge Function `jigi` (헤더 x-jigi-secret = jigi_config.hook_secret). 트리거(posts/post_reports/reports/meetups insert → scan, 실패해도 원래 동작을 막지 않음)
--     크론: jigi-scan */10분 · jigi-brief 23:00 UTC(08:00 KST) · jigi-tech 19:30 UTC · jigi-yarn 20:00 UTC · jigi-clean
--   Edge Function `jigi`(supabase/functions/jigi, verify_jwt=false, 경로별 자체 인증): route scan|brief|tech|yarn(훅 비밀값 또는 관리자) · ?fn=tg(텔레그램 웹훅: secret 헤더 + chat_id 일치) · status|chat|buttons|confirm(관리자 JWT)
-- ---------------------------------------------------------------

-- ---------------------------------------------------------------
-- 45. 지기 예약 알림 + 텔레그램 웹훅 지킴이 (마이그레이션 jigi_reminders) — 2026-09-21
--   jigi_reminders(due_at, text, sent_at): 관리자 열람만. 시간이 되면 Edge Function `jigi-remind` 가 대표 텔레그램으로 보냄(크론 jigi-remind 5분마다, 보낼 것이 있을 때만 호출)
--   크론 jigi-guard(매시 7분): 텔레그램 getWebhookInfo 로 웹훅 주소가 우리 주소인지 확인, 바뀌었으면 되돌리고 보안 알림(봇 토큰 도용 대비)
--   알림 추가: insert into jigi_reminders(due_at, text) values ('2026-09-22 09:30+09', '...');
-- ---------------------------------------------------------------
