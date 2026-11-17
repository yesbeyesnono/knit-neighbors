-- 144. 어떤 뜨친을 찾으시나요? (2026-11-18 대표 확정 시안 friend_want_v2)
-- 회원이 고른 조건(8개 중 3개까지) + 직접 쓴 한 줄(50자). 고른 조건에 맞는 항목은 점수 1.5배, 이유에 '찾으시는 조건' 표시.
-- 직접 쓴 글은 Edge Function friend-want 가 읽어 rec_want_ai 에 나눠 적는다(우리가 아는 정보 → 점수 / 모르는 정보 → unknown 으로 모아 콘솔에서 봄).
-- 글은 인사를 받은 쪽에도 보인다. 저장은 함수로만(링크·연락처·금칙어 막기).

alter table public.profiles add column if not exists rec_want text[] not null default '{}';
alter table public.profiles add column if not exists rec_want_text text;
alter table public.profiles add column if not exists rec_want_ai jsonb;
alter table public.profiles add column if not exists rec_want_at timestamptz;
alter table public.friend_recs add column if not exists rerolls int not null default 0;

create or replace function public._friend_rec_score(a uuid, b uuid)
returns jsonb language plpgsql stable set search_path to 'public', 'extensions' as $fn$
declare
  pa public.profiles; pb public.profiles;
  items jsonb := '[]'::jsonb; s int; n int; t text; names text; recent boolean; d double precision; total int := 0; near text;
  sa text[]; sb text[]; com text[]; want text[]; ai jsonb; boost text[] := '{}';
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

  -- ── 회원이 찾는 뜨친(schema 144): 고른 조건 · 직접 쓴 글에서 AI 가 읽은 것 ──
  want := coalesce(pa.rec_want, '{}'); ai := coalesce(pa.rec_want_ai, '{}'::jsonb);
  -- 내가 알려 줄 수 있는 초보(이 조건을 고른 회원에게만, 한쪽 이유)
  if 'junior' = any(want) then
    if coalesce(pa.level_knit,0) > 0 and coalesce(pb.level_knit,0) > 0 and pa.level_knit - pb.level_knit >= 2 then
      items := items || jsonb_build_object('k','junior','s',60,'t','내가 알려 줄 수 있어요 — 대바늘 '||pb.level_knit||'단계','one',true);
    elsif coalesce(pa.level_crochet,0) > 0 and coalesce(pb.level_crochet,0) > 0 and pa.level_crochet - pb.level_crochet >= 2 then
      items := items || jsonb_build_object('k','junior','s',60,'t','내가 알려 줄 수 있어요 — 코바늘 '||pb.level_crochet||'단계','one',true);
    end if;
  end if;
  -- 글에서 읽은 작품 종류를 상대가 떴음(한쪽 이유)
  if jsonb_typeof(ai->'item_types') = 'array' and jsonb_array_length(ai->'item_types') > 0 then
    select string_agg(distinct w.item_type, '·') into names from public.works w
     where w.profile_id = b and w.review_status = 'approved' and w.item_type in (select jsonb_array_elements_text(ai->'item_types'));
    if names is not null then items := items || jsonb_build_object('k','wtext','s',75,'t','찾으시는 작품을 떠요 — '||names,'one',true,'want',true); end if;
  end if;
  -- 고른 조건에 해당하는 항목은 1.5배
  if 'near'   = any(want) then boost := boost || array['near']; end if;
  if 'level'  = any(want) then boost := boost || array['level']; end if;
  if 'same'   = any(want) then boost := boost || array['tech','item','yarn']; end if;
  if 'senior' = any(want) then boost := boost || array['learn','beginner']; end if;
  if 'junior' = any(want) then boost := boost || array['junior']; end if;
  if 'cross'  = any(want) then boost := boost || array['cross']; end if;
  if 'time'   = any(want) or (jsonb_typeof(ai->'avail') = 'array' and jsonb_array_length(ai->'avail') > 0) then boost := boost || array['time']; end if;
  if 'chat'   = any(want) then boost := boost || array['active','wave','mbti']; end if;
  if cardinality(boost) > 0 then
    select coalesce(jsonb_agg(case when (x->>'k') = any(boost) then x || jsonb_build_object('s', round((x->>'s')::int * 1.5)::int, 'want', true) else x end), '[]'::jsonb)
      into items from jsonb_array_elements(items) x;
  end if;
  -- 서로 찾는 것이 맞음(선배 ↔ 알려 줄 초보): 합계에만
  if ('senior' = any(want) and 'junior' = any(coalesce(pb.rec_want,'{}'))) or ('junior' = any(want) and 'senior' = any(coalesce(pb.rec_want,'{}'))) then
    items := items || jsonb_build_object('k','match','s',30);
  end if;

  select coalesce(sum((x->>'s')::int), 0)::int into total from jsonb_array_elements(items) x;
  return jsonb_build_object('score', total, 'items', items, 'near', near);
end $fn$;

-- 보여 줄 이유를 고를 때 'match' 도 뺀다(_friend_rec_make 는 50점 이상만 쓰므로 그대로 둬도 30점인 match 는 올라오지 않는다)

-- 앱: 찾는 뜨친 저장
create or replace function public.friend_want_set(p_want text[], p_text text)
returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $fn$
declare me uuid := auth.uid(); w text[]; t text := nullif(btrim(coalesce(p_text,'')), ''); old text; changed boolean;
begin
  if me is null then raise exception '로그인이 필요해요'; end if;
  w := array(select x from unnest(coalesce(p_want,'{}')) with ordinality u(x, o)
              where x in ('near','level','same','senior','junior','cross','time','chat') group by x order by min(o) limit 3);
  if t is not null then
    if char_length(t) > 50 then raise exception '50자까지 쓸 수 있어요'; end if;
    if t ~* '(https?://|www\.|[a-z0-9-]+\.(com|co\.kr|kr|net|io|me|shop)(/|\s|$))' or t ~ '[0-9]{2,6}[- ][0-9]{2,6}[- ][0-9]{2,8}' or t ~ '01[0-9][- .]?[0-9]{3,4}[- .]?[0-9]{4}' or t ~ '@' then
      raise exception '링크나 연락처는 넣을 수 없어요'; end if;
    if public.contains_banned(t) then raise exception '커뮤니티 가이드라인에 맞지 않는 표현이 있어요'; end if;
  end if;
  select rec_want_text into old from public.profiles where id = me;
  changed := t is distinct from old;
  update public.profiles set rec_want = w, rec_want_text = t, rec_want_at = now(),
         rec_want_ai = case when changed then null else rec_want_ai end
   where id = me;
  return jsonb_build_object('ok', true, 'parse', changed and t is not null);
end $fn$;

-- 앱: 조건을 바꾼 뒤 오늘의 추천을 다시 고른다(하루 2번까지, 이미 인사를 건넸으면 그대로)
create or replace function public.friend_rec_refresh()
returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $fn$
declare me uuid := auth.uid(); d date := (now() at time zone 'Asia/Seoul')::date; r public.friend_recs; n int;
begin
  if me is null then return null; end if;
  select * into r from public.friend_recs where profile_id = me and day = d;
  if r.id is not null and r.rerolls < 2
     and not exists (select 1 from public.friendships f where f.requester_id = me and f.addressee_id = r.rec_id and f.created_at > now() - interval '1 day') then
    n := r.rerolls;
    delete from public.friend_recs where id = r.id;
    perform public._friend_rec_make(me, d);
    update public.friend_recs set rerolls = n + 1 where profile_id = me and day = d;
  end if;
  return public.friend_rec_today();
end $fn$;

-- 앱 카드: 이유에 '찾으시는 조건' 표시를 함께
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
    'reasons', (select coalesce(jsonb_agg(jsonb_build_object('t', x->>'t', 'want', coalesce((x->>'want')::boolean, false))), '[]'::jsonb) from jsonb_array_elements(r.reasons) x),
    'photos', ph);
end $fn$;

-- 받은 쪽: 소개한 이유 + 상대가 쓴 '이런 뜨친을 찾고 있어요'
create or replace function public.friend_rec_reasons(p_other uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'extensions' as $fn$
declare me uuid := auth.uid(); d date := (now() at time zone 'Asia/Seoul')::date; r public.friend_recs; res jsonb; looking text; asked boolean;
begin
  if me is null or p_other is null then return null; end if;
  asked := exists (select 1 from public.friendships f where f.requester_id = p_other and f.addressee_id = me and f.status in ('pending','accepted'));
  select * into r from public.friend_recs
   where ((profile_id = me and rec_id = p_other) or (profile_id = p_other and rec_id = me)) and day > d - 60
   order by (profile_id = me) desc, day desc limit 1;
  if r.id is not null then
    if r.profile_id = me then
      select jsonb_agg(x->>'t') into res from jsonb_array_elements(r.reasons) x;
    elsif asked then
      -- 상대가 추천을 받았다는 사실은, 그 사람이 나에게 신청했을 때만 알려 준다. 한쪽 이유는 뺀다
      select jsonb_agg(x->>'t') into res from jsonb_array_elements(r.reasons) x where not coalesce((x->>'one')::boolean, false);
    end if;
  end if;
  if asked then select nullif(btrim(coalesce(p.rec_want_text,'')),'') into looking from public.profiles p where p.id = p_other and p.deleted_at is null; end if;
  if res is null and looking is null then return null; end if;
  return jsonb_build_object('reasons', coalesce(res, '[]'::jsonb), 'looking', looking);
end $fn$;

-- 콘솔 › 회원이 찾는 뜨친
create or replace function public.admin_friend_wants()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare r jsonb;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  with m as (select p.* from public.profiles p where not p.is_test and p.onboarded_at is not null and p.deleted_at is null)
  select jsonb_build_object(
    'total', (select count(*) from m),
    'answered', (select count(*) from m where rec_want_at is not null),
    'off', (select count(*) from m where rec_off),
    'opts', (select coalesce(jsonb_agg(jsonb_build_object('k', k, 'n', n) order by n desc), '[]'::jsonb) from (select x k, count(*) n from m, unnest(m.rec_want) x group by 1) q),
    'unknown', (select coalesce(jsonb_agg(jsonb_build_object('label', k, 'n', n) order by n desc, k), '[]'::jsonb) from (select x k, count(*) n from m, jsonb_array_elements_text(case when jsonb_typeof(m.rec_want_ai->'unknown') = 'array' then m.rec_want_ai->'unknown' else '[]'::jsonb end) x group by 1) q),
    'texts', (select coalesce(jsonb_agg(jsonb_build_object('nickname', nickname, 'text', rec_want_text, 'at', rec_want_at, 'ai', rec_want_ai) order by rec_want_at desc), '[]'::jsonb) from (select * from m where rec_want_text is not null order by rec_want_at desc limit 200) q),
    'recs', (select jsonb_build_object('days7', count(*) filter (where fr.day > current_date - 7 and fr.rec_id is not null), 'none7', count(*) filter (where fr.day > current_date - 7 and fr.rec_id is null),
              'hello7', (select count(*) from public.friend_recs f2 join public.friendships fs on fs.requester_id = f2.profile_id and fs.addressee_id = f2.rec_id where f2.day > current_date - 7 and fs.created_at::date >= f2.day)) from public.friend_recs fr)
  ) into r;
  return r;
end $fn$;

revoke all on function public._friend_rec_score(uuid, uuid) from public, anon, authenticated;
revoke all on function public.friend_want_set(text[], text) from public, anon;
revoke all on function public.friend_rec_refresh() from public, anon;
revoke all on function public.friend_rec_today() from public, anon;
revoke all on function public.friend_rec_reasons(uuid) from public, anon;
revoke all on function public.admin_friend_wants() from public, anon;
grant execute on function public.friend_want_set(text[], text), public.friend_rec_refresh(), public.friend_rec_today(), public.friend_rec_reasons(uuid), public.admin_friend_wants() to authenticated;
grant execute on function public._friend_rec_score(uuid, uuid) to service_role;
