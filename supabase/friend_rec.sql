-- 142. 오늘의 추천 뜨친 (2026-11-17 대표 확정 시안 friend_recommend_v3)
-- 하루 한 명. 가까운 이웃 가운데 항목별 점수(0~100)의 합계가 가장 높은 사람을 소개하고, 점수 높은 이유 3개를 두 사람 모두에게 보여 준다.
-- 값이 곧 권리가 아니지만 다른 회원의 정보를 섞어 쓰므로 점수·선정은 서버가 한다. 위치는 서버 안에서만 쓰고 숫자 거리는 내보내지 않는다.
-- 함께: 답이 없는 뜨친 신청 알림을 3일 → 24시간 뒤로(friend_request_remind, 09:30~21:30 사이 매시 30분).

alter table public.profiles add column if not exists rec_off boolean not null default false;
grant update (rec_off) on public.profiles to authenticated;

create table if not exists public.friend_recs (
  id          bigint generated always as identity primary key,
  profile_id  uuid not null references public.profiles(id) on delete cascade,   -- 추천을 받은 회원
  rec_id      uuid references public.profiles(id) on delete cascade,            -- 소개한 회원(null = 그날은 소개할 이웃이 없음)
  day         date not null,                                                    -- 한국 날짜
  score       int  not null default 0,
  near        text,                                                             -- '같은 동네' | '가까운 이웃' | '같은 지역'
  reasons     jsonb not null default '[]'::jsonb,                               -- [{k, s, t, one}] 보여 줄 이유(최대 3)
  items       jsonb not null default '[]'::jsonb,                               -- 항목별 점수 전체(점검용)
  created_at  timestamptz not null default now(),
  unique (profile_id, day)
);
create index if not exists friend_recs_rec_day on public.friend_recs (rec_id, day);
create index if not exists friend_recs_pair on public.friend_recs (profile_id, rec_id);
alter table public.friend_recs enable row level security;
revoke all on public.friend_recs from anon, authenticated;
grant all on public.friend_recs to service_role;
-- 회원은 함수로만 읽는다(직접 조회 정책 없음)

-- 두 사람 사이의 항목별 점수. a = 추천받는 회원, b = 후보
create or replace function public._friend_rec_score(a uuid, b uuid)
returns jsonb language plpgsql stable set search_path to 'public', 'extensions' as $fn$
declare
  pa public.profiles; pb public.profiles;
  items jsonb := '[]'::jsonb; s int; n int; t text; names text; recent boolean; d double precision; total int := 0; near text;
  sa text[]; sb text[]; com text[];
begin
  select * into pa from public.profiles where id = a;
  select * into pb from public.profiles where id = b;
  if pa.id is null or pb.id is null then return null; end if;
  sa := array(select distinct x from unnest(coalesce(pa.skills::text[], '{}') || coalesce(pa.verified_skills::text[], '{}')) x);
  sb := array(select distinct x from unnest(coalesce(pb.skills::text[], '{}') || coalesce(pb.verified_skills::text[], '{}')) x);
  com := array(select unnest(sa) intersect select unnest(sb));

  -- ① 같은 기법: 어려운 기법일수록 더
  select least(100, coalesce(sum(case tq.level when 1 then 3 when 2 then 8 when 3 then 15 when 4 then 22 else 30 end), 0))::int, count(*)::int
    into s, n from public.techniques tq where tq.id = any(com) and not coalesce(tq.hidden, false);
  if s > 0 then
    select string_agg(x.name_ko, '·') into names from (select tq.name_ko from public.techniques tq where tq.id = any(com) and not coalesce(tq.hidden, false) order by tq.level desc, tq.sort nulls last limit 3) x;
    items := items || jsonb_build_object('k','tech','s',s,'t','같은 기법을 떠요 — '||names||case when n > 3 then ' 등 '||n||'가지' else '' end);
  end if;

  -- ② 같은 종류의 작품
  select w1.item_type, (max(w1.created_at) > now() - interval '90 days' and max(w2.created_at) > now() - interval '90 days')
    into t, recent
    from public.works w1 join public.works w2 on w2.item_type = w1.item_type
   where w1.profile_id = a and w2.profile_id = b and w1.review_status = 'approved' and w2.review_status = 'approved'
     and w1.item_type is not null and w1.item_type <> '기타'
   group by 1 order by 2 desc, count(*) desc limit 1;
  if t is not null then
    items := items || jsonb_build_object('k','item','s',case when recent then 80 else 55 end,'t',case when recent then '요즘 뜬 작품이 같아요 — ' else '같은 종류를 떠 봤어요 — ' end||t);
  end if;

  -- ③ 단계가 비슷
  s := 0; t := null;
  if coalesce(pa.level_knit,0) > 0 and coalesce(pb.level_knit,0) > 0 and abs(pa.level_knit - pb.level_knit) <= 1 then
    s := case when pa.level_knit = pb.level_knit then 70 else 40 end;
    t := '대바늘 '||case when pa.level_knit = pb.level_knit then pa.level_knit::text else least(pa.level_knit,pb.level_knit)||'·'||greatest(pa.level_knit,pb.level_knit) end||'단계';
  end if;
  if coalesce(pa.level_crochet,0) > 0 and coalesce(pb.level_crochet,0) > 0 and abs(pa.level_crochet - pb.level_crochet) <= 1
     and (case when pa.level_crochet = pb.level_crochet then 70 else 40 end) > s then
    s := case when pa.level_crochet = pb.level_crochet then 70 else 40 end;
    t := '코바늘 '||case when pa.level_crochet = pb.level_crochet then pa.level_crochet::text else least(pa.level_crochet,pb.level_crochet)||'·'||greatest(pa.level_crochet,pb.level_crochet) end||'단계';
  end if;
  if s > 0 then items := items || jsonb_build_object('k','level','s',s,'t','단계가 비슷해요 — '||t); end if;

  -- ④ 내가 다음에 익힐 기법을 상대가 인증함(한쪽 이유)
  select count(*)::int, string_agg(x.name_ko, '·') into n, names from (
    select tq.name_ko from public.techniques tq
     where tq.id = any(coalesce(pb.verified_skills::text[], '{}')) and not (tq.id = any(sa)) and not coalesce(tq.hidden, false)
       and (case tq.craft when 'knitting' then coalesce(pa.level_knit,0) else coalesce(pa.level_crochet,0) end) > 0
       and tq.level = (case tq.craft when 'knitting' then coalesce(pa.level_knit,0) else coalesce(pa.level_crochet,0) end) + 1
     order by tq.sort nulls last limit 2) x;
  if n > 0 then items := items || jsonb_build_object('k','learn','s',least(90, 50 + 15*n),'t','내가 다음에 익힐 기법을 인증했어요 — '||names,'one',true); end if;

  -- ⑤ 같은 실
  with ya as (
      select lower(btrim(y->>'name')) k, y->>'name' nm from public.works w, jsonb_array_elements(case when jsonb_typeof(w.yarns) = 'array' then w.yarns else '[]'::jsonb end) y
       where w.profile_id = a and w.review_status = 'approved' and coalesce(btrim(y->>'name'),'') <> ''
      union select lower(btrim(coalesce(c.brand||' ','')||c.product)), coalesce(c.brand||' ','')||c.product from public.yarn_stash st join public.yarn_catalog c on c.id = st.catalog_id where st.owner_id = a),
    yb as (
      select lower(btrim(y->>'name')) k from public.works w, jsonb_array_elements(case when jsonb_typeof(w.yarns) = 'array' then w.yarns else '[]'::jsonb end) y
       where w.profile_id = b and w.review_status = 'approved' and coalesce(btrim(y->>'name'),'') <> ''
      union select lower(btrim(coalesce(c.brand||' ','')||c.product)) from public.yarn_stash st join public.yarn_catalog c on c.id = st.catalog_id where st.owner_id = b)
  select count(distinct ya.k)::int, min(ya.nm) into n, names from ya join yb on yb.k = ya.k;
  if n > 0 then items := items || jsonb_build_object('k','yarn','s',case n when 1 then 50 when 2 then 70 else 90 end,'t','같은 실을 써 봤어요 — '||left(names, 24)||case when n > 1 then ' 등 '||n||'가지' else '' end); end if;

  -- ⑥ 시간이 겹침
  select count(*)::int, string_agg(case x when 'weekend' then '주말' when 'weekday_evening' then '평일 저녁' when 'weekday_day' then '평일 낮' else x end, '·' order by x desc)
    into n, names from (select unnest(coalesce(pa.available::text[], '{}')) intersect select unnest(coalesce(pb.available::text[], '{}'))) q(x);
  if n > 0 then items := items || jsonb_build_object('k','time','s',case n when 1 then 50 when 2 then 65 else 75 end,'t','시간이 맞아요 — '||names); end if;

  -- ⑦ 뜨친 찾는 중(한쪽 이유)
  if pb.wave_until > now() then items := items || jsonb_build_object('k','wave','s',60,'t','뜨친을 찾고 있어요','one',true); end if;

  -- ⑧ 초보 환영(한쪽 이유)
  if coalesce(pb.beginner_ok,false) and greatest(coalesce(pa.level_knit,0), coalesce(pa.level_crochet,0)) <= 2 then
    items := items || jsonb_build_object('k','beginner','s',55,'t','초보도 반겨요','one',true); end if;

  -- ⑧-2 다른 종목을 같이 배워 볼 수 있음(한쪽 이유, 2026-11-18 대표): 나는 한 종목만 하고 상대는 다른 종목이 3단계 이상
  if coalesce(pa.level_knit,0) = 0 and coalesce(pa.level_crochet,0) > 0 and coalesce(pb.level_knit,0) >= 3 then
    items := items || jsonb_build_object('k','cross','s',case when coalesce(pb.beginner_ok,false) then 60 else 45 end,'t','대바늘을 같이 배워 볼 수 있어요 — 대바늘 '||pb.level_knit||'단계','one',true);
  elsif coalesce(pa.level_crochet,0) = 0 and coalesce(pa.level_knit,0) > 0 and coalesce(pb.level_crochet,0) >= 3 then
    items := items || jsonb_build_object('k','cross','s',case when coalesce(pb.beginner_ok,false) then 60 else 45 end,'t','코바늘을 같이 배워 볼 수 있어요 — 코바늘 '||pb.level_crochet||'단계','one',true);
  end if;

  -- ⑨ 함께 아는 뜨친
  select count(*)::int into n from
    (select case when requester_id = a then addressee_id else requester_id end x from public.friendships where status = 'accepted' and a in (requester_id, addressee_id)) fa
    join (select case when requester_id = b then addressee_id else requester_id end x from public.friendships where status = 'accepted' and b in (requester_id, addressee_id)) fb on fb.x = fa.x;
  if n > 0 then items := items || jsonb_build_object('k','mutual','s',case n when 1 then 50 when 2 then 80 else 90 end,'t','함께 아는 뜨친이 '||n||'명 있어요'); end if;

  -- ⑩ 같은 모임
  select count(*)::int into n from public.meetups m
    join public.room_members x on x.room_id = m.room_id and x.profile_id = a
    join public.room_members y on y.room_id = m.room_id and y.profile_id = b;
  if n > 0 then items := items || jsonb_build_object('k','meetup','s',case when n = 1 then 60 else 80 end,'t','같은 모임에 나왔어요'); end if;

  -- ⑪ 요즘 활발(한쪽 이유)
  if exists (select 1 from public.works w where w.profile_id = b and w.review_status = 'approved' and w.created_at > now() - interval '14 days') then
    items := items || jsonb_build_object('k','active','s',50,'t','최근에 완성작품을 올렸어요','one',true); end if;

  -- ⑫ MBTI: 최대 30점 — 다른 이유가 모자랄 때만 이유로 올라온다
  if length(btrim(coalesce(pa.mbti::text,''))) = 4 and length(btrim(coalesce(pb.mbti::text,''))) = 4 then
    s := (case when substr(pa.mbti::text,2,1) = substr(pb.mbti::text,2,1) then 15 else 0 end) + (case when substr(pa.mbti::text,3,1) = substr(pb.mbti::text,3,1) then 15 else 0 end);
    if s > 0 then items := items || jsonb_build_object('k','mbti','s',s,'t','MBTI 가 잘 맞아요 — '||upper(pa.mbti::text)||' · '||upper(pb.mbti::text)); end if;
  end if;

  -- ⑬ 거리: 합계에만 넣고 이유로는 쓰지 않는다(카드 맨 위에 늘 보이므로). 숫자 거리는 내보내지 않는다
  if pa.location is not null and pb.location is not null then
    d := ST_Distance(pa.location, pb.location);
    s := case when d < 1000 then 60 when d < 2000 then 45 when d < 3000 then 30 when d < 5000 then 15 else 0 end;
    if s > 0 then items := items || jsonb_build_object('k','near','s',s); end if;
  end if;
  near := case when pa.dong_name is not null and pa.dong_name = pb.dong_name then '같은 동네' when d is not null and d < 5000 then '가까운 이웃' else '같은 지역' end;

  select coalesce(sum((x->>'s')::int), 0)::int into total from jsonb_array_elements(items) x;
  return jsonb_build_object('score', total, 'items', items, 'near', near);
end $fn$;

-- 그날의 한 명을 골라 적어 둔다. 없으면 rec_id = null 로 적어 같은 날 다시 계산하지 않는다
create or replace function public._friend_rec_make(p uuid, d date)
returns bigint language plpgsql security definer set search_path to 'public', 'extensions' as $fn$
declare
  pme public.profiles; c record; sc jsonb; best jsonb; best_id uuid; best_s numeric := -1; cur numeric; found_any boolean := false;
  seen int; tier int; rid bigint; rs jsonb; k int;
  sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e';
begin
  select * into pme from public.profiles where id = p;
  if pme.id is null then return null; end if;
  select id into rid from public.friend_recs where profile_id = p and day = d;
  if rid is not null then return rid; end if;

  foreach seen in array array[7, 30] loop
    for tier in 1..3 loop
      continue when tier < 3 and pme.location is null;
      continue when tier = 3 and coalesce(pme.dong_code,'') = '';
      for c in
        select q.id from public.profiles q
         where q.id <> p and q.id <> sup and q.is_test = pme.is_test
           and q.onboarded_at is not null and q.deleted_at is null and q.suspended_at is null
           and coalesce(q.is_visible, true) and not q.rec_off and not coalesce(q.is_author, false)
           and q.last_seen_at > now() - make_interval(days => seen)
           and (case tier when 1 then q.location is not null and ST_DWithin(q.location, pme.location, 3000)
                          when 2 then q.location is not null and ST_DWithin(q.location, pme.location, 5000)
                          else left(q.dong_code, 5) = left(pme.dong_code, 5) end)
           and not exists (select 1 from public.shops sh where sh.owner_id = q.id)
           and not exists (select 1 from public.friendships f
                            where ((f.requester_id = p and f.addressee_id = q.id) or (f.requester_id = q.id and f.addressee_id = p))
                              and (f.status in ('pending','accepted','blocked') or (f.status = 'declined' and f.responded_at > now() - interval '30 days')))
           and not exists (select 1 from public.friend_recs fr where fr.profile_id = p and fr.rec_id = q.id and fr.day > d - 30)
           and (select count(*) from public.friend_recs fr where fr.rec_id = q.id and fr.day = d) < 3
         order by case when pme.location is not null and q.location is not null then ST_Distance(q.location, pme.location) else 0 end
         limit 40
      loop
        found_any := true;
        sc := public._friend_rec_score(p, c.id);
        continue when sc is null;
        cur := (sc->>'score')::numeric + random();   -- 같은 점수면 무작위
        if cur > best_s then best_s := cur; best := sc; best_id := c.id; end if;
      end loop;
      exit when found_any;
    end loop;
    exit when found_any;
  end loop;

  if best_id is null then
    insert into public.friend_recs(profile_id, rec_id, day) values (p, null, d) on conflict (profile_id, day) do nothing returning id into rid;
    return rid;
  end if;

  -- 보여 줄 이유: 50점 이상 가운데 높은 3개(거리·MBTI 제외). 모자라면 MBTI 를 덧붙인다
  select coalesce(jsonb_agg(x order by (x->>'s')::int desc), '[]'::jsonb) into rs from (
    select x from jsonb_array_elements(best->'items') x where x->>'k' not in ('near','mbti') and (x->>'s')::int >= 50 order by (x->>'s')::int desc limit 3) q;
  k := jsonb_array_length(rs);
  if k < 3 then
    select rs || coalesce(jsonb_agg(x), '[]'::jsonb) into rs from jsonb_array_elements(best->'items') x where x->>'k' = 'mbti';
  end if;

  insert into public.friend_recs(profile_id, rec_id, day, score, near, reasons, items)
    values (p, best_id, d, (best->>'score')::int, best->>'near', rs, best->'items')
    on conflict (profile_id, day) do nothing returning id into rid;
  return rid;
end $fn$;

-- 앱: 오늘의 추천 뜨친 카드
create or replace function public.friend_rec_today()
returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $fn$
declare
  me uuid := auth.uid(); d date := (now() at time zone 'Asia/Seoul')::date;
  pme public.profiles; r public.friend_recs; pb public.profiles; st text; ph jsonb;
begin
  if me is null then return null; end if;
  select * into pme from public.profiles where id = me;
  if pme.id is null or pme.onboarded_at is null or pme.deleted_at is not null or pme.suspended_at is not null or pme.rec_off then return null; end if;
  select * into r from public.friend_recs where profile_id = me and day = d;
  if r.id is null then
    perform public._friend_rec_make(me, d);
    select * into r from public.friend_recs where profile_id = me and day = d;
  end if;
  if r.id is null or r.rec_id is null then return null; end if;
  select * into pb from public.profiles where id = r.rec_id;
  if pb.id is null or pb.deleted_at is not null or pb.suspended_at is not null then return null; end if;
  select f.status::text into st from public.friendships f
   where (f.requester_id = me and f.addressee_id = pb.id) or (f.requester_id = pb.id and f.addressee_id = me) limit 1;
  if st = 'blocked' then return null; end if;
  select coalesce(jsonb_agg(u), '[]'::jsonb) into ph from (
    select po.photos[1] u from public.posts po
     where po.author_id = pb.id and po.parent_id is null and po.work_id is not null and not po.hidden and not coalesce(po.hidden_by_mod, false) and po.archived_at is null
       and po.photos[1] is not null
     order by po.created_at desc limit 3) q;
  return jsonb_build_object('id', r.id, 'day', r.day, 'near', r.near, 'state', coalesce(st, 'none'),
    'p', jsonb_build_object('id', pb.id, 'nickname', pb.nickname, 'avatar_url', pb.avatar_url, 'level_knit', pb.level_knit, 'level_crochet', pb.level_crochet, 'wave', coalesce(pb.wave_until > now(), false)),
    'reasons', (select coalesce(jsonb_agg(x->>'t'), '[]'::jsonb) from jsonb_array_elements(r.reasons) x),
    'photos', ph);
end $fn$;

-- 앱: 이 사람과 나를 knitup 이 소개한 이유(신청을 받은 쪽에도 보여 준다). 받은 쪽에는 한쪽 이유를 빼고 준다
create or replace function public.friend_rec_reasons(p_other uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'extensions' as $fn$
declare me uuid := auth.uid(); d date := (now() at time zone 'Asia/Seoul')::date; r public.friend_recs; res jsonb;
begin
  if me is null or p_other is null then return null; end if;
  select * into r from public.friend_recs
   where ((profile_id = me and rec_id = p_other) or (profile_id = p_other and rec_id = me)) and day > d - 60
   order by (profile_id = me) desc, day desc limit 1;
  if r.id is null then return null; end if;
  if r.profile_id = me then
    select jsonb_agg(x->>'t') into res from jsonb_array_elements(r.reasons) x;
  else
    -- 상대가 추천을 받았다는 사실은, 그 사람이 나에게 신청했을 때만 알려 준다
    if not exists (select 1 from public.friendships f where f.requester_id = p_other and f.addressee_id = me and f.status in ('pending','accepted')) then return null; end if;
    select jsonb_agg(x->>'t') into res from jsonb_array_elements(r.reasons) x where not coalesce((x->>'one')::boolean, false);
  end if;
  return res;
end $fn$;

revoke all on function public._friend_rec_score(uuid, uuid) from public, anon, authenticated;
revoke all on function public._friend_rec_make(uuid, date) from public, anon, authenticated;
revoke all on function public.friend_rec_today() from public, anon;
revoke all on function public.friend_rec_reasons(uuid) from public, anon;
grant execute on function public.friend_rec_today() to authenticated;
grant execute on function public.friend_rec_reasons(uuid) to authenticated;
grant execute on function public._friend_rec_score(uuid, uuid), public._friend_rec_make(uuid, date) to service_role;

-- 답이 없는 뜨친 신청 알림: 3일 → 24시간 뒤, 받은 인사말을 함께
create or replace function public.friend_request_remind()
returns integer language plpgsql security definer set search_path to 'public', 'extensions' as $fn$
declare r record; n int := 0;
begin
  for r in select f.requester_id, f.addressee_id, p.nickname, f.message from public.friendships f
            join public.profiles p on p.id = f.requester_id join public.profiles a on a.id = f.addressee_id
           where f.status = 'pending' and f.reminded_at is null and f.created_at < now() - interval '24 hours' and f.created_at > now() - interval '60 days'
             and p.deleted_at is null and p.suspended_at is null and a.deleted_at is null and a.suspended_at is null
             and not exists (select 1 from public.friendships b where b.status = 'blocked'
                              and ((b.requester_id = f.requester_id and b.addressee_id = f.addressee_id) or (b.requester_id = f.addressee_id and b.addressee_id = f.requester_id)))
           order by f.created_at limit 200 loop
    insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
      values (r.addressee_id, r.requester_id, 'remind',
        left(coalesce(nullif(btrim(r.nickname),''),'이웃') || ' 님이 인사를 기다리고 있어요' || case when coalesce(btrim(r.message),'') <> '' then ' “' || left(btrim(r.message), 60) || '”' else '' end, 120),
        jsonb_build_object('type','profile','id',r.requester_id));
    update public.friendships set reminded_at = now() where requester_id = r.requester_id and addressee_id = r.addressee_id;
    n := n + 1;
  end loop;
  return n;
end $fn$;
revoke all on function public.friend_request_remind() from public, anon, authenticated;
-- 하루 한 번(19:30) → 09:30~21:30 사이 매시 30분(밤에는 보내지 않음)
select cron.schedule('friend-remind', '30 0-12 * * *', $$select public.friend_request_remind()$$);
