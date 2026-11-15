-- public 스키마 함수 363개 (pg_get_functiondef 그대로). 권한(acl)은 각 함수 위 주석

-- _admin_meetup_base()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public._admin_meetup_base()
 RETURNS TABLE(id uuid, title text, kind text, craft text, place_name text, address text, starts_at timestamp with time zone, created_at timestamp with time zone, capacity smallint, is_public boolean, hidden boolean, created_by uuid, host text, dong text, region text, joined integer, reviews integer, f_upcoming boolean, f_empty boolean, f_noreview boolean, f_flag boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select m.id, m.title, m.kind, m.craft, m.place_name, m.address, m.starts_at, m.created_at, m.capacity, m.is_public, m.hidden, m.created_by,
    p.nickname, p.dong_name, nullif(split_part(coalesce(p.dong_code,''),'|',1),''),
    greatest(coalesce(m.participant_count,0),0)::int, coalesce(m.review_count,0)::int,
    m.starts_at > now(),
    m.starts_at > now() and m.starts_at < now() + interval '3 days' and coalesce(m.participant_count,0) <= 1,
    m.starts_at < now() - interval '2 days' and coalesce(m.review_count,0) = 0,
    m.hidden or exists(select 1 from public.mod_items mi where mi.status = 'open' and mi.target_id = m.id::text)
  from public.meetups m left join public.profiles p on p.id = m.created_by;
$function$;

-- _admin_meetup_filter(p jsonb)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public._admin_meetup_filter(p jsonb)
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select b.id from public._admin_meetup_base() b
  where (case coalesce(p->>'seg','all') when 'upcoming' then b.f_upcoming when 'empty' then b.f_empty when 'noreview' then b.f_noreview when 'flag' then b.f_flag else true end)
    and (coalesce(p->>'q','') = '' or b.title ilike '%'||(p->>'q')||'%' or coalesce(b.place_name,'') ilike '%'||(p->>'q')||'%' or coalesce(b.host,'') ilike '%'||(p->>'q')||'%')
    and (coalesce(p->>'region','') = '' or b.region = p->>'region')
    and (case coalesce(p->>'when','') when 'week' then b.starts_at >= date_trunc('day', now()) and b.starts_at < now() + interval '7 days'
          when 'month' then b.starts_at >= date_trunc('day', now()) and b.starts_at < now() + interval '30 days'
          when 'past30' then b.starts_at < now() and b.starts_at > now() - interval '30 days' else true end);
$function$;

-- _admin_member_base()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public._admin_member_base()
 RETURNS TABLE(id uuid, nickname text, email text, dong_name text, dong_code text, created_at timestamp with time zone, seen timestamp with time zone, onboarded_at timestamp with time zone, suspended_at timestamp with time zone, deleted_at timestamp with time zone, level_crochet smallint, level_knit smallint, cert_count integer, is_visible boolean, has_loc boolean, f_incomplete boolean, f_dong boolean, f_inactive boolean, f_flag boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select p.id, p.nickname::text, u.email::text, p.dong_name::text, p.dong_code::text, p.created_at,
    greatest(p.last_seen_at, u.last_sign_in_at) as seen, p.onboarded_at, p.suspended_at, p.deleted_at,
    p.level_crochet::smallint, p.level_knit::smallint, coalesce(p.cert_count,0)::integer, coalesce(p.is_visible,true), p.location is not null,
    p.onboarded_at is null,
    p.onboarded_at is not null and (p.location is null or (p.dong_name ~ '(로|길)(\s|$|[0-9])' and p.dong_name !~ '(동|읍|면|리|가)$')),
    p.onboarded_at is not null and coalesce(greatest(p.last_seen_at, u.last_sign_in_at), p.created_at) < now() - interval '3 days',
    p.suspended_at is not null or exists(select 1 from public.reports r where r.reported_id = p.id and r.reviewed_at is null)
  from public.profiles p join auth.users u on u.id = p.id
  where u.email not like '%@knit.local'
$function$;

-- _admin_member_filter(p jsonb)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public._admin_member_filter(p jsonb)
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select b.id from public._admin_member_base() b
  where (coalesce(p->>'seg','all') = 'all' or (p->>'seg' = 'incomplete' and b.f_incomplete) or (p->>'seg' = 'dong' and b.f_dong)
      or (p->>'seg' = 'inactive' and b.f_inactive) or (p->>'seg' = 'flag' and b.f_flag))
    and (coalesce(p->>'q','') = '' or b.nickname ilike '%'||(p->>'q')||'%' or b.email ilike '%'||(p->>'q')||'%' or b.dong_name ilike '%'||(p->>'q')||'%')
    and (coalesce(p->>'days','') = '' or b.created_at >= date_trunc('day', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul' - make_interval(days => greatest((p->>'days')::int - 1, 0)))
    and (coalesce(p->>'from','') = '' or b.created_at >= ((p->>'from')::date)::timestamp at time zone 'Asia/Seoul')
    and (coalesce(p->>'to','') = '' or b.created_at < (((p->>'to')::date + 1))::timestamp at time zone 'Asia/Seoul')
    and (coalesce(p->>'region','') = '' or (position('|' in coalesce(b.dong_code,'')) > 0 and split_part(b.dong_code,'|',1) = p->>'region'))
$function$;

-- _admin_talk_base()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public._admin_talk_base()
 RETURNS TABLE(room_id uuid, uid uuid, nickname text, dong text, joined timestamp with time zone, last_body text, last_photo boolean, last_from_member boolean, last_at timestamp with time zone, member_msgs integer, human_msgs integer, last_member_at timestamp with time zone, last_human_at timestamp with time zone, member_read timestamp with time zone, push_on boolean, tags text[], f_need boolean, f_wait boolean, f_talk boolean, f_unread boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with sup as (select 'e120eb67-b254-4008-92d8-08c95c821e9e'::uuid as id),
  b as (
    select r.id as room_id, u.profile_id as uid, p.nickname, p.dong_name, p.created_at, u.last_read_at,
      lm.body as last_body, lm.photo_url is not null as last_photo, lm.sender_id = u.profile_id as last_from_member, lm.created_at as last_at,
      (select count(*) from public.messages m where m.room_id = r.id and m.sender_id = u.profile_id)::int as member_msgs,
      (select count(*) from public.messages m where m.room_id = r.id and m.sender_id = (select id from sup) and m.by_ai is not true)::int as human_msgs,
      (select max(m.created_at) from public.messages m where m.room_id = r.id and m.sender_id = u.profile_id) as last_member_at,
      (select max(m.created_at) from public.messages m where m.room_id = r.id and m.sender_id = (select id from sup) and m.by_ai is not true) as last_human_at,
      exists (select 1 from public.device_tokens d where d.profile_id = u.profile_id and d.disabled_at is null) as push_on,
      coalesce((select n.tags from public.member_notes n where n.profile_id = u.profile_id), '{}') as tags,
      exists (select 1 from public.support_tickets t where t.room_id = r.id and t.status = 'waiting_admin') as tk_wait
    from public.rooms r
    join public.room_members s on s.room_id = r.id and s.profile_id = (select id from sup)
    join public.room_members u on u.room_id = r.id and u.profile_id <> (select id from sup)
    join public.profiles p on p.id = u.profile_id
    join auth.users au on au.id = p.id and au.email not like '%@knit.local'
    join lateral (select m.body, m.photo_url, m.sender_id, m.created_at from public.messages m where m.room_id = r.id order by m.created_at desc, m.id desc limit 1) lm on true
    where r.kind = 'direct'
  )
  select room_id, uid, nickname, dong_name, created_at, left(regexp_replace(coalesce(last_body,''), '\s+', ' ', 'g'), 90), last_photo, last_from_member, last_at,
    member_msgs, human_msgs, last_member_at, last_human_at, last_read_at, push_on, tags,
    (last_from_member or tk_wait),
    (human_msgs > 0 and not (last_from_member or tk_wait) and (last_member_at is null or last_human_at > last_member_at)),
    (member_msgs > 0 or human_msgs > 0),
    (human_msgs > 0 and not (last_from_member or tk_wait) and (last_member_at is null or last_human_at > last_member_at) and (last_read_at is null or last_read_at < last_human_at))
  from b;
$function$;

-- _bc_deliver(p_id bigint)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public._bc_deliver(p_id bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare b public.broadcasts; uid uuid; n integer := 0; rid uuid; sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e'; lk jsonb; tgt uuid[];
begin
  select * into b from public.broadcasts where id = p_id for update;
  if b.id is null or b.status not in ('scheduled','sending') then return 0; end if;
  update public.broadcasts set status = 'sending' where id = p_id;
  lk := b.link;
  tgt := array(select t.id from public._bc_targets(b.filter, b.exclude, b.limit_n, b.random_pick) t(id));
  foreach uid in array tgt loop
    if 'notify' = any(b.channels) then
      insert into public.notifications(recipient_id, actor_id, kind, snippet, broadcast_id, link, meetup_id, event_id, shop_id, post_id)
      values (uid, sup, 'notice', left(b.body, 200), b.id, lk,
        case when lk->>'type' = 'meetup' then (lk->>'id')::uuid end, case when lk->>'type' = 'event' then (lk->>'id')::uuid end,
        case when lk->>'type' in ('shop','class') then (lk->>'id')::uuid end, case when lk->>'type' = 'post' then (lk->>'id')::uuid end);
    end if;
    if 'chat' = any(b.channels) then
      select r.id into rid from public.rooms r join public.room_members a on a.room_id = r.id and a.profile_id = uid join public.room_members c on c.room_id = r.id and c.profile_id = sup where r.kind = 'direct' limit 1;
      if rid is null then insert into public.rooms(kind, created_by) values ('direct', uid) returning id into rid; insert into public.room_members(room_id, profile_id) values (rid, uid), (rid, sup); end if;
      insert into public.messages(room_id, sender_id, body, by_ai, support_seen) values (rid, sup, b.body, false, true);
    end if;
    n := n + 1;
  end loop;
  update public.broadcasts set status = 'sent', target_count = cardinality(tgt), sent_count = n, sent_at = now() where id = p_id;
  if b.repeat <> 'none' and b.schedule_at is not null then
    insert into public.broadcasts(created_by, name, body, channels, link, filter, exclude, limit_n, random_pick, schedule_at, repeat, status)
    values (b.created_by, b.name, b.body, b.channels, b.link, b.filter, b.exclude, b.limit_n, b.random_pick, b.schedule_at + case b.repeat when 'weekly' then interval '7 days' else interval '1 month' end, b.repeat, 'scheduled');
  end if;
  return n;
exception when others then
  update public.broadcasts set status = 'failed', last_error = left(sqlerrm, 300) where id = p_id; return 0;
end $function$;

-- _bc_ids(f jsonb)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public._bc_ids(f jsonb)
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select p.id from public.profiles p left join auth.users u on u.id = p.id
  where p.suspended_at is null
    and case coalesce(f->>'onboarded','yes') when 'no' then p.onboarded_at is null when 'any' then true else p.onboarded_at is not null end
    and (not f ? 'ids' or p.id = any(array(select (jsonb_array_elements_text(f->'ids'))::uuid)))
    and (not f ? 'nickname' or p.nickname ilike '%' || (f->>'nickname') || '%')
    and (not f ? 'dong' or p.dong_name = any(array(select jsonb_array_elements_text(f->'dong'))))
    and (not f ? 'dong_like' or p.dong_name ilike '%' || (f->>'dong_like') || '%')
    and (not f ? 'radius' or (p.location is not null and st_dwithin(p.location, st_setsrid(st_makepoint((f->'radius'->>'lng')::float8, (f->'radius'->>'lat')::float8), 4326)::geography, coalesce((f->'radius'->>'km')::float8, 3) * 1000)))
    and (not f ? 'craft' or case f->>'craft' when 'crochet' then p.craft in ('crochet','both') when 'knit' then p.craft in ('knit','both') when 'both' then p.craft = 'both' else true end)
    and (not f ? 'lv_crochet' or coalesce(p.level_crochet,0) between coalesce((f->'lv_crochet'->>0)::int,0) and coalesce((f->'lv_crochet'->>1)::int,9))
    and (not f ? 'lv_knit' or coalesce(p.level_knit,0) between coalesce((f->'lv_knit'->>0)::int,0) and coalesce((f->'lv_knit'->>1)::int,9))
    and (not f ? 'skills_has' or coalesce(p.skills,'{}') @> array(select jsonb_array_elements_text(f->'skills_has')))
    and (not f ? 'skills_any' or coalesce(p.skills,'{}') && array(select jsonb_array_elements_text(f->'skills_any')))
    and (not f ? 'skills_missing' or not (coalesce(p.skills,'{}') && array(select jsonb_array_elements_text(f->'skills_missing'))))
    and (not f ? 'verified_has' or coalesce(p.verified_skills,'{}') && array(select jsonb_array_elements_text(f->'verified_has')))
    and (not f ? 'act_level' or coalesce(p.act_level,0) between coalesce((f->'act_level'->>0)::int,0) and coalesce((f->'act_level'->>1)::int,999))
    and (not f ? 'seen_within' or u.last_sign_in_at >= now() - ((f->>'seen_within')::int || ' days')::interval)
    and (not f ? 'seen_over' or coalesce(u.last_sign_in_at, p.created_at) < now() - ((f->>'seen_over')::int || ' days')::interval)
    and (not f ? 'joined_within' or p.created_at >= now() - ((f->>'joined_within')::int || ' days')::interval)
    and (not f ? 'joined_over' or p.created_at < now() - ((f->>'joined_over')::int || ' days')::interval)
    and (not (f->>'no_activity')::boolean is true or (not exists (select 1 from public.posts x where x.author_id = p.id) and not exists (select 1 from public.works w where w.profile_id = p.id)))
    and (not f ? 'active_within' or exists (select 1 from public.posts x where x.author_id = p.id and x.created_at >= now() - ((f->>'active_within')::int || ' days')::interval)
                                  or exists (select 1 from public.works w where w.profile_id = p.id and w.created_at >= now() - ((f->>'active_within')::int || ' days')::interval))
    and (not f ? 'supporter' or case f->>'supporter' when 'active' then exists (select 1 from public.supporters s where s.user_id = p.id and s.status = 'active')
                                                        when 'completed' then exists (select 1 from public.supporters s where s.user_id = p.id and s.status = 'completed')
                                                        when 'any' then exists (select 1 from public.supporters s where s.user_id = p.id)
                                                        when 'none' then not exists (select 1 from public.supporters s where s.user_id = p.id) else true end)
    and (not f ? 'supporter_tier' or exists (select 1 from public.supporters s where s.user_id = p.id and s.tier = any(array(select jsonb_array_elements_text(f->'supporter_tier')))))
    and (not (f->>'waitlist')::boolean is true or exists (select 1 from public.supporter_waitlist w where w.user_id = p.id))
    and (not f ? 'author' or coalesce(p.is_author,false) = (f->>'author')::boolean)
    and (not f ? 'shop_owner' or exists (select 1 from public.shops s where s.owner_id = p.id) = (f->>'shop_owner')::boolean)
    and (not f ? 'shop_follow' or exists (select 1 from public.shop_follows sf where sf.profile_id = p.id and sf.shop_id = (f->>'shop_follow')::uuid))
    and (not (f->>'waving')::boolean is true or p.wave_until > now())
    and (not f ? 'meetup_member' or exists (select 1 from public.meetups m join public.room_members rm on rm.room_id = m.room_id where m.id = (f->>'meetup_member')::uuid and rm.profile_id = p.id))
    and (not f ? 'event' or exists (select 1 from public.event_applications ea where ea.profile_id = p.id and ea.event_id = (f->'event'->>'id')::uuid
          and case coalesce(f->'event'->>'status','any') when 'any' then true when 'not_certified' then ea.status = 'selected' and ea.done_at is null else ea.status = f->'event'->>'status' end))
    and (not (f->>'has_ticket')::boolean is true or exists (select 1 from public.support_tickets t where t.profile_id = p.id))
    and (not (f->>'feedback')::boolean is true or exists (select 1 from public.feedback_reports fr where fr.user_id = p.id))
    and (not f ? 'yarn' or exists (select 1 from public.works w where w.profile_id = p.id and (w.yarn_name ilike '%' || (f->>'yarn') || '%' or w.yarns::text ilike '%' || (f->>'yarn') || '%')))
    and (not f ? 'item_type' or exists (select 1 from public.works w where w.profile_id = p.id and w.item_type = f->>'item_type'))
    and (not f ? 'stash_yarn' or exists (select 1 from public.yarn_stash ys where ys.owner_id = p.id and ys.finished_at is null and ys.raw_name ilike '%' || (f->>'stash_yarn') || '%'))
$function$;

-- _bc_targets(p_filter jsonb, p_exclude jsonb, p_limit integer, p_random boolean)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public._bc_targets(p_filter jsonb, p_exclude jsonb, p_limit integer, p_random boolean)
 RETURNS SETOF uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  return query
  with inc as (
    select t.id from public._bc_ids(coalesce(p_filter,'{}')) t(id) where jsonb_typeof(p_filter->'groups') is distinct from 'array'
    union
    select t.id from jsonb_array_elements(case when jsonb_typeof(p_filter->'groups') = 'array' then p_filter->'groups' else '[]'::jsonb end) g, lateral public._bc_ids(g.value) t(id)),
  exc as (
    select t.id from public._bc_ids(coalesce(p_exclude,'{}')) t(id) where coalesce(p_exclude,'{}') - 'notified_within' - 'event_applied' <> '{}'::jsonb
    union select n.recipient_id from public.notifications n where p_exclude ? 'notified_within' and n.broadcast_id is not null and n.created_at >= now() - ((p_exclude->>'notified_within')::int || ' days')::interval
    union select ea.profile_id from public.event_applications ea where p_exclude ? 'event_applied' and ea.event_id = (p_exclude->>'event_applied')::uuid and ea.status <> 'cancelled')
  select i.id from inc i where i.id not in (select e.id from exc e) and i.id <> coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid)
  order by case when p_random then random() else 0 end, i.id
  limit coalesce(nullif(p_limit,0), 100000);
end $function$;

-- _bigram_dice(a text, b text)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public._bigram_dice(a text, b text)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  with x as (select distinct substr(a, i, 2) g from generate_series(1, greatest(length(a) - 1, 0)) i),
       y as (select distinct substr(b, i, 2) g from generate_series(1, greatest(length(b) - 1, 0)) i)
  select case when (select count(*) from x) = 0 or (select count(*) from y) = 0 then 0
    else round(2.0 * (select count(*) from x join y using (g)) / ((select count(*) from x) + (select count(*) from y)), 3) end;
$function$;

-- _chat_mask(t text)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public._chat_mask(t text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  select regexp_replace(regexp_replace(coalesce(t,''), '[0-9]{3,}', '●●●', 'g'), '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+', '●@●', 'g');
$function$;

-- _chat_rules(p_body text, p_sender uuid, p_room uuid)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public._chat_rules(p_body text, p_sender uuid, p_room uuid)
 RETURNS TABLE(level text, rules text[], warn text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare b text := lower(coalesce(p_body,'')); nb text := regexp_replace(lower(coalesce(p_body,'')), '\s+', '', 'g');
  r text[] := '{}'; lv int := 0; w text; v_new boolean; v_group boolean; v_host boolean;
  phone boolean; acct boolean; money boolean; offapp boolean; link boolean; sexual boolean; threat boolean; selfharm boolean; minor boolean; spray boolean; bad boolean;
begin
  if length(nb) < 2 then return; end if;
  select coalesce((now() - p.created_at) < interval '3 days', false) into v_new from public.profiles p where p.id = p_sender; v_new := coalesce(v_new, false);
  select coalesce(rm.kind = 'group', false) into v_group from public.rooms rm where rm.id = p_room; v_group := coalesce(v_group, false);
  v_host := exists (select 1 from public.meetups m where m.room_id = p_room and m.created_by = p_sender) or exists (select 1 from public.shop_posts sp where sp.room_id = p_room and sp.author_id = p_sender);
  phone := b ~ '01[016789][-. ]?[0-9]{3,4}[-. ]?[0-9]{4}';
  acct := (b ~ '(은행|농협|수협|신협|새마을|우체국|카카오뱅크|카뱅|토스뱅크|케이뱅크|계좌)' and b ~ '[0-9][0-9 -]{8,}[0-9]') or (b ~ '[0-9]{3,6}-[0-9]{2,6}-[0-9]{3,8}' and not phone);
  money := nb ~ '(선입금|먼저입금|입금먼저|입금해주시면|입금부터|송금해|돈좀빌려|돈빌려|상품권|기프티콘번호|수수료먼저|택배비먼저|보증금먼저|예약금먼저)';
  offapp := nb ~ '(카톡아이디|카톡id|카카오톡아이디|카톡주세요|오픈채팅|오픈카톡|오픈톡|텔레그램|라인아이디|라인id|인스타디엠|디엠주세요|dm주세요)';
  link := b ~ '(https?://|www\.)';
  sexual := nb ~ '(섹스|성관계|조건만남|원나잇|야한사진|몸사진|벗은사진|가슴사진|노출사진|모텔가|자위)';
  threat := nb ~ '(죽여버|죽인다|죽일거|가만안둬|가만안둔다|찾아간다|찾아갈게|찾아가서|신상털|신상을털)';
  selfharm := nb ~ '(죽고싶|자살|자해)';
  minor := nb ~ '(몇살|중학생|고등학생|초등학생|미성년|중딩|고딩|초딩)' and nb ~ '(만나|만날|둘이|사진|비밀|혼자)';
  spray := length(nb) >= 15 and (select count(distinct m.room_id) from public.messages m where m.sender_id = p_sender and m.created_at > now() - interval '1 hour' and m.body = p_body) >= 3;
  bad := exists (select 1 from public.bad_words bw where length(bw.word) >= 2 and position(lower(bw.word) in b) > 0);

  if threat then r := array_append(r, '위협'); lv := 3; end if;
  if minor then r := array_append(r, '미성년자 보호'); lv := 3; end if;
  if selfharm then r := array_append(r, '위험 표현'); lv := 3; end if;
  if money then r := array_append(r, '돈 요구'); lv := greatest(lv, case when acct or v_new then 3 else 2 end); w := 'money'; end if;
  if acct then
    if v_group and v_host and not money then r := array_append(r, '계좌번호(모임 안내)'); lv := greatest(lv, 1);
    else r := array_append(r, '계좌번호'); lv := greatest(lv, 2); w := 'money'; end if;
  end if;
  if sexual then r := array_append(r, '성적 표현'); lv := greatest(lv, case when minor then 3 else 2 end); end if;
  if offapp then r := array_append(r, '앱 밖 연락'); if v_new or spray then lv := greatest(lv, 2); w := coalesce(w, 'offapp'); else lv := greatest(lv, 1); end if; end if;
  if phone and not offapp then r := array_append(r, '전화번호'); if v_new then lv := greatest(lv, 2); w := coalesce(w, 'offapp'); else lv := greatest(lv, 1); end if; end if;
  if link then r := array_append(r, '외부 링크'); lv := greatest(lv, case when v_new then 2 else 1 end); end if;
  if spray then r := array_append(r, '같은 내용 반복'); lv := greatest(lv, 2); end if;
  if bad then r := array_append(r, '욕설'); lv := greatest(lv, 2); end if;
  if lv = 0 then return; end if;
  if v_new and lv >= 2 then r := array_append(r, '가입 3일 이내'); end if;
  if lv = 1 and (select count(*) from public.chat_flags f where f.sender_id = p_sender and f.level = 'info' and f.created_at > now() - interval '7 days') >= 3 then
    lv := 2; r := array_append(r, '참고 누적');
  end if;
  return query select case lv when 3 then 'urgent' when 2 then 'check' else 'info' end, r, case when lv >= 2 then w else null end;
end $function$;

-- _chat_scan_on()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public._chat_scan_on()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ select coalesce((select value = 'on' from public.jigi_config where key = 'chat_scan'), false); $function$;

-- _ddeuchin_cfg()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public._ddeuchin_cfg()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when coalesce((value->>'active')::boolean, false)
                   and now() >= coalesce((value->>'from')::timestamptz, now())
                   and now() <  coalesce((value->>'until')::timestamptz, now())
              then value end
  from public.app_config where key = 'ddeuchin_event' $function$;

-- _decide_shop_claim(p_id uuid, p_approve boolean, p_reason text, p_actor uuid, p_via text)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public._decide_shop_claim(p_id uuid, p_approve boolean, p_reason text, p_actor uuid, p_via text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare c public.shop_claims; sid uuid; loc geography;
begin
  select * into c from public.shop_claims where id = p_id for update;
  if c.id is null then raise exception '신청을 찾을 수 없습니다'; end if;
  if c.status <> 'pending' then raise exception '이미 처리된 신청입니다'; end if;
  if p_approve then
    if exists (select 1 from public.shops where owner_id = c.profile_id) then raise exception '이미 가게를 가진 계정입니다'; end if;
    if c.lat is not null and c.lng is not null then loc := st_setsrid(st_makepoint(c.lng, c.lat), 4326)::geography; end if;
    if c.shop_id is not null then
      select id into sid from public.shops where id = c.shop_id and owner_id is null;
      if sid is null then raise exception '이미 오너가 있는 가게입니다'; end if;
      update public.shops set owner_id = c.profile_id, links = coalesce(nullif(c.links,'{}'::jsonb), links), phone = coalesce(phone, c.phone) where id = sid;
    else
      insert into public.shops(name, kind, address, phone, owner_id, links, location, is_active)
      values (c.name, c.kind, c.address, c.phone, c.profile_id, coalesce(c.links,'{}'::jsonb), loc, loc is not null) returning id into sid;
    end if;
    update public.shop_claims set status='approved', shop_id=sid, decided_by=p_actor, decided_at=now() where id = p_id;
    insert into public.notifications(recipient_id, actor_id, kind, snippet, shop_id)
    values (c.profile_id, 'e120eb67-b254-4008-92d8-08c95c821e9e', 'notice', '가게 등록이 승인됐어요: '||c.name||'. 마이 › 설정 › 내 가게 관리에서 사진·소개·링크를 채워 보세요', sid);
  else
    update public.shop_claims set status='rejected', reject_reason=p_reason, decided_by=p_actor, decided_at=now() where id = p_id;
    insert into public.notifications(recipient_id, actor_id, kind, snippet)
    values (c.profile_id, 'e120eb67-b254-4008-92d8-08c95c821e9e', 'notice', '가게 등록 신청이 반려됐어요'||coalesce(': '||nullif(p_reason,''),''));
  end if;
  insert into public.admin_logs(admin_id, action, target_type, target_id, detail)
  values (p_actor, case when p_approve then 'approve_shop_claim' else 'reject_shop_claim' end, 'shop_claim', p_id::text, jsonb_build_object('shop_id', sid, 'name', c.name, 'reason', p_reason, 'via', p_via, 'ai_status', c.ai_status));
  update public.mod_items set status = 'done', resolved_at = now(), resolved_by = case when p_via = 'ai' then 'ai' else 'admin' end where kind = 'shop_claim' and target_id = p_id::text and status = 'open';
  return sid;
end $function$;

-- _friend_next_goal(n integer)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public._friend_next_goal(n integer)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  select coalesce((select min(g) from unnest(array[10,50,100,200,300,500,1000]) g where g > n), ((n / 1000) + 1) * 1000);
$function$;

-- _friend_pairs()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public._friend_pairs()
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select count(*)::int from public.friendships f where f.status = 'accepted'
    and f.requester_id in (select id from public._friend_real()) and f.addressee_id in (select id from public._friend_real());
$function$;

-- _friend_real()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public._friend_real()
 RETURNS TABLE(id uuid, region text, dong text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select p.id,
    case when p.dong_code is null or array_length(string_to_array(p.dong_code,'|'),1) < 2 then null
      when array_length(string_to_array(p.dong_code,'|'),1) = 2 then split_part(p.dong_code,'|',1)
      when split_part(p.dong_code,'|',1) ~ '(도|특별시|광역시|특별자치시)$' then regexp_replace(split_part(p.dong_code,'|',2), '^(.+시)(.+구)$', '\1 \2')
      when split_part(p.dong_code,'|',2) ~ '(구|군)$' then split_part(p.dong_code,'|',1)||' '||split_part(p.dong_code,'|',2)
      else split_part(p.dong_code,'|',1) end,
    p.dong_name
  from public.profiles p join auth.users u on u.id = p.id
  where u.email not like '%@knit.local' and p.id <> 'e120eb67-b254-4008-92d8-08c95c821e9e'::uuid
    and not exists (select 1 from public.admins a where a.profile_id = p.id);
$function$;

-- _jigi_say(p_user uuid, p_body text)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public._jigi_say(p_user uuid, p_body text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e'; rid uuid;
begin
  if p_user is null or p_user = sup then return; end if;
  rid := public._support_room(p_user);
  insert into public.messages(room_id, sender_id, body, by_ai) values (rid, sup, p_body, true);
  insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
    values (p_user, sup, 'notice', left('지기가 메시지를 보냈어요: '||regexp_replace(p_body, '\s+', ' ', 'g'), 200), jsonb_build_object('type','view','view','support'));
end $function$;

-- _meetup_hidden_guard()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public._meetup_hidden_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.hidden is distinct from old.hidden and auth.uid() is not null and not public.is_admin() then new.hidden := old.hidden; end if;
  return new;
end $function$;

-- _news_from_home_notice()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public._news_from_home_notice()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v jsonb := new.value; v_title text; v_body text; v_btn text; v_link jsonb;
begin
  if new.key <> 'home_notice' or v is null then return new; end if;
  v_body := left(trim(coalesce(v->>'body','')),1000); v_title := left(trim(coalesce(v->>'title','')),60);
  if not coalesce((v->>'active')::boolean,false) or v_body = '' or coalesce(v->>'id','') = '' then return new; end if;
  if v_title = '' then v_title := '뜨개동네 소식'; end if;
  v_btn := nullif(left(trim(coalesce(v->>'btn','')),20),'');
  v_link := case when jsonb_typeof(v->'link') = 'object' and v->'link'->>'type' in ('view','post','event','meetup') then v->'link' end;
  if v_link is null then v_btn := null; end if;
  insert into public.news_posts(kind, title, body, src, btn, link) values ('notice', v_title, v_body, 'home:'||(v->>'id'), v_btn, v_link)
    on conflict (src) do update set title = excluded.title, body = excluded.body, btn = excluded.btn, link = excluded.link;
  return new;
end $function$;

-- _nick_key(t text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public._nick_key(t text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$ select regexp_replace(lower(coalesce(t,'')), '\s', '', 'g') $function$;

-- _own_storage_url(u text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public._own_storage_url(u text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'extensions'
AS $function$ select u is null or u ~ '^https://(api\.knitup\.co\.kr|thfcrodfaitzrzlrxyir\.supabase\.co)/storage/v1/object/public/(avatars|shops)/[A-Za-z0-9/_.-]+$' $function$;

-- _partner_guide_send(p_user uuid, p_kind text)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public._partner_guide_send(p_user uuid, p_kind text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e'; rid uuid; mid bigint; nm text; body text; card jsonb; snip text; dup boolean;
begin
  if p_user is null or p_user = sup or p_kind not in ('author','shop') then return false; end if;
  insert into public.partner_guides(profile_id, kind) values (p_user, p_kind) on conflict do nothing;
  if not found then return false; end if;
  if p_kind = 'author' then
    select nickname into nm from public.profiles where id = p_user;
    body := coalesce(nm,'작가')||' 님, knitup 작가가 되셨어요 ♛'||E'\n'
      ||'이제 지도에 황금색 작가 핀으로 보이고, 나만의 작가 페이지가 생겼어요.'||E'\n\n'
      ||'먼저 이 두 가지만 해 두시면 좋아요.'||E'\n'
      ||'1. 마이 › 설정 › 작가 화면 꾸미기에서 대표 사진과 링크 넣기'||E'\n'
      ||'2. 아래 ＋ 에서 모임이나 클래스 열기'||E'\n\n'
      ||'작가 안내: app.knitup.co.kr/authors.html';
    card := jsonb_build_object('type','guide','guide','author','label','작가 안내 보기','url','https://app.knitup.co.kr/authors.html');
    snip := coalesce(nm,'작가')||' 님, knitup 작가가 되셨어요 ♛ 작가 안내를 보내 드렸어요. 눌러서 확인해 보세요.';
    dup := exists (select 1 from public.notifications n where n.recipient_id = p_user and n.kind = 'notice' and n.snippet like '작가로 승인됐어요%' and n.created_at > now() - interval '2 minutes');
  else
    select s.name into nm from public.shops s where s.owner_id = p_user order by s.created_at limit 1;
    body := coalesce(nm,'')||' 사장님, knitup 가게 문이 열렸어요'||E'\n'
      ||'지도에 가게 핀과 가게 페이지가 생겼어요.'||E'\n\n'
      ||'먼저 이 두 가지만 해 두시면 좋아요.'||E'\n'
      ||'1. 마이 › 설정 › 내 가게 관리에서 로고와 매장 사진 넣기'||E'\n'
      ||'2. 아래 ＋ › 가게 소식으로 첫 소식 올리기'||E'\n\n'
      ||'가게 안내: app.knitup.co.kr/shop-guide.html';
    card := jsonb_build_object('type','guide','guide','shop','label','가게 안내 보기','url','https://app.knitup.co.kr/shop-guide.html');
    snip := 'knitup 가게 문이 열렸어요. 가게 안내를 보내 드렸어요. 눌러서 확인해 보세요.';
    dup := exists (select 1 from public.notifications n where n.recipient_id = p_user and n.kind = 'notice' and n.snippet like '가게 등록이 승인됐어요%' and n.created_at > now() - interval '2 minutes');
  end if;
  rid := public._support_room(p_user);
  insert into public.messages(room_id, sender_id, body, by_ai, card) values (rid, sup, body, true, card) returning id into mid;
  if not dup then   -- 승인 알림이 방금 갔으면 푸시를 한 번 더 보내지 않는다
    insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
      values (p_user, sup, 'notice', snip, jsonb_build_object('type','view','view','support'));
  end if;
  update public.partner_guides set sent_at = now(), msg_id = mid where profile_id = p_user and kind = p_kind;
  return true;
end $function$;

-- _post_photo_ok(p_new text[], p_old text[])  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public._post_photo_ok(p_new text[], p_old text[])
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select not exists (select 1 from unnest(coalesce(p_new,'{}')) u
    where not (u = any(coalesce(p_old,'{}')))
      and u !~ '^https://(api\.knitup\.co\.kr|thfcrodfaitzrzlrxyir\.supabase\.co)/storage/v1/object/public/[A-Za-z0-9/_.%-]+$');
$function$;

-- _report_case_close(p_case bigint, p_ok boolean, p_by text, p_why text)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public._report_case_close(p_case bigint, p_ok boolean, p_by text, p_why text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

-- _support_room(p_user uuid)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public._support_room(p_user uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e'; rid uuid;
begin
  select r.id into rid from public.rooms r join public.room_members a on a.room_id = r.id and a.profile_id = p_user join public.room_members b on b.room_id = r.id and b.profile_id = sup where r.kind = 'direct' limit 1;
  if rid is null then
    insert into public.rooms(kind, created_by) values ('direct', p_user) returning id into rid;
    insert into public.room_members(room_id, profile_id) values (rid, p_user), (rid, sup);
  end if;
  return rid;
end $function$;

-- _work_tags(p_work uuid)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public._work_tags(p_work uuid)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(array_agg(distinct t), '{}') from (
    select lower(x) t from public.works w, regexp_split_to_table(coalesce(w.item_type,''), '[^가-힣A-Za-z0-9_]+') x where w.id = p_work and length(x) between 1 and 20
    union select case tq.craft::text when 'crochet' then '코바늘' when 'knitting' then '대바늘' end from public.works w join public.techniques tq on tq.id = any(w.techniques) where w.id = p_work
    union select lower(left(regexp_replace(tq.name_ko, '[^가-힣A-Za-z0-9_]', '', 'g'), 20)) from public.works w join public.techniques tq on tq.id = any(w.techniques) where w.id = p_work
  ) s where t is not null and t <> '';
$function$;

-- admin_bad_word(p_word text, p_category text, p_add boolean)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_bad_word(p_word text, p_category text, p_add boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  if p_add then insert into public.bad_words(word, category) values (left(btrim(p_word),30), coalesce(nullif(p_category,''),'abuse')) on conflict (word) do update set category = excluded.category;
  else delete from public.bad_words where word = p_word; end if;
  perform public.admin_log(case when p_add then 'add_bad_word' else 'remove_bad_word' end, 'bad_word', p_word, null);
end $function$;

-- admin_banned_word(p_word text, p_add boolean)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_banned_word(p_word text, p_add boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  if p_add then insert into public.banned_words(word) values (btrim(p_word)) on conflict do nothing;
  else delete from public.banned_words where word = btrim(p_word); end if;
  perform public.admin_log(case when p_add then 'add_banned' else 'remove_banned' end, 'word', btrim(p_word), null);
end $function$;

-- admin_bc_options()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_bc_options()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when public.is_admin() then jsonb_build_object(
    'dongs', (select coalesce(jsonb_agg(jsonb_build_object('name', dong_name, 'n', n) order by n desc), '[]') from (select dong_name, count(*) n from public.profiles where dong_name is not null and onboarded_at is not null group by 1) d),
    'techniques', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name_ko, 'craft', craft, 'level', level) order by sort), '[]') from public.techniques),
    'shops', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name) order by name), '[]') from public.shops),
    'events', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'title', title, 'status', status) order by created_at desc), '[]') from (select * from public.events order by created_at desc limit 30) e),
    'meetups', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'title', title, 'starts_at', starts_at) order by starts_at desc), '[]') from (select * from public.meetups where starts_at > now() - interval '30 days' order by starts_at desc limit 50) m),
    'posts', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'title', left(coalesce(body,''), 40)) order by created_at desc), '[]') from (select * from public.posts where parent_id is null and not hidden order by created_at desc limit 30) ps),
    'patterns', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'title', title) order by created_at desc), '[]') from (select * from public.patterns order by created_at desc limit 30) pt),
    'segments', (select coalesce(jsonb_agg(to_jsonb(s) order by s.name), '[]') from public.broadcast_segments s),
    'item_types', (select coalesce(jsonb_agg(distinct item_type), '[]') from public.works where item_type is not null)) else '{}'::jsonb end;
$function$;

-- admin_broadcast(p_body text, p_user uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_broadcast(p_body text, p_user uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n integer;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  if p_user is not null then
    insert into public.notifications(recipient_id, actor_id, kind, snippet) values (p_user, auth.uid(), 'notice', left(p_body, 200));
    n := 1;
  else
    insert into public.notifications(recipient_id, actor_id, kind, snippet)
      select id, auth.uid(), 'notice', left(p_body, 200) from public.profiles where onboarded_at is not null and suspended_at is null and id <> auth.uid();
    get diagnostics n = row_count;
  end if;
  perform public.admin_log('broadcast', case when p_user is null then 'all' else 'user' end, coalesce(p_user::text,'all'), jsonb_build_object('body', left(p_body,200), 'count', n));
  return n;
end $function$;

-- admin_broadcast_cancel(p_id bigint)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_broadcast_cancel(p_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  update public.broadcasts set status = 'cancelled' where id = p_id and status = 'scheduled';
  perform public.admin_log('broadcast_cancel', 'broadcast', p_id::text, null);
end $function$;

-- admin_broadcast_history(p_limit integer)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_broadcast_history(p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when public.is_admin() then coalesce(jsonb_agg(to_jsonb(b) || jsonb_build_object('read_count', s.rd, 'clicked_count', s.ck, 'who', pr.nickname) order by coalesce(b.schedule_at, b.created_at) desc), '[]') else '[]'::jsonb end
  from (select * from public.broadcasts order by coalesce(schedule_at, created_at) desc limit p_limit) b
  left join lateral (select count(*) filter (where n.read_at is not null) rd, count(*) filter (where n.clicked_at is not null) ck from public.notifications n where n.broadcast_id = b.id) s on true
  left join public.profiles pr on pr.id = b.created_by;
$function$;

-- admin_broadcast_preview(p jsonb)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_broadcast_preview(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n integer; smp jsonb;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  select count(*) into n from public._bc_targets(p->'filter', p->'exclude', (p->>'limit_n')::int, coalesce((p->>'random')::boolean,false)) t(id);
  select coalesce(jsonb_agg(jsonb_build_object('id', pr.id, 'nickname', pr.nickname, 'dong', pr.dong_name, 'craft', pr.craft, 'lv', greatest(coalesce(pr.level_crochet,0), coalesce(pr.level_knit,0)))), '[]') into smp
    from (select t.id from public._bc_targets(p->'filter', p->'exclude', (p->>'limit_n')::int, coalesce((p->>'random')::boolean,false)) t(id) limit 8) t join public.profiles pr on pr.id = t.id;
  return jsonb_build_object('count', n, 'sample', smp);
end $function$;

-- admin_broadcast_send(p jsonb)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_broadcast_send(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare bid bigint; n integer; sched timestamptz; sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e'; rid uuid; lk jsonb;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  if nullif(btrim(p->>'body'),'') is null then raise exception '내용을 입력하세요'; end if;
  lk := p->'link'; if jsonb_typeof(lk) <> 'object' then lk := null; end if;
  if coalesce((p->>'test')::boolean,false) then
    insert into public.notifications(recipient_id, actor_id, kind, snippet, link) values (auth.uid(), sup, 'notice', left(p->>'body',200), lk);
    if p->'channels' ? 'chat' then
      select r.id into rid from public.rooms r join public.room_members a on a.room_id = r.id and a.profile_id = auth.uid() join public.room_members c on c.room_id = r.id and c.profile_id = sup where r.kind = 'direct' limit 1;
      if rid is null then insert into public.rooms(kind, created_by) values ('direct', auth.uid()) returning id into rid; insert into public.room_members(room_id, profile_id) values (rid, auth.uid()), (rid, sup); end if;
      insert into public.messages(room_id, sender_id, body, by_ai, support_seen) values (rid, sup, p->>'body', false, true);
    end if;
    return jsonb_build_object('test', true, 'sent', 1);
  end if;
  sched := nullif(p->>'schedule_at','')::timestamptz;
  insert into public.broadcasts(created_by, name, body, channels, link, filter, exclude, limit_n, random_pick, schedule_at, repeat, status)
  values (auth.uid(), nullif(p->>'name',''), left(p->>'body',300), coalesce(array(select jsonb_array_elements_text(p->'channels')), '{notify}'), lk,
    coalesce(p->'filter','{}'), coalesce(p->'exclude','{}'), nullif(p->>'limit_n','')::int, coalesce((p->>'random')::boolean,false), sched,
    coalesce(nullif(p->>'repeat',''),'none'), case when sched is not null and sched > now() then 'scheduled' else 'sending' end) returning id into bid;
  if sched is not null and sched > now() then
    perform public.admin_log('broadcast_schedule', 'broadcast', bid::text, jsonb_build_object('at', sched, 'repeat', p->>'repeat'));
    return jsonb_build_object('id', bid, 'scheduled', true, 'at', sched);
  end if;
  n := public._bc_deliver(bid);
  perform public.admin_log('broadcast', 'broadcast', bid::text, jsonb_build_object('body', left(p->>'body',200), 'count', n, 'filter', p->'filter', 'exclude', p->'exclude', 'channels', p->'channels'));
  return jsonb_build_object('id', bid, 'sent', n);
end $function$;

-- admin_chat_flag_ctx(p_id bigint)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_chat_flag_ctx(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare f public.chat_flags; m public.messages; r jsonb;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  select * into f from public.chat_flags where id = p_id; if f.id is null then raise exception '점검 건을 찾을 수 없어요'; end if;
  select * into m from public.messages where id = f.message_id; if m.id is null then raise exception '메시지가 이미 지워졌어요'; end if;
  select jsonb_agg(jsonb_build_object('id', x.id, 'body', x.body, 'photo', x.photo_url is not null, 'at', x.created_at, 'from', pp.nickname, 'is_sender', x.sender_id = f.sender_id, 'hit', x.id = m.id) order by x.created_at, x.id) into r
    from ((select * from public.messages a where a.room_id = m.room_id and (a.created_at, a.id) <= (m.created_at, m.id) order by a.created_at desc, a.id desc limit 6)
          union all (select * from public.messages a where a.room_id = m.room_id and (a.created_at, a.id) > (m.created_at, m.id) order by a.created_at, a.id limit 5)) x
    left join public.profiles pp on pp.id = x.sender_id;
  perform public.log_access('chat_flag', p_id::text, jsonb_array_length(coalesce(r,'[]'::jsonb)));
  return jsonb_build_object('flag', jsonb_build_object('id', f.id, 'level', f.level, 'rules', to_jsonb(f.rules), 'ai', f.ai, 'status', f.status, 'resolution', f.resolution, 'room', f.room_id, 'at', f.created_at, 'warn', f.warn),
    'sender', (select jsonb_build_object('id', p.id, 'nick', p.nickname, 'days', floor(extract(epoch from (now() - p.created_at)) / 86400)::int, 'suspended', p.suspended_at is not null,
        'restricted', coalesce(p.chat_restricted_until > now(), false),
        'reports', (select count(*) from public.reports rp where rp.reported_id = p.id), 'flags', (select count(*) from public.chat_flags cf where cf.sender_id = p.id and cf.level in ('urgent','check')))
      from public.profiles p where p.id = f.sender_id),
    'more_before', exists (select 1 from public.messages a where a.room_id = m.room_id and a.created_at < (select min((e->>'at')::timestamptz) from jsonb_array_elements(r) e)),
    'more_after', exists (select 1 from public.messages a where a.room_id = m.room_id and a.created_at > (select max((e->>'at')::timestamptz) from jsonb_array_elements(r) e)),
    'msgs', coalesce(r, '[]'::jsonb));
end $function$;

-- admin_chat_flag_resolve(p_id bigint, p_action text, p_days integer)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_chat_flag_resolve(p_id bigint, p_action text, p_days integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare f public.chat_flags; n int := 0; v_until timestamptz; sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e';
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  select * into f from public.chat_flags where id = p_id; if f.id is null then raise exception '점검 건을 찾을 수 없어요'; end if;
  if p_action = 'ok' then
    update public.chat_flags set status = 'ok', warn = null, resolution = '문제없음', resolved_by = auth.uid(), resolved_at = now() where id = p_id;
  elsif p_action = 'warn' then
    insert into public.notifications(recipient_id, actor_id, kind, snippet, link) values (f.sender_id, sup, 'notice',
      '채팅에서 커뮤니티 가이드라인에 맞지 않는 내용이 확인됐어요. 돈거래 요구, 앱 밖으로 끌어내는 연락, 불쾌한 표현은 삼가 주세요. 반복되면 채팅이 제한될 수 있어요.', jsonb_build_object('type','view','view','support'));
    update public.chat_flags set status = 'actioned', resolution = '경고', resolved_by = auth.uid(), resolved_at = now() where id = p_id;
  elsif p_action = 'restrict' then
    v_until := now() + make_interval(days => greatest(1, least(coalesce(p_days,7), 90)));
    update public.profiles set chat_restricted_until = v_until where id = f.sender_id;
    insert into public.notifications(recipient_id, actor_id, kind, snippet, link) values (f.sender_id, sup, 'notice',
      '커뮤니티 가이드라인에 맞지 않는 채팅이 확인되어 '||to_char(v_until at time zone 'Asia/Seoul', 'FMMM"월" FMDD"일"')||'까지 채팅이 제한됐어요. 궁금한 점은 지기에게 말하기로 알려 주세요.', jsonb_build_object('type','view','view','support'));
    update public.chat_flags set status = 'actioned', resolution = '채팅 제한 '||greatest(1, least(coalesce(p_days,7), 90))||'일', resolved_by = auth.uid(), resolved_at = now() where id = p_id;
  elsif p_action = 'suspended' then
    update public.chat_flags set status = 'actioned', resolution = '정지', resolved_by = auth.uid(), resolved_at = now() where id = p_id;
  elsif p_action = 'caution' then
    insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
      select rm.profile_id, sup, 'notice', '방금 받으신 채팅 가운데 주의가 필요한 내용이 있어 운영진이 확인했어요. 돈을 먼저 보내거나 개인 정보를 알려 주지 마세요. 불안하면 그 메시지를 길게 눌러 신고해 주세요.', jsonb_build_object('type','view','view','chats')
      from public.room_members rm where rm.room_id = f.room_id and rm.profile_id <> f.sender_id and rm.profile_id <> sup;
    get diagnostics n = row_count;
  else raise exception '알 수 없는 작업이에요'; end if;
  perform public.admin_log('chat_flag', 'chat_flag', p_id::text, jsonb_build_object('action', p_action, 'sender', f.sender_id, 'rules', f.rules, 'notified', n));
  return jsonb_build_object('ok', true, 'notified', n);
end $function$;

-- admin_chat_flags(p jsonb)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_chat_flags(p jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_day timestamptz := date_trunc('day', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul'; v_show text := coalesce(p->>'show','open'); sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e';
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  return jsonb_build_object('enabled', public._chat_scan_on(),
    'today', jsonb_build_object(
      'total', (select count(*) from public.messages m where m.created_at >= v_day and m.sender_id <> sup and not exists (select 1 from public.room_members s where s.room_id = m.room_id and s.profile_id = sup)),
      'urgent', (select count(*) from public.chat_flags f where f.created_at >= v_day and f.level = 'urgent'),
      'check', (select count(*) from public.chat_flags f where f.created_at >= v_day and f.level = 'check'),
      'info', (select count(*) from public.chat_flags f where f.created_at >= v_day and f.level = 'info')),
    'open', (select count(*) from public.chat_flags f where f.status = 'open' and f.level in ('urgent','check')),
    'rows', coalesce((select jsonb_agg(x order by (x->>'ord')::int, x->>'at' desc) from (
      select jsonb_build_object('id', f.id, 'level', f.level, 'ord', case f.level when 'urgent' then 0 when 'check' then 1 else 2 end, 'rules', to_jsonb(f.rules), 'at', f.created_at, 'status', f.status, 'resolution', f.resolution,
        'ai', f.ai, 'from', ps.nickname, 'from_id', f.sender_id, 'from_days', floor(extract(epoch from (now() - ps.created_at)) / 86400)::int,
        'group', r.kind = 'group', 'room_title', case when r.kind = 'group' then coalesce(nullif(r.title,''), (select title from public.meetups where room_id = r.id limit 1), '모임 채팅') end,
        'to', case when r.kind = 'group' then null else (select pp.nickname from public.room_members rm join public.profiles pp on pp.id = rm.profile_id where rm.room_id = f.room_id and rm.profile_id <> f.sender_id limit 1) end) x
      from public.chat_flags f join public.rooms r on r.id = f.room_id left join public.profiles ps on ps.id = f.sender_id
      where case v_show when 'info' then f.level = 'info' and f.status = 'open' when 'done' then f.status <> 'open' else f.status = 'open' and f.level in ('urgent','check') end
      order by f.created_at desc limit 100) t), '[]'::jsonb));
end $function$;

-- admin_chat_room_open(p_room uuid, p_reason text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_chat_room_open(p_room uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb; v_reason text := trim(coalesce(p_reason,''));
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  if length(v_reason) < 5 then raise exception '열람 사유를 5자 이상 적어 주세요'; end if;
  if not exists (select 1 from public.rooms where id = p_room) then raise exception '대화방을 찾을 수 없어요'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'body', x.body, 'photo', x.photo_url is not null, 'at', x.created_at, 'from', pp.nickname, 'from_id', x.sender_id,
      'flag', exists (select 1 from public.chat_flags cf where cf.message_id = x.id)) order by x.created_at, x.id), '[]'::jsonb) into r
    from (select * from public.messages a where a.room_id = p_room order by a.created_at desc, a.id desc limit 500) x left join public.profiles pp on pp.id = x.sender_id;
  perform public.log_access('chat_room', left(p_room::text||' · '||v_reason, 200), jsonb_array_length(r));
  perform public.admin_log('chat_room_open', 'room', p_room::text, jsonb_build_object('reason', left(v_reason, 300), 'n', jsonb_array_length(r)));
  return jsonb_build_object('msgs', r);
end $function$;

-- admin_chat_scan_set(p_on boolean)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_chat_scan_set(p_on boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  insert into public.jigi_config(key, value) values ('chat_scan', case when p_on then 'on' else 'off' end) on conflict (key) do update set value = excluded.value;
  perform public.admin_log('chat_scan_set', 'config', 'chat_scan', jsonb_build_object('on', p_on));
  return p_on;
end $function$;

-- admin_cohort_set(p_open boolean, p_capacity integer)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_cohort_set(p_open boolean, p_capacity integer DEFAULT NULL::integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  update public.supporter_cohorts set is_open = p_open, capacity = coalesce(p_capacity, capacity) where id = (select id from public.supporter_cohorts order by id desc limit 1);
  perform public.admin_log('cohort_set', 'cohort', '', jsonb_build_object('open', p_open, 'capacity', p_capacity));
end $function$;

-- admin_ddeuchin_decide(p_id bigint, p_pass boolean, p_reason text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_ddeuchin_decide(p_id bigint, p_pass boolean, p_reason text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v record; sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e';
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  select * into v from public.ddeuchin_claims where id = p_id for update;
  if v.id is null then raise exception '찾을 수 없어요'; end if;
  if v.status = 'sent' then raise exception '이미 쿠폰을 보낸 건이에요'; end if;
  if p_pass then
    if v.pair is null then raise exception '뜨친·기간 조건을 채우지 못한 글은 통과시킬 수 없어요'; end if;
    update public.ddeuchin_claims set status = 'ok', reason = null, decided_at = now() where id = p_id;
  else
    update public.ddeuchin_claims set status = 'excluded', reason = coalesce(nullif(trim(p_reason),''), '사진에서 함께 뜬 모습을 확인하지 못했어요'), decided_at = now() where id = p_id;
    insert into public.notifications(recipient_id, actor_id, kind, post_id, snippet, link)
      values (v.author_id, sup, 'notice', v.post_id, left('뜨친 인증 이벤트: 이번 글은 대상이 아니에요 — '||coalesce(nullif(trim(p_reason),''), '사진에서 함께 뜬 모습을 확인하지 못했어요')||'. 궁금한 점은 지기에게 말씀해 주세요.', 200),
              jsonb_build_object('type','view','view','support','push','0'));
  end if;
  perform public.admin_log('ddeuchin_decide', 'ddeuchin', p_id::text, jsonb_build_object('pass', p_pass, 'reason', p_reason));
  return (select status from public.ddeuchin_claims where id = p_id);
end $function$;

-- admin_ddeuchin_list()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_ddeuchin_list()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  return jsonb_build_object(
    'cfg', (select value from public.app_config where key = 'ddeuchin_event'),
    'stats', (select jsonb_build_object('all', count(*), 'ok', count(*) filter (where status='ok'), 'review', count(*) filter (where status='review'),
                                        'sent', count(*) filter (where status='sent'), 'excluded', count(*) filter (where status='excluded')) from public.ddeuchin_claims),
    'rows', coalesce((select jsonb_agg(x order by x.created_at desc) from (
        select c.id, c.post_id, c.status, c.reason, c.ai, c.ai_note, c.created_at, c.sent_at, c.author_id, c.friend_id,
               a.nickname as author, b.nickname as friend, p.photos[1] as photo, left(p.body, 140) as body
        from public.ddeuchin_claims c join public.posts p on p.id = c.post_id
        left join public.profiles a on a.id = c.author_id left join public.profiles b on b.id = c.friend_id
        order by c.created_at desc limit 300) x), '[]'::jsonb));
end $function$;

-- admin_ddeuchin_rooms(p_id bigint)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_ddeuchin_rooms(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v record;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  select * into v from public.ddeuchin_claims where id = p_id;
  if v.id is null or v.status <> 'ok' then raise exception '확인 완료된 건만 보낼 수 있어요'; end if;
  return jsonb_build_object('a', public._support_room(v.author_id), 'b', public._support_room(v.friend_id));
end $function$;

-- admin_ddeuchin_send(p_id bigint, p_photo_a text, p_photo_b text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_ddeuchin_send(p_id bigint, p_photo_a text, p_photo_b text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v record; msg constant text := '뜨친 인증 축하드려요! ☕ 약속드린 커피 쿠폰을 보내 드려요. 뜨친과 함께 따뜻한 시간 보내세요 🧶';
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  if coalesce(p_photo_a,'') = '' or coalesce(p_photo_b,'') = '' then raise exception '쿠폰 이미지 2장이 필요해요'; end if;
  if p_photo_a = p_photo_b then raise exception '두 분에게 서로 다른 쿠폰을 보내야 해요'; end if;
  select * into v from public.ddeuchin_claims where id = p_id for update;
  if v.id is null then raise exception '찾을 수 없어요'; end if;
  if v.status <> 'ok' then raise exception '확인 완료된 건만 보낼 수 있어요'; end if;
  perform public.admin_talk_send(public._support_room(v.author_id), msg, p_photo_a, true);
  perform public.admin_talk_send(public._support_room(v.friend_id), msg, p_photo_b, true);
  update public.ddeuchin_claims set status = 'sent', sent_at = now() where id = p_id;
  perform public.admin_log('ddeuchin_send', 'ddeuchin', p_id::text, '{}'::jsonb);
  return true;
end $function$;

-- admin_decide_author(p_id uuid, p_approve boolean, p_reason text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_decide_author(p_id uuid, p_approve boolean, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a public.author_applications;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  select * into a from public.author_applications where id = p_id for update;
  if a.id is null then raise exception '신청을 찾을 수 없습니다'; end if;
  if a.status <> 'pending' then raise exception '이미 처리된 신청입니다'; end if;
  update public.author_applications set status = case when p_approve then 'approved' else 'rejected' end, reject_reason = case when p_approve then null else p_reason end, decided_by = auth.uid(), decided_at = now() where id = p_id;
  if p_approve then update public.profiles set is_author = true, author_since = now(), author_link = coalesce(author_link, a.link) where id = a.profile_id; end if;
  insert into public.notifications(recipient_id, actor_id, kind, snippet)
  values (a.profile_id, 'e120eb67-b254-4008-92d8-08c95c821e9e', 'notice',
    case when p_approve then '작가로 승인됐어요! 지도에 작가 핀으로 표시되고, 설정에서 내 링크를 프로필에 넣을 수 있어요' else '작가 신청이 반려됐어요'||coalesce(': '||nullif(p_reason,''),'') end);
  perform public.admin_log(case when p_approve then 'approve_author' else 'reject_author' end, 'profile', a.profile_id::text, jsonb_build_object('application', p_id, 'reason', p_reason));
end $function$;

-- admin_decide_event_app(p_app uuid, p_status text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_decide_event_app(p_app uuid, p_status text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a public.event_applications; e public.events;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  if p_status not in ('selected','rejected','applied') then raise exception 'bad status'; end if;
  select * into a from public.event_applications where id = p_app;
  if a.id is null or a.status in ('cancelled','done') then raise exception '바꿀 수 없는 신청이에요'; end if;
  select * into e from public.events where id = a.event_id;
  update public.event_applications set status = p_status, decided_at = now() where id = p_app;
  if p_status in ('selected','rejected') and a.status <> p_status then
    insert into public.notifications(recipient_id, actor_id, kind, event_id, snippet) values (a.profile_id, null, 'event_'||p_status, e.id, left(e.title,80));
  end if;
  perform public.admin_log('event_app_'||p_status, 'event', e.id::text, jsonb_build_object('app', p_app));
end $function$;

-- admin_decide_shop_claim(p_id uuid, p_approve boolean, p_reason text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_decide_shop_claim(p_id uuid, p_approve boolean, p_reason text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  return public._decide_shop_claim(p_id, p_approve, p_reason, auth.uid(), 'console');
end $function$;

-- admin_delete_meetup(p_meetup uuid, p_reason text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_delete_meetup(p_meetup uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  perform public.admin_log('delete_meetup', 'meetup', p_meetup::text, jsonb_build_object('reason', p_reason));
  update public.notifications set meetup_id = null where meetup_id = p_meetup;
  delete from public.posts where meetup_id = p_meetup or review_of = p_meetup;
  delete from public.meetups where id = p_meetup;
end $function$;

-- admin_delete_meetup(p_meetup uuid, p_reason text, p_notify boolean)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_delete_meetup(p_meetup uuid, p_reason text, p_notify boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_host uuid;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  select created_by into v_host from public.meetups where id = p_meetup;
  perform public.admin_log('delete_meetup', 'meetup', p_meetup::text, jsonb_build_object('reason', p_reason, 'notify', p_notify));
  if p_notify then perform public.mod_notify_delete(v_host, '모임', p_reason); end if;
  update public.notifications set meetup_id = null where meetup_id = p_meetup;
  delete from public.posts where meetup_id = p_meetup or review_of = p_meetup;
  delete from public.meetups where id = p_meetup;
end $function$;

-- admin_delete_post(p_post uuid, p_reason text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_delete_post(p_post uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  perform public.admin_log('delete_post', 'post', p_post::text, jsonb_build_object('reason', p_reason));
  delete from public.posts where id = p_post;
end $function$;

-- admin_delete_post(p_post uuid, p_reason text, p_notify boolean)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_delete_post(p_post uuid, p_reason text, p_notify boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_author uuid; v_parent uuid;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  select author_id, parent_id into v_author, v_parent from public.posts where id = p_post;
  perform public.admin_log('delete_post', 'post', p_post::text, jsonb_build_object('reason', p_reason, 'notify', p_notify));
  if p_notify then perform public.mod_notify_delete(v_author, case when v_parent is null then '글' else '댓글' end, p_reason); end if;
  delete from public.posts where id = p_post;
end $function$;

-- admin_delete_shop(p_shop uuid, p_reason text, p_notify boolean)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_delete_shop(p_shop uuid, p_reason text DEFAULT NULL::text, p_notify boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_owner uuid; v_name text;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  select owner_id, name into v_owner, v_name from public.shops where id = p_shop;
  if v_name is null then raise exception '가게를 찾을 수 없어요'; end if;
  perform public.admin_log('delete_shop', 'shop', p_shop::text, jsonb_build_object('reason', p_reason, 'notify', p_notify, 'name', v_name, 'owner', v_owner));
  if p_notify then perform public.mod_notify_delete(v_owner, '가게('||v_name||')', p_reason); end if;
  delete from public.shops where id = p_shop;
end $function$;

-- admin_delete_user(p_user uuid, p_reason text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_delete_user(p_user uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ids uuid[]; v_fr jsonb; v_vis boolean; v_wave timestamptz;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  if p_user = auth.uid() then raise exception '본인 계정은 앱의 계정 삭제로 지워 주세요'; end if;
  if exists (select 1 from public.admins where profile_id = p_user) then raise exception '관리자 계정은 지울 수 없어요(먼저 관리자에서 빼 주세요)'; end if;
  if not exists (select 1 from public.profiles where id = p_user) then raise exception '회원을 찾을 수 없어요'; end if;
  perform public.admin_log('delete_user', 'user', p_user::text, jsonb_build_object('reason', p_reason));
  if not exists (select 1 from public.account_deletions where user_id = p_user) then
    select coalesce(array_agg(id), '{}') into v_ids from public.posts where author_id = p_user and coalesce(hidden, false) = false;
    update public.posts set hidden = true where id = any(v_ids);
    select coalesce(jsonb_agg(to_jsonb(f)), '[]') into v_fr from public.friendships f where f.requester_id = p_user or f.addressee_id = p_user;
    delete from public.friendships where requester_id = p_user or addressee_id = p_user;
    select is_visible, wave_until into v_vis, v_wave from public.profiles where id = p_user;
    update public.profiles set deleted_at = now(), is_visible = false, wave_until = null where id = p_user;
    insert into public.account_deletions(user_id, purge_after, hidden_post_ids, friendships, was_visible, wave_until)
      values (p_user, now(), v_ids, v_fr, coalesce(v_vis, false), v_wave);
  else
    update public.account_deletions set purge_after = now() where user_id = p_user;
  end if;
  perform public.jigi_remind_call('purge');   -- 몇 초 안에 Edge Function 이 파일·계정을 지움(실패하면 매일 03:30 크론이 재시도)
end $function$;

-- admin_delete_work(p_work uuid, p_reason text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_delete_work(p_work uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  perform public.admin_log('delete_work', 'work', p_work::text, jsonb_build_object('reason', p_reason));
  update public.event_applications set work_id = null where work_id = p_work;
  delete from public.yarn_entries where work_id = p_work;
  delete from public.posts where work_id = p_work;
  delete from public.works where id = p_work;
end $function$;

-- admin_delete_work(p_work uuid, p_reason text, p_notify boolean)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_delete_work(p_work uuid, p_reason text, p_notify boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_owner uuid;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  select profile_id into v_owner from public.works where id = p_work;
  perform public.admin_log('delete_work', 'work', p_work::text, jsonb_build_object('reason', p_reason, 'notify', p_notify));
  if p_notify then perform public.mod_notify_delete(v_owner, '완성작품 인증', p_reason); end if;
  update public.event_applications set work_id = null where work_id = p_work;
  delete from public.yarn_entries where work_id = p_work;
  delete from public.posts where work_id = p_work;
  delete from public.works where id = p_work;
end $function$;

-- admin_dong_map()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_dong_map()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare out jsonb;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  select jsonb_build_object(
    'dongs', (select coalesce(jsonb_agg(jsonb_build_object('dong', dong_name, 'n', n, 'waving', w, 'lat', lat, 'lng', lng) order by n desc), '[]'::jsonb) from (
        select dong_name, count(*) n, count(*) filter (where wave_until > now()) w, avg(st_y(location::geometry)) lat, avg(st_x(location::geometry)) lng
        from profiles where location is not null and dong_name is not null and onboarded_at is not null group by dong_name) t),
    'meetups', (select coalesce(jsonb_agg(jsonb_build_object('title', title, 'place', place_name, 'starts_at', starts_at, 'n', participant_count, 'lat', st_y(location::geometry), 'lng', st_x(location::geometry))), '[]'::jsonb) from meetups where location is not null and starts_at > now()),
    'shops', (select coalesce(jsonb_agg(jsonb_build_object('name', name, 'kind', kind, 'lat', st_y(location::geometry), 'lng', st_x(location::geometry))), '[]'::jsonb) from shops where location is not null and is_active)
  ) into out;
  return out;
end $function$;

-- admin_event_apps(p_event uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_event_apps(p_event uuid)
 RETURNS TABLE(app_id uuid, profile_id uuid, nickname text, act_level integer, level_at integer, level_crochet smallint, level_knit smallint, note text, status text, created_at timestamp with time zone, work_id uuid, past_selected integer, past_done integer, ship_name text, ship_phone text, ship_zip text, ship_addr text, ship_memo text, shipped_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  delete from public.event_shipping s where s.shipped_at < now() - interval '30 days';
  perform public.log_access('event_shipping', p_event::text, (select count(*)::int from public.event_shipping s join public.event_applications a on a.id = s.application_id where a.event_id = p_event));
  return query
  select a.id, a.profile_id, pr.nickname, pr.act_level, a.level_at, pr.level_crochet, pr.level_knit, a.note, a.status, a.created_at, a.work_id,
    (select count(*)::int from public.event_applications x join public.events ex on ex.id = x.event_id where x.profile_id = a.profile_id and x.event_id <> a.event_id and x.status in ('selected','done') and ex.cert_due < current_date),
    (select count(*)::int from public.event_applications x where x.profile_id = a.profile_id and x.event_id <> a.event_id and x.status = 'done'),
    s.name, s.phone, s.zip, s.addr, s.memo, s.shipped_at
  from public.event_applications a join public.profiles pr on pr.id = a.profile_id left join public.event_shipping s on s.application_id = a.id
  where a.event_id = p_event order by a.created_at;
end $function$;

-- admin_event_lottery(p_event uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_event_lottery(p_event uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare e public.events; v_left integer; r record; n integer := 0;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  select * into e from public.events where id = p_event;
  if e.capacity is null then raise exception '모집 인원을 먼저 정해 주세요'; end if;
  v_left := e.capacity - public.event_selected_count(p_event);
  for r in select id from public.event_applications where event_id = p_event and status = 'applied' order by random() limit greatest(v_left,0) loop
    perform public.admin_decide_event_app(r.id, 'selected'); n := n + 1;
  end loop;
  return n;
end $function$;

-- admin_event_mark_shipped(p_app uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_event_mark_shipped(p_app uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  update public.event_shipping set shipped_at = now() where application_id = p_app;
  perform public.admin_log('event_shipped', 'event_app', p_app::text, null);
end $function$;

-- admin_feedback_decide(p_id bigint, p_accept boolean, p_note text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_feedback_decide(p_id bigint, p_accept boolean, p_note text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare f public.feedback_reports; pts integer := 0;
begin
  if not public.is_admin() and current_user <> 'service_role' then raise exception 'forbidden'; end if;
  select * into f from public.feedback_reports where id = p_id for update; if f.id is null then raise exception '제보가 없어요'; end if;
  if f.status <> 'open' then return 0; end if;
  update public.feedback_reports set status = case when p_accept then 'accepted' else 'rejected' end, admin_note = p_note, decided_at = now() where id = p_id;
  if p_accept then pts := public.award_points(f.user_id, 'bug_accepted', 'feedback_reports', f.id::text); end if;
  insert into public.notifications(recipient_id, actor_id, kind, snippet) values (f.user_id, 'e120eb67-b254-4008-92d8-08c95c821e9e', 'supporter', case when p_accept then '버그 제보가 채택됐어요. 고마워요! (+10점)' else '보내 주신 제보를 확인했어요. 이번엔 반영하지 못했지만 고마워요.' end);
  if auth.uid() is not null then perform public.admin_log(case when p_accept then 'feedback_accept' else 'feedback_reject' end, 'feedback', p_id::text, jsonb_build_object('note', p_note)); end if;
  return pts;
end $function$;

-- admin_find_users(p_q text, p_limit integer)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_find_users(p_q text, p_limit integer DEFAULT 50)
 RETURNS TABLE(id uuid, nickname text, email text, dong_name text, level_crochet smallint, level_knit smallint, created_at timestamp with time zone, onboarded_at timestamp with time zone, suspended_at timestamp with time zone, cert_count integer, wave_until timestamp with time zone, last_sign_in_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  perform public.log_access('find_users', p_q, null);
  return query
  select p.id, p.nickname::text, u.email::text, p.dong_name::text, p.level_crochet::smallint, p.level_knit::smallint, p.created_at, p.onboarded_at, p.suspended_at, p.cert_count::integer, p.wave_until, u.last_sign_in_at
  from public.profiles p join auth.users u on u.id = p.id
  where (p_q is null or p_q = '' or p.nickname ilike '%'||p_q||'%' or u.email ilike '%'||p_q||'%' or p.dong_name ilike '%'||p_q||'%')
  order by p.created_at desc limit p_limit;
end $function$;

-- admin_friend_stats()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_friend_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb; v_pairs int; v_req int; v_pending int; v_today date := (now() at time zone 'Asia/Seoul')::date;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  with real as (select * from public._friend_real()),
  f as (select fr.requester_id, fr.addressee_id, fr.status, fr.created_at, coalesce(fr.responded_at, fr.created_at) as at, a.region as ra, a.dong as da, b.region as rb, b.dong as db
        from public.friendships fr join real a on a.id = fr.requester_id join real b on b.id = fr.addressee_id),
  acc as (select * from f where status = 'accepted')
  select jsonb_build_object(
    'pairs', (select count(*) from acc),
    'week', (select count(*) from acc where at > now() - interval '7 days'),
    'members', (select count(distinct x) from (select requester_id x from acc union all select addressee_id from acc) t),
    'waving', (select count(*) from public.profiles p where p.id in (select id from real) and p.wave_until > now()),
    'requests', (select count(*) from f),
    'pending', (select count(*) from f where status = 'pending'),
    'chatted', (select count(*) from acc where exists (select 1 from public.rooms rm join public.room_members m1 on m1.room_id = rm.id and m1.profile_id = acc.requester_id
                 join public.room_members m2 on m2.room_id = rm.id and m2.profile_id = acc.addressee_id
                 where rm.kind = 'direct' and exists (select 1 from public.messages x where x.room_id = rm.id and x.sender_id = acc.requester_id)
                   and exists (select 1 from public.messages x where x.room_id = rm.id and x.sender_id = acc.addressee_id))),
    'same_meetup', (select count(*) from acc where exists (select 1 from public.meetups mt join public.room_members m1 on m1.room_id = mt.room_id and m1.profile_id = acc.requester_id
                 join public.room_members m2 on m2.room_id = mt.room_id and m2.profile_id = acc.addressee_id)),
    'same_dong', (select count(*) from acc where da is not null and da = db and ra is not distinct from rb),
    'daily', (select jsonb_agg(jsonb_build_object('d', to_char(d, 'MM-DD'), 'n', (select count(*) from acc where (acc.at at time zone 'Asia/Seoul')::date = d::date)) order by d)
              from generate_series(v_today - 13, v_today, interval '1 day') d),
    'regions', coalesce((select jsonb_agg(jsonb_build_object('name', name, 'n', n) order by n desc, name) from (select coalesce(ra, '동네 미설정') as name, count(*) n from acc group by 1) x), '[]'::jsonb)
  ) into r;
  v_pairs := (r->>'pairs')::int; v_req := (r->>'requests')::int;
  return r || jsonb_build_object('accept_pct', case when v_req > 0 then round(100.0 * v_pairs / v_req) else 0 end,
    'chat_pct', case when v_pairs > 0 then round(100.0 * (r->>'chatted')::int / v_pairs) else 0 end, 'next_goal', public._friend_next_goal(v_pairs));
end $function$;

-- admin_hide_post(p_post uuid, p_hidden boolean, p_reason text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_hide_post(p_post uuid, p_hidden boolean, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  update public.posts set hidden = p_hidden where id = p_post;
  update public.post_reports set reviewed_at = now() where post_id = p_post and reviewed_at is null;
  perform public.admin_log(case when p_hidden then 'hide_post' else 'unhide_post' end, 'post', p_post::text, jsonb_build_object('reason', p_reason));
end $function$;

-- admin_jigi_tool(p_name text, p_args jsonb)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_jigi_tool(p_name text, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  perform public.admin_log('jigi:'||p_name, 'mod', coalesce(p_args->>'item_id', p_args->>'post_id', p_args->>'user_id', ''), p_args);
  return public.jigi_tool(p_name, p_args, 'admin', true);
end $function$;

-- admin_kb(p jsonb)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_kb(p jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id bigint := nullif(p->>'id','')::bigint;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  if coalesce((p->>'delete')::boolean,false) then delete from public.support_kb where id = v_id; perform public.admin_log('kb_delete','kb',v_id::text,null); return v_id; end if;
  if v_id is null then
    insert into public.support_kb(kind, category, q, a, enabled) values (p->>'kind', left(coalesce(nullif(p->>'category',''),'기타'),30), left(btrim(p->>'q'),300), left(btrim(p->>'a'),2000), coalesce((p->>'enabled')::boolean,true)) returning id into v_id;
  else
    update public.support_kb set kind = coalesce(p->>'kind',kind), category = left(coalesce(nullif(p->>'category',''),category),30), q = left(btrim(coalesce(p->>'q',q)),300), a = left(btrim(coalesce(p->>'a',a)),2000), enabled = coalesce((p->>'enabled')::boolean,enabled), updated_at = now() where id = v_id;
  end if;
  perform public.admin_log('kb_upsert','kb',v_id::text, jsonb_build_object('kind',p->>'kind','q',left(coalesce(p->>'q',''),100)));
  return v_id;
end $function$;

-- admin_kb_candidate(p_id bigint, p_approve boolean, p_q text, p_a text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_kb_candidate(p_id bigint, p_approve boolean, p_q text DEFAULT NULL::text, p_a text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c public.support_kb_candidates; v_id bigint;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  select * into c from public.support_kb_candidates where id = p_id and status='open'; if c.id is null then raise exception '후보가 없어요'; end if;
  if p_approve then insert into public.support_kb(kind, category, q, a) values (c.kind, c.category, left(coalesce(nullif(btrim(p_q),''), c.q),300), left(coalesce(nullif(btrim(p_a),''), c.a),2000)) returning id into v_id; end if;
  update public.support_kb_candidates set status = case when p_approve then 'approved' else 'rejected' end, decided_at = now() where id = p_id;
  perform public.admin_log(case when p_approve then 'kb_candidate_approve' else 'kb_candidate_reject' end, 'kb', p_id::text, null);
  return v_id;
end $function$;

-- admin_log(p_action text, p_type text, p_target text, p_detail jsonb)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_log(p_action text, p_type text, p_target text, p_detail jsonb DEFAULT NULL::jsonb)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  insert into public.admin_logs(admin_id, action, target_type, target_id, detail) values (auth.uid(), p_action, p_type, p_target, p_detail);
$function$;

-- admin_meetup_edit(p_meetup uuid, p_action text, p jsonb, p_notify boolean)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_meetup_edit(p_meetup uuid, p_action text, p jsonb DEFAULT '{}'::jsonb, p_notify boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m public.meetups; v_txt text; v_ts timestamptz; v_msg text; n int := 0; v_hide boolean;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  select * into m from public.meetups where id = p_meetup; if not found then raise exception '모임을 찾을 수 없어요'; end if;
  if p_action = 'title' then
    v_txt := left(trim(coalesce(p->>'title','')), 60); if v_txt = '' then raise exception '제목을 입력하세요'; end if;
    update public.meetups set title = v_txt where id = p_meetup; v_msg := '운영진이 모임 제목을 「'||v_txt||'」(으)로 고쳤어요';
  elsif p_action = 'starts' then
    v_ts := (p->>'starts_at')::timestamptz; if v_ts is null then raise exception '일시를 입력하세요'; end if;
    update public.meetups set starts_at = v_ts where id = p_meetup;
    v_msg := '「'||m.title||'」 모임 일시가 '||to_char(v_ts at time zone 'Asia/Seoul', 'FMMM"월" FMDD"일" HH24:MI')||'(으)로 바뀌었어요';
  elsif p_action = 'place' then
    v_txt := left(trim(coalesce(p->>'place','')), 80); if v_txt = '' then raise exception '장소를 입력하세요'; end if;
    update public.meetups set place_name = v_txt where id = p_meetup; v_msg := '「'||m.title||'」 모임 장소가 '||v_txt||'(으)로 바뀌었어요';
  elsif p_action = 'hidden' then
    v_hide := coalesce((p->>'hidden')::boolean, true);
    update public.meetups set hidden = v_hide where id = p_meetup;
    update public.posts set hidden = v_hide where meetup_id = p_meetup;
    v_msg := case when v_hide then '「'||m.title||'」 모임을 운영진이 잠시 숨겼어요. 궁금한 점은 설정 › 지기에게 말하기로 알려 주세요' else '「'||m.title||'」 모임이 다시 보여요' end;
  else raise exception '알 수 없는 작업이에요'; end if;
  if p_notify and v_msg is not null then
    if p_action = 'hidden' then
      insert into public.notifications(recipient_id, actor_id, kind, snippet) select m.created_by, auth.uid(), 'notice', left(v_msg,200) where m.created_by is not null and m.created_by <> auth.uid();
    else
      insert into public.notifications(recipient_id, actor_id, kind, snippet, meetup_id)
        select rm.profile_id, auth.uid(), 'notice', left(v_msg,200), p_meetup from public.room_members rm where rm.room_id = m.room_id and rm.profile_id <> auth.uid();
    end if;
    get diagnostics n = row_count;
  end if;
  perform public.admin_log('meetup_edit', 'meetup', p_meetup::text, jsonb_build_object('action', p_action, 'p', p, 'notified', n));
  return jsonb_build_object('ok', true, 'notified', n);
end $function$;

-- admin_meetup_stats()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_meetup_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  select jsonb_build_object(
    'upcoming', count(*) filter (where f_upcoming),
    'week', count(*) filter (where starts_at >= date_trunc('day', now()) and starts_at < now() + interval '7 days'),
    'avg_join', coalesce(round(avg(joined) filter (where starts_at > now() - interval '90 days'), 1), 0),
    'review_pct', coalesce(round(100.0 * count(*) filter (where starts_at < now() and reviews > 0) / nullif(count(*) filter (where starts_at < now()), 0)), 0),
    'counts', jsonb_build_object('all', count(*), 'upcoming', count(*) filter (where f_upcoming), 'empty', count(*) filter (where f_empty),
       'noreview', count(*) filter (where f_noreview), 'flag', count(*) filter (where f_flag)),
    'regions', coalesce((select jsonb_agg(jsonb_build_object('name', x.region, 'n', x.n) order by x.n desc) from (select region, count(*) n from public._admin_meetup_base() where region is not null group by 1) x), '[]'::jsonb)
  ) into r from public._admin_meetup_base();
  return r;
end $function$;

-- admin_meetups(p jsonb)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_meetups(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_page int := greatest(coalesce((p->>'page')::int, 1), 1); v_size int := 50; v_total int; v_rows jsonb;
  v_sort text := coalesce(p->>'sort','starts'); v_desc boolean := coalesce(p->>'dir','desc') <> 'asc';
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  select count(*) into v_total from public._admin_meetup_filter(p);
  select coalesce(jsonb_agg(to_jsonb(x) - 'rn' order by x.rn), '[]'::jsonb) into v_rows from (
    select b.id, b.title, b.kind, b.place_name, b.starts_at, b.capacity, b.is_public, b.hidden, b.host, b.dong, b.joined, b.reviews,
      b.f_upcoming, b.f_empty, b.f_noreview, b.f_flag,
      row_number() over (order by
        case when v_sort = 'title' and not v_desc then b.title end asc nulls last, case when v_sort = 'title' and v_desc then b.title end desc nulls last,
        case when v_sort = 'dong' and not v_desc then b.dong end asc nulls last, case when v_sort = 'dong' and v_desc then b.dong end desc nulls last,
        case when v_sort = 'joined' and not v_desc then b.joined end asc, case when v_sort = 'joined' and v_desc then b.joined end desc,
        case when v_sort = 'starts' and not v_desc then b.starts_at end asc, case when v_sort = 'starts' and v_desc then b.starts_at end desc,
        b.starts_at desc, b.id) as rn
    from public._admin_meetup_base() b where b.id in (select public._admin_meetup_filter(p))
  ) x where x.rn > (v_page - 1) * v_size and x.rn <= v_page * v_size;
  return jsonb_build_object('total', v_total, 'page', v_page, 'size', v_size, 'rows', v_rows);
end $function$;

-- admin_meetups_notify(p jsonb, p_body text, p_meetup uuid, p_dry boolean)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_meetups_notify(p jsonb, p_body text, p_meetup uuid DEFAULT NULL::uuid, p_dry boolean DEFAULT false)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n integer; v_body text := left(trim(coalesce(p_body,'')), 200);
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  create temp table if not exists _mt_tg(id uuid primary key, mid uuid) on commit drop; truncate _mt_tg;
  if p_meetup is not null then
    insert into _mt_tg select rm.profile_id, p_meetup from public.meetups m join public.room_members rm on rm.room_id = m.room_id where m.id = p_meetup on conflict do nothing;
  else
    insert into _mt_tg select distinct on (b.created_by) b.created_by, b.id from public._admin_meetup_base() b
      where b.id in (select public._admin_meetup_filter(p)) and b.created_by is not null order by b.created_by, b.starts_at desc on conflict do nothing;
  end if;
  delete from _mt_tg t using public.profiles pr where pr.id = t.id and (pr.suspended_at is not null or pr.deleted_at is not null);
  delete from _mt_tg where id = auth.uid();
  select count(*) into n from _mt_tg;
  if p_dry then return least(n, 2000); end if;
  if v_body = '' then raise exception '보낼 내용을 적어 주세요'; end if;
  insert into public.notifications(recipient_id, actor_id, kind, snippet, meetup_id) select id, auth.uid(), 'notice', v_body, mid from _mt_tg limit 2000;
  get diagnostics n = row_count;
  perform public.admin_log('meetups_notify', case when p_meetup is null then 'filter' else 'meetup' end, coalesce(p_meetup::text, coalesce(p->>'seg','all')), jsonb_build_object('filter', p - 'page' - 'sort' - 'dir', 'body', v_body, 'count', n));
  return n;
end $function$;

-- admin_member_edit(p_user uuid, p_action text, p jsonb, p_notify boolean)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_member_edit(p_user uuid, p_action text, p jsonb DEFAULT '{}'::jsonb, p_notify boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v_old public.profiles%rowtype; v_msg text; v_detail jsonb; v_lat double precision; v_lng double precision; v_name text; v_code text; v_nick text;
  cell constant double precision := 0.0018;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  select * into v_old from public.profiles where id = p_user; if not found then raise exception '회원을 찾을 수 없어요'; end if;
  if p_action = 'dong' then
    v_name := left(trim(coalesce(p->>'dong_name','')), 30); v_code := left(trim(coalesce(p->>'dong_code','')), 80);
    v_lat := (p->>'lat')::double precision; v_lng := (p->>'lng')::double precision;
    if v_name = '' or v_code = '' or v_lat is null or v_lng is null or v_lat not between 32 and 40 or v_lng not between 123 and 133 then raise exception '동네를 목록에서 골라 주세요'; end if;
    update public.profiles set dong_name = v_name, dong_code = v_code, dong_verified_at = null,
      location = st_setsrid(st_makepoint(floor(v_lng / cell) * cell + cell / 2, floor(v_lat / cell) * cell + cell / 2), 4326)::geography where id = p_user;
    v_detail := jsonb_build_object('from', v_old.dong_name, 'to', v_name);
    v_msg := '운영진이 동네를 「' || v_name || '」(으)로 고쳐 드렸어요. 지도 핀도 그 동네로 옮겨졌어요. 바꾸고 싶으면 프로필 편집에서 언제든 다시 정할 수 있어요.';
  elsif p_action = 'visible' then
    update public.profiles set is_visible = coalesce((p->>'on')::boolean, false) where id = p_user;
    v_detail := jsonb_build_object('from', v_old.is_visible, 'to', coalesce((p->>'on')::boolean, false));
    v_msg := case when coalesce((p->>'on')::boolean, false) then '운영진이 지도에 내 핀이 보이도록 켜 드렸어요. 프로필 편집에서 언제든 끌 수 있어요.' else '운영진이 지도에서 내 핀을 잠시 숨겼어요. 궁금한 점은 마이 › 설정 › 지기에게 말하기로 알려 주세요.' end;
  elsif p_action = 'clear_nick' then
    v_nick := '뜨개이웃' || (1000 + floor(random() * 9000))::int;
    update public.profiles set nickname = v_nick where id = p_user;
    v_detail := jsonb_build_object('from', v_old.nickname, 'to', v_nick);
    v_msg := '닉네임이 커뮤니티 가이드라인에 맞지 않아 「' || v_nick || '」(으)로 바뀌었어요. 프로필 편집에서 새 닉네임으로 바꿔 주세요.';
  elsif p_action = 'clear_bio' then
    update public.profiles set bio = null where id = p_user;
    v_detail := jsonb_build_object('from', left(coalesce(v_old.bio,''), 200));
    v_msg := '소개 글이 커뮤니티 가이드라인에 맞지 않아 지워졌어요. 프로필 편집에서 다시 적어 주세요.';
  else raise exception '알 수 없는 조치';
  end if;
  if p_notify then insert into public.notifications(recipient_id, actor_id, kind, snippet) values (p_user, auth.uid(), 'notice', left(v_msg, 200)); end if;
  perform public.admin_log('member_edit', 'profile', p_user::text, v_detail || jsonb_build_object('action', p_action, 'notified', p_notify));
  return jsonb_build_object('ok', true, 'detail', v_detail);
end $function$;

-- admin_member_note_save(p_user uuid, p_memo text, p_tags text[])  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_member_note_save(p_user uuid, p_memo text, p_tags text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_tags text[];
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  if not exists (select 1 from public.profiles where id = p_user) then raise exception '회원을 찾을 수 없어요'; end if;
  select coalesce(array_agg(t order by t), '{}') into v_tags from (select distinct left(trim(x), 12) t from unnest(coalesce(p_tags,'{}')) x where trim(x) <> '' limit 8) s;
  insert into public.member_notes(profile_id, memo, tags, updated_at, updated_by) values (p_user, nullif(left(trim(coalesce(p_memo,'')), 1000), ''), v_tags, now(), auth.uid())
    on conflict (profile_id) do update set memo = excluded.memo, tags = excluded.tags, updated_at = now(), updated_by = auth.uid();
  perform public.admin_log('member_note', 'profile', p_user::text, jsonb_build_object('tags', v_tags));
  return jsonb_build_object('ok', true, 'tags', to_jsonb(v_tags));
end $function$;

-- admin_member_stats()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_member_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  select jsonb_build_object(
    'today', count(*) filter (where b.created_at >= date_trunc('day', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul'),
    'total', count(*),
    'onboard_pct', case when count(*) > 0 then round(100.0 * count(*) filter (where b.onboarded_at is not null) / count(*)) else 0 end,
    'map_pct', case when count(*) filter (where b.onboarded_at is not null) > 0 then round(100.0 * count(*) filter (where b.onboarded_at is not null and b.has_loc and b.is_visible) / count(*) filter (where b.onboarded_at is not null)) else 0 end,
    'counts', jsonb_build_object('all', count(*), 'incomplete', count(*) filter (where b.f_incomplete), 'dong', count(*) filter (where b.f_dong),
      'inactive', count(*) filter (where b.f_inactive), 'flag', count(*) filter (where b.f_flag))
  ) into r from public._admin_member_base() b;
  return r || jsonb_build_object('regions', coalesce((select jsonb_agg(jsonb_build_object('name', z.name, 'n', z.n) order by z.n desc, z.name)
    from (select split_part(b.dong_code,'|',1) as name, count(*) as n from public._admin_member_base() b where position('|' in coalesce(b.dong_code,'')) > 0 group by 1) z), '[]'::jsonb));
end $function$;

-- admin_members(p jsonb)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_members(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_page int := greatest(coalesce((p->>'page')::int, 1), 1); v_size int := 50; v_total int; v_rows jsonb;
  v_sort text := coalesce(p->>'sort','created'); v_desc boolean := coalesce(p->>'dir','desc') <> 'asc';
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  select count(*) into v_total from public._admin_member_filter(p);
  select coalesce(jsonb_agg(to_jsonb(x) - 'rn' order by x.rn), '[]'::jsonb) into v_rows from (
    select b.id, b.nickname, b.email, b.dong_name, b.created_at, b.seen, b.onboarded_at, b.suspended_at, b.deleted_at, b.level_crochet, b.level_knit, b.cert_count,
      b.f_incomplete, b.f_dong, b.f_flag,
      row_number() over (order by
        case when v_sort = 'nick' and not v_desc then b.nickname end asc nulls last, case when v_sort = 'nick' and v_desc then b.nickname end desc nulls last,
        case when v_sort = 'dong' and not v_desc then b.dong_name end asc nulls last, case when v_sort = 'dong' and v_desc then b.dong_name end desc nulls last,
        case when v_sort = 'seen' and not v_desc then b.seen end asc nulls last, case when v_sort = 'seen' and v_desc then b.seen end desc nulls last,
        case when v_sort = 'created' and not v_desc then b.created_at end asc, case when v_sort = 'created' and v_desc then b.created_at end desc,
        b.created_at desc, b.id) as rn
    from public._admin_member_base() b where b.id in (select public._admin_member_filter(p))
  ) x where x.rn > (v_page - 1) * v_size and x.rn <= v_page * v_size;
  perform public.log_access('members', left(coalesce(p->>'seg','all') || ' ' || coalesce(p->>'q',''), 80), jsonb_array_length(v_rows));   -- 이메일이 포함된 목록
  return jsonb_build_object('total', v_total, 'page', v_page, 'size', v_size, 'rows', v_rows);
end $function$;

-- admin_members_notify(p jsonb, p_body text, p_dry boolean)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_members_notify(p jsonb, p_body text, p_dry boolean DEFAULT false)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n integer; v_body text := left(trim(coalesce(p_body,'')), 200);
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  if p_dry then
    select count(*) into n from public._admin_member_base() b where b.id in (select public._admin_member_filter(p)) and b.suspended_at is null and b.deleted_at is null and b.id <> auth.uid();
    return least(n, 5000);
  end if;
  if v_body = '' then raise exception '보낼 내용을 적어 주세요'; end if;
  insert into public.notifications(recipient_id, actor_id, kind, snippet)
    select b.id, auth.uid(), 'notice', v_body from public._admin_member_base() b
    where b.id in (select public._admin_member_filter(p)) and b.suspended_at is null and b.deleted_at is null and b.id <> auth.uid()
    order by b.created_at desc limit 5000;
  get diagnostics n = row_count;
  perform public.admin_log('members_notify', 'filter', coalesce(p->>'seg','all'), jsonb_build_object('filter', p - 'page' - 'sort' - 'dir', 'body', v_body, 'count', n));
  return n;
end $function$;

-- admin_news_list()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_news_list()
 RETURNS SETOF news_posts
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  return query select * from public.news_posts order by published_at desc limit 200;
end $function$;

-- admin_news_save(p jsonb)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_news_save(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid := nullif(p->>'id','')::uuid; v_kind text := coalesce(nullif(p->>'kind',''),'notice');
  v_title text := left(trim(coalesce(p->>'title','')),60); v_body text := left(trim(coalesce(p->>'body','')),1000);
  v_ver text := nullif(left(trim(coalesce(p->>'version','')),12),''); v_img text := nullif(trim(coalesce(p->>'image_url','')),'');
  v_active boolean := coalesce((p->>'active')::boolean, true); v_pub timestamptz := coalesce(nullif(p->>'published_at','')::timestamptz, now());
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  if v_kind not in ('notice','update') then raise exception '종류가 올바르지 않아요'; end if;
  if v_title = '' or v_body = '' then raise exception '제목과 내용을 입력하세요'; end if;
  if v_img is not null and v_img !~ '^https://app\.knitup\.co\.kr/images/[A-Za-z0-9._-]+\.(jpg|jpeg|png|webp)$' then raise exception '이미지는 app.knitup.co.kr/images/ 의 파일 주소만 쓸 수 있어요'; end if;
  if v_kind <> 'update' then v_ver := null; end if;
  if v_id is null then
    insert into public.news_posts(kind, version, title, body, image_url, active, published_at, created_by)
      values (v_kind, v_ver, v_title, v_body, v_img, v_active, v_pub, auth.uid()) returning id into v_id;
  else
    update public.news_posts set kind=v_kind, version=v_ver, title=v_title, body=v_body, image_url=v_img, active=v_active,
      published_at = case when p ? 'published_at' and nullif(p->>'published_at','') is not null then v_pub else published_at end
      where id = v_id;
    if not found then raise exception '글을 찾을 수 없어요'; end if;
  end if;
  perform public.admin_log('news_save', 'news_posts', v_id::text, jsonb_build_object('kind',v_kind,'title',v_title,'active',v_active));
  return v_id;
end $function$;

-- admin_order_set(p_id uuid, p_status text, p_tracking text, p_note text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_order_set(p_id uuid, p_status text, p_tracking text DEFAULT NULL::text, p_note text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o record; x jsonb; msg text;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  select * into o from public.orders where id = p_id; if o.id is null then raise exception 'no order'; end if;
  if p_status not in ('pending_payment','paid','shipped','done','cancelled') then raise exception 'bad status'; end if;
  if p_status = 'cancelled' and o.status <> 'cancelled' then for x in select * from jsonb_array_elements(o.items) loop update public.shop_products set stock = stock + (x->>'qty')::int where id = (x->>'product_id')::uuid; end loop; end if;
  update public.orders set status = p_status, paid_at = case when p_status = 'paid' then coalesce(paid_at, now()) else paid_at end, shipped_at = case when p_status = 'shipped' then coalesce(shipped_at, now()) else shipped_at end,
    tracking = coalesce(p_tracking, tracking), note = coalesce(p_note, note), updated_at = now() where id = p_id;
  msg := case p_status when 'paid' then '입금이 확인됐어요. 곧 발송할게요' when 'shipped' then '주문하신 실을 발송했어요' || case when coalesce(p_tracking, o.tracking) is not null then ' · 송장 ' || coalesce(p_tracking, o.tracking) else '' end when 'done' then '주문이 완료됐어요. 즐거운 뜨개 되세요' when 'cancelled' then '주문이 취소됐어요' else null end;
  if msg is not null then insert into public.notifications(recipient_id, actor_id, kind, snippet, link) values (o.profile_id, o.profile_id, 'notice', '주문 ' || o.no || ' · ' || msg, jsonb_build_object('type','view','view','orders')); end if;
  perform public.admin_log('order_' || p_status, 'order', p_id::text, jsonb_build_object('no', o.no, 'tracking', p_tracking));
end $function$;

-- admin_orders(p_status text, p_limit integer)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_orders(p_status text DEFAULT NULL::text, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare out jsonb;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  perform public.log_access('orders', coalesce(p_status, 'all'), p_limit);
  select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'no', o.no, 'status', o.status, 'items', o.items, 'subtotal', o.subtotal, 'shipping_fee', o.shipping_fee, 'total', o.total,
      'ship_name', o.ship_name, 'ship_phone', o.ship_phone, 'ship_addr', o.ship_addr, 'ship_memo', o.ship_memo, 'depositor', o.depositor, 'paid_at', o.paid_at, 'shipped_at', o.shipped_at, 'tracking', o.tracking, 'note', o.note,
      'created_at', o.created_at, 'nickname', pr.nickname) order by o.created_at desc), '[]'::jsonb) into out
    from (select * from public.orders where p_status is null or status = p_status order by created_at desc limit p_limit) o left join public.profiles pr on pr.id = o.profile_id;
  return out;
end $function$;

-- admin_partner_invite(p_kind text, p_name text, p_memo text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_partner_invite(p_kind text, p_name text, p_memo text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare i uuid; nm text := btrim(regexp_replace(coalesce(p_name,''), '[<>#]', '', 'g'));
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  if p_kind not in ('author','shop') then raise exception '종류를 골라 주세요'; end if;
  if char_length(nm) < 1 or char_length(nm) > 40 then raise exception '이름을 1~40자로 적어 주세요'; end if;
  insert into public.partner_invites(kind, name, memo, created_by) values (p_kind, nm, nullif(btrim(coalesce(p_memo,'')), ''), auth.uid()) returning id into i;
  perform public.admin_log('partner_invite', 'partner_invite', i::text, jsonb_build_object('kind', p_kind, 'name', nm));
  return i;
end $function$;

-- admin_partner_invite_set(p_id uuid, p_op text, p_val text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_partner_invite_set(p_id uuid, p_op text, p_val text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v public.partner_invites; pid uuid; k int; key text;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  select * into v from public.partner_invites where id = p_id for update;
  if v.id is null then raise exception '초대 기록을 찾을 수 없습니다'; end if;
  if p_op = 'sent' then update public.partner_invites set sent_at = coalesce(sent_at, now()) where id = p_id;
  elsif p_op = 'unsent' then update public.partner_invites set sent_at = null where id = p_id;
  elsif p_op = 'link' then
    key := lower(regexp_replace(coalesce(p_val,''), '\s+', '', 'g'));
    if key = '' then raise exception '닉네임을 적어 주세요'; end if;
    select count(*), (array_agg(id))[1] into k, pid from public.profiles
      where deleted_at is null and lower(regexp_replace(coalesce(nickname,''), '\s+', '', 'g')) = key;
    if k = 0 then raise exception '그 닉네임의 회원을 찾지 못했어요'; end if;
    if k > 1 then raise exception '같은 닉네임의 회원이 %명이에요. 회원 화면에서 확인해 주세요', k; end if;
    update public.partner_invites set profile_id = pid where id = p_id;
  elsif p_op = 'unlink' then update public.partner_invites set profile_id = null where id = p_id;
  elsif p_op = 'memo' then update public.partner_invites set memo = nullif(left(btrim(coalesce(p_val,'')), 300), '') where id = p_id;
  elsif p_op = 'delete' then delete from public.partner_invites where id = p_id;
  else raise exception '알 수 없는 동작입니다'; end if;
  perform public.admin_log('partner_invite_'||p_op, 'partner_invite', p_id::text, jsonb_build_object('name', v.name, 'profile', pid));
  return jsonb_build_object('ok', true, 'profile_id', pid);
end $function$;

-- admin_partner_list()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_partner_list()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  with base as (
    select i.id, i.kind, i.name, i.memo, i.sent_at, i.created_at, i.profile_id from public.partner_invites i
    union all
    select null, g.kind, null, null, null, coalesce(g.sent_at, g.created_at), g.profile_id from public.partner_guides g
      where not exists (select 1 from public.partner_invites i where i.profile_id = g.profile_id and i.kind = g.kind)
  )
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb) into r from (
    select b.id, b.kind, b.name, b.memo, b.sent_at, b.created_at, b.profile_id,
      p.nickname, p.created_at as joined_at, coalesce(p.is_author, false) as is_author, p.author_since,
      (p.cover_url is not null) as a_cover,
      coalesce(jsonb_array_length(case when jsonb_typeof(p.author_links) = 'array' then p.author_links else '[]'::jsonb end), 0) as a_links,
      s.id as shop_id, s.name as shop_name, coalesce(s.is_active, false) as shop_active, s.created_at as shop_at,
      (s.cover_url is not null) as s_cover, (s.logo_url is not null) as s_logo,
      (select count(*) from jsonb_each(case when jsonb_typeof(s.links) = 'object' then s.links else '{}'::jsonb end) e where coalesce(e.value #>> '{}', '') <> '') as s_links,
      (select c.status from public.shop_claims c where c.profile_id = b.profile_id order by c.created_at desc limit 1) as claim_status,
      g.sent_at as guide_at, coalesce(g.seeded, false) as seeded, g.nudged_at, coalesce(g.nudge_sent, false) as nudge_sent,
      (g.msg_id is not null and exists (select 1 from public.messages m join public.room_members rm on rm.room_id = m.room_id and rm.profile_id = b.profile_id where m.id = g.msg_id and rm.last_read_at >= m.created_at)) as guide_read
    from base b
      left join public.profiles p on p.id = b.profile_id
      left join lateral (select * from public.shops s where s.owner_id = b.profile_id order by s.created_at limit 1) s on b.kind = 'shop'
      left join public.partner_guides g on g.profile_id = b.profile_id and g.kind = b.kind
  ) x;
  return r;
end $function$;

-- admin_pattern_sales(p_month text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_pattern_sales(p_month text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  return coalesce((select jsonb_agg(r order by (r->>'author_amt')::int desc) from (
    select jsonb_build_object('author_id', p.author_id, 'author', pr.nickname, 'n', count(*), 'gross', sum(pp.price), 'store_fee', sum(pp.store_fee), 'platform_fee', sum(pp.platform_fee), 'tax', sum(pp.tax), 'author_amt', sum(pp.author_amt)) r
    from public.pattern_purchases pp join public.patterns p on p.id = pp.pattern_id left join public.profiles pr on pr.id = p.author_id
    where p_month is null or to_char(pp.created_at at time zone 'Asia/Seoul', 'YYYY-MM') = p_month group by p.author_id, pr.nickname) q), '[]'::jsonb);
end $function$;

-- admin_product_delete(p_id uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_product_delete(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  delete from public.shop_products where id = p_id;
  perform public.admin_log('product_delete', 'product', p_id::text, null);
end $function$;

-- admin_product_upsert(p jsonb)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_product_upsert(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pid uuid := nullif(p->>'id','')::uuid; cols jsonb;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  cols := coalesce(p->'colors', '[]'::jsonb);
  if (p->>'fill_colors')::boolean is true and nullif(p->>'catalog_id','') is not null then
    select coalesce(jsonb_agg(jsonb_build_object('no', y.no, 'name', y.name, 'photo', y.photo, 'hex', y.color_hex[1]) order by y.photo is null, y.no), '[]'::jsonb) into cols
      from (select * from public.yarn_colors where catalog_id = (p->>'catalog_id')::uuid order by (photo is null), no limit 12) y;
  end if;
  if pid is null then
    insert into public.shop_products(catalog_id, name, brand, descr, price, stock, ball_g, ball_m, photo, colors, is_active, sort)
      values (nullif(p->>'catalog_id','')::uuid, left(p->>'name', 80), left(p->>'brand', 40), left(p->>'descr', 1000), greatest(0, (p->>'price')::int), greatest(0, coalesce((p->>'stock')::int, 0)), (p->>'ball_g')::numeric, (p->>'ball_m')::numeric, p->>'photo', cols, coalesce((p->>'is_active')::boolean, true), coalesce((p->>'sort')::int, 0))
      returning id into pid;
  else
    update public.shop_products set catalog_id = nullif(p->>'catalog_id','')::uuid, name = left(p->>'name', 80), brand = left(p->>'brand', 40), descr = left(p->>'descr', 1000), price = greatest(0, (p->>'price')::int), stock = greatest(0, coalesce((p->>'stock')::int, 0)),
      ball_g = (p->>'ball_g')::numeric, ball_m = (p->>'ball_m')::numeric, photo = p->>'photo', colors = case when (p->>'fill_colors')::boolean is true then cols else colors end, is_active = coalesce((p->>'is_active')::boolean, true), sort = coalesce((p->>'sort')::int, 0), updated_at = now() where id = pid;
  end if;
  perform public.admin_log('product_upsert', 'product', pid::text, jsonb_build_object('name', p->>'name', 'price', p->>'price'));
  return pid;
end $function$;

-- admin_reply_support(p_room uuid, p_body text, p_photo text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_reply_support(p_room uuid, p_body text DEFAULT NULL::text, p_photo text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare mid bigint; sup uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e';
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  if not exists (select 1 from public.room_members where room_id = p_room and profile_id = sup) then raise exception '지기 채팅방이 아니에요'; end if;
  if btrim(coalesce(p_body,'')) = '' and p_photo is null then raise exception '내용이나 사진을 넣어 주세요'; end if;
  insert into public.messages(room_id, sender_id, body, photo_url) values (p_room, sup, nullif(left(btrim(coalesce(p_body,'')), 1000), ''), p_photo) returning id into mid;
  update public.room_members set last_read_at = now() where room_id = p_room and profile_id = sup;
  perform public.admin_log('reply_support', 'room', p_room::text, jsonb_build_object('message_id', mid, 'body', left(coalesce(p_body,''), 200), 'photo', p_photo is not null));
  if mid is not null then perform public.chat_push(mid); end if;
  return mid;
end $function$;

-- admin_report_case_decide(p_case bigint, p_ok boolean)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_report_case_decide(p_case bigint, p_ok boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  perform public._report_case_close(p_case, p_ok, 'admin', 'decided');
  perform public.admin_log(case when p_ok then 'report_case_ok' else 'report_case_hide' end, 'report_case', p_case::text, '{}'::jsonb);
end $function$;

-- admin_resolve_report(p_kind text, p_id text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_resolve_report(p_kind text, p_id text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  if p_kind = 'post' then update public.post_reports set reviewed_at = now() where post_id = p_id::uuid and reviewed_at is null;
  else update public.reports set reviewed_at = now() where id = p_id::bigint; end if;
  perform public.admin_log('resolve_report', p_kind, p_id, null);
end $function$;

-- admin_set_admin(p_user uuid, p_add boolean)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_set_admin(p_user uuid, p_add boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  if p_add then insert into public.admins(profile_id, added_by) values (p_user, auth.uid()) on conflict do nothing;
  else
    if p_user = auth.uid() then raise exception '자기 자신은 해제할 수 없어요'; end if;
    delete from public.admins where profile_id = p_user;
  end if;
  perform public.admin_log(case when p_add then 'add_admin' else 'remove_admin' end, 'user', p_user::text, null);
end $function$;

-- admin_set_author(p_profile uuid, p_on boolean)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_set_author(p_profile uuid, p_on boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  update public.profiles set is_author = p_on, author_since = case when p_on then coalesce(author_since, now()) else author_since end where id = p_profile;
  perform public.admin_log(case when p_on then 'set_author' else 'unset_author' end, 'profile', p_profile::text, '{}'::jsonb);
end $function$;

-- admin_set_home_notice(p jsonb)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_set_home_notice(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_old jsonb; v_new jsonb; v_title text := left(coalesce(trim(p->>'title'),''), 60); v_body text := left(coalesce(trim(p->>'body'),''), 400); v_id text;
  v_btn text := left(coalesce(trim(p->>'btn'),''), 20); v_link jsonb := p->'link'; v_ok boolean := false;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  -- 버튼이 여는 곳은 정해진 종류만(앱 openLink 와 같은 목록). 임의 URL 은 받지 않는다
  if v_btn <> '' then
    if v_link is not null and jsonb_typeof(v_link) = 'object' then
      if v_link->>'type' = 'view' and (v_link->>'view') in ('map','comm','chats','my','skills','stash','cert','support') then
        v_link := jsonb_build_object('type','view','view', v_link->>'view'); v_ok := true;
      elsif v_link->>'type' = 'post' and (v_link->>'id') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        and exists(select 1 from public.posts where id = (v_link->>'id')::uuid and parent_id is null and not coalesce(hidden,false)) then
        v_link := jsonb_build_object('type','post','id', v_link->>'id'); v_ok := true;
      end if;
    end if;
    if not v_ok then raise exception '버튼을 누르면 이동할 곳을 골라 주세요'; end if;
  else
    v_link := null;
  end if;
  select value into v_old from public.app_config where key = 'home_notice';
  v_id := case when v_old is not null and coalesce(v_old->>'title','') = v_title and coalesce(v_old->>'body','') = v_body then v_old->>'id' else to_char(now() at time zone 'Asia/Seoul', 'YYYYMMDD-HH24MISS') end;
  v_new := jsonb_build_object('id', v_id, 'active', coalesce((p->>'active')::boolean, false) and v_body <> '', 'title', v_title, 'body', v_body,
    'sheet', coalesce((p->>'sheet')::boolean, false), 'btn', v_btn, 'link', v_link);
  insert into public.app_config(key, value) values ('home_notice', v_new)
    on conflict (key) do update set value = excluded.value, updated_at = now();
  perform public.admin_log('set_home_notice', 'app_config', 'home_notice', v_new);
  return v_new;
end $function$;

-- admin_shop_post(p jsonb)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_shop_post(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pid uuid;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  if (p->>'id') is not null then
    pid := (p->>'id')::uuid;
    update public.shop_posts set title = coalesce(p->>'title', title), body = p->>'body', kind = coalesce(p->>'kind', kind), photos = coalesce((select array_agg(x) from jsonb_array_elements_text(p->'photos') x), photos), ends_at = (p->>'ends_at')::timestamptz, hidden = coalesce((p->>'hidden')::boolean, hidden) where id = pid;
  else
    insert into public.shop_posts(shop_id, author_id, kind, title, body, photos, ends_at)
    values ((p->>'shop_id')::uuid, auth.uid(), coalesce(p->>'kind','notice'), p->>'title', p->>'body', coalesce((select array_agg(x) from jsonb_array_elements_text(p->'photos') x), '{}'), (p->>'ends_at')::timestamptz)
    returning id into pid;
  end if;
  perform public.admin_log('shop_post', 'shop_post', pid::text, jsonb_build_object('title', p->>'title'));
  return pid;
end $function$;

-- admin_stash_search(p_q text, p_offset integer)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_stash_search(p_q text, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when not public.is_admin() then null else (
    select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc), '[]') from (
      select s.id, s.owner_id, p.nickname, s.raw_name, s.color, s.color_family, s.ball_g, s.ball_m, s.fibers, s.fiber, s.bought_balls, s.left_balls, s.read_status, s.band_photo, s.created_at, s.catalog_id,
        (select coalesce(c.brand||' ','')||c.product from public.yarn_catalog c where c.id = s.catalog_id) catalog_name
      from public.yarn_stash s join public.profiles p on p.id = s.owner_id
      where nullif(btrim(p_q),'') is null or p.nickname ilike '%'||btrim(p_q)||'%' or s.raw_name ilike '%'||btrim(p_q)||'%'
         or exists (select 1 from public.yarn_catalog c where c.id = s.catalog_id and (c.product ilike '%'||btrim(p_q)||'%' or c.brand ilike '%'||btrim(p_q)||'%'))
      order by s.created_at desc limit 50 offset greatest(p_offset,0)) t) end;
$function$;

-- admin_stats()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare out jsonb;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  select jsonb_build_object(
    'totals', jsonb_build_object(
      'users', (select count(*) from profiles), 'onboarded', (select count(*) from profiles where onboarded_at is not null),
      'suspended', (select count(*) from profiles where suspended_at is not null),
      'waving', (select count(*) from profiles where wave_until > now()),
      'posts', (select count(*) from posts where parent_id is null), 'replies', (select count(*) from posts where parent_id is not null),
      'works', (select count(*) from works), 'meetups', (select count(*) from meetups), 'upcoming', (select count(*) from meetups where starts_at > now()),
      'rooms', (select count(*) from rooms), 'messages', (select count(*) from messages),
      'rooms_member', (select count(*) from rooms r where not exists (select 1 from room_members s where s.room_id = r.id and s.profile_id = 'e120eb67-b254-4008-92d8-08c95c821e9e')),
      'messages_member', (select count(*) from messages m where not exists (select 1 from room_members s where s.room_id = m.room_id and s.profile_id = 'e120eb67-b254-4008-92d8-08c95c821e9e')),
      'rooms_support', (select count(*) from rooms r where exists (select 1 from room_members s where s.room_id = r.id and s.profile_id = 'e120eb67-b254-4008-92d8-08c95c821e9e')),
      'friendships', (select count(*) from friendships where status='accepted'),
      'active7', (select count(distinct u) from (select author_id u from posts where created_at > now()-interval '7 days' union select sender_id from messages where created_at > now()-interval '7 days' union select profile_id from post_likes where created_at > now()-interval '7 days') x),
      'active30', (select count(distinct u) from (select author_id u from posts where created_at > now()-interval '30 days' union select sender_id from messages where created_at > now()-interval '30 days' union select profile_id from post_likes where created_at > now()-interval '30 days') x),
      'reports_open', (select count(*) from post_reports where reviewed_at is null) + (select count(*) from reports where reviewed_at is null)
    ),
    'daily', (select coalesce(jsonb_agg(jsonb_build_object('d', d, 'signups', s, 'posts', p, 'works', w, 'messages', m) order by d), '[]'::jsonb) from (
      select d::date d,
        (select count(*) from profiles where created_at::date = d::date) s,
        (select count(*) from posts where created_at::date = d::date) p,
        (select count(*) from works where created_at::date = d::date) w,
        (select count(*) from messages where created_at::date = d::date) m
      from generate_series(now()::date - 29, now()::date, interval '1 day') d) t),
    'dong', (select coalesce(jsonb_agg(jsonb_build_object('dong', dong_name, 'n', n) order by n desc), '[]'::jsonb) from (select dong_name, count(*) n from profiles where dong_name is not null group by 1 order by 2 desc limit 40) t),
    'levels', jsonb_build_object(
      'crochet', (select coalesce(jsonb_object_agg(coalesce(level_crochet,0), n), '{}'::jsonb) from (select level_crochet, count(*) n from profiles where onboarded_at is not null group by 1) t),
      'knit', (select coalesce(jsonb_object_agg(coalesce(level_knit,0), n), '{}'::jsonb) from (select level_knit, count(*) n from profiles where onboarded_at is not null group by 1) t)),
    'techniques', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name_ko, 'craft', t.craft, 'level', t.level, 'checked', c.n, 'verified', v.n) order by t.sort), '[]'::jsonb)
      from techniques t
      left join lateral (select count(*) n from profiles p where t.id = any(p.skills)) c on true
      left join lateral (select count(*) n from profiles p where t.id = any(p.verified_skills)) v on true),
    'custom_techniques', (select coalesce(jsonb_agg(jsonb_build_object('name', x, 'n', n) order by n desc), '[]'::jsonb) from (select x, count(*) n from works, unnest(custom_techniques) x group by x order by 2 desc limit 50) t),
    'yarn', (select coalesce(jsonb_agg(jsonb_build_object('name', yarn_name, 'n', n) order by n desc), '[]'::jsonb) from (select yarn_name, count(*) n from works where yarn_name is not null group by 1 order by 2 desc limit 30) t),
    'yarn_weight', (select coalesce(jsonb_object_agg(yarn_weight, n), '{}'::jsonb) from (select yarn_weight, count(*) n from works where yarn_weight is not null group by 1) t),
    'solved', jsonb_build_object('questions_with_replies', (select count(*) from posts where parent_id is null and reply_count>0), 'solved', (select count(*) from posts where solved_reply_id is not null))
  ) into out;
  return out;
end $function$;

-- admin_support_answer(p_ticket bigint, p_text text, p_close boolean)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_support_answer(p_ticket bigint, p_text text, p_close boolean DEFAULT false)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t public.support_tickets; mid bigint; sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e';
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  select * into t from public.support_tickets where id = p_ticket; if t.id is null then raise exception '티켓이 없어요'; end if;
  if btrim(coalesce(p_text,'')) <> '' then
    insert into public.messages(room_id, sender_id, body, by_ai, support_seen) values (t.room_id, sup, left(btrim(p_text),1000), false, true) returning id into mid;
    update public.room_members set last_read_at = now() where room_id = t.room_id and profile_id = sup;
  end if;
  update public.support_tickets set admin_answer = coalesce(nullif(btrim(p_text),''), admin_answer), answered_by = auth.uid(), answered_at = now(),
    status = case when p_close then 'closed' else 'answered' end, closed_at = case when p_close then now() else closed_at end,
    followup_at = case when p_close then null else now() + interval '1 day' end, updated_at = now() where id = p_ticket;
  insert into public.support_events(ticket_id, actor, kind, body) values (p_ticket, 'admin', case when p_close then 'close' else 'answer' end, left(coalesce(p_text,''),1000));
  update public.mod_items set status='done', resolved_at=now(), resolved_by='admin', resolution='답변' where kind='support' and target_id = p_ticket::text and status='open';
  perform public.admin_log('support_answer', 'ticket', p_ticket::text, jsonb_build_object('close', p_close, 'text', left(coalesce(p_text,''),200)));
  if mid is not null then perform public.chat_push(mid); end if;
  return mid;
end $function$;

-- admin_support_stats(p_days integer)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_support_stats(p_days integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when public.is_admin() then jsonb_build_object(
    'total', (select count(*) from public.support_tickets where created_at > now() - make_interval(days=>p_days)),
    'open', (select count(*) from public.support_tickets where status in ('open','waiting_admin')),
    'by_category', (select coalesce(jsonb_object_agg(category, n), '{}'::jsonb) from (select category, count(*) n from public.support_tickets where created_at > now() - make_interval(days=>p_days) group by 1 order by 2 desc limit 12) x),
    'avg_answer_hours', (select round(avg(extract(epoch from answered_at - created_at))/3600, 1) from public.support_tickets where answered_at is not null and created_at > now() - make_interval(days=>p_days)),
    'faq_direct', (select count(*) from public.support_events where actor='ai' and kind='faq' and created_at > now() - make_interval(days=>p_days)),
    'reopened', (select count(*) from public.support_events where kind='reopen' and created_at > now() - make_interval(days=>p_days))
  ) else null end $function$;

-- admin_survey_upsert(p jsonb)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_survey_upsert(p jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id integer := nullif(p->>'id','')::integer;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  if v_id is null then insert into public.surveys(cohort_id, round, title, opens_at, closes_at, questions) values ((select id from public.supporter_cohorts order by id desc limit 1), (p->>'round')::smallint, coalesce(p->>'title',''), coalesce((p->>'opens_at')::timestamptz, now()), coalesce((p->>'closes_at')::timestamptz, now() + interval '14 days'), coalesce(p->'questions','[]'::jsonb)) returning id into v_id;
  else update public.surveys set title = coalesce(p->>'title', title), opens_at = coalesce((p->>'opens_at')::timestamptz, opens_at), closes_at = coalesce((p->>'closes_at')::timestamptz, closes_at), questions = coalesce(p->'questions', questions) where id = v_id; end if;
  perform public.admin_log('survey_upsert', 'survey', v_id::text, jsonb_build_object('round', p->>'round'));
  return v_id;
end $function$;

-- admin_suspend_user(p_user uuid, p_suspend boolean, p_reason text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_suspend_user(p_user uuid, p_suspend boolean, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  update public.profiles set suspended_at = case when p_suspend then now() else null end where id = p_user;
  update public.reports set reviewed_at = now() where reported_id = p_user and reviewed_at is null;
  perform public.admin_log(case when p_suspend then 'suspend_user' else 'unsuspend_user' end, 'user', p_user::text, jsonb_build_object('reason', p_reason));
end $function$;

-- admin_tag_hide(p_tag text, p_hide boolean)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_tag_hide(p_tag text, p_hide boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v text := lower(trim(coalesce(p_tag,'')));
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  if v = '' then raise exception '태그를 적어 주세요'; end if;
  if p_hide then insert into public.tag_hidden(tag, created_by) values (v, auth.uid()) on conflict do nothing; else delete from public.tag_hidden where tag = v; end if;
  perform public.admin_log('tag_hide', 'tag', v, jsonb_build_object('hide', p_hide));
  return p_hide;
end $function$;

-- admin_tags()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_tags()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  return coalesce((select jsonb_agg(x order by (x->>'n')::int desc, x->>'tag') from (
    select jsonb_build_object('tag', t, 'n', count(*), 'week', count(*) filter (where p.created_at > now() - interval '7 days'), 'last', max(p.created_at),
      'hidden', exists (select 1 from public.tag_hidden h where h.tag = t)) x
    from public.posts p, unnest(p.tags) t where p.parent_id is null group by t order by count(*) desc limit 300) s), '[]'::jsonb);
end $function$;

-- admin_talk_list(p jsonb)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_talk_list(p jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_seg text := coalesce(p->>'seg','all'); v_q text := trim(coalesce(p->>'q','')); v_tag text := coalesce(p->>'tag','');
  v_page int := greatest(coalesce((p->>'page')::int,1),1); v_size int := 50; r jsonb; v_rows jsonb; v_total int;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  select jsonb_build_object('need', count(*) filter (where f_need), 'wait', count(*) filter (where f_wait), 'wait_unread', count(*) filter (where f_unread),
    'talked', count(*) filter (where member_msgs > 0), 'all', count(*) filter (where f_talk), 'auto', count(*) filter (where not f_talk), 'rooms', count(*)) into r
    from public._admin_talk_base();
  with f as (
    select b.* from public._admin_talk_base() b
    where (case v_seg when 'need' then b.f_need when 'wait' then b.f_wait when 'auto' then not b.f_talk else b.f_talk end)
      and (v_tag = '' or v_tag = any(b.tags))
      and (v_q = '' or b.nickname ilike '%'||v_q||'%' or coalesce(b.dong,'') ilike '%'||v_q||'%'
           or exists (select 1 from public.messages m where m.room_id = b.room_id and m.by_ai is not true and m.body ilike '%'||v_q||'%'))
  ), o as (select f.*, row_number() over (order by f.last_at desc) rn, count(*) over () total from f)
  select coalesce(jsonb_agg(jsonb_build_object('room', room_id, 'uid', uid, 'nick', nickname, 'dong', dong, 'joined', joined, 'body', last_body, 'photo', last_photo,
      'from_member', last_from_member, 'at', last_at, 'member_msgs', member_msgs, 'human_msgs', human_msgs, 'last_human_at', last_human_at, 'member_read', member_read,
      'push_on', push_on, 'tags', to_jsonb(tags), 'need', f_need, 'wait', f_wait, 'unread', f_unread) order by rn), '[]'::jsonb), coalesce(max(total), 0)
    into v_rows, v_total from o where rn > (v_page-1)*v_size and rn <= v_page*v_size;
  return jsonb_build_object('counts', r, 'total', v_total, 'page', v_page, 'size', v_size, 'rows', v_rows,
    'tags', coalesce((select jsonb_agg(distinct t order by t) from public.member_notes n, unnest(n.tags) t), '[]'::jsonb));
end $function$;

-- admin_talk_member(p_user uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_talk_member(p_user uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare p public.profiles; r jsonb; v_snip int := 34;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  select * into p from public.profiles where id = p_user; if p.id is null then raise exception '회원을 찾을 수 없어요'; end if;
  r := jsonb_build_object(
    'id', p.id, 'nick', p.nickname, 'dong', p.dong_name, 'joined', p.created_at, 'lc', coalesce(p.level_crochet,0), 'lk', coalesce(p.level_knit,0),
    'provider', (select string_agg(distinct i.provider, ',') from auth.identities i where i.user_id = p.id),
    'seen', (select greatest(p.last_seen_at, au.last_sign_in_at) from auth.users au where au.id = p.id),
    'flags', jsonb_build_object('waving', coalesce(p.wave_until > now(), false), 'visible', coalesce(p.is_visible, false) and p.location is not null,
      'push', exists (select 1 from public.device_tokens d where d.profile_id = p.id and d.disabled_at is null), 'author', coalesce(p.is_author, false),
      'onboarded', p.onboarded_at is not null, 'suspended', p.suspended_at is not null, 'leaving', p.deleted_at is not null),
    'counts', jsonb_build_object(
      'posts', (select count(*) from public.posts x where x.author_id = p.id and x.parent_id is null and x.meetup_id is null and x.work_id is null),
      'replies', (select count(*) from public.posts x where x.author_id = p.id and x.parent_id is not null),
      'works', (select count(*) from public.works w where w.profile_id = p.id),
      'friends', (select count(*) from public.friendships f where f.status = 'accepted' and p.id in (f.requester_id, f.addressee_id)),
      'friend_pending', (select count(*) from public.friendships f where f.status = 'pending' and p.id in (f.requester_id, f.addressee_id)),
      'meet_host', (select count(*) from public.meetups m where m.created_by = p.id),
      'meet_join', (select count(*) from public.meetups m join public.room_members rm on rm.room_id = m.room_id and rm.profile_id = p.id where m.created_by <> p.id),
      'classes', (select count(*) from public.shop_posts sp where sp.author_id = p.id and sp.kind = 'class'),
      'class_apps', (select count(*) from public.class_applications ca where ca.profile_id = p.id),
      'shop_follows', (select count(*) from public.shop_follows sf where sf.profile_id = p.id),
      'stash', (select count(*) from public.yarn_stash ys where ys.owner_id = p.id),
      'events', (select count(*) from public.event_applications ea where ea.profile_id = p.id)),
    'meetups', coalesce((select jsonb_agg(x order by x->>'starts_at' desc) from (
        select jsonb_build_object('id', m.id, 'title', m.title, 'starts_at', m.starts_at, 'joined', coalesce(m.participant_count,0), 'capacity', m.capacity,
          'host', m.created_by = p.id, 'hidden', m.hidden, 'upcoming', m.starts_at > now()) x
        from public.meetups m where m.created_by = p.id or exists (select 1 from public.room_members rm where rm.room_id = m.room_id and rm.profile_id = p.id)
        order by m.starts_at desc limit 8) t), '[]'::jsonb),
    'shops', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'active', s.is_active,
          'followers', (select count(*) from public.shop_follows sf where sf.shop_id = s.id)) order by s.created_at) from public.shops s where s.owner_id = p.id), '[]'::jsonb),
    'classes', coalesce((select jsonb_agg(x order by x->>'created_at' desc) from (
        select jsonb_build_object('id', sp.id, 'title', sp.title, 'shop_id', sp.shop_id, 'created_at', sp.created_at, 'hidden', coalesce(sp.hidden,false),
          'applicants', (select count(*) from public.class_applications ca where ca.post_id = sp.id)) x
        from public.shop_posts sp where sp.author_id = p.id and sp.kind = 'class' order by sp.created_at desc limit 6) t), '[]'::jsonb),
    'note', coalesce((select jsonb_build_object('memo', n.memo, 'tags', to_jsonb(n.tags), 'updated_at', n.updated_at) from public.member_notes n where n.profile_id = p.id),
                     jsonb_build_object('memo', null, 'tags', '[]'::jsonb))
  );
  return r || jsonb_build_object('timeline', coalesce((select jsonb_agg(jsonb_build_object('at', at, 'text', txt, 'ref', ref) order by at desc) from (
    select * from (
      select p.created_at as at, '가입'::text as txt, null::jsonb as ref
      union all select p.onboarded_at, '프로필 저장', null where p.onboarded_at is not null
      union all select min(se.created_at), case se.craft::text when 'crochet' then '코바늘' when 'knitting' then '대바늘' else '뜨개' end||' 기법 체크 '||count(*)||'개', null
        from public.skill_events se where se.profile_id = p.id and se.kind = 'add' and se.source = 'manual' group by se.craft, date_trunc('minute', se.created_at)
      union all select x.created_at, '글 "'||left(regexp_replace(coalesce(x.body,'(사진)'), '\s+', ' ', 'g'), v_snip)||'"', jsonb_build_object('type','post','id', x.id)
        from public.posts x where x.author_id = p.id and x.parent_id is null and x.meetup_id is null and x.work_id is null
      union all select x.created_at, '댓글 "'||left(regexp_replace(coalesce(x.body,'(사진)'), '\s+', ' ', 'g'), v_snip)||'"', jsonb_build_object('type','post','id', x.parent_id)
        from public.posts x where x.author_id = p.id and x.parent_id is not null
      union all select w.created_at, '완성작품 인증 "'||left(coalesce(w.title,''), v_snip)||'"', jsonb_build_object('type','work','id', w.id) from public.works w where w.profile_id = p.id
      union all select coalesce(f.responded_at, f.created_at), '뜨친이 됐어요', null from public.friendships f where f.status = 'accepted' and p.id in (f.requester_id, f.addressee_id)
      union all select m.created_at, '모임 "'||left(coalesce(m.title,''), v_snip)||'" 열었어요', jsonb_build_object('type','meetup','id', m.id) from public.meetups m where m.created_by = p.id
      union all select rm.joined_at, '모임 "'||left(coalesce(m.title,''), v_snip)||'" 참여', jsonb_build_object('type','meetup','id', m.id)
        from public.meetups m join public.room_members rm on rm.room_id = m.room_id and rm.profile_id = p.id where m.created_by <> p.id
      union all select sp.created_at, case when sp.kind = 'class' then '클래스 "' else '가게 소식 "' end||left(coalesce(sp.title, sp.body, ''), v_snip)||'"',
          case when sp.kind = 'class' then jsonb_build_object('type','class','id', sp.id) when sp.shop_id is not null then jsonb_build_object('type','shop','id', sp.shop_id) else null end
        from public.shop_posts sp where sp.author_id = p.id
      union all select ca.created_at, '클래스 신청', jsonb_build_object('type','class','id', ca.post_id) from public.class_applications ca where ca.profile_id = p.id
      union all select ea.created_at, '이벤트 신청', null from public.event_applications ea where ea.profile_id = p.id
    ) e where e.at is not null order by e.at desc limit 14) tl), '[]'::jsonb));
end $function$;

-- admin_talk_remind(p_user uuid, p_days integer)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_talk_remind(p_user uuid, p_days integer DEFAULT 3)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_nick text; v_last text; v_at timestamptz := now() + make_interval(days => greatest(1, least(coalesce(p_days,3), 60))); v_memo text;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  select nickname into v_nick from public.profiles where id = p_user; if v_nick is null then raise exception '회원을 찾을 수 없어요'; end if;
  select left(regexp_replace(coalesce(b.last_body,''), '\s+', ' ', 'g'), 80) into v_last from public._admin_talk_base() b where b.uid = p_user limit 1;
  select memo into v_memo from public.member_notes where profile_id = p_user;
  insert into public.jigi_reminders(due_at, text) values (v_at,
    '💬 다시 연락하기로 한 회원이 있어요 — '||v_nick||E'\n\n'||
    '대표님이 '||to_char(now() at time zone 'Asia/Seoul', 'FMMM"월" FMDD"일"')||'에 콘솔 대화 화면에서 "다시 알려줘"를 눌러 두신 건이에요. 그때 마지막으로 오간 말은 이랬어요:'||E'\n'||
    '「'||coalesce(nullif(v_last,''), '(내용 없음)')||'」'||E'\n\n'||
    case when coalesce(v_memo,'') <> '' then '운영 메모: '||left(v_memo, 300)||E'\n\n' else '' end||
    '지금 하실 일: 콘솔 › 오늘 › 지기 문의함 › 대화에서 '||v_nick||' 님을 찾아(검색창에 닉네임) 답이 왔는지, 읽었는지 확인하고 필요하면 한마디 더 건네 보세요. 오른쪽 칸에서 그 사이 이 회원이 앱에서 한 활동도 볼 수 있어요.'||E'\n'||
    'https://yesbeyesnono.github.io/knit-neighbors/admin.html#support');
  perform public.admin_log('talk_remind', 'profile', p_user::text, jsonb_build_object('due_at', v_at));
  return v_at;
end $function$;

-- admin_talk_room(p_user uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_talk_room(p_user uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r uuid;
begin
  if not public.is_admin() then raise exception '관리자만 할 수 있어요'; end if;
  if not exists (select 1 from public.profiles where id = p_user) then raise exception '회원을 찾을 수 없어요'; end if;
  r := public._support_room(p_user);
  return r;
end $function$;

-- admin_talk_send(p_room uuid, p_body text, p_photo text, p_bell boolean)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_talk_send(p_room uuid, p_body text DEFAULT NULL::text, p_photo text DEFAULT NULL::text, p_bell boolean DEFAULT true)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare mid bigint; v_user uuid; sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e';
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  mid := public.admin_reply_support(p_room, p_body, p_photo);
  if p_bell then
    select profile_id into v_user from public.room_members where room_id = p_room and profile_id <> sup limit 1;
    if v_user is not null then
      insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
        values (v_user, sup, 'notice', left('지기가 답장을 보냈어요: '||coalesce(nullif(regexp_replace(coalesce(p_body,''), '\s+', ' ', 'g'), ''), '사진'), 200),
                jsonb_build_object('type','view','view','support','push','0'));
    end if;
  end if;
  return mid;
end $function$;

-- admin_upsert_event(p jsonb)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_upsert_event(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid := nullif(p->>'id','')::uuid; v_open boolean; e public.events;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  if v_id is null then
    insert into public.events(title, body, photo, kind, min_level, capacity, select_mode, apply_from, apply_until, cert_due, needs_shipping, catalog_id, status, created_by)
    values (left(btrim(p->>'title'),60), nullif(p->>'body',''), nullif(p->>'photo',''), coalesce(nullif(p->>'kind',''),'general'), coalesce(nullif(p->>'min_level','')::int,0), nullif(p->>'capacity','')::int,
            coalesce(nullif(p->>'select_mode',''),'admin'), coalesce(nullif(p->>'apply_from','')::timestamptz, now()), (p->>'apply_until')::timestamptz, nullif(p->>'cert_due','')::date,
            coalesce((p->>'needs_shipping')::boolean,false), nullif(p->>'catalog_id','')::uuid, coalesce(nullif(p->>'status',''),'draft'), auth.uid()) returning id into v_id;
  else
    update public.events set title = left(btrim(p->>'title'),60), body = nullif(p->>'body',''), photo = nullif(p->>'photo',''), kind = coalesce(nullif(p->>'kind',''),kind), min_level = coalesce(nullif(p->>'min_level','')::int,0),
      capacity = nullif(p->>'capacity','')::int, select_mode = coalesce(nullif(p->>'select_mode',''),select_mode), apply_from = coalesce(nullif(p->>'apply_from','')::timestamptz, apply_from),
      apply_until = (p->>'apply_until')::timestamptz, cert_due = nullif(p->>'cert_due','')::date, needs_shipping = coalesce((p->>'needs_shipping')::boolean,false),
      catalog_id = nullif(p->>'catalog_id','')::uuid, status = coalesce(nullif(p->>'status',''),status) where id = v_id;
  end if;
  select * into e from public.events where id = v_id;
  -- 처음 공개될 때 레벨이 되는 회원에게 한 번만 알림
  if e.status = 'open' and e.announced_at is null then
    insert into public.notifications(recipient_id, actor_id, kind, event_id, snippet)
      select pr.id, null, 'event_open', e.id, left(e.title, 80) from public.profiles pr
      where pr.act_level >= e.min_level and pr.onboarded_at is not null and pr.suspended_at is null;
    update public.events set announced_at = now() where id = v_id;
  end if;
  perform public.admin_log('event_upsert', 'event', v_id::text, jsonb_build_object('title', e.title, 'status', e.status));
  return v_id;
end $function$;

-- admin_upsert_pattern(p jsonb)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_upsert_pattern(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare pid uuid;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  if (p->>'id') is not null then
    pid := (p->>'id')::uuid;
    update public.patterns set
      title = coalesce(p->>'title', title), descr = case when p ? 'descr' then p->>'descr' else descr end,
      craft = coalesce(p->>'craft', craft), level = coalesce((p->>'level')::smallint, level),
      techniques = case when p ? 'techniques' then array(select jsonb_array_elements_text(p->'techniques')) else techniques end,
      photos = case when p ? 'photos' then array(select jsonb_array_elements_text(p->'photos')) else photos end,
      yarn_weight = case when p ? 'yarn_weight' then p->>'yarn_weight' else yarn_weight end,
      needle_size = case when p ? 'needle_size' then p->>'needle_size' else needle_size end,
      price = coalesce((p->>'price')::int, price), buy_url = case when p ? 'buy_url' then nullif(p->>'buy_url','') else buy_url end,
      is_published = coalesce((p->>'is_published')::boolean, is_published), hidden = coalesce((p->>'hidden')::boolean, hidden),
      author_id = coalesce(nullif(p->>'author_id','')::uuid, author_id), updated_at = now()
    where id = pid;
  else
    insert into public.patterns(author_id, title, descr, craft, level, techniques, photos, yarn_weight, needle_size, price, buy_url, is_published)
    values (coalesce(nullif(p->>'author_id','')::uuid, 'e120eb67-b254-4008-92d8-08c95c821e9e'), p->>'title', p->>'descr', p->>'craft', (p->>'level')::smallint,
      coalesce(array(select jsonb_array_elements_text(p->'techniques')), '{}'), coalesce(array(select jsonb_array_elements_text(p->'photos')), '{}'),
      p->>'yarn_weight', p->>'needle_size', coalesce((p->>'price')::int, 0), nullif(p->>'buy_url',''), coalesce((p->>'is_published')::boolean, true))
    returning id into pid;
  end if;
  perform public.admin_log('upsert_pattern', 'pattern', pid::text, p - 'descr');
  return pid;
end $function$;

-- admin_upsert_shop(p jsonb)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_upsert_shop(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare sid uuid; loc geography;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  if (p->>'lat') is not null and (p->>'lng') is not null then loc := st_setsrid(st_makepoint((p->>'lng')::double precision, (p->>'lat')::double precision), 4326)::geography; end if;
  if (p->>'id') is not null then
    sid := (p->>'id')::uuid;
    update public.shops set name = coalesce(p->>'name', name), kind = coalesce(p->>'kind', kind), descr = p->>'descr', address = p->>'address',
      location = coalesce(loc, location), phone = p->>'phone', hours = p->>'hours', links = coalesce(p->'links', links), logo_url = p->>'logo_url',
      radius_m = coalesce((p->>'radius_m')::int, radius_m), is_active = coalesce((p->>'is_active')::boolean, is_active),
      owner_id = case when p ? 'owner_id' then nullif(p->>'owner_id','')::uuid else owner_id end
    where id = sid;
  else
    insert into public.shops(name, kind, descr, address, location, phone, hours, links, logo_url, radius_m, is_active, owner_id)
    values (p->>'name', coalesce(p->>'kind','yarn'), p->>'descr', p->>'address', loc, p->>'phone', p->>'hours', coalesce(p->'links','{}'::jsonb), p->>'logo_url', coalesce((p->>'radius_m')::int,5000), coalesce((p->>'is_active')::boolean,true), nullif(p->>'owner_id','')::uuid)
    returning id into sid;
  end if;
  perform public.admin_log('upsert_shop', 'shop', sid::text, p - 'descr');
  return sid;
end $function$;

-- admin_yarn_bulk_upsert(p jsonb)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_yarn_bulk_upsert(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare y jsonb; c jsonb; s jsonb; cid uuid; keys text[]; n_ins int := 0; n_upd int := 0; n_col int := 0; per numeric; nm text; en text;
begin
  if auth.uid() is not null and not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  for y in select * from jsonb_array_elements(p) loop
    cid := null; nm := left(btrim(y->>'product'), 60); en := nullif(btrim(coalesce(y->>'product_en','')), '');
    keys := array(select distinct public.yarn_norm(x) from unnest(array[nm, coalesce(y->>'brand','')||nm] || case when en is not null then array[en, coalesce(y->>'brand','')||en] else '{}'::text[] end || array(select jsonb_array_elements_text(coalesce(y->'aliases','[]'::jsonb)))) x where public.yarn_norm(x) is not null and length(public.yarn_norm(x)) >= 2);
    select t.id into cid from public.yarn_catalog t where t.merged_into is null and (
        t.norm_keys && array[public.yarn_norm(coalesce(y->>'brand','')||nm)]
        or (t.norm_keys && keys and (t.brand is null or y->>'brand' is null or t.brand = y->>'brand' or t.brand in ('쎄비','앵콜스','바늘이야기','청송뜨개실') or y->>'brand' in ('쎄비','앵콜스','바늘이야기','청송뜨개실')))
      ) order by (t.status='verified') desc, t.uses desc limit 1;
    per := case when (y->>'g')::numeric > 0 and (y->>'m')::numeric > 0 then (y->>'m')::numeric / (y->>'g')::numeric * 100 end;
    if cid is null then
      insert into public.yarn_catalog(brand, product, product_en, aliases, norm_keys, ball_g, ball_m, weight_class, fiber_main, fibers, status, shop, source_url, season, needle_knit, needle_crochet, gauge, put_up, texture, use_tags)
      values (nullif(y->>'brand',''), nm, en, array(select distinct x from unnest(array[nm] || array(select jsonb_array_elements_text(coalesce(y->'aliases','[]'::jsonb)))) x), keys,
        (y->>'g')::numeric, (y->>'m')::numeric,
        coalesce(nullif(y->>'weight_class',''), case when per is null then null when per >= 600 then '레이스·극세' when per >= 350 then '합세(Fingering)' when per >= 250 then '중세(Sport)' when per >= 200 then '합태(DK)' when per >= 120 then '병태(Worsted)' when per >= 60 then '극태(Bulky)' else '초극태' end),
        nullif(y->>'fiber_main',''), case when jsonb_typeof(y->'fibers')='object' then y->'fibers' end, 'verified', y->>'shop', y->>'url', nullif(y->>'season',''), nullif(y->>'needle_knit',''), nullif(y->>'needle_crochet',''), left(y->>'gauge',60), nullif(y->>'put_up',''), nullif(y->>'texture',''), array(select jsonb_array_elements_text(coalesce(y->'use_tags','[]'::jsonb))))
      returning id into cid; n_ins := n_ins + 1;
    else
      update public.yarn_catalog t set
        brand = case when (t.brand is null or t.brand in ('쎄비','앵콜스','바늘이야기','청송뜨개실')) and nullif(y->>'brand','') is not null and (y->>'brand') not in ('쎄비','앵콜스','바늘이야기','청송뜨개실') then y->>'brand' else coalesce(t.brand, nullif(y->>'brand','')) end,
        product_en = coalesce(t.product_en, en),
        aliases = array(select distinct x from unnest(t.aliases || array[nm] || array(select jsonb_array_elements_text(coalesce(y->'aliases','[]'::jsonb)))) x),
        norm_keys = array(select distinct x from unnest(t.norm_keys || keys) x),
        ball_g = coalesce(t.ball_g, (y->>'g')::numeric), ball_m = coalesce(t.ball_m, (y->>'m')::numeric),
        weight_class = coalesce(t.weight_class, nullif(y->>'weight_class','')),
        fiber_main = coalesce(t.fiber_main, nullif(y->>'fiber_main','')), fibers = coalesce(t.fibers, case when jsonb_typeof(y->'fibers')='object' then y->'fibers' end),
        shop = coalesce(t.shop, y->>'shop'), source_url = coalesce(t.source_url, y->>'url'), season = coalesce(t.season, nullif(y->>'season','')),
        needle_knit = coalesce(t.needle_knit, nullif(y->>'needle_knit','')), needle_crochet = coalesce(t.needle_crochet, nullif(y->>'needle_crochet','')), gauge = coalesce(t.gauge, left(y->>'gauge',60)), put_up = coalesce(t.put_up, nullif(y->>'put_up','')),
        texture = coalesce(t.texture, nullif(y->>'texture','')), use_tags = case when cardinality(t.use_tags) = 0 then array(select jsonb_array_elements_text(coalesce(y->'use_tags','[]'::jsonb))) else t.use_tags end,
        status = 'verified', updated_at = now()
      where t.id = cid; n_upd := n_upd + 1;
      update public.yarn_catalog t set weight_class = case when t.m_per_100g >= 600 then '레이스·극세' when t.m_per_100g >= 350 then '합세(Fingering)' when t.m_per_100g >= 250 then '중세(Sport)' when t.m_per_100g >= 200 then '합태(DK)' when t.m_per_100g >= 120 then '병태(Worsted)' when t.m_per_100g >= 60 then '극태(Bulky)' else '초극태' end where t.id = cid and t.weight_class is null and t.m_per_100g is not null;
    end if;
    for c in select * from jsonb_array_elements(coalesce(y->'colors','[]'::jsonb)) loop
      if not exists (select 1 from public.yarn_colors yc where yc.catalog_id = cid and ((nullif(c->>'no','') is not null and yc.no = c->>'no') or (nullif(c->>'no','') is null and yc.name = c->>'name'))) then
        insert into public.yarn_colors(catalog_id, no, name) values (cid, nullif(c->>'no',''), left(coalesce(nullif(c->>'name',''), c->>'no'),40)) on conflict do nothing; n_col := n_col + 1;
      end if;
    end loop;
    for s in select * from jsonb_array_elements(coalesce(y->'sellers','[]'::jsonb)) loop
      insert into public.yarn_sellers(catalog_id, shop, url, price) values (cid, s->>'shop', s->>'url', nullif(regexp_replace(coalesce(s->>'price',''),'[^0-9]','','g'),'')::int)
      on conflict (catalog_id, shop) do update set url = coalesce(yarn_sellers.url, excluded.url), price = coalesce(excluded.price, yarn_sellers.price), checked_at = now();
    end loop;
  end loop;
  return jsonb_build_object('inserted', n_ins, 'updated', n_upd, 'colors', n_col);
end $function$;

-- admin_yarn_color_photo(p_catalog uuid, p_no text, p_name text, p_photo text, p_hex text[], p_mode text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_yarn_color_photo(p_catalog uuid, p_no text, p_name text, p_photo text, p_hex text[], p_mode text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  if p_photo is not null and p_photo !~ '^[A-Za-z0-9_./-]+\.(jpg|webp|png)$' then raise exception 'photo path'; end if;
  insert into public.yarn_colors(catalog_id, no, name, photo, color_hex, color_mode) values (p_catalog, nullif(p_no,''), left(coalesce(nullif(p_name,''), p_no),40), p_photo, public.color_hex_clean(p_hex), p_mode)
  on conflict (catalog_id, no, name) do update set photo = excluded.photo, color_hex = excluded.color_hex, color_mode = excluded.color_mode;
end $function$;

-- admin_yarn_delete(p_ids uuid[], p_reason text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_yarn_delete(p_ids uuid[], p_reason text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n integer;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  perform public.admin_log('delete_yarn', 'yarn_catalog', array_to_string(p_ids, ','), jsonb_build_object('reason', p_reason, 'n', coalesce(array_length(p_ids, 1), 0),
    'names', (select jsonb_agg(btrim(coalesce(brand||' ','')||product)) from public.yarn_catalog where id = any(p_ids))));
  update public.yarn_catalog set merged_into = null where merged_into = any(p_ids);
  delete from public.yarn_catalog where id = any(p_ids);
  get diagnostics n = row_count;
  return n;
end $function$;

-- admin_yarn_demand(p_days integer, p_craft text, p_item text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_yarn_demand(p_days integer DEFAULT NULL::integer, p_craft text DEFAULT NULL::text, p_item text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with e as (
    select e.id, e.raw_name, e.catalog_id, c.status cstatus, coalesce(c.brand||' ','')||c.product cname,
      public.yarn_fiber_combo(coalesce(e.fibers, c.fibers), coalesce(e.fiber, c.fiber_main)) fiber,
      coalesce(e.color_family, e.color_families[1], '(색 미상)') fam,
      coalesce(c.weight_class, e.weight, '(굵기 미상)') wc,
      case when e.unit='g' then e.amount else e.amount * coalesce(e.ball_g, c.ball_g) end g,
      case when e.unit='g' then e.amount / nullif(coalesce(e.ball_g, c.ball_g),0) * coalesce(e.ball_m, c.ball_m) else e.amount * coalesce(e.ball_m, c.ball_m) end m,
      case when coalesce(e.unit,'볼')<>'g' and e.amount is not null and coalesce(e.ball_g, c.ball_g) is null then e.amount end unknown_balls,
      w.profile_id member_id, e.created_at
    from public.yarn_entries e
    left join public.yarn_catalog c on c.id = e.catalog_id
    left join public.works w on w.id = e.work_id
    where coalesce(e.source,'') <> 'stash'
      and (p_days is null or e.created_at > now() - make_interval(days => p_days))
      and (p_craft is null or e.craft = p_craft or (p_craft <> 'both' and e.craft = 'both'))
      and (p_item is null or e.item_type = p_item)
  ), s as (
    select s.id, public.yarn_fiber_combo(coalesce(s.fibers, c.fibers), coalesce(s.fiber, c.fiber_main)) fiber,
      coalesce(s.color_family, s.color_families[1], '(색 미상)') fam,
      coalesce(c.weight_class, s.weight, '(굵기 미상)') wc,
      s.bought_balls * coalesce(s.ball_g, c.ball_g) g_bought, s.left_balls * coalesce(s.ball_g, c.ball_g) g_left,
      case when coalesce(s.ball_g, c.ball_g) is null then s.bought_balls end unknown_balls, s.owner_id, s.created_at
    from public.yarn_stash s left join public.yarn_catalog c on c.id = s.catalog_id
    where (p_days is null or s.created_at > now() - make_interval(days => p_days))
  )
  select case when not public.is_admin() then null else jsonb_build_object(
    'summary', (select jsonb_build_object('n', count(*), 'members', count(distinct member_id), 'g', coalesce(sum(g),0), 'm', coalesce(sum(m),0), 'unknown_balls', coalesce(sum(unknown_balls),0), 'unknown_n', count(*) filter (where g is null), 'unmatched_n', count(*) filter (where catalog_id is null or cstatus='auto')) from e),
    'heat', (select coalesce(jsonb_agg(jsonb_build_object('fiber', t.fiber, 'fam', t.fam, 'g', t.g, 'n', t.n, 'members', t.mem, 'unknown_balls', t.ub)), '[]') from (select fiber, fam, coalesce(sum(g),0) g, count(*) n, count(distinct member_id) mem, coalesce(sum(unknown_balls),0) ub from e group by 1,2) t),
    'weights', (select coalesce(jsonb_agg(jsonb_build_object('k', t.wc, 'g', t.g, 'n', t.n) order by t.g desc), '[]') from (select wc, coalesce(sum(g),0) g, count(*) n from e group by 1) t),
    'combos', (select coalesce(jsonb_agg(jsonb_build_object('fiber', t.fiber, 'fam', t.fam, 'wc', t.wc, 'g', t.g, 'm', t.m, 'n', t.n, 'members', t.mem, 'unknown_balls', t.ub) order by t.g desc, t.n desc), '[]') from (select fiber, fam, wc, coalesce(sum(g),0) g, coalesce(sum(m),0) m, count(*) n, count(distinct member_id) mem, coalesce(sum(unknown_balls),0) ub from e group by 1,2,3 order by 4 desc, 6 desc limit 40) t),
    'yarns', (select coalesce(jsonb_agg(jsonb_build_object('id', t.catalog_id, 'name', t.cname, 'fiber', t.fiber, 'wc', t.wc, 'g', t.g, 'n', t.n, 'members', t.mem, 'unknown_balls', t.ub,
                'price', (select min(price) from public.yarn_sellers ys where ys.catalog_id = t.catalog_id and ys.price is not null), 'price_at', (select max(checked_at) from public.yarn_sellers ys where ys.catalog_id = t.catalog_id and ys.price is not null),
                'fams', (select coalesce(jsonb_agg(jsonb_build_object('k', f.fam, 'g', f.g) order by f.g desc), '[]') from (select fam, coalesce(sum(g),0) g from e e2 where e2.catalog_id = t.catalog_id group by 1 order by 2 desc limit 5) f)) order by t.g desc, t.n desc), '[]')
              from (select catalog_id, max(cname) cname, max(fiber) fiber, max(wc) wc, coalesce(sum(g),0) g, count(*) n, count(distinct member_id) mem, coalesce(sum(unknown_balls),0) ub from e where catalog_id is not null and cstatus='verified' group by 1 order by 5 desc, 6 desc limit 40) t),
    'unmatched', (select coalesce(jsonb_agg(jsonb_build_object('raw', t.raw_name, 'id', t.catalog_id, 'n', t.n, 'g', t.g) order by t.n desc), '[]') from (select raw_name, max(catalog_id::text)::uuid catalog_id, count(*) n, coalesce(sum(g),0) g from e where catalog_id is null or cstatus='auto' group by 1 order by 3 desc limit 40) t),
    'months', (select coalesce(jsonb_agg(jsonb_build_object('m', t.m, 'g', t.g, 'n', t.n) order by t.m), '[]') from (select to_char(created_at,'YY.MM') m, coalesce(sum(g),0) g, count(*) n from e where created_at > now() - interval '12 months' group by 1) t),
    'stash', (select jsonb_build_object('rows', count(*), 'members', count(distinct owner_id), 'g_bought', coalesce(sum(g_bought),0), 'g_left', coalesce(sum(g_left),0), 'unknown_balls', coalesce(sum(unknown_balls),0)) from s),
    'stash_heat', (select coalesce(jsonb_agg(jsonb_build_object('fiber', t.fiber, 'fam', t.fam, 'g', t.g, 'g_left', t.gl, 'n', t.n)), '[]') from (select fiber, fam, coalesce(sum(g_bought),0) g, coalesce(sum(g_left),0) gl, count(*) n from s group by 1,2) t),
    'items', (select coalesce(jsonb_agg(jsonb_build_object('k', t.k, 'n', t.n) order by t.n desc), '[]') from (select item_type k, count(*) n from public.yarn_entries where item_type is not null group by 1 order by 2 desc limit 20) t)
  ) end;
$function$;

-- admin_yarn_detail_stats(p_id uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_yarn_detail_stats(p_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when not public.is_admin() then null else jsonb_build_object(
    'entries', (select count(*) from yarn_entries where catalog_id=p_id),
    'works', (select count(distinct work_id) from yarn_entries where catalog_id=p_id and work_id is not null),
    'stash', (select count(*) from yarn_stash where catalog_id=p_id),
    'rating_pos', (select count(*) from yarn_entries where catalog_id=p_id and rating=1),
    'rating_neg', (select count(*) from yarn_entries where catalog_id=p_id and rating=-1),
    'reasons', (select coalesce(jsonb_agg(jsonb_build_object('k', t.k, 'n', t.n) order by t.n desc), '[]') from (select rating_reason k, count(*) n from yarn_entries where catalog_id=p_id and rating_reason is not null group by 1 order by 2 desc limit 6) t),
    'items', (select coalesce(jsonb_agg(jsonb_build_object('k', t.k, 'n', t.n) order by t.n desc), '[]') from (select item_type k, count(*) n from yarn_entries where catalog_id=p_id and item_type is not null group by 1 order by 2 desc limit 8) t),
    'colors', (select coalesce(jsonb_agg(jsonb_build_object('k', t.k, 'n', t.n) order by t.n desc), '[]') from (select color k, count(*) n from yarn_entries where catalog_id=p_id and color is not null group by 1 order by 2 desc limit 8) t),
    'needles', (select coalesce(jsonb_agg(jsonb_build_object('k', t.k, 'n', t.n) order by t.n desc), '[]') from (select n->>'size' k, count(*) n from yarn_entries e, jsonb_array_elements(coalesce(e.needles,'[]')) n where e.catalog_id=p_id group by 1 order by 2 desc limit 6) t),
    'months', (select coalesce(jsonb_agg(jsonb_build_object('m', t.m, 'n', t.n) order by t.m), '[]') from (select to_char(created_at,'YY.MM') m, count(*) n from yarn_entries where catalog_id=p_id and created_at > now() - interval '6 months' group by 1) t)
  ) end;
$function$;

-- admin_yarn_merge(p_from uuid, p_into uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_yarn_merge(p_from uuid, p_into uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  if p_from = p_into then return; end if;
  update public.yarn_entries set catalog_id = p_into where catalog_id = p_from;
  update public.yarn_stash set catalog_id = p_into where catalog_id = p_from;
  update public.yarn_sellers s set catalog_id = p_into where catalog_id = p_from and not exists (select 1 from public.yarn_sellers t where t.catalog_id = p_into and t.shop = s.shop);
  delete from public.yarn_sellers where catalog_id = p_from;
  insert into public.yarn_colors(catalog_id, no, name, photo, color_hex, color_mode) select p_into, no, name, photo, color_hex, color_mode from public.yarn_colors where catalog_id = p_from on conflict do nothing;
  delete from public.yarn_colors where catalog_id = p_from;
  update public.yarn_catalog t set aliases = array(select distinct x from unnest(t.aliases || f.aliases) x), norm_keys = array(select distinct x from unnest(t.norm_keys || f.norm_keys) x), uses = t.uses + f.uses, updated_at = now()
    from public.yarn_catalog f where t.id = p_into and f.id = p_from;
  update public.yarn_catalog set merged_into = p_into, updated_at = now() where id = p_from;
  perform public.admin_log('yarn_merge', 'yarn', p_from::text, jsonb_build_object('into', p_into));
end $function$;

-- admin_yarn_photos_apply(p jsonb)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_yarn_photos_apply(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare y jsonb; cid uuid; n_ok int := 0; n_miss int := 0; n_nocol int := 0; hx text[]; k text;
begin
  if auth.uid() is not null and not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  for y in select * from jsonb_array_elements(p) loop
    k := public.yarn_norm(coalesce(y->>'brand','')||(y->>'product'));
    select t.id into cid from public.yarn_catalog t where t.merged_into is null and (t.norm_keys && array[k] or (t.norm_keys && array[public.yarn_norm(y->>'product')] and (t.brand = y->>'brand' or t.brand is null))) order by (t.brand = y->>'brand') desc, (t.status='verified') desc limit 1;
    if cid is null then n_miss := n_miss + 1; continue; end if;
    if jsonb_typeof(y->'hex')='array' then select array_agg(e) into hx from jsonb_array_elements_text(y->'hex') e; else hx := null; end if;
    update public.yarn_colors yc set photo = y->>'file', color_hex = public.color_hex_clean(hx), color_mode = case when hx is null then null when y->>'mode' in ('solid','gradient','mix','melange') then y->>'mode' else 'solid' end
      where yc.catalog_id = cid and ((nullif(y->>'no','') is not null and yc.no = y->>'no') or (nullif(y->>'no','') is null and yc.name = y->>'name'));
    if found then n_ok := n_ok + 1;
    else
      insert into public.yarn_colors(catalog_id, no, name, photo, color_hex, color_mode) values (cid, nullif(y->>'no',''), left(coalesce(nullif(y->>'name',''), y->>'no'),40), y->>'file', public.color_hex_clean(hx), case when hx is null then null else 'solid' end) on conflict do nothing;
      n_nocol := n_nocol + 1;
    end if;
  end loop;
  return jsonb_build_object('linked', n_ok, 'added', n_nocol, 'yarn_missing', n_miss);
end $function$;

-- admin_yarn_queue()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_yarn_queue()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with st as (
    select s.id, s.owner_id, s.raw_name, s.read_json, s.read_status, coalesce(s.ball_g, (s.read_json->>'ball_g')::numeric) g, coalesce(s.ball_m, (s.read_json->>'ball_m')::numeric) m,
      coalesce(s.fibers, case when jsonb_typeof(s.read_json->'fibers')='object' then s.read_json->'fibers' end) f, s.read_json->>'brand' brand, coalesce(s.color, s.read_json->>'color_no') color,
      coalesce('n:'||public.yarn_norm(s.raw_name), 's:'||md5(concat_ws('|', lower(coalesce(s.read_json->>'brand','')), (s.read_json->>'ball_g'), (s.read_json->>'ball_m'), (s.read_json->'fibers')::text))) gkey
    from public.yarn_stash s where s.catalog_id is null
  ), sg as (
    select gkey, max(raw_name) raw_name, max(brand) brand, max(g) g, max(m) m, (array_agg(f) filter (where f is not null))[1] f, count(*) n, count(distinct owner_id) members,
      array_agg(distinct color) filter (where color is not null) colors, array_agg(id) ids, count(*) filter (where read_status='failed') failed
    from st group by gkey
  ), we as (
    select e.norm_name gkey, max(e.raw_name) raw_name, max(e.ball_g) g, max(e.ball_m) m, (array_agg(e.fibers) filter (where e.fibers is not null))[1] f, count(*) n, count(distinct w.profile_id) members,
      array_agg(distinct e.color) filter (where e.color is not null) colors, max(e.catalog_id::text)::uuid auto_id
    from public.yarn_entries e left join public.yarn_catalog c on c.id = e.catalog_id left join public.works w on w.id = e.work_id
    where coalesce(e.source,'') <> 'stash' and (e.catalog_id is null or c.status = 'auto') and e.norm_name is not null group by 1
  ), g as (
    select 'stash' kind, 'stash:'||gkey key, coalesce(raw_name, concat_ws(' ', brand, case when g is not null then g||'g' end, case when m is not null then m||'m' end, (select string_agg(k||v, '/') from jsonb_each_text(f) t(k,v)))) label,
      brand, g, m, f, n, members, colors, ids, failed, null::uuid auto_id from sg
    union all
    select 'work', 'work:'||gkey, raw_name, null, g, m, f, n, members, colors, null, 0, auto_id from we
  )
  select case when not public.is_admin() then null else jsonb_build_object(
    'stats', jsonb_build_object(
      'stash_rows', (select count(*) from public.yarn_stash), 'stash_members', (select count(distinct owner_id) from public.yarn_stash),
      'stash_matched', (select count(*) from public.yarn_stash where catalog_id is not null), 'stash_failed', (select count(*) from public.yarn_stash where read_status='failed'), 'stash_pending', (select count(*) from public.yarn_stash where read_status='pending'),
      'entries', (select count(*) from public.yarn_entries where coalesce(source,'')<>'stash'), 'entries_matched', (select count(*) from public.yarn_entries e join public.yarn_catalog c on c.id=e.catalog_id where coalesce(e.source,'')<>'stash' and c.status='verified'),
      'groups', (select count(*) from g)),
    'groups', (select coalesce(jsonb_agg(jsonb_build_object('kind', g.kind, 'key', g.key, 'label', g.label, 'brand', g.brand, 'g', g.g, 'm', g.m, 'fibers', g.f, 'n', g.n, 'members', g.members, 'colors', (select array_agg(x) from unnest(g.colors) with ordinality u(x,o) where o <= 6), 'failed', g.failed, 'auto_id', g.auto_id,
        'suggest', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'name', r.name, 'score', r.score)), '[]') from public.yarn_match_spec(g.brand, g.g, g.m, g.f, g.colors[1], 3) r)) order by g.members desc, g.n desc), '[]')
      from (select * from g order by members desc, n desc limit 100) g)
  ) end;
$function$;

-- admin_yarn_queue_link(p_key text, p_catalog uuid, p_alias text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_yarn_queue_link(p_key text, p_catalog uuid, p_alias text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare kind text; gkey text; c public.yarn_catalog; n int := 0; r record; cid uuid; auto_id uuid;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  select * into c from public.yarn_catalog where id = p_catalog and merged_into is null; if c.id is null then raise exception '실을 찾을 수 없어요'; end if;
  kind := split_part(p_key, ':', 1); gkey := substr(p_key, length(kind) + 2);
  if kind = 'stash' then
    for r in select s.* from public.yarn_stash s where s.catalog_id is null
      and coalesce('n:'||public.yarn_norm(s.raw_name), 's:'||md5(concat_ws('|', lower(coalesce(s.read_json->>'brand','')), (s.read_json->>'ball_g'), (s.read_json->>'ball_m'), (s.read_json->'fibers')::text))) = gkey loop
      if r.raw_name is not null and r.raw_name <> coalesce(c.brand||' ','')||c.product then perform public.yarn_add_alias(p_catalog, r.raw_name); end if;
      update public.yarn_stash set catalog_id = p_catalog, raw_name = coalesce(raw_name, coalesce(c.brand||' ','')||c.product),
        ball_g = coalesce(ball_g, nullif((read_json->>'ball_g'),'')::numeric, c.ball_g), ball_m = coalesce(ball_m, nullif((read_json->>'ball_m'),'')::numeric, c.ball_m),
        fibers = coalesce(fibers, case when jsonb_typeof(read_json->'fibers')='object' then read_json->'fibers' end, c.fibers),
        color = coalesce(color, read_json->>'color_no'), read_status = case when read_status in ('failed','pending') then 'done' else read_status end
        where id = r.id;
      cid := public.yarn_log_entry(null, jsonb_strip_nulls(jsonb_build_object('name', coalesce(c.brand||' ','')||c.product, 'color', coalesce(r.color, r.read_json->>'color_no'), 'ball_g', coalesce(r.ball_g, c.ball_g), 'ball_m', coalesce(r.ball_m, c.ball_m), 'fibers', coalesce(r.fibers, c.fibers))), null, null, null, null, null);
      update public.yarn_entries set source = 'stash' where id = (select max(id) from public.yarn_entries where catalog_id = cid and work_id is null and source = 'work');
      n := n + 1;
    end loop;
  elsif kind = 'work' then
    select max(e.catalog_id::text)::uuid into auto_id from public.yarn_entries e join public.yarn_catalog t on t.id = e.catalog_id where e.norm_name = gkey and t.status = 'auto' and t.id <> p_catalog;
    if auto_id is not null then perform public.admin_yarn_merge(auto_id, p_catalog); end if;
    update public.yarn_entries set catalog_id = p_catalog where norm_name = gkey and (catalog_id is null or catalog_id <> p_catalog); get diagnostics n = row_count;
    perform public.yarn_add_alias(p_catalog, (select max(raw_name) from public.yarn_entries where norm_name = gkey));
    update public.yarn_catalog set uses = (select count(*) from public.yarn_entries where catalog_id = p_catalog) where id = p_catalog;
  else raise exception '알 수 없는 묶음'; end if;
  if nullif(btrim(coalesce(p_alias,'')),'') is not null then perform public.yarn_add_alias(p_catalog, p_alias); end if;
  perform public.admin_log('yarn_queue_link', 'yarn', p_catalog::text, jsonb_build_object('key', p_key, 'rows', n));
  return jsonb_build_object('linked', n);
end $function$;

-- admin_yarn_set_gauge(p_id uuid, p_knit jsonb, p_crochet jsonb, p_clear boolean)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_yarn_set_gauge(p_id uuid, p_knit jsonb DEFAULT NULL::jsonb, p_crochet jsonb DEFAULT NULL::jsonb, p_clear boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  update public.yarn_catalog set
    gauge_knit = case when p_clear and p_knit is null then null when jsonb_typeof(p_knit)='object' then jsonb_strip_nulls(p_knit) else gauge_knit end,
    gauge_crochet = case when p_clear and p_crochet is null then null when jsonb_typeof(p_crochet)='object' then jsonb_strip_nulls(p_crochet) else gauge_crochet end,
    updated_at = now() where id = p_id;
  perform public.admin_log('yarn_gauge', 'yarn', p_id::text, jsonb_build_object('knit', p_knit, 'crochet', p_crochet));
end $function$;

-- admin_yarn_set_kind(p_id uuid, p_texture text, p_use_tags text[])  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_yarn_set_kind(p_id uuid, p_texture text, p_use_tags text[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  update public.yarn_catalog set texture = nullif(p_texture,''), use_tags = coalesce(p_use_tags,'{}'), updated_at = now() where id = p_id;
  perform public.admin_log('yarn_update', 'yarn', p_id::text, jsonb_build_object('texture', p_texture, 'use_tags', p_use_tags));
end $function$;

-- admin_yarn_stats()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_yarn_stats()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when not public.is_admin() then null else jsonb_build_object(
    'yarns', (select count(*) from yarn_catalog where merged_into is null),
    'verified', (select count(*) from yarn_catalog where merged_into is null and status='verified'),
    'auto', (select count(*) from yarn_catalog where merged_into is null and status='auto'),
    'brands', (select count(distinct brand) from yarn_catalog where merged_into is null and brand is not null),
    'colors', (select count(*) from yarn_colors),
    'colors_photo', (select count(*) from yarn_colors where photo is not null),
    'entries', (select count(*) from yarn_entries),
    'entries_30d', (select count(*) from yarn_entries where created_at > now() - interval '30 days' and coalesce(source,'') <> 'stash'),
    'entries_stash', (select count(*) from yarn_entries where source='stash'),
    'stash_rows', (select count(*) from yarn_stash),
    'no_spec', (select count(*) from yarn_catalog where merged_into is null and (ball_g is null or ball_m is null)),
    'no_texture', (select count(*) from yarn_catalog where merged_into is null and texture is null),
    'no_colors', (select count(*) from yarn_catalog c where merged_into is null and not exists (select 1 from yarn_colors yc where yc.catalog_id=c.id)),
    'brands_tbl', (select coalesce(jsonb_agg(jsonb_build_object('brand', b.brand, 'yarns', b.n, 'colors', b.cn, 'photos', b.pn, 'uses', b.u) order by b.n desc), '[]') from (
        select coalesce(c.brand,'(브랜드 없음)') brand, count(distinct c.id) n, count(yc.id) cn, count(yc.photo) pn, sum(distinct c.uses) u
        from yarn_catalog c left join yarn_colors yc on yc.catalog_id=c.id where c.merged_into is null group by 1) b),
    'top_30d', (select coalesce(jsonb_agg(jsonb_build_object('name', t.name, 'n', t.n) order by t.n desc), '[]') from (
        select coalesce(c.brand||' ','')||c.product name, count(*) n from yarn_entries e join yarn_catalog c on c.id=e.catalog_id where e.created_at > now() - interval '30 days' and coalesce(e.source,'') <> 'stash' group by 1 order by 2 desc limit 10) t),
    'items', (select coalesce(jsonb_agg(jsonb_build_object('k', t.k, 'n', t.n) order by t.n desc), '[]') from (select item_type k, count(*) n from yarn_entries where item_type is not null group by 1 order by 2 desc limit 10) t)
  ) end;
$function$;

-- admin_yarn_update(p jsonb)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_yarn_update(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cid uuid := nullif(p->>'id','')::uuid; al text[]; num constant text := '^[0-9]{1,5}(\.[0-9]{1,2})?$';
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  al := case when jsonb_typeof(p->'aliases')='array' then array(select distinct left(btrim(x),60) from jsonb_array_elements_text(p->'aliases') x where btrim(x) <> '') end;
  if cid is null then
    insert into public.yarn_catalog(brand, product, aliases, norm_keys, status) values (nullif(btrim(p->>'brand'),''), btrim(p->>'product'), coalesce(al, array[btrim(p->>'product')]), '{}', 'verified') returning id into cid;
  end if;
  update public.yarn_catalog c set
    brand = case when p ? 'brand' then nullif(left(btrim(p->>'brand'),40),'') else brand end,
    product = coalesce(nullif(left(btrim(coalesce(p->>'product','')),60),''), product),
    product_en = case when p ? 'product_en' then nullif(left(btrim(p->>'product_en'),60),'') else product_en end,
    aliases = coalesce(al, aliases),
    ball_g = case when p ? 'ball_g' then (case when (p->>'ball_g') ~ num then (p->>'ball_g')::numeric end) else ball_g end,
    ball_m = case when p ? 'ball_m' then (case when (p->>'ball_m') ~ num then (p->>'ball_m')::numeric end) else ball_m end,
    weight_class = case when p ? 'weight_class' then nullif(left(btrim(p->>'weight_class'),20),'') else weight_class end,
    fiber_main = case when p ? 'fiber_main' then nullif(left(btrim(p->>'fiber_main'),20),'') else fiber_main end,
    fibers = case when p ? 'fibers' then (case when jsonb_typeof(p->'fibers')='object' then p->'fibers' end) else fibers end,
    shop = case when p ? 'shop' then nullif(left(btrim(p->>'shop'),40),'') else shop end,
    source_url = case when p ? 'source_url' then nullif(left(btrim(p->>'source_url'),300),'') else source_url end,
    season = case when p ? 'season' then nullif(left(btrim(p->>'season'),10),'') else season end,
    needle_knit = case when p ? 'needle_knit' then nullif(left(btrim(p->>'needle_knit'),30),'') else needle_knit end,
    needle_crochet = case when p ? 'needle_crochet' then nullif(left(btrim(p->>'needle_crochet'),30),'') else needle_crochet end,
    gauge = case when p ? 'gauge' then nullif(left(btrim(p->>'gauge'),60),'') else gauge end,
    put_up = case when p ? 'put_up' then nullif(left(btrim(p->>'put_up'),40),'') else put_up end,
    texture = case when p ? 'texture' then nullif(left(btrim(p->>'texture'),30),'') else texture end,
    use_tags = case when p ? 'use_tags' and jsonb_typeof(p->'use_tags')='array' then array(select jsonb_array_elements_text(p->'use_tags')) else use_tags end,
    status = coalesce(nullif(p->>'status',''), status), updated_at = now()
  where c.id = cid;
  update public.yarn_catalog c set norm_keys = array(select distinct k from unnest(array(select public.yarn_norm(a) from unnest(c.aliases) a) || public.yarn_norm(c.product) || public.yarn_norm(coalesce(c.brand,'')||c.product)) k where k is not null) where c.id = cid;
  perform public.admin_log('yarn_update', 'yarn', cid::text, p);
  return cid;
end $function$;

-- admins_change_alert()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admins_change_alert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_who text; v_by text; t text;
begin
  select nickname into v_who from public.profiles where id = coalesce(new.profile_id, old.profile_id);
  select nickname into v_by from public.profiles where id = auth.uid();
  t := format('🚨 보안 알림: 관리자 목록이 바뀌었어요.'||E'\n'||'무엇: 관리자 %s — %s'||E'\n'||'누가: %s'||E'\n'||'언제: %s (KST)'||E'\n\n'||
              '대표가 직접 한 일이면 무시하세요. 아니면 ① 콘솔 › 관리자에서 바로 되돌리고 ② Supabase 대시보드 › Authentication 에서 그 관리자 계정의 세션을 끊고 ③ 구글·애플 계정 비밀번호와 2단계 인증을 확인하세요. 관리자 추가·삭제는 admin_logs 에 남고, 이 알림은 access_logs 와 함께 사고 대응 근거가 됩니다.',
              case tg_op when 'INSERT' then '추가' else '삭제' end, coalesce(v_who, coalesce(new.profile_id, old.profile_id)::text),
              coalesce(v_by, '서비스 키 또는 SQL(대시보드)'), to_char(now() at time zone 'Asia/Seoul', 'YYYY-MM-DD HH24:MI'));
  insert into public.jigi_reminders(due_at, text) values (now(), t);
  begin perform public.jigi_remind_call('tick'); exception when others then null; end;
  return null;
end $function$;

-- ai_decide_shop_claim(p_id uuid, p_approve boolean, p_reason text, p_check jsonb, p_via text)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.ai_decide_shop_claim(p_id uuid, p_approve boolean, p_reason text, p_check jsonb, p_via text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if p_check is not null then update public.shop_claims set ai_check = p_check where id = p_id; end if;
  return public._decide_shop_claim(p_id, p_approve, p_reason, 'e120eb67-b254-4008-92d8-08c95c821e9e', p_via);
end $function$;

-- apply_author(p_real_name text, p_link text, p_note text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.apply_author(p_real_name text, p_link text, p_note text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me public.profiles; aid uuid; adv integer;
begin
  select * into me from public.profiles where id = auth.uid();
  if me.id is null then raise exception '로그인이 필요합니다'; end if;
  if me.suspended_at is not null then raise exception '정지된 계정입니다'; end if;
  if me.is_author then raise exception '이미 작가입니다'; end if;
  adv := public.author_adv_count(me.id);
  if adv < 3 then raise exception '전문(5단계) 기법으로 뜬 완성작품 인증 3개부터 신청할 수 있어요 (지금 %개)', adv; end if;
  insert into public.author_applications(profile_id, real_name, link, note)
  values (me.id, btrim(p_real_name), nullif(btrim(p_link),''), nullif(btrim(p_note),'')) returning id into aid;
  return aid;
end $function$;

-- apply_class(p_post uuid, p_note text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.apply_class(p_post uuid, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid := auth.uid(); sp public.shop_posts; host uuid; ex public.class_applications; n_acc integer; mx integer; starts timestamptz;
begin
  if uid is null then raise exception '로그인이 필요해요'; end if;
  select * into sp from public.shop_posts where id = p_post;
  if sp.id is null or sp.kind <> 'class' or sp.hidden then raise exception '클래스를 찾을 수 없어요'; end if;
  host := public.class_host(p_post);
  if host = uid then raise exception '내가 연 클래스에는 신청할 수 없어요'; end if;
  starts := nullif(sp.extra->>'starts_at','')::timestamptz;
  if starts is not null and starts < now() then raise exception '이미 시작한 클래스예요'; end if;
  if sp.ends_at is not null and sp.ends_at < now() then raise exception '모집이 마감됐어요'; end if;
  select * into ex from public.class_applications where post_id = p_post and profile_id = uid;
  if ex.id is not null and ex.status in ('applied','accepted') then raise exception '이미 신청했어요'; end if;
  if ex.id is not null and ex.status = 'rejected' then raise exception '이 클래스는 다시 신청할 수 없어요'; end if;
  if ex.id is not null then update public.class_applications set status = 'applied', note = left(p_note, 300), created_at = now(), decided_at = null, host_note = null where id = ex.id;
  else insert into public.class_applications(post_id, profile_id, note) values (p_post, uid, left(p_note, 300)); end if;
  mx := nullif(sp.extra->>'max','')::int; select count(*) into n_acc from public.class_applications where post_id = p_post and status = 'accepted';
  insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
    values (host, uid, 'notice', format('「%s」 클래스에 신청이 왔어요 (%s). 눌러서 확정해 주세요', left(sp.title, 40), (select nickname from public.profiles where id = uid)), jsonb_build_object('type','class_manage','id',p_post));
  return jsonb_build_object('ok', true, 'accepted', n_acc, 'max', mx);
end $function$;

-- apply_event(p_event uuid, p_note text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.apply_event(p_event uuid, p_note text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare e public.events; v_lv integer; v_susp timestamptz; v_status text := 'applied';
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  select * into e from public.events where id = p_event for update;
  if e.id is null or e.status <> 'open' then raise exception '신청할 수 없는 이벤트예요'; end if;
  if now() < e.apply_from or now() > e.apply_until then raise exception '신청 기간이 아니에요'; end if;
  select act_level, suspended_at into v_lv, v_susp from public.profiles where id = auth.uid();
  if v_susp is not null then raise exception '이용이 제한된 계정이에요'; end if;
  if coalesce(v_lv,0) < e.min_level then raise exception 'Lv.% 부터 신청할 수 있어요', e.min_level; end if;
  if e.select_mode = 'first' then
    if e.capacity is not null and public.event_selected_count(e.id) >= e.capacity then raise exception '선착순 마감됐어요'; end if;
    v_status := 'selected';
  end if;
  insert into public.event_applications(event_id, profile_id, note, level_at, status, decided_at)
    values (e.id, auth.uid(), nullif(left(btrim(coalesce(p_note,'')),200),''), coalesce(v_lv,0), v_status, case when v_status='selected' then now() end)
    on conflict (event_id, profile_id) do update set status = excluded.status, note = excluded.note, level_at = excluded.level_at, decided_at = excluded.decided_at, created_at = now()
      where public.event_applications.status = 'cancelled';
  if not found then raise exception '이미 신청했어요'; end if;
  return v_status;
end $function$;

-- author_adv_count(p_user uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.author_adv_count(p_user uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select count(*)::int from public.works w where w.profile_id = p_user
    and exists (select 1 from public.techniques t where t.id = any(w.techniques) and t.level >= 5);
$function$;

-- author_settlement()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.author_settlement()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid := auth.uid(); out jsonb;
begin
  if uid is null then raise exception 'not signed in'; end if;
  select jsonb_build_object(
    'months', coalesce((select jsonb_agg(jsonb_build_object('month', m.ym, 'n', m.n, 'gross', m.gross, 'store_fee', m.store_fee, 'platform_fee', m.platform_fee, 'tax', m.tax, 'author_amt', m.author_amt) order by m.ym desc)
        from (select to_char(pp.created_at at time zone 'Asia/Seoul', 'YYYY-MM') as ym, count(*) as n, sum(pp.price) as gross, sum(pp.store_fee) as store_fee, sum(pp.platform_fee) as platform_fee, sum(pp.tax) as tax, sum(pp.author_amt) as author_amt
              from public.pattern_purchases pp join public.patterns p on p.id = pp.pattern_id where p.author_id = uid group by to_char(pp.created_at at time zone 'Asia/Seoul', 'YYYY-MM')) m), '[]'::jsonb),
    'total', (select jsonb_build_object('n', count(*), 'gross', coalesce(sum(pp.price),0), 'author_amt', coalesce(sum(pp.author_amt),0)) from public.pattern_purchases pp join public.patterns p on p.id = pp.pattern_id where p.author_id = uid),
    'recent', coalesce((select jsonb_agg(jsonb_build_object('title', p.title, 'price', pp.price, 'author_amt', pp.author_amt, 'buyer', pr.nickname, 'via', pp.via, 'created_at', pp.created_at) order by pp.created_at desc)
        from (select * from public.pattern_purchases pp0 where exists (select 1 from public.patterns p0 where p0.id = pp0.pattern_id and p0.author_id = uid) order by pp0.created_at desc limit 10) pp join public.patterns p on p.id = pp.pattern_id left join public.profiles pr on pr.id = pp.profile_id), '[]'::jsonb),
    'by_pattern', coalesce((select jsonb_agg(jsonb_build_object('pattern_id', p.id, 'title', p.title, 'price', p.price, 'n', c.n, 'author_amt', c.amt) order by c.n desc) from public.patterns p join lateral (select count(*) as n, coalesce(sum(author_amt),0) as amt from public.pattern_purchases where pattern_id = p.id) c on true where p.author_id = uid and c.n > 0), '[]'::jsonb),
    'payout_day', to_char((date_trunc('month', now() at time zone 'Asia/Seoul') + interval '1 month 14 days')::date, 'YYYY-MM-DD')
  ) into out;
  return out;
end $function$;

-- author_upsert_pattern(p jsonb)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.author_upsert_pattern(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me public.profiles; pid uuid; txt text; cat uuid;
begin
  select * into me from public.profiles where id = auth.uid();
  if me.id is null or not me.is_author then raise exception '작가만 도안을 등록할 수 있어요'; end if;
  if me.suspended_at is not null then raise exception '정지된 계정입니다'; end if;
  txt := lower(coalesce(p->>'title','')||' '||coalesce(p->>'descr',''));
  if exists (select 1 from public.banned_words b where txt like '%'||lower(b.word)||'%') then raise exception '사용할 수 없는 표현이 들어 있어요'; end if;
  if jsonb_array_length(coalesce(p->'photos','[]'::jsonb)) > 4 then raise exception '사진은 4장까지 올릴 수 있어요'; end if;
  if nullif(p->>'catalog_id','') is not null then select id into cat from public.yarn_catalog where id = (p->>'catalog_id')::uuid and merged_into is null; end if;
  if (p->>'id') is not null then
    pid := (p->>'id')::uuid;
    update public.patterns set title = p->>'title', descr = nullif(p->>'descr',''), craft = p->>'craft', level = (p->>'level')::smallint,
      techniques = array(select jsonb_array_elements_text(coalesce(p->'techniques','[]'::jsonb))),
      photos = array(select jsonb_array_elements_text(coalesce(p->'photos','[]'::jsonb))),
      yarn_weight = nullif(p->>'yarn_weight',''), needle_size = nullif(p->>'needle_size',''),
      price = coalesce((p->>'price')::int,0), buy_url = nullif(p->>'buy_url',''), is_published = coalesce((p->>'is_published')::boolean,true),
      gauge = case when p ? 'gauge' then public.gauge_clean(p->'gauge') else gauge end,
      catalog_id = case when p ? 'catalog_id' then cat else catalog_id end, updated_at = now()
    where id = pid and author_id = me.id;
    if not found then raise exception '내 도안만 수정할 수 있어요'; end if;
  else
    if (select count(*) from public.patterns where author_id = me.id and created_at > now() - interval '1 day') >= 20 then raise exception '하루에 등록할 수 있는 도안 수를 넘었어요'; end if;
    insert into public.patterns(author_id, title, descr, craft, level, techniques, photos, yarn_weight, needle_size, price, buy_url, is_published, gauge, catalog_id)
    values (me.id, p->>'title', nullif(p->>'descr',''), p->>'craft', (p->>'level')::smallint,
      array(select jsonb_array_elements_text(coalesce(p->'techniques','[]'::jsonb))), array(select jsonb_array_elements_text(coalesce(p->'photos','[]'::jsonb))),
      nullif(p->>'yarn_weight',''), nullif(p->>'needle_size',''), coalesce((p->>'price')::int,0), nullif(p->>'buy_url',''), coalesce((p->>'is_published')::boolean,true),
      public.gauge_clean(p->'gauge'), cat)
    returning id into pid;
  end if;
  return pid;
end $function$;

-- award_points(p_user uuid, p_kind text, p_ref_table text, p_ref_id text, p_at timestamp with time zone)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.award_points(p_user uuid, p_kind text, p_ref_table text, p_ref_id text, p_at timestamp with time zone DEFAULT now())
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.supporters; seg smallint; d date; pts integer; today_sum integer; cap_pts integer;
begin
  s := public.supporter_of(p_user); if s.id is null then return 0; end if;
  if p_at < s.started_at or p_at >= s.ends_at then return 0; end if;
  seg := public.supporter_segment(s.started_at, p_at); if seg = 0 then return 0; end if;
  d := public.kst_date(p_at);
  pts := case p_kind when 'attendance' then 1 when 'work_verified' then 10 when 'post' then 3 when 'comment' then 1 when 'survey' then 10 when 'bug_accepted' then 10 when 'referral' then 20 else null end;
  if pts is null then return 0; end if;
  cap_pts := case p_kind when 'attendance' then 1 when 'work_verified' then 10 when 'post' then 3 when 'comment' then 2 else null end;
  if exists (select 1 from public.point_events e where e.kind = p_kind and e.ref_table = p_ref_table and e.ref_id = p_ref_id) then return 0; end if;
  if cap_pts is not null then
    select coalesce(sum(points),0) into today_sum from public.point_events e where e.supporter_id = s.id and e.kind = p_kind and e.kst_date = d;
    if today_sum + pts > cap_pts then return 0; end if;
  end if;
  insert into public.point_events(supporter_id, user_id, kind, points, ref_table, ref_id, kst_date, segment, created_at) values (s.id, p_user, p_kind, pts, p_ref_table, p_ref_id, d, seg, p_at);
  perform public.supporter_cheer(s.id, seg);
  return pts;
end $function$;

-- broadcast_run_due()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.broadcast_run_due()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; n integer := 0;
begin
  for r in select id from public.broadcasts where status = 'scheduled' and schedule_at <= now() order by schedule_at loop
    n := n + public._bc_deliver(r.id);
  end loop;
  return n;
end $function$;

-- cancel_class_application(p_post uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.cancel_class_application(p_post uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid := auth.uid(); a public.class_applications; sp public.shop_posts;
begin
  select * into a from public.class_applications where post_id = p_post and profile_id = uid;
  if a.id is null or a.status not in ('applied','accepted') then raise exception '취소할 신청이 없어요'; end if;
  update public.class_applications set status = 'cancelled', decided_at = now() where id = a.id;
  select * into sp from public.shop_posts where id = p_post;
  if sp.room_id is not null then delete from public.room_members where room_id = sp.room_id and profile_id = uid; end if;
  insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
    values (public.class_host(p_post), uid, 'notice', format('%s님이 「%s」 클래스 신청을 취소했어요', (select nickname from public.profiles where id = uid), left(sp.title, 40)), jsonb_build_object('type','class_manage','id',p_post));
end $function$;

-- cancel_event_application(p_event uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.cancel_event_application(p_event uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update public.event_applications set status = 'cancelled' where event_id = p_event and profile_id = auth.uid() and status in ('applied','selected');
  if not found then raise exception '취소할 신청이 없어요'; end if;
  delete from public.event_shipping s using public.event_applications a where s.application_id = a.id and a.event_id = p_event and a.profile_id = auth.uid() and s.shipped_at is null;
end $function$;

-- cancel_meetup(p_meetup_id uuid, p_note text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.cancel_meetup(p_meetup_id uuid, p_note text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_room uuid; v_title text; v_starts timestamptz; v_note text := nullif(btrim(left(coalesce(p_note,''), 200)), '');
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  select room_id, title, starts_at into v_room, v_title, v_starts from public.meetups where id = p_meetup_id and created_by = auth.uid();
  if v_room is null then raise exception '주최자만 취소할 수 있어요'; end if;
  if v_starts < now() then raise exception '이미 끝난 모임은 취소할 수 없어요'; end if;
  insert into public.notifications(recipient_id, actor_id, kind, snippet)
    select rm.profile_id, auth.uid(), 'meetup_cancel', left(v_title || coalesce(' · ' || v_note, ''), 80)
    from public.room_members rm where rm.room_id = v_room and rm.profile_id <> auth.uid() and not public.is_blocked(rm.profile_id, auth.uid());
  delete from public.posts where meetup_id = p_meetup_id and author_id = auth.uid();
  delete from public.meetups where id = p_meetup_id;
  insert into public.messages (room_id, sender_id, body) values (v_room, auth.uid(), '❌ 모임 "' || v_title || '" 이(가) 취소됐어요' || coalesce(E'\n' || v_note, ''));
end $function$;

-- cancel_my_order(p_id uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.cancel_my_order(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o record; x jsonb;
begin
  select * into o from public.orders where id = p_id and profile_id = auth.uid();
  if o.id is null then raise exception '주문을 찾을 수 없어요'; end if;
  if o.status <> 'pending_payment' then raise exception '입금 확인 전 주문만 취소할 수 있어요'; end if;
  for x in select * from jsonb_array_elements(o.items) loop update public.shop_products set stock = stock + (x->>'qty')::int where id = (x->>'product_id')::uuid; end loop;
  update public.orders set status = 'cancelled', updated_at = now() where id = p_id;
end $function$;

-- chat_flag_ai_apply(p_id bigint, p_ai jsonb)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.chat_flag_ai_apply(p_id bigint, p_ai jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare f public.chat_flags; m public.messages; v_risk text := lower(coalesce(p_ai->>'risk','')); v_text text; v_from text; v_room text;
begin
  select * into f from public.chat_flags where id = p_id; if f.id is null then return null; end if;
  if p_ai is not null then
    update public.chat_flags set ai = jsonb_build_object('risk', v_risk, 'reason', left(coalesce(p_ai->>'reason',''), 200)),
      level = case when level = 'check' and v_risk = 'high' then 'urgent' when level = 'check' and v_risk = 'low' then 'info' else level end,
      warn = case when level = 'check' and v_risk = 'low' then null else warn end
      where id = p_id returning * into f;
  end if;
  if f.level = 'urgent' and f.alerted_at is null and f.status = 'open' then
    update public.chat_flags set alerted_at = now() where id = p_id;
    select * into m from public.messages where id = f.message_id;
    select nickname into v_from from public.profiles where id = f.sender_id;
    select case when r.kind = 'group' then '단체방 「'||coalesce(nullif(r.title,''), (select title from public.meetups where room_id = r.id limit 1), '모임 채팅')||'」' else '1:1 채팅' end into v_room from public.rooms r where r.id = f.room_id;
    v_text := '🚨 채팅 점검 — 긴급 1건'||E'\n\n'||
      '무엇이 걸렸나요: '||array_to_string(f.rules, ' · ')||E'\n'||
      '보낸 회원: '||coalesce(v_from,'(알 수 없음)')||' · '||coalesce(v_room,'')||E'\n'||
      case when f.ai is not null and coalesce(f.ai->>'reason','') <> '' then 'AI 판단: '||(f.ai->>'reason')||E'\n' else '' end||E'\n'||
      '걸린 메시지(숫자·연락처는 가렸어요):'||E'\n'||'「'||public._chat_mask(left(coalesce(m.body,''), 300))||'」'||E'\n\n'||
      '왜 알려 드리나요: 채팅은 평소에 아무도 읽지 않고 기계가 위험 신호만 찾는데, 이 메시지는 돈 요구·위협·미성년자 보호처럼 바로 확인이 필요한 유형으로 분류됐어요. 받는 회원에게는 메시지 아래에 주의 문구가 이미 붙어 있을 수 있어요.'||E'\n\n'||
      '지금 하실 일: 콘솔 › 오늘 › 채팅 점검에서 이 건을 열면 걸린 메시지와 앞뒤 몇 줄이 보여요. 문제가 없으면 [문제없음], 문제가 있으면 [경고 보내기]·[채팅 제한]·[정지] 중에서 고르세요. 더 봐야 하면 사유를 적고 대화 전체를 열 수 있어요(열람 기록이 남아요).'||E'\n'||
      'https://yesbeyesnono.github.io/knit-neighbors/admin.html#today';
  end if;
  return jsonb_build_object('level', f.level, 'telegram', v_text);
end $function$;

-- chat_flag_ai_payload(p_id bigint)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.chat_flag_ai_payload(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare f public.chat_flags; m public.messages;
begin
  select * into f from public.chat_flags where id = p_id; if f.id is null then return null; end if;
  select * into m from public.messages where id = f.message_id; if m.id is null then return null; end if;
  return jsonb_build_object('id', f.id, 'level', f.level, 'rules', to_jsonb(f.rules), 'alerted', f.alerted_at is not null, 'hit', public._chat_mask(left(m.body, 400)),
    'before', coalesce((select jsonb_agg(jsonb_build_object('mine', x.sender_id = m.sender_id, 'body', public._chat_mask(left(x.body, 200))) order by x.created_at)
      from (select * from public.messages x where x.room_id = m.room_id and x.created_at < m.created_at order by x.created_at desc limit 2) x), '[]'::jsonb),
    'group', (select kind = 'group' from public.rooms where id = f.room_id));
end $function$;

-- chat_push(p_msg bigint)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.chat_push(p_msg bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_secret text; v_room uuid; v_sender uuid;
begin
  begin
    select room_id, sender_id into v_room, v_sender from public.messages where id = p_msg;
    if v_room is null then return; end if;
    if exists (select 1 from public.room_members rm join public.device_tokens d on d.profile_id = rm.profile_id and d.disabled_at is null where rm.room_id = v_room and rm.profile_id <> v_sender) then
      select value into v_secret from public.jigi_config where key = 'hook_secret';
      perform net.http_post(url := 'https://thfcrodfaitzrzlrxyir.supabase.co/functions/v1/push-send',
        body := jsonb_build_object('route','chat','message_id', p_msg), headers := jsonb_build_object('Content-Type','application/json','x-jigi-secret', v_secret), timeout_milliseconds := 8000);
    end if;
  exception when others then null;
  end;
end $function$;

-- chat_restrict_guard()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.chat_restrict_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_until timestamptz;
begin
  if auth.uid() is null or new.sender_id is distinct from auth.uid() then return new; end if;
  select chat_restricted_until into v_until from public.profiles where id = new.sender_id;
  if v_until is not null and v_until > now()
     and not exists (select 1 from public.room_members s where s.room_id = new.room_id and s.profile_id = 'e120eb67-b254-4008-92d8-08c95c821e9e'::uuid) then
    raise exception '채팅이 %까지 잠시 제한됐어요. 궁금한 점은 설정 › 지기에게 말하기로 알려 주세요', to_char(v_until at time zone 'Asia/Seoul', 'FMMM"월" FMDD"일"') using errcode = 'P0001';
  end if;
  return new;
end $function$;

-- chat_scan_message()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.chat_scan_message()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e'; v record; v_id bigint; v_secret text;
begin
  begin
    if not public._chat_scan_on() or new.sender_id is null or new.sender_id = sup or coalesce(new.body,'') = '' then return null; end if;
    if exists (select 1 from public.room_members s where s.room_id = new.room_id and s.profile_id = sup) then return null; end if;
    select * into v from public._chat_rules(new.body, new.sender_id, new.room_id);
    if v.level is null then return null; end if;
    insert into public.chat_flags(message_id, room_id, sender_id, level, rules, warn) values (new.id, new.room_id, new.sender_id, v.level, v.rules, v.warn)
      on conflict (message_id) do nothing returning id into v_id;
    if v_id is not null and v.level in ('urgent','check') then
      select value into v_secret from public.jigi_config where key = 'hook_secret';
      perform net.http_post(url := 'https://thfcrodfaitzrzlrxyir.supabase.co/functions/v1/chat-scan',
        body := jsonb_build_object('flag_id', v_id), headers := jsonb_build_object('Content-Type','application/json','x-jigi-secret', v_secret), timeout_milliseconds := 8000);
    end if;
  exception when others then null;   -- 점검 실패가 채팅을 막으면 안 된다
  end;
  return null;
end $function$;

-- chat_warns(p_room uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.chat_warns(p_room uuid)
 RETURNS TABLE(message_id bigint, warn text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select f.message_id, f.warn from public.chat_flags f
  where f.room_id = p_room and f.warn is not null and f.status <> 'ok' and f.sender_id is distinct from auth.uid() and public.is_room_member(p_room);
$function$;

-- check_in()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.check_in()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid := auth.uid(); p public.profiles; r public.referrals; k int;
begin
  if uid is null then return '{}'::jsonb; end if;
  select * into p from public.profiles where id = uid;
  if p.onboarded_at is not null and p.last_seen_at is not null and p.last_seen_at < now() - interval '14 days' then
    select count(*) into k from public.meetups m where m.created_at > p.last_seen_at and m.starts_at > now();
    perform public.support_msg(uid, 'e3:' || public.kst_date(now())::text, case when k > 0 then format('오랜만이에요! 그동안 %s 근처에 모임이 %s개 열렸어요. 지도에서 둘러보고, 뜨다 만 작품이 있으면 인증으로 기록해 두세요.', coalesce(p.dong_name,'우리 동네'), k) else '오랜만이에요! 다시 오셔서 반가워요. 뜨다 만 작품이 있으면 인증으로 기록해 두세요. 궁금한 건 여기서 언제든 물어보세요.' end);
  end if;
  if p.last_seen_at is null or p.last_seen_at < now() - interval '1 hour' then update public.profiles set last_seen_at = now() where id = uid; end if;
  perform public.award_points(uid, 'attendance', 'attendance', uid::text || ':' || public.kst_date(now())::text);
  if p.referred_by is not null and p.onboarded_at is not null and public.kst_date(now()) > public.kst_date(p.created_at) then
    select * into r from public.referrals where invitee_user_id = uid and status = 'pending';
    if r.id is not null then
      update public.referrals set status = 'confirmed', confirmed_at = now() where id = r.id;
      perform public.award_points(r.inviter_user_id, 'referral', 'referrals', r.id::text);
      insert into public.notifications(recipient_id, actor_id, kind, snippet) values (r.inviter_user_id, uid, 'supporter', format('초대한 %s님이 활동을 시작했어요. 20점이 적립됐어요!', p.nickname));
    end if;
  end if;
  perform public.supporter_invite_notice();
  perform public.nudge_first_work();
  return public.get_supporter_status();
end $function$;

-- cheer_daily()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.cheer_daily()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare today date := public.kst_date(now()); r record; n int := 0; q int; k int; s1 int; nx text;
  sup_on boolean := coalesce((select (value)::text = 'true' from public.app_config where key = 'supporters_enabled'), true);
begin
  q := public.cheer_flush_queue();
  -- A2 가입 다음 날 활동 0
  for r in select p.* from public.profiles p where p.onboarded_at is not null and public.kst_date(p.created_at) = today - 1
      and not exists (select 1 from public.posts x where x.author_id = p.id) and not exists (select 1 from public.works x where x.profile_id = p.id) and not exists (select 1 from public.messages x where x.sender_id = p.id) loop
    select count(distinct author_id) into k from public.posts x join public.profiles a on a.id = x.author_id where a.dong_code = r.dong_code and x.created_at > now() - interval '7 days' and x.author_id <> r.id;
    if public.cheer_send(r.id, 'a2', case when k > 0 then format('%s 이웃 %s명이 이번 주에 글을 올렸어요. 커뮤니티에서 인사 한 줄 남겨 볼까요?', coalesce(r.dong_name,'우리 동네'), k) else '커뮤니티에서 인사 한 줄 남겨 볼까요? 지금 뜨고 있는 것 한 가지면 충분해요.' end, '{"type":"view","view":"comm"}'::jsonb) then n := n + 1; end if;
  end loop;
  -- 서포터: B2 3일째 0점 · B5 D-2 100점 미만(지기 채팅) · B7 5일 연속 · B8 7일 미출석 · B10 종료 후 7일 — supporters_enabled 일 때만
  if sup_on then
  for r in select s.*, public.supporter_segment(s.started_at) seg, today - public.kst_date(s.started_at) dayn, p.nickname from public.supporters s join public.profiles p on p.id = s.user_id where s.status = 'active' loop
    select coalesce(sum(points),0) into s1 from public.point_events where supporter_id = r.id and segment = r.seg;
    if r.dayn = 3 and (select coalesce(sum(points),0) from public.point_events where supporter_id = r.id) = 0 then
      if public.cheer_send(r.user_id, 'b2', '서포터 첫 점수는 출석 1점부터예요. 오늘 앱을 열었으니 +1! 완성작품 인증은 10점, 오늘 한 개 어때요?', '{"type":"view","view":"supporters"}'::jsonb) then n := n + 1; end if;
    end if;
    if ((r.seg = 1 and r.dayn = 27) or (r.seg = 2 and r.dayn = 57)) and s1 < 100 then
      perform public.support_msg(r.user_id, format('b5:%s', r.seg), format('%s님, %s구간이 이틀 남았고 %s점이 부족해요. 오늘 완성작품 인증(10점)과 글(3점)이면 채울 수 있어요. 막히는 게 있으면 여기서 말해 주세요.', r.nickname, r.seg, 100 - s1));
    end if;
    if (select count(distinct kst_date) from public.point_events where supporter_id = r.id and kind = 'attendance' and kst_date between today - 4 and today) = 5 then
      if public.cheer_send(r.user_id, 'b7', '5일 연속 출석! 꾸준함이 서포터의 힘이에요.', '{"type":"view","view":"supporters"}'::jsonb) then n := n + 1; end if;
    end if;
    if (select coalesce(max(kst_date), public.kst_date(r.started_at)) from public.point_events where supporter_id = r.id and kind = 'attendance') = today - 8 then
      if public.cheer_send(r.user_id, 'b8', format('일주일 만이에요. 구간 마감까지 %s일, %s점 남았어요. 출석만 해도 1점!', greatest((public.kst_date(r.started_at) + (case when r.seg = 1 then 29 else 59 end)) - today, 0), greatest(100 - s1, 0)), '{"type":"view","view":"supporters"}'::jsonb) then n := n + 1; end if;
    end if;
  end loop;
  for r in select s.* from public.supporters s where s.status = 'completed' and s.finalized_at is not null and public.kst_date(s.finalized_at) = today - 7 loop
    if public.cheer_send(r.user_id, 'b10', '서포터 활동 끝나고 일주일이에요. 점수는 기록으로 남고, 2기 모집 때 먼저 알려 드릴게요. 불편했던 점 한 가지만 지기에게 남겨 주시면 큰 도움이 돼요.', '{"type":"view","view":"support"}'::jsonb) then n := n + 1; end if;
  end loop;
  end if;
  -- D3 내 모임 D-3 참여자 0 (지기 채팅)
  for r in select m.*, p.dong_code, p.craft from public.meetups m join public.profiles p on p.id = m.created_by where public.kst_date(m.starts_at) = today + 3 and coalesce(m.participant_count, 0) = 0 loop
    select count(*) into k from public.profiles x where x.dong_code = r.dong_code and x.id <> r.created_by and x.onboarded_at is not null and (r.craft is null or r.craft = 'both' or x.craft::text = 'both' or x.craft::text = case r.craft when 'knitting' then 'knit' else r.craft end);
    perform public.support_msg(r.created_by, format('d3:%s', r.id), format('''%s''에 아직 참여자가 없어요. 커뮤니티에 소개 글을 올리거나 시간을 주말로 바꿔 볼까요?%s', r.title, case when k > 0 then format(' 근처 이웃 %s명이 같은 종목이에요.', k) else '' end));
  end loop;
  -- E1 14일 · E2 30일 미접속
  for r in select * from public.profiles p where p.onboarded_at is not null and p.last_seen_at is not null and public.kst_date(p.last_seen_at) = today - 14 loop
    select count(*) into k from public.profiles x where x.dong_code = r.dong_code and x.id <> r.id and x.created_at > now() - interval '14 days' and x.onboarded_at is not null;
    select count(*) into s1 from public.meetups m where m.created_at > now() - interval '14 days' and m.starts_at > now();
    if public.cheer_send(r.id, 'e1', case when k > 0 and s1 > 0 then format('%s에 새 이웃 %s명, 새 모임 %s개가 생겼어요. 잠깐 들러 보세요.', coalesce(r.dong_name,'우리 동네'), k, s1) when k > 0 then format('%s에 새 이웃 %s명이 왔어요. 잠깐 들러 인사해 보세요.', coalesce(r.dong_name,'우리 동네'), k) when s1 > 0 then format('새 모임 %s개가 열렸어요. 지도에서 둘러보세요.', s1) else '뜨다 만 작품, 어디까지 떴나요? 사진 한 장 올려 두면 이웃이 반가워해요.' end, '{"type":"view","view":"map"}'::jsonb) then n := n + 1; end if;
  end loop;
  for r in select * from public.profiles p where p.onboarded_at is not null and p.last_seen_at is not null and public.kst_date(p.last_seen_at) = today - 30 loop
    if public.cheer_send(r.id, 'e2', '요즘 뜨개 어떻게 지내세요? 뜨다 만 작품도 인증하면 기록이 남아요.', '{"type":"view","view":"cert"}'::jsonb) then n := n + 1; end if;
  end loop;
  -- F1 가게 승인 3일 소식 0
  for r in select * from public.shops s where s.is_active and s.owner_id is not null and public.kst_date(s.created_at) = today - 3 and not exists (select 1 from public.shop_posts x where x.shop_id = s.id) loop
    if public.cheer_send(r.owner_id, format('f1:%s', r.id), '가게가 지도에 올라갔어요. 첫 소식을 올리면 근처 이웃 핀에 종이 울려요.', jsonb_build_object('type','shop','id', r.id)) then n := n + 1; end if;
  end loop;
  delete from public.notifications where kind = 'cheer' and created_at < now() - interval '7 days';
  return jsonb_build_object('queued_sent', q, 'sent', n);
end $function$;

-- cheer_flush_queue()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.cheer_flush_queue()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; n int := 0; sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e';
begin
  for r in select * from public.cheer_log where queued order by user_id, created_at loop
    if not exists (select 1 from public.notifications x where x.recipient_id = r.user_id and x.kind = 'cheer' and public.kst_date(x.created_at) = public.kst_date(now())) then
      insert into public.notifications(recipient_id, actor_id, kind, snippet, link) values (r.user_id, sup, 'cheer', r.body, r.link);
      update public.cheer_log set queued = false, sent_at = now() where user_id = r.user_id and key = r.key; n := n + 1;
    else
      update public.cheer_log set queued = false where user_id = r.user_id and key = r.key;
    end if;
  end loop; return n;
end $function$;

-- cheer_on_follow()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.cheer_on_follow()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.shops; nick text;
begin
  select * into s from public.shops where id = new.shop_id; if s.owner_id is null then return null; end if;
  if (select count(*) from public.shop_follows where shop_id = new.shop_id) = 1 then
    select nickname into nick from public.profiles where id = new.profile_id;
    perform public.cheer_send(s.owner_id, format('f2:%s', s.id), format('%s님이 %s의 첫 팔로워가 됐어요. 소식을 올리면 바로 알림이 가요.', coalesce(nick,'이웃'), s.name), jsonb_build_object('type','shop','id', s.id));
  end if; return null;
end $function$;

-- cheer_on_points()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.cheer_on_points()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.supporters; tot int; seg_end date; leftd int;
begin
  if new.points <= 0 or new.supporter_id is null then return null; end if;
  select * into s from public.supporters where id = new.supporter_id; if s.id is null then return null; end if;
  select coalesce(sum(points),0) into tot from public.point_events where supporter_id = s.id and segment = new.segment;
  seg_end := public.kst_date(s.started_at) + (case when new.segment = 1 then 29 else 59 end); leftd := greatest(seg_end - public.kst_date(now()), 0);
  if tot - new.points < 60 and tot >= 60 then
    perform public.cheer_send(s.user_id, format('b3:%s:%s', s.id, new.segment), format('%s구간 60점 통과, 절반 넘었어요. 남은 %s일에 %s점이면 100점이에요.', new.segment, leftd, 100 - tot), '{"type":"view","view":"supporters"}'::jsonb);
  end if;
  if tot - new.points < 100 and tot >= 100 then
    perform public.cheer_send(s.user_id, format('b6:%s:%s', s.id, new.segment),
      case when new.segment = 1 then format('1구간 100점 완료 🎉 기본 등급까지 한 구간 남았어요. 2구간은 %s부터예요.', to_char(public.kst_date(s.started_at) + 30, 'MM월 DD일')) else '2구간 100점 완료 🎉 60일 완주가 눈앞이에요. 끝까지 함께해 주셔서 고마워요.' end,
      '{"type":"view","view":"supporters"}'::jsonb);
  end if;
  return null;
end $function$;

-- cheer_on_post()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.cheer_on_post()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if (select count(*) from public.posts where author_id = new.author_id) = 1 then
    perform public.cheer_send(new.author_id, 'a4', '첫 글을 남기셨네요! 이웃의 댓글이 오면 활동 탭에 알려 드려요.', '{"type":"view","view":"my"}'::jsonb);
  end if; return null;
end $function$;

-- cheer_on_profile()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.cheer_on_profile()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c text; lv int; nx jsonb; st record; need int; k int; nb int;
begin
  if old.onboarded_at is null and new.onboarded_at is not null then
    select count(*) into nb from public.profiles where dong_code = new.dong_code and is_visible and id <> new.id and onboarded_at is not null;
    perform public.support_msg(new.id, 'a1', case when nb > 0 then format('%s님, 뜨개동네에 오신 걸 환영해요 🧶 %s에 뜨개 이웃 %s명이 있어요. 지도에서 가까운 이웃을 구경하거나, 완성작 사진 한 장으로 첫 인증을 해 보세요. 궁금한 건 여기서 언제든 물어보세요.', new.nickname, coalesce(new.dong_name, '우리 동네'), nb) else format('%s님, 뜨개동네에 오신 걸 환영해요 🧶 %s의 첫 뜨개 이웃이 되셨어요. 완성작이나 지금 뜨는 것 사진 한 장을 올려 두면, 다음에 오는 이웃이 가장 먼저 보게 돼요. 궁금한 건 여기서 언제든 물어보세요.', new.nickname, coalesce(new.dong_name, '우리 동네')) end);
  end if;
  foreach c in array array['crochet','knitting'] loop
    lv := case c when 'crochet' then new.level_crochet else new.level_knit end;
    if lv > (case c when 'crochet' then old.level_crochet else old.level_knit end) and lv > 0 then
      select * into st from public.lv_stats(new.id, c) s where s.level = lv + 1;
      need := greatest(ceil(coalesce(st.total,0) / 2.0) - coalesce(st.done,0), 0); nx := public.next_tech(new.id, c, lv + 1);
      perform public.cheer_send(new.id, format('c1:%s:%s', c, lv),
        format('%s %s단계 %s이 됐어요!%s', case c when 'crochet' then '코바늘' else '대바늘' end, lv, public.lv_name(lv),
          case when lv < 5 and need > 0 then format(' %s단계까지 기법 %s개 — 다음은 %s.', lv + 1, need, coalesce(nx->>'name_ko', '')) else ' 최고 단계예요, 멋져요.' end),
        '{"type":"view","view":"skills"}'::jsonb);
    end if;
    if new.skills is distinct from old.skills then
      lv := public.lv_of(new.id, c);
      if lv < 5 then
        select * into st from public.lv_stats(new.id, c) s where s.level = lv + 1;
        need := ceil(coalesce(st.total,0) / 2.0) - coalesce(st.done,0);
        if need = 1 then
          nx := public.next_tech(new.id, c, lv + 1);
          select count(*) into k from public.meetups m where m.starts_at > now() and (nx->>'id') = any(coalesce(m.technique_ids, '{}'));
          perform public.cheer_send(new.id, format('c2:%s:%s', c, lv + 1),
            format('%s 하나만 더 체크하면 %s단계예요.%s', coalesce(nx->>'name_ko','기법'), lv + 1, case when k > 0 then format(' 이 기법 배우는 모임이 %s개 열려 있어요.', k) else '' end),
            '{"type":"view","view":"skills"}'::jsonb);
        end if;
      end if;
    end if;
  end loop;
  if new.act_level > coalesce(old.act_level, 0) then
    k := greatest(3 - public.author_adv_count(new.id), 0);
    perform public.cheer_send(new.id, format('c3:%s', new.act_level),
      format('Lv.%s! 인증한 날이 %s일이에요.%s', new.act_level, new.act_level,
        case when new.is_author then '' when k = 0 then ' 작가 신청이 열려 있어요 — 설정에서 신청할 수 있어요.' else format(' 전문(5단계) 기법 작품 %s번 더 인증하면 작가 신청 자격이 돼요.', k) end),
      '{"type":"view","view":"my"}'::jsonb);
  end if;
  if coalesce(old.trait, 'new') = 'new' and new.trait is not null and new.trait <> 'new' then
    perform public.cheer_send(new.id, 'c4', format('활동이 쌓여 성향이 보여요: %s. 마이에서 확인해 보세요.', upper(new.trait)), '{"type":"view","view":"my"}'::jsonb);
  end if;
  return null;
end $function$;

-- cheer_on_work()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.cheer_on_work()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare p public.profiles; c text; nx jsonb; lv int;
begin
  select * into p from public.profiles where id = new.profile_id;
  if (select count(*) from public.works where profile_id = new.profile_id) = 1 then
    c := case when p.craft::text = 'knitting' then 'knitting' else 'crochet' end; lv := public.lv_of(new.profile_id, c); nx := public.next_tech(new.profile_id, c);
    perform public.cheer_send(new.profile_id, 'a5', format('첫 인증 축하해요, Lv.1이 됐어요! 인증한 기법은 내 뜨개 단계에 ''인증'' 표시가 붙어요.%s',
      case when nx is not null then format(' 다음엔 %s을(를) 떠 보면 %s단계에 가까워져요.', nx->>'name_ko', greatest(lv, (nx->>'level')::int)) else '' end), '{"type":"view","view":"skills"}'::jsonb);
  end if;
  if not p.is_author and public.author_adv_count(new.profile_id) >= 3 and not exists (select 1 from public.author_applications a where a.profile_id = new.profile_id and a.status = 'pending') then
    perform public.cheer_send(new.profile_id, 'c5', '전문(5단계) 기법 작품 3개를 인증했어요. 작가 신청이 열렸어요 — 설정 › 작가 신청에서 할 수 있어요. 작가가 되면 클래스를 열 수 있어요.', '{"type":"view","view":"my"}'::jsonb);
  end if;
  return null;
end $function$;

-- cheer_quiet(t timestamp with time zone)  acl: {=X/postgres,postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.cheer_quiet(t timestamp with time zone DEFAULT now())
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select extract(hour from (t at time zone 'Asia/Seoul')) >= 21 or extract(hour from (t at time zone 'Asia/Seoul')) < 8;
$function$;

-- cheer_send(p_user uuid, p_key text, p_body text, p_link jsonb, p_kind text)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.cheer_send(p_user uuid, p_key text, p_body text, p_link jsonb DEFAULT NULL::jsonb, p_kind text DEFAULT 'cheer'::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e';
begin
  if p_user is null or p_body is null or p_key is null then return false; end if;
  if exists (select 1 from public.cheer_log where user_id = p_user and key = p_key) then return false; end if;
  if p_kind = 'cheer' then
    if public.cheer_quiet() then
      insert into public.cheer_log(user_id, key, kind, body, link, queued) values (p_user, p_key, 'cheer', p_body, p_link, true); return false;
    end if;
    if exists (select 1 from public.notifications n where n.recipient_id = p_user and n.kind = 'cheer' and public.kst_date(n.created_at) = public.kst_date(now())) then
      insert into public.cheer_log(user_id, key, kind, body, link) values (p_user, p_key, 'cheer', p_body, p_link); return false;   -- 오늘 몫 소진 → 버림(기록만)
    end if;
  end if;
  insert into public.notifications(recipient_id, actor_id, kind, snippet, link) values (p_user, sup, p_kind, p_body, p_link);
  insert into public.cheer_log(user_id, key, kind, body, link, sent_at) values (p_user, p_key, p_kind, p_body, p_link, now());
  return true;
end $function$;

-- claim_referral(p_inviter uuid, p_nickname text)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.claim_referral(p_inviter uuid, p_nickname text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.supporters; f public.profiles; n integer; last_in timestamptz; pts integer := 0; st text;
begin
  s := public.supporter_of(p_inviter);
  if s.id is null then return jsonb_build_object('error','NOT_SUPPORTER'); end if;
  if nullif(btrim(coalesce(p_nickname,'')),'') is null then return jsonb_build_object('error','NO_NICKNAME'); end if;
  select count(*) into n from public.profiles where lower(nickname) = lower(btrim(p_nickname));
  if n = 0 then return jsonb_build_object('error','NOT_FOUND'); end if;
  if n > 1 then return jsonb_build_object('error','AMBIGUOUS'); end if;
  select * into f from public.profiles where lower(nickname) = lower(btrim(p_nickname));
  if f.id = p_inviter then return jsonb_build_object('error','SELF'); end if;
  if f.referred_by is not null then return jsonb_build_object('error', case when f.referred_by = p_inviter then 'ALREADY_MINE' else 'ALREADY' end); end if;
  if f.created_at < s.started_at - interval '3 days' then return jsonb_build_object('error','NOT_NEW', 'joined', public.kst_date(f.created_at)); end if;
  update public.profiles set referred_by = p_inviter where id = f.id;
  insert into public.referrals(inviter_user_id, invitee_user_id, source) values (p_inviter, f.id, 'manual') on conflict (invitee_user_id) do nothing;
  select last_sign_in_at into last_in from auth.users where id = f.id;
  if f.onboarded_at is not null and last_in is not null and public.kst_date(last_in) > public.kst_date(f.created_at) then
    update public.referrals set status = 'confirmed', confirmed_at = now() where invitee_user_id = f.id and status = 'pending';
    pts := public.award_points(p_inviter, 'referral', 'referrals', (select id::text from public.referrals where invitee_user_id = f.id));
    st := 'confirmed';
  else st := 'pending'; end if;
  return jsonb_build_object('ok', true, 'status', st, 'points', pts, 'invitee', f.nickname, 'onboarded', f.onboarded_at is not null);
end $function$;

-- class_app_summary(p_posts uuid[])  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.class_app_summary(p_posts uuid[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_object_agg(x.post_id, jsonb_build_object('mine', x.mine, 'mine_paid', x.mine_paid, 'accepted', x.acc, 'applied', x.app, 'room_id', x.room_id)), '{}')
  from (select sp.id post_id, sp.room_id,
          (select a.status from public.class_applications a where a.post_id = sp.id and a.profile_id = auth.uid()) mine,
          (select a.paid_at is not null from public.class_applications a where a.post_id = sp.id and a.profile_id = auth.uid()) mine_paid,
          (select count(*) from public.class_applications a where a.post_id = sp.id and a.status = 'accepted') acc,
          (select count(*) from public.class_applications a where a.post_id = sp.id and a.status = 'applied') app
        from public.shop_posts sp where sp.id = any(p_posts)) x;
$function$;

-- class_applicants(p_post uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.class_applicants(p_post uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when public.class_host(p_post) = auth.uid() or public.is_admin() then
    coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'user_id', a.profile_id, 'nickname', p.nickname, 'avatar_url', p.avatar_url, 'dong', p.dong_name, 'status', a.status, 'note', a.note, 'host_note', a.host_note, 'created_at', a.created_at, 'paid_at', a.paid_at,
      'lv_crochet', p.level_crochet, 'lv_knit', p.level_knit) order by case a.status when 'accepted' then 0 when 'applied' then 1 else 2 end, a.created_at)
      from public.class_applications a join public.profiles p on p.id = a.profile_id where a.post_id = p_post), '[]') else '[]'::jsonb end;
$function$;

-- class_host(p_post uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.class_host(p_post uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when sp.shop_id is not null then (select s.owner_id from public.shops s where s.id = sp.shop_id) else sp.author_id end from public.shop_posts sp where sp.id = p_post;
$function$;

-- color_families_clean(p text[])  acl: {=X/postgres,postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.color_families_clean(p text[])
 RETURNS text[]
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select nullif((select array_agg(f) from unnest(p) f where exists (select 1 from public.color_lexicon l where l.family = f)), '{}');
$function$;

-- color_family(p text)  acl: {=X/postgres,postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.color_family(p text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select l.family from public.color_lexicon l, (select public.color_norm(p) as n) x
  where x.n is not null and position(l.token in x.n) > 0
  order by (length(x.n) - position(reverse(l.token) in reverse(x.n)) + 1) desc, length(l.token) desc limit 1;
$function$;

-- color_hex_clean(p text[])  acl: {=X/postgres,postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.color_hex_clean(p text[])
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select nullif((select array_agg(lower(h)) from unnest(p) h where h ~ '^#[0-9a-fA-F]{6}$' limit 4), '{}');
$function$;

-- color_norm(p text)  acl: {=X/postgres,postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.color_norm(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select nullif(regexp_replace(lower(coalesce(p,'')), '[^a-z가-힣]', '', 'g'), '');
$function$;

-- compute_skill_level(p_skills text[], p_craft text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.compute_skill_level(p_skills text[], p_craft text)
 RETURNS smallint
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select coalesce(max(level), 0)::smallint from (
    select t.level, count(*) filter (where t.id = any(p_skills)) as done, count(*) as total
    from public.techniques t where t.craft = p_craft and not t.hidden
    group by t.level
  ) s where done * 2 >= total;
$function$;

-- compute_trait_index(p_user uuid)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.compute_trait_index(p_user uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare w90 timestamptz := now() - interval '90 days'; xc numeric := 0; xh numeric := 0; xs numeric := 0; ic int; ih int; isk int; tr text; acts int; lv int; top int; sec int;
  wt constant numeric := 0.5;
begin
  -- Connect
  select coalesce(sum(case when created_at >= w90 then 1 else wt end + case when like_count > 0 then 0.5 else 0 end),0) into xc from public.posts where author_id = p_user and parent_id is not null and not hidden;
  xc := xc + coalesce((select sum(case when l.created_at >= w90 then 0.5 else 0.25 end) from public.post_likes l where l.profile_id = p_user),0);
  xc := xc + coalesce((select sum(case when m.starts_at >= w90 then 2 else 1 end) from public.meetups m join public.room_members rm on rm.room_id = m.room_id and rm.profile_id = p_user where m.created_by <> p_user and m.starts_at <= now()),0);
  -- Host
  select coalesce(sum((case when created_at >= w90 then 1 else wt end) * (case when coalesce(array_length(photos,1),0) > 0 then 1.5 else 1 end)),0) into xh from public.posts where author_id = p_user and parent_id is null and meetup_id is null and work_id is null and not hidden;
  xh := xh + coalesce((select sum(case when created_at >= w90 then 3 else 1.5 end) from public.meetups where created_by = p_user),0);
  xh := xh + coalesce((select sum(case when created_at >= w90 then 3 else 1.5 end) from public.shop_posts where author_id = p_user and kind = 'class' and not hidden),0);
  -- Skill
  select coalesce(sum((case when w.created_at >= w90 then 2 else 1 end) + case when exists (select 1 from public.techniques t where t.id = any(w.techniques) and t.level >= 4) then 2 else 0 end),0) into xs from public.works w where w.profile_id = p_user;
  select greatest(coalesce(level_crochet,0), coalesce(level_knit,0)), coalesce(array_length(verified_skills,1),0) into lv, ic from public.profiles where id = p_user;
  xs := xs + lv * 3 + ic * 0.5;
  ic := round(100 * (1 - exp(-xc / 12))); ih := round(100 * (1 - exp(-xh / 8))); isk := round(100 * (1 - exp(-xs / 12)));
  acts := (select count(*) from public.posts where author_id = p_user and not hidden) + (select count(*) from public.works where profile_id = p_user) + (select count(*) from public.meetups where created_by = p_user);
  top := greatest(ic, ih, isk); sec := ic + ih + isk - top - least(ic, ih, isk);
  tr := case when acts < 3 then 'new' when top - sec < 15 then 'balanced' when top = isk then 'skill' when top = ih then 'host' else 'connect' end;
  update public.profiles set idx_connect = ic, idx_host = ih, idx_skill = isk, trait = tr, idx_updated_at = now() where id = p_user;
  return jsonb_build_object('connect', ic, 'host', ih, 'skill', isk, 'trait', tr);
end $function$;

-- contains_banned(p_text text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.contains_banned(p_text text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select p_text is not null and exists (select 1 from public.banned_words b where position(b.word in lower(p_text)) > 0);
$function$;

-- create_meetup(p_title text, p_place text, p_starts_at timestamp with time zone, p_is_public boolean, p_body text, p_lat double precision, p_lng double precision, p_photos text[], p_extra jsonb)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.create_meetup(p_title text, p_place text, p_starts_at timestamp with time zone, p_is_public boolean, p_body text DEFAULT NULL::text, p_lat double precision DEFAULT NULL::double precision, p_lng double precision DEFAULT NULL::double precision, p_photos text[] DEFAULT '{}'::text[], p_extra jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v_room uuid; v_meetup uuid; v_post uuid; v_loc geography; v_existing uuid; v_techs text[];
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  if not exists (select 1 from public.works where profile_id = auth.uid()) then raise exception '모임을 열려면 완성작품 인증이 1회 이상 필요해요'; end if;
  if p_starts_at < now() then raise exception '일시를 지금 이후로 정해 주세요'; end if;
  if p_lat is not null and p_lng is not null then v_loc := st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography;
  else select location into v_loc from public.profiles where id = auth.uid(); end if;
  v_techs := array(select t.id from public.techniques t where t.id = any(array(select jsonb_array_elements_text(case when jsonb_typeof(p_extra->'technique_ids')='array' then p_extra->'technique_ids' else '[]'::jsonb end))) order by t.sort limit 10);
  if cardinality(v_techs) = 0 and nullif(p_extra->>'technique_id','') is not null then v_techs := array[p_extra->>'technique_id']; end if;
  v_existing := nullif(p_extra->>'room_id','')::uuid;
  if v_existing is not null then
    if not exists (select 1 from public.room_members where room_id = v_existing and profile_id = auth.uid()) then raise exception '참여 중인 방에서만 모임을 만들 수 있어요'; end if;
    v_room := v_existing;
  else
    insert into public.rooms (kind, title, created_by) values ('group', left(p_title, 40), auth.uid()) returning id into v_room;
  end if;
  insert into public.meetups (room_id, created_by, title, place_name, address, location, starts_at, is_public, descr,
      kind, craft, level_min, level_max, technique_id, technique_ids, capacity, fee, bring, duration_min, repeat)
    values (v_room, auth.uid(), p_title, p_place, left(nullif(p_extra->>'address',''), 200), v_loc, p_starts_at, p_is_public, p_body,
      coalesce(p_extra->>'kind','free'), nullif(p_extra->>'craft',''),
      (p_extra->>'level_min')::smallint, (p_extra->>'level_max')::smallint, v_techs[1], v_techs,
      (p_extra->>'capacity')::smallint, nullif(p_extra->>'fee',''), nullif(p_extra->>'bring',''),
      (p_extra->>'duration_min')::smallint, coalesce(p_extra->>'repeat','once'))
    returning id into v_meetup;
  if v_existing is null then insert into public.room_members (room_id, profile_id) values (v_room, auth.uid());
  else update public.meetups set participant_count = (select count(*) from public.room_members where room_id = v_room) where id = v_meetup; end if;
  insert into public.posts (author_id, body, photos, meetup_id)
    values (auth.uid(), coalesce(nullif(p_body,''), p_title), coalesce(p_photos,'{}'), v_meetup) returning id into v_post;
  if v_existing is not null then
    insert into public.messages (room_id, sender_id, body) values (v_room, auth.uid(), '📍 모임: ' || p_title || E'\n' || p_place);
  end if;
  return v_post;
end $function$;

-- create_review(p_meetup_id uuid, p_body text, p_photos text[])  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.create_review(p_meetup_id uuid, p_body text, p_photos text[] DEFAULT '{}'::text[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_room uuid; v_starts timestamptz; v_post uuid;
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  select room_id, starts_at into v_room, v_starts from public.meetups where id = p_meetup_id;
  if v_room is null then raise exception '모임을 찾을 수 없어요'; end if;
  if v_starts > now() then raise exception '모임이 끝난 뒤에 후기를 쓸 수 있어요'; end if;
  if not exists (select 1 from public.room_members where room_id = v_room and profile_id = auth.uid()) then raise exception '참여한 모임만 후기를 쓸 수 있어요'; end if;
  if exists (select 1 from public.posts where review_of = p_meetup_id and author_id = auth.uid()) then raise exception '이미 후기를 남겼어요'; end if;
  if (p_body is null or btrim(p_body) = '') and cardinality(coalesce(p_photos,'{}')) = 0 then raise exception '후기 내용이나 사진을 넣어 주세요'; end if;
  insert into public.posts (author_id, body, photos, review_of) values (auth.uid(), nullif(btrim(p_body),''), coalesce(p_photos,'{}'), p_meetup_id) returning id into v_post;
  return v_post;
end $function$;

-- create_work(p_title text, p_photos text[], p_techniques text[], p_yarn text, p_note text, p_custom text[], p_yarn_meta jsonb)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.create_work(p_title text, p_photos text[], p_techniques text[], p_yarn text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_custom text[] DEFAULT '{}'::text[], p_yarn_meta jsonb DEFAULT NULL::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_work uuid; v_post uuid; v_known text[]; v_custom text[]; v_yarns jsonb; v_needles jsonb; v_item text; v_gauge text; v_level smallint; y jsonb;
  num constant text := '^[0-9]{1,5}(\.[0-9]{1,2})?$';
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  if p_photos is null or cardinality(p_photos) = 0 then raise exception '작품 사진이 필요해요'; end if;
  v_known := array(select t.id from public.techniques t where t.id = any(coalesce(p_techniques,'{}')) order by t.sort);
  v_custom := array(select distinct left(btrim(x), 30) from unnest(coalesce(p_custom,'{}')) x where btrim(x) <> '' limit 20);
  if cardinality(v_known) = 0 and cardinality(v_custom) = 0 then raise exception '사용한 기법을 하나 이상 골라 주세요'; end if;
  v_item := nullif(left(btrim(coalesce(p_yarn_meta->>'item_type','')),20),'');
  v_gauge := nullif(left(btrim(coalesce(p_yarn_meta->>'gauge','')),60),'');
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'name',   nullif(left(btrim(coalesce(q.y->>'name','')),60),''),
      'color',  nullif(left(btrim(coalesce(q.y->>'color','')),40),''),
      'amount', case when (q.y->>'amount') ~ num then (q.y->>'amount')::numeric end,
      'unit',   case when q.y->>'unit' in ('볼','g') then q.y->>'unit' end,
      'ball_g', case when (q.y->>'ball_g') ~ num then (q.y->>'ball_g')::numeric end,
      'ball_m', case when (q.y->>'ball_m') ~ num then (q.y->>'ball_m')::numeric end,
      'weight', nullif(left(btrim(coalesce(q.y->>'weight','')),20),''),
      'fiber',  nullif(left(btrim(coalesce(q.y->>'fiber','')),20),''),
      'fibers', case when jsonb_typeof(q.y->'fibers')='object' and pg_column_size(q.y->'fibers') < 300 then q.y->'fibers' end,
      'rating', case when q.y->>'rating' in ('-1','0','1') then (q.y->>'rating')::int end,
      'rating_reason', nullif(left(btrim(coalesce(q.y->>'rating_reason','')),20),''),
      'color_hex', (select jsonb_agg(h.v) from (select hx.v from jsonb_array_elements_text(case when jsonb_typeof(q.y->'color_hex')='array' then q.y->'color_hex' else '[]'::jsonb end) hx(v) where hx.v ~ '^#[0-9A-Fa-f]{6}$' limit 4) h),
      'color_mode', case when q.y->>'color_mode' in ('solid','gradient','mix','melange') then q.y->>'color_mode' end,
      'brand', nullif(left(btrim(q.y->>'brand'), 40), ''),
      'color_families', (select jsonb_agg(left(cf.v,10)) from (select fx.v from jsonb_array_elements_text(case when jsonb_typeof(q.y->'color_families')='array' then q.y->'color_families' else '[]'::jsonb end) fx(v) where btrim(fx.v) <> '' limit 4) cf),
      'stash_id', case when (q.y->>'stash_id') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then q.y->>'stash_id' end)) order by q.ord), '[]'::jsonb)
    into v_yarns
    from (select t.y, t.ord from jsonb_array_elements(case when jsonb_typeof(p_yarn_meta->'yarns')='array' then p_yarn_meta->'yarns' else '[]'::jsonb end) with ordinality as t(y, ord)
          where jsonb_typeof(t.y)='object' and btrim(coalesce(t.y->>'name','')) <> '' limit 6) q;
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'type', case when q.n->>'type' in ('코바늘','대바늘','줄바늘','레이스 바늘') then q.n->>'type' end,
      'size', nullif(left(btrim(coalesce(q.n->>'size','')),30),''))) order by q.ord), '[]'::jsonb)
    into v_needles
    from (select t.n, t.ord from jsonb_array_elements(case when jsonb_typeof(p_yarn_meta->'needles')='array' then p_yarn_meta->'needles' else '[]'::jsonb end) with ordinality as t(n, ord)
          where jsonb_typeof(t.n)='object' and btrim(coalesce(t.n->>'size','')) <> '' limit 4) q;
  insert into public.works (profile_id, photo_url, photos, title, yarn_info, techniques, custom_techniques, note, yarn_name, yarn_weight, needle_size, yarns, needles, gauge, finished_size, item_type)
    values (auth.uid(), p_photos[1], p_photos, p_title, left(p_yarn, 200), v_known, v_custom, p_note,
            nullif(left(btrim(coalesce(p_yarn_meta->>'name','')),60),''), nullif(left(btrim(coalesce(p_yarn_meta->>'weight','')),20),''), nullif(left(btrim(coalesce(p_yarn_meta->>'needle','')),40),''),
            v_yarns, v_needles, v_gauge, nullif(left(btrim(coalesce(p_yarn_meta->>'size','')),60),''), v_item)
    returning id into v_work;
  -- 실 빅데이터 로그 + 표준 사전 매칭 (옛 앱처럼 이름만 온 경우도 1건으로 기록)
  select greatest(level_crochet, level_knit) into v_level from public.profiles where id = auth.uid();
  if jsonb_array_length(v_yarns) > 0 then
    for y in select * from jsonb_array_elements(v_yarns) loop perform public.yarn_log_entry(v_work, y, v_needles, v_gauge, v_known, v_item, v_level); end loop;
  elsif nullif(btrim(coalesce(p_yarn_meta->>'name','')),'') is not null then
    perform public.yarn_log_entry(v_work, jsonb_build_object('name', p_yarn_meta->>'name', 'weight', nullif(p_yarn_meta->>'weight','')), v_needles, v_gauge, v_known, v_item, v_level);
  end if;
  perform public.stash_consume(v_work);
  insert into public.posts (author_id, body, photos, work_id)
    values (auth.uid(), coalesce(nullif(p_note,''), p_title), p_photos, v_work) returning id into v_post;
  return v_post;
end $function$;

-- ddeuchin_ai_apply(p_id bigint, p_ai text, p_note text)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.ddeuchin_ai_apply(p_id bigint, p_ai text, p_note text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v record; a text; b text;
begin
  update public.ddeuchin_claims set ai = case when p_ai in ('pass','unsure') then p_ai end, ai_note = left(p_note, 200),
         status = case when p_ai = 'pass' then 'ok' else status end, decided_at = case when p_ai = 'pass' then now() else decided_at end
   where id = p_id and status = 'review' returning * into v;
  if v.id is null then return null; end if;
  select nickname into a from public.profiles where id = v.author_id; select nickname into b from public.profiles where id = v.friend_id;
  insert into public.jigi_reminders(due_at, text) values (now(),
    '☕ 뜨친 인증 이벤트 — 새 인증 글이 들어왔어요.'||E'\n\n'||
    '올린 회원: '||coalesce(a,'?')||' · 함께 뜬 뜨친: '||coalesce(b,'?')||E'\n'||
    '서버 확인: 두 분은 실제 뜨친이고, 이벤트 기간 안이며, 이 두 분으로는 처음 참여예요.'||E'\n'||
    '사진(AI): '||case when p_ai = 'pass' then '통과 — 뜨개 작품이나 함께 뜨는 모습이 보여요.' when p_ai = 'unsure' then '애매함 — '||coalesce(p_note,'')||' → 대표님이 사진을 직접 보고 [통과] 또는 [제외]를 눌러 주세요.' else '판별하지 못했어요(AI 연결 문제) → 대표님이 사진을 직접 봐 주세요.' end||E'\n\n'||
    '할 일: 콘솔 › 알리기 › 이벤트 맨 위 「뜨친 인증」 칸에서 '||case when p_ai = 'pass' then '[두 분에게 쿠폰 보내기]를 눌러 쿠폰 이미지 2장을 골라 보내 주세요.' else '먼저 글을 확인해 주세요.' end);
  return v.status;
end $function$;

-- ddeuchin_ai_payload(p_id bigint)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.ddeuchin_ai_payload(p_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object('photos', to_jsonb(p.photos[1:2]), 'body', left(p.body, 300))
  from public.ddeuchin_claims c join public.posts p on p.id = c.post_id where c.id = p_id and c.status = 'review' and c.ai is null $function$;

-- ddeuchin_on_friend()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.ddeuchin_on_friend()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e'; cfg jsonb; lk jsonb;
begin
  begin
    if new.status::text <> 'accepted' or (tg_op = 'UPDATE' and old.status::text = 'accepted') then return null; end if;
    if sup in (new.requester_id, new.addressee_id) then return null; end if;
    cfg := public._ddeuchin_cfg(); if cfg is null then return null; end if;
    lk := case when cfg->>'post_id' is not null then jsonb_build_object('type','post','id',cfg->>'post_id') else jsonb_build_object('type','view','view','comm') end;
    insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
      select u, sup, 'notice', '뜨친이 생겼어요! 🎉 뜨친과 만나 함께 뜨고, 사진에 @뜨친 과 #뜨친인증 을 적어 올리면 두 분 모두 커피 쿠폰을 드려요.', lk
      from unnest(array[new.requester_id, new.addressee_id]) u;
  exception when others then null;
  end;
  return null;
end $function$;

-- ddeuchin_on_post()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.ddeuchin_on_post()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e'; cfg jsonb; m uuid; v_friend uuid; v_any_friend uuid; v_pair text; v_id bigint; v_reason text; v_secret text; v_nick text;
        cand uuid[]; b text := lower(coalesce(new.body,''));
begin
  begin
    if new.parent_id is not null or new.author_id = sup or not ('뜨친인증' = any(coalesce(new.tags,'{}'))) then return null; end if;
    cfg := public._ddeuchin_cfg(); if cfg is null then return null; end if;
    -- 후보: 글쓴이의 뜨친 중 (멘션으로 고른 사람) 또는 (본문에 '@닉네임'이 적힌 사람). 닉네임이 긴 사람부터(짧은 닉네임이 긴 닉네임의 앞부분일 때)
    select array_agg(x.fid order by length(x.nick) desc) into cand from (
      select case when f.requester_id = new.author_id then f.addressee_id else f.requester_id end as fid, p.nickname as nick
      from public.friendships f join public.profiles p on p.id = case when f.requester_id = new.author_id then f.addressee_id else f.requester_id end
      where f.status = 'accepted' and new.author_id in (f.requester_id, f.addressee_id) and p.id <> sup and p.deleted_at is null) x
    where x.fid = any(coalesce(new.mentions,'{}')) or (coalesce(x.nick,'') <> '' and position('@'||lower(x.nick) in b) > 0);
    if coalesce(array_length(new.photos,1),0) = 0 then v_reason := '사진이 없어요';
    elsif coalesce(array_length(cand,1),0) = 0 then
      v_reason := case when position('@' in b) > 0 or coalesce(array_length(new.mentions,1),0) > 0 then '적어 주신 분과 아직 뜨친이 아니에요(@ 뒤에 뜨친의 닉네임을 정확히 적어 주세요)' else '@뜨친 닉네임을 적지 않았어요' end;
    else
      foreach m in array cand loop
        v_any_friend := coalesce(v_any_friend, m);
        v_pair := least(new.author_id::text, m::text)||':'||greatest(new.author_id::text, m::text);
        if not exists (select 1 from public.ddeuchin_claims c where c.pair = v_pair and c.status <> 'excluded') then v_friend := m; exit; end if;
      end loop;
      if v_friend is null then v_reason := '같은 두 분은 이미 참여했어요'; end if;
    end if;
    if v_reason is not null then
      insert into public.ddeuchin_claims(post_id, author_id, friend_id, status, reason, decided_at)
        values (new.id, new.author_id, v_any_friend, 'excluded', v_reason, now()) on conflict (post_id) do nothing;
      insert into public.notifications(recipient_id, actor_id, kind, post_id, snippet, link)
        values (new.author_id, sup, 'notice', new.id, left('뜨친 인증 이벤트: 이번 글은 대상이 아니에요 — '||v_reason||'. 사진과 @뜨친 닉네임, #뜨친인증을 함께 적어 새 글로 올려 주세요.', 200),
                jsonb_build_object('type','post','id',new.id,'push','0'));
      return null;
    end if;
    insert into public.ddeuchin_claims(post_id, author_id, friend_id, pair, status)
      values (new.id, new.author_id, v_friend, v_pair, 'review') on conflict do nothing returning id into v_id;
    if v_id is null then return null; end if;
    select nickname into v_nick from public.profiles where id = new.author_id;
    insert into public.notifications(recipient_id, actor_id, kind, post_id, snippet, link)
      values (v_friend, new.author_id, 'notice', new.id,
              left(coalesce(v_nick,'뜨친')||' 님이 뜨친 인증 글에 회원님을 함께 뜬 뜨친으로 적었어요. 확인되면 두 분 모두 커피 쿠폰을 받아요. 함께 뜬 적이 없다면 눌러서 지기에게 알려 주세요.', 200),
              jsonb_build_object('type','view','view','support'));
    select value into v_secret from public.jigi_config where key = 'hook_secret';
    perform net.http_post(url := 'https://thfcrodfaitzrzlrxyir.supabase.co/functions/v1/ddeuchin-check',
      body := jsonb_build_object('claim_id', v_id), headers := jsonb_build_object('Content-Type','application/json','x-jigi-secret', v_secret), timeout_milliseconds := 8000);
  exception when others then null;
  end;
  return null;
end $function$;

-- decide_class_application(p_id bigint, p_accept boolean, p_note text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.decide_class_application(p_id bigint, p_accept boolean, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid := auth.uid(); a public.class_applications; sp public.shop_posts; rid uuid; n_acc integer; mx integer; nick text; pay text; msg text; due date;
begin
  select * into a from public.class_applications where id = p_id for update;
  if a.id is null then raise exception '신청을 찾을 수 없어요'; end if;
  if public.class_host(a.post_id) is distinct from uid then raise exception '클래스를 연 사람만 확정할 수 있어요'; end if;
  if a.status not in ('applied','accepted') then raise exception '이미 처리된 신청이에요'; end if;
  select * into sp from public.shop_posts where id = a.post_id;
  select nickname into nick from public.profiles where id = a.profile_id;
  if p_accept then
    mx := nullif(sp.extra->>'max','')::int; select count(*) into n_acc from public.class_applications where post_id = a.post_id and status = 'accepted' and id <> a.id;
    if mx is not null and n_acc >= mx then raise exception '최대 인원(%명)이 찼어요', mx; end if;
    if sp.room_id is null then
      insert into public.rooms(kind, title, created_by) values ('group', left('[클래스] ' || sp.title, 40), uid) returning id into rid;
      insert into public.room_members(room_id, profile_id) values (rid, uid) on conflict do nothing;
      update public.shop_posts set room_id = rid where id = sp.id;
      insert into public.messages(room_id, sender_id, body) values (rid, uid, '클래스 채팅방이에요. 결제·준비물·장소 안내를 여기서 드릴게요. 계좌번호는 이 방에서만 안내해요.');
    else rid := sp.room_id; end if;
    insert into public.room_members(room_id, profile_id) values (rid, a.profile_id) on conflict do nothing;
    update public.class_applications set status = 'accepted', decided_at = now(), host_note = left(p_note, 300) where id = a.id;
    -- 결제 안내 메시지(자동): 방법·기한·환불
    due := (now() at time zone 'Asia/Seoul')::date + coalesce(nullif(sp.extra->>'pay_days','')::int, 2);
    pay := case coalesce(sp.extra->>'pay','onsite')
      when 'transfer' then format('계좌이체 — 계좌는 호스트가 이 방에서 알려 드려요. %s까지 입금해 주세요', to_char(due, 'MM/DD'))
      when 'deposit' then format('예약금 %s원 계좌이체(%s까지) + 잔금은 현장에서. 계좌는 호스트가 이 방에서 알려 드려요', coalesce(sp.extra->>'deposit',''), to_char(due, 'MM/DD'))
      else '현장 결제(수업 당일)' end;
    msg := format('%s님 확정됐어요 🎉%s'||E'\n'||'결제: %s'||E'\n'||'취소·환불: %s 환불은 호스트가 이체로 돌려드려요.'||E'\n'||'뜨개동네는 신청·확정만 기록하고 결제에는 관여하지 않아요.', nick, coalesce(' — ' || nullif(p_note,''), ''), pay, coalesce(sp.extra->>'refund',''));
    insert into public.messages(room_id, sender_id, body) values (rid, uid, left(msg, 1000));
    insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
      values (a.profile_id, uid, 'notice', format('「%s」 클래스 신청이 확정됐어요! 채팅방에서 결제·준비물 안내를 확인하세요', left(sp.title, 40)), jsonb_build_object('type','class','id',a.post_id));
  else
    update public.class_applications set status = 'rejected', decided_at = now(), host_note = left(p_note, 300), paid_at = null where id = a.id;
    if sp.room_id is not null then delete from public.room_members where room_id = sp.room_id and profile_id = a.profile_id; end if;
    insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
      values (a.profile_id, uid, 'notice', format('「%s」 클래스는 이번에 함께하지 못하게 됐어요%s', left(sp.title, 40), coalesce(' — ' || nullif(p_note,''), '')), jsonb_build_object('type','class','id',a.post_id));
  end if;
  return jsonb_build_object('ok', true, 'room_id', rid);
end $function$;

-- delete_my_account()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.delete_my_account()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception '로그인이 필요해요'; end if;
  delete from auth.users where id = uid;   -- profiles·posts·works·messages·friendships 등 cascade
end $function$;

-- delete_my_shop(p_shop uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.delete_my_shop(p_shop uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_shop public.shops%rowtype; v_busy int;
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  select * into v_shop from public.shops where id = p_shop;
  if not found then raise exception '가게를 찾을 수 없어요'; end if;
  if v_shop.owner_id is distinct from auth.uid() then raise exception '가게 오너만 삭제할 수 있어요'; end if;
  select count(*) into v_busy
    from public.class_applications a join public.shop_posts p on p.id = a.post_id
   where p.shop_id = p_shop and p.kind = 'class' and a.status = 'accepted'
     and coalesce((p.extra->>'starts_at')::timestamptz, p.ends_at, p.created_at + interval '60 days') > now();
  if v_busy > 0 then raise exception '확정된 수강생이 있는 클래스가 있어요. 클래스를 먼저 마무리하거나 신청자 관리에서 확정을 취소한 뒤 삭제해 주세요'; end if;
  delete from public.shops where id = p_shop;
  return jsonb_build_object('ok', true, 'name', v_shop.name);
end $function$;

-- dong_autofix_apply(p_profile uuid, p_tried text, p_ok boolean, p_note text, p_name text, p_code text, p_lat double precision, p_lng double precision)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.dong_autofix_apply(p_profile uuid, p_tried text, p_ok boolean, p_note text DEFAULT NULL::text, p_name text DEFAULT NULL::text, p_code text DEFAULT NULL::text, p_lat double precision DEFAULT NULL::double precision, p_lng double precision DEFAULT NULL::double precision)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare cell constant double precision := 0.0018; n int := 0;
begin
  if p_ok then
    if p_lat is null or p_lng is null or p_lat not between 32 and 40 or p_lng not between 123 and 133 or nullif(btrim(coalesce(p_name,'')),'') is null then return false; end if;
    update public.profiles set dong_name = left(btrim(p_name), 40), dong_code = left(p_code, 120),
           location = st_setsrid(st_makepoint(floor(p_lng / cell) * cell + cell / 2, floor(p_lat / cell) * cell + cell / 2), 4326)::geography
     where id = p_profile and location is null and onboarded_at is not null and btrim(coalesce(dong_name,'')) = btrim(p_tried);
    get diagnostics n = row_count;
    if n = 0 then return false; end if;
    insert into public.admin_logs(admin_id, action, target_type, target_id, detail)
      values ('e120eb67-b254-4008-92d8-08c95c821e9e', 'member_edit', 'profile', p_profile::text, jsonb_build_object('field','dong','from',p_tried,'to',p_name,'code',p_code,'why',p_note,'auto',true));
  end if;
  insert into public.dong_fix_log(profile_id, tried, ok, note) values (p_profile, btrim(p_tried), p_ok, left(p_note, 300))
    on conflict (profile_id) do update set tried = excluded.tried, ok = excluded.ok, note = excluded.note, tried_at = now();
  return true;
end $function$;

-- dong_autofix_candidates()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.dong_autofix_candidates()
 RETURNS TABLE(id uuid, nickname text, dong_name text, dong_code text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select p.id, p.nickname, p.dong_name, p.dong_code from public.profiles p
   where p.onboarded_at is not null and p.location is null and p.deleted_at is null and p.suspended_at is null and nullif(btrim(coalesce(p.dong_name,'')),'') is not null
     and not exists (select 1 from auth.users u where u.id = p.id and u.email like '%@knit.local')   -- 테스트 계정 제외
     and not exists (select 1 from public.dong_fix_log l where l.profile_id = p.id and l.tried = btrim(p.dong_name) and l.tried_at > now() - interval '30 days')
   order by p.created_at limit 20;
$function$;

-- dong_fix_call()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.dong_fix_call()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_secret text;
begin
  select value into v_secret from public.jigi_config where key = 'hook_secret';
  perform net.http_post(url := 'https://thfcrodfaitzrzlrxyir.supabase.co/functions/v1/dong-fix', body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json','x-jigi-secret', v_secret), timeout_milliseconds := 20000);
exception when others then null;
end $function$;

-- edit_post(p_post uuid, p_body text, p_photos text[], p_mentions uuid[])  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.edit_post(p_post uuid, p_body text, p_photos text[], p_mentions uuid[] DEFAULT NULL::uuid[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.posts; v_body text := nullif(btrim(coalesce(p_body,'')),''); v_photos text[] := coalesce(p_photos,'{}'); v_until timestamptz;
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  if not public.is_active_user() then raise exception '지금은 글을 고칠 수 없어요'; end if;
  select post_restricted_until into v_until from public.profiles where id = auth.uid();
  if v_until is not null and v_until > now() then raise exception '글쓰기가 제한된 동안에는 고칠 수 없어요'; end if;
  select * into r from public.posts where id = p_post and author_id = auth.uid() for update;
  if not found then raise exception '내 글만 고칠 수 있어요'; end if;
  if r.parent_id is not null then raise exception '댓글은 고칠 수 없어요'; end if;
  if r.meetup_id is not null then raise exception '모임 글은 모임 화면에서 고쳐 주세요'; end if;
  if r.work_id is not null then raise exception '완성작품 인증은 완성작품 인증 수정에서 고쳐 주세요'; end if;
  if exists (select 1 from public.ddeuchin_claims c where c.post_id = p_post) then raise exception '이벤트에 접수된 글은 고칠 수 없어요'; end if;
  if cardinality(v_photos) > 4 then raise exception '사진은 4장까지예요'; end if;
  if v_body is null and cardinality(v_photos) = 0 then raise exception '내용이나 사진을 넣어 주세요'; end if;
  if not public._post_photo_ok(v_photos, r.photos) then raise exception '사진을 다시 올려 주세요'; end if;
  update public.posts set body = v_body, photos = v_photos,
      mentions = case when p_mentions is null then mentions else array(select distinct m from unnest(p_mentions) m where m is not null limit 20) end,
      edited_at = now(), mod_scanned_at = null
    where id = p_post;
  begin perform public.jigi_call('scan'); exception when others then null; end;
end $function$;

-- edit_work(p_post uuid, p_title text, p_note text, p_photos text[], p_add_techniques text[], p_add_custom text[])  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.edit_work(p_post uuid, p_title text, p_note text, p_photos text[], p_add_techniques text[] DEFAULT '{}'::text[], p_add_custom text[] DEFAULT '{}'::text[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.posts; w public.works; v_title text := nullif(btrim(coalesce(p_title,'')),''); v_note text := nullif(btrim(coalesce(p_note,'')),'');
  v_photos text[] := coalesce(p_photos,'{}'); v_known text[]; v_custom text[]; v_until timestamptz;
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  if not public.is_active_user() then raise exception '지금은 글을 고칠 수 없어요'; end if;
  select post_restricted_until into v_until from public.profiles where id = auth.uid();
  if v_until is not null and v_until > now() then raise exception '글쓰기가 제한된 동안에는 고칠 수 없어요'; end if;
  select * into r from public.posts where id = p_post and author_id = auth.uid() for update;
  if not found or r.work_id is null then raise exception '내 완성작품 인증만 고칠 수 있어요'; end if;
  select * into w from public.works where id = r.work_id and profile_id = auth.uid() for update;
  if not found then raise exception '내 완성작품 인증만 고칠 수 있어요'; end if;
  if w.event_id is not null or exists (select 1 from public.ddeuchin_claims c where c.post_id = p_post) then raise exception '이벤트에 접수된 글은 고칠 수 없어요'; end if;
  if v_title is null then raise exception '작품 이름을 적어 주세요'; end if;
  if cardinality(v_photos) = 0 then raise exception '작품 사진이 필요해요'; end if;
  if cardinality(v_photos) > 4 then raise exception '사진은 4장까지예요'; end if;
  if not public._post_photo_ok(v_photos, r.photos || coalesce(w.photos,'{}')) then raise exception '사진을 다시 올려 주세요'; end if;
  v_custom := array(select distinct x from (select unnest(coalesce(w.custom_techniques,'{}')) x union all
               select left(btrim(x),30) from unnest(coalesce(p_add_custom,'{}')) x where btrim(x) <> '') q limit 20);
  if public.contains_banned(v_title) or public.contains_banned(array_to_string(v_custom,' ')) then raise exception '커뮤니티 가이드라인에 맞지 않는 표현이 있어요'; end if;
  v_known := array(select t.id from public.techniques t where t.id = any(coalesce(w.techniques,'{}') || coalesce(p_add_techniques,'{}')) order by t.sort);
  update public.works set title = v_title, note = v_note, photos = v_photos, photo_url = v_photos[1], techniques = v_known, custom_techniques = v_custom where id = w.id;
  update public.posts set body = coalesce(v_note, v_title), photos = v_photos, edited_at = now(), mod_scanned_at = null where id = p_post;
  begin perform public.jigi_call('scan'); exception when others then null; end;
end $function$;

-- edit_work_yarn(p_post uuid, p_yarn text, p_yarn_meta jsonb)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.edit_work_yarn(p_post uuid, p_yarn text, p_yarn_meta jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.posts; w public.works; v_yarns jsonb; v_needles jsonb; v_item text; v_gauge text; v_level smallint; y jsonb;
  num constant text := '^[0-9]{1,5}(\.[0-9]{1,2})?$';
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  if not public.is_active_user() then raise exception '지금은 글을 고칠 수 없어요'; end if;
  select * into r from public.posts where id = p_post and author_id = auth.uid() for update;
  if not found or r.work_id is null then raise exception '내 완성작품 인증만 고칠 수 있어요'; end if;
  select * into w from public.works where id = r.work_id and profile_id = auth.uid() for update;
  if not found then raise exception '내 완성작품 인증만 고칠 수 있어요'; end if;
  if w.event_id is not null or exists (select 1 from public.ddeuchin_claims c where c.post_id = p_post) then raise exception '이벤트에 접수된 글은 고칠 수 없어요'; end if;
  v_item := nullif(left(btrim(coalesce(p_yarn_meta->>'item_type','')),20),'');
  v_gauge := nullif(left(btrim(coalesce(p_yarn_meta->>'gauge','')),60),'');
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'name',   nullif(left(btrim(coalesce(q.y->>'name','')),60),''),
      'color',  nullif(left(btrim(coalesce(q.y->>'color','')),40),''),
      'amount', case when (q.y->>'amount') ~ num then (q.y->>'amount')::numeric end,
      'unit',   case when q.y->>'unit' in ('볼','g') then q.y->>'unit' end,
      'ball_g', case when (q.y->>'ball_g') ~ num then (q.y->>'ball_g')::numeric end,
      'ball_m', case when (q.y->>'ball_m') ~ num then (q.y->>'ball_m')::numeric end,
      'weight', nullif(left(btrim(coalesce(q.y->>'weight','')),20),''),
      'fiber',  nullif(left(btrim(coalesce(q.y->>'fiber','')),20),''),
      'fibers', case when jsonb_typeof(q.y->'fibers')='object' and pg_column_size(q.y->'fibers') < 300 then q.y->'fibers' end,
      'rating', case when q.y->>'rating' in ('-1','0','1') then (q.y->>'rating')::int end,
      'rating_reason', nullif(left(btrim(coalesce(q.y->>'rating_reason','')),20),''),
      'color_hex', (select jsonb_agg(h.v) from (select hx.v from jsonb_array_elements_text(case when jsonb_typeof(q.y->'color_hex')='array' then q.y->'color_hex' else '[]'::jsonb end) hx(v) where hx.v ~ '^#[0-9A-Fa-f]{6}$' limit 4) h),
      'color_mode', case when q.y->>'color_mode' in ('solid','gradient','mix','melange') then q.y->>'color_mode' end,
      'brand', nullif(left(btrim(q.y->>'brand'), 40), ''),
      'color_families', (select jsonb_agg(left(cf.v,10)) from (select fx.v from jsonb_array_elements_text(case when jsonb_typeof(q.y->'color_families')='array' then q.y->'color_families' else '[]'::jsonb end) fx(v) where btrim(fx.v) <> '' limit 4) cf),
      'stash_id', case when (q.y->>'stash_id') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then q.y->>'stash_id' end)) order by q.ord), '[]'::jsonb)
    into v_yarns
    from (select t.y, t.ord from jsonb_array_elements(case when jsonb_typeof(p_yarn_meta->'yarns')='array' then p_yarn_meta->'yarns' else '[]'::jsonb end) with ordinality as t(y, ord)
          where jsonb_typeof(t.y)='object' and btrim(coalesce(t.y->>'name','')) <> '' limit 6) q;
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'type', case when q.n->>'type' in ('코바늘','대바늘','줄바늘','레이스 바늘') then q.n->>'type' end,
      'size', nullif(left(btrim(coalesce(q.n->>'size','')),30),''))) order by q.ord), '[]'::jsonb)
    into v_needles
    from (select t.n, t.ord from jsonb_array_elements(case when jsonb_typeof(p_yarn_meta->'needles')='array' then p_yarn_meta->'needles' else '[]'::jsonb end) with ordinality as t(n, ord)
          where jsonb_typeof(t.n)='object' and btrim(coalesce(t.n->>'size','')) <> '' limit 4) q;
  perform public.stash_restore(w.id);
  update public.yarn_catalog c set uses = greatest(0, c.uses - q.n) from (select catalog_id, count(*)::int n from public.yarn_entries where work_id = w.id and catalog_id is not null group by 1) q where c.id = q.catalog_id;
  delete from public.yarn_entries where work_id = w.id;
  update public.works set yarn_info = left(p_yarn, 200), yarns = v_yarns, needles = v_needles, gauge = v_gauge, item_type = v_item,
      finished_size = nullif(left(btrim(coalesce(p_yarn_meta->>'size','')),60),''),
      yarn_name = nullif(left(btrim(coalesce(p_yarn_meta->>'name','')),60),''), yarn_weight = nullif(left(btrim(coalesce(p_yarn_meta->>'weight','')),20),''),
      needle_size = nullif(left(btrim(coalesce(p_yarn_meta->>'needle','')),40),'')
    where id = w.id;
  select greatest(level_crochet, level_knit) into v_level from public.profiles where id = auth.uid();
  for y in select * from jsonb_array_elements(v_yarns) loop perform public.yarn_log_entry(w.id, y, v_needles, v_gauge, w.techniques, v_item, v_level); end loop;
  perform public.stash_consume(w.id);
  update public.posts set edited_at = now() where id = p_post;
end $function$;

-- event_selected_count(p_event uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.event_selected_count(p_event uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ select count(*)::int from public.event_applications where event_id = p_event and status in ('selected','done') $function$;

-- expand_prereqs(p_ids text[])  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.expand_prereqs(p_ids text[])
 RETURNS text[]
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with recursive r(id) as (
    select unnest(p_ids)
    union
    select unnest(t.prereq) from public.techniques t join r on t.id = r.id
  ) select array(select id from r);
$function$;

-- feed_ranked(p_limit integer, p_offset integer)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.feed_ranked(p_limit integer DEFAULT 30, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, author_id uuid, body text, photos text[], dong_code text, reply_count integer, like_count integer, created_at timestamp with time zone, author jsonb, score double precision, meetup_id uuid)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
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
      po.id, po.author_id, po.body, po.photos, po.dong_code, po.reply_count, po.like_count, po.created_at, po.meetup_id,
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
      * case when po.meetup_id is not null then 1.4 else 1.0 end     -- 모임 글 부스트
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
         case when rn > 2 then base * 0.3 else base end as score, meetup_id
  from ranked
  order by score desc, created_at desc
  limit p_limit offset p_offset;
$function$;

-- finalize_supporters()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.finalize_supporters()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; s1 integer; s2 integer; t text; n_done integer := 0; c public.supporter_cohorts; mvp jsonb := '[]'; done jsonb := '[]'; sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e';
begin
  for r in select * from public.supporters where status = 'active' and ends_at <= now() loop
    select coalesce(sum(points) filter (where segment=1),0), coalesce(sum(points) filter (where segment=2),0) into s1, s2 from public.point_events where supporter_id = r.id;
    t := case when s1 >= 100 and s2 >= 100 and s1 + s2 >= 300 then 'excellent' when s1 >= 100 and s2 >= 100 then 'basic' else 'none' end;
    update public.supporters set status = 'completed', tier = t, finalized_at = now() where id = r.id;
    if t <> 'none' then update public.profiles set supporter_badge = '1기 서포터' where id = r.user_id; end if;
    insert into public.notifications(recipient_id, actor_id, kind, snippet) values (r.user_id, sup, 'supporter',
      case t
        when 'none' then format('60일 서포터 활동이 끝났어요. 1구간 %s점·2구간 %s점으로 구간 조건(각 100점)에 조금 못 미쳤지만, 함께해 주셔서 정말 고마워요. 점수 기록은 마이 › 1기 서포터즈에 그대로 남고, 2기 모집 때 먼저 알려 드릴게요.', s1, s2)
        when 'basic' then format('60일 완주! 1구간 %s점·2구간 %s점, 기본 등급이에요. 프로필에 1기 서포터 뱃지가 붙었고 니트업 매거진을 보내 드려요. 배송지는 대표가 이 알림 뒤 지기 채팅으로 여쭤볼게요. 점수는 기록으로 남고 더 쌓이지는 않아요. MVP(상위 5명)는 1기 전원 종료 후 따로 알려 드려요.', s1, s2)
        else format('60일 완주! 누적 %s점, 우수 등급이에요. 1기 서포터 뱃지 + 니트업 매거진 + 레벨업 쿠션을 보내 드려요. 배송지는 대표가 이 알림 뒤 지기 채팅으로 여쭤볼게요. MVP(우수 중 상위 5명, 실 키트 추가)는 1기 전원 종료 후 따로 알려 드려요.', s1 + s2)
      end);
    done := done || jsonb_build_object('user_id', r.user_id, 'tier', t, 'seg1', s1, 'seg2', s2); n_done := n_done + 1;
  end loop;
  select * into c from public.supporter_cohorts order by id desc limit 1;
  if not exists (select 1 from public.supporters where cohort_id = c.id and status = 'active') and exists (select 1 from public.supporters where cohort_id = c.id and tier = 'excellent') and not exists (select 1 from public.supporters where cohort_id = c.id and tier = 'mvp') then
    with ranked as (select s.id, s.user_id, coalesce((select sum(points) from public.point_events e where e.supporter_id = s.id),0) total from public.supporters s where s.cohort_id = c.id and s.tier = 'excellent' order by total desc, s.id limit 5)
    update public.supporters s set tier = 'mvp' from ranked where s.id = ranked.id;
    select coalesce(jsonb_agg(user_id), '[]') into mvp from public.supporters where cohort_id = c.id and tier = 'mvp';
    insert into public.notifications(recipient_id, actor_id, kind, snippet) select user_id, sup, 'supporter', '축하해요! 1기 서포터즈 MVP(상위 5명)로 뽑혔어요. 실 키트를 추가로 보내 드려요. 배송지는 대표가 지기 채팅으로 여쭤볼게요.' from public.supporters where cohort_id = c.id and tier = 'mvp';
  end if;
  for r in select s.*, public.supporter_segment(s.started_at) seg, public.kst_date(now()) - public.kst_date(s.started_at) dayn from public.supporters s where s.status = 'active' loop
    if (r.seg = 1 and r.dayn = 23) or (r.seg = 2 and r.dayn = 53) then
      select coalesce(sum(points),0) into s1 from public.point_events where supporter_id = r.id and segment = r.seg;
      if s1 < 100 and not exists (select 1 from public.supporter_notices where supporter_id = r.id and notice_key = format('seg%s_d7', r.seg)) then   -- 2026-10-10: 100점 미만만
        insert into public.supporter_notices(supporter_id, notice_key) values (r.id, format('seg%s_d7', r.seg));
        insert into public.notifications(recipient_id, actor_id, kind, snippet) values (r.user_id, sup, 'supporter', format('%s구간 마감까지 7일! 지금 %s점, 100점까지 %s점 남았어요.', r.seg, s1, greatest(100 - s1, 0)));
      end if;
    end if;
  end loop;
  return jsonb_build_object('finalized', n_done, 'done', done, 'mvp', mvp);
end $function$;

-- follower_count(p_kind text, p_id uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.follower_count(p_kind text, p_id uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when auth.uid() is null then 0
    when p_kind = 'shop' then (select count(*)::int from public.shop_follows where shop_id = p_id)
    when p_kind = 'author' then (select count(*)::int from public.author_follows where author_id = p_id)
    else 0 end $function$;

-- friend_milestone_check()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.friend_milestone_check()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n int; v_last int; v_goal int;
begin
  begin
    if new.status = 'accepted' and (tg_op = 'INSERT' or old.status is distinct from new.status) then
      n := public._friend_pairs();
      select coalesce(nullif(value,'')::int, 0) into v_last from public.jigi_config where key = 'friend_milestone'; v_last := coalesce(v_last, 0);
      select max(g) into v_goal from (select unnest(array[10,50,100,200,300,500,1000]) g union all select generate_series(2000, greatest(2000, n), 1000)) x where g <= n;
      if v_goal is not null and v_goal > v_last then
        insert into public.jigi_config(key, value) values ('friend_milestone', v_goal::text) on conflict (key) do update set value = excluded.value;
        insert into public.jigi_reminders(due_at, text) values (now(),
          '🧶 뜨친 '||v_goal||'쌍 돌파!'||E'\n\n'||
          '방금 뜨개동네에서 맺어진 뜨친이 '||n||'쌍이 됐어요. 신청을 상대가 수락한 쌍만 센 숫자이고, 테스트·운영 계정은 빼고 실제 회원만 셌어요.'||E'\n\n'||
          '왜 알려 드리나요: 대표님이 "뜨친 성사 수는 앱 홍보에 좋은 소재"라고 하셔서, 고비를 넘을 때마다 한 번씩 알려 드리기로 했어요. 다음 고비는 '||public._friend_next_goal(n)||'쌍이에요.'||E'\n\n'||
          '지금 하실 수 있는 일:'||E'\n'||
          '① 콘솔 › 현황·분석 › 대시보드의 ''뜨친'' 칸에서 이번 주 성사 수, 채팅까지 간 쌍, 동네별 숫자를 확인하세요.'||E'\n'||
          '② 같은 칸의 ''홍보에 쓸 문구''를 눌러 복사해 뉴스레터·인스타그램·광고 문구에 쓰실 수 있어요.'||E'\n'||
          '③ 앱 첫 화면 공지나 ''공지·새 소식''에 올리고 싶으시면 Claude 에게 "뜨친 '||v_goal||'쌍 소식 올려줘"라고 하시면 문구와 이미지를 먼저 보여 드려요.'||E'\n\n'||
          '참고: 누가 누구와 뜨친인지는 이 알림에도 콘솔 화면에도 나오지 않아요. 숫자만 다뤄요.');
      end if;
    end if;
  exception when others then null;
  end;
  return null;
end $function$;

-- friend_request_remind()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.friend_request_remind()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; n int := 0;
begin
  for r in select f.requester_id, f.addressee_id, p.nickname from public.friendships f
            join public.profiles p on p.id = f.requester_id join public.profiles a on a.id = f.addressee_id
           where f.status = 'pending' and f.reminded_at is null and f.created_at < now() - interval '3 days' and f.created_at > now() - interval '60 days'
             and p.deleted_at is null and p.suspended_at is null and a.deleted_at is null and a.suspended_at is null
             and not public.is_blocked(f.addressee_id, f.requester_id)
           order by f.created_at limit 200 loop
    insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
      values (r.addressee_id, r.requester_id, 'remind', left(coalesce(r.nickname,'이웃') || ' 님의 뜨친 신청이 기다리고 있어요', 80), jsonb_build_object('type','profile','id',r.requester_id));
    update public.friendships set reminded_at = now() where requester_id = r.requester_id and addressee_id = r.addressee_id;
    n := n + 1;
  end loop;
  return n;
end $function$;

-- gauge_clean(g jsonb)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.gauge_clean(g jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select case when jsonb_typeof(g) = 'object' and (g->>'sts') ~ '^[0-9]+(\.[0-9]+)?$' and (g->>'rows') ~ '^[0-9]+(\.[0-9]+)?$'
      and (g->>'sts')::numeric between 3 and 80 and (g->>'rows')::numeric between 2 and 150
    then jsonb_strip_nulls(jsonb_build_object('sts', (g->>'sts')::numeric, 'rows', (g->>'rows')::numeric, 'needle', nullif(left(g->>'needle', 20), ''), 'stitch', nullif(left(g->>'stitch', 20), ''), 'size', '10x10'))
    else null end;
$function$;

-- get_supporter_status()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.get_supporter_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.supporters; c public.supporter_cohorts; seg smallint; s1 integer; s2 integer; d date := public.kst_date(now()); dayn integer; n integer;
begin
  select * into c from public.supporter_cohorts order by id desc limit 1;
  select count(*) into n from public.supporters where cohort_id = c.id;
  select * into s from public.supporters where user_id = auth.uid() order by id desc limit 1;
  if s.id is null then return jsonb_build_object('supporter', false, 'is_open', c.is_open and n < c.capacity, 'remaining', greatest(c.capacity - n, 0), 'cohort', c.name, 'waitlisted', exists (select 1 from public.supporter_waitlist where user_id = auth.uid())); end if;
  select coalesce(sum(points) filter (where segment=1),0), coalesce(sum(points) filter (where segment=2),0) into s1, s2 from public.point_events where supporter_id = s.id;
  dayn := d - public.kst_date(s.started_at); seg := public.supporter_segment(s.started_at);
  return jsonb_build_object('supporter', true, 'id', s.id, 'status', s.status, 'tier', s.tier, 'ref_code', s.ref_code, 'started_at', s.started_at, 'ends_at', s.ends_at, 'day', dayn + 1, 'segment', seg,
    'seg1', s1, 'seg2', s2, 'total', s1 + s2, 'seg_days_left', case seg when 1 then 30 - dayn when 2 then 60 - dayn else 0 end, 'days_left', greatest(60 - dayn, 0),
    'expected_tier', case when s1 >= 100 and s2 >= 100 and s1 + s2 >= 300 then 'excellent' when s1 >= 100 and s2 >= 100 then 'basic' else 'none' end,
    'today', (select jsonb_object_agg(kind, pts) from (select kind, sum(points) pts from public.point_events where supporter_id = s.id and kst_date = d and points > 0 group by kind) t),
    'recent', (select coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'points', points, 'at', created_at) order by id desc), '[]') from (select * from public.point_events where supporter_id = s.id order by id desc limit 20) r),
    'badge', (select supporter_badge from public.profiles where id = auth.uid()), 'cohort', c.name, 'is_open', c.is_open and n < c.capacity, 'remaining', greatest(c.capacity - n, 0));
end $function$;

-- guard_friend_request()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.guard_friend_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

-- handle_friendship_accepted()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.handle_friendship_accepted()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

-- handle_new_user()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

-- handle_report()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.handle_report()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if (select count(*) from public.reports where reported_id = new.reported_id) >= 3 then
    update public.profiles set suspended_at = coalesce(suspended_at, now()) where id = new.reported_id;
  end if;
  return new;
end $function$;

-- is_active_user()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.is_active_user()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from public.profiles where id = auth.uid() and suspended_at is null);
$function$;

-- is_admin()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from public.admins where profile_id = auth.uid());
$function$;

-- is_blocked(a uuid, b uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.is_blocked(a uuid, b uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select (a = auth.uid() or b = auth.uid()) and exists (
    select 1 from public.friendships
    where status = 'blocked'
      and ((requester_id = a and addressee_id = b) or (requester_id = b and addressee_id = a))
  );
$function$;

-- is_friend(a uuid, b uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.is_friend(a uuid, b uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select (a = auth.uid() or b = auth.uid()) and exists (
    select 1 from public.friendships
    where status = 'accepted'
      and ((requester_id = a and addressee_id = b) or (requester_id = b and addressee_id = a))
  );
$function$;

-- is_room_creator(p_room_id uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.is_room_creator(p_room_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from public.rooms where id = p_room_id and created_by = auth.uid());
$function$;

-- is_room_member(p_room_id uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.is_room_member(p_room_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.room_members
    where room_id = p_room_id and profile_id = auth.uid()
  );
$function$;

-- is_test_user(p_user uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.is_test_user(p_user uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ select coalesce((select is_test from public.profiles where id = p_user), false) $function$;

-- jigi_call(p_route text)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.jigi_call(p_route text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_secret text;
begin
  select value into v_secret from public.jigi_config where key = 'hook_secret';
  perform net.http_post(
    url := 'https://thfcrodfaitzrzlrxyir.supabase.co/functions/v1/jigi',
    body := jsonb_build_object('route', p_route),
    headers := jsonb_build_object('Content-Type','application/json','x-jigi-secret', v_secret),
    timeout_milliseconds := 5000);
exception when others then null;   -- 호출 실패가 글쓰기를 막으면 안 된다
end $function$;

-- jigi_on_change()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.jigi_on_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  begin
    if (to_jsonb(new)->>'mod_scanned_at') is not null then return null; end if;   -- 지기가 쓴 답글 등(이미 검사 표시)
    perform public.jigi_call('scan');
  exception when others then null;   -- 어떤 경우에도 원래 동작(글쓰기·신고)을 막지 않는다
  end;
  return null;
end $function$;

-- jigi_on_shop_claim()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.jigi_on_shop_claim()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  begin perform public.jigi_call('shop_claim'); exception when others then null; end;
  return null;
end $function$;

-- jigi_remind_call(p_route text)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.jigi_remind_call(p_route text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_secret text;
begin
  if p_route = 'tick' and not exists (select 1 from public.jigi_reminders where sent_at is null and due_at <= now()) then return; end if;
  select value into v_secret from public.jigi_config where key = 'hook_secret';
  perform net.http_post(url := 'https://thfcrodfaitzrzlrxyir.supabase.co/functions/v1/jigi-remind', body := jsonb_build_object('route', p_route),
    headers := jsonb_build_object('Content-Type','application/json','x-jigi-secret', v_secret), timeout_milliseconds := 8000);
exception when others then null;
end $function$;

-- jigi_tool(p_name text, p_args jsonb, p_actor text, p_approved boolean)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.jigi_tool(p_name text, p_args jsonb, p_actor text DEFAULT 'ai'::text, p_approved boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  jigi constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e';
  a jsonb := coalesce(p_args, '{}'::jsonb);
  v_item bigint := nullif(a->>'item_id','')::bigint;
  v_post uuid; v_user uuid; v_txt text; v_days int; v_act bigint; r record; j jsonb; n int;
  solo constant text[] := array['hide_temp','add_to_feedback_group'];
  need constant text[] := array['unhide','send_warning','restrict_posting','dismiss_item','reply_as_jigi','notify_reporter','link_technique_alias','save_rule','delete_rule','set_rule_enabled','revert_action','exclude_candidate'];
begin
  if p_actor not in ('ai','admin') then raise exception 'bad actor'; end if;
  if p_name = any(need) and not p_approved then return jsonb_build_object('error','needs_approval','tool',p_name); end if;

  -- ===== 읽기 =====
  if p_name = 'get_item' then
    select to_jsonb(m) into j from public.mod_items m where m.id = v_item; return coalesce(j, jsonb_build_object('error','not_found'));
  elsif p_name = 'list_open_items' then
    select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'kind',m.kind,'severity',m.severity,'summary',m.summary,'target_type',m.target_type,'target_id',m.target_id,'created_at',m.created_at,'suggestion',m.ai_suggestion)
      order by case m.severity when 'urgent' then 0 when 'today' then 1 else 2 end, m.created_at), '[]'::jsonb) into j from public.mod_items m where m.status='open';
    return j;
  elsif p_name = 'get_post_thread' then
    v_post := (a->>'post_id')::uuid;
    select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'author',pr.nickname,'author_id',p.author_id,'body',left(p.body,500),'hidden',p.hidden,'created_at',p.created_at,'is_target',p.id=v_post) order by p.created_at), '[]'::jsonb) into j
      from public.posts p left join public.profiles pr on pr.id = p.author_id
      where p.id = v_post or p.id = (select parent_id from public.posts where id = v_post) or p.parent_id = coalesce((select parent_id from public.posts where id = v_post), v_post);
    return j;
  elsif p_name = 'get_user_summary' then   -- 연락처·배송지·이메일은 넣지 않는다
    v_user := (a->>'user_id')::uuid;
    select jsonb_build_object('id',pr.id,'nickname',pr.nickname,'joined_days',floor(extract(epoch from now()-pr.created_at)/86400),'cert_count',pr.cert_count,'act_level',pr.act_level,
      'suspended',pr.suspended_at is not null,'post_restricted_until',pr.post_restricted_until,
      'posts_7d',(select count(*) from public.posts p where p.author_id=pr.id and p.created_at>now()-interval '7 days'),
      'reports_received',(select count(*) from public.post_reports x join public.posts p on p.id=x.post_id where p.author_id=pr.id)+(select count(*) from public.reports x where x.reported_id=pr.id),
      'warnings',(select count(*) from public.mod_actions m where m.action='send_warning' and m.target=pr.id::text and m.reverted_at is null),
      'past_items',(select count(*) from public.mod_items m where m.author_id=pr.id)) into j from public.profiles pr where pr.id = v_user;
    return coalesce(j, jsonb_build_object('error','not_found'));
  elsif p_name = 'get_stats' then
    v_days := least(greatest(coalesce((a->>'days')::int,1),1),90);
    return jsonb_build_object('days',v_days,
      'posts',(select count(*) from public.posts where parent_id is null and created_at>now()-make_interval(days=>v_days)),
      'replies',(select count(*) from public.posts where parent_id is not null and created_at>now()-make_interval(days=>v_days)),
      'signups',(select count(*) from public.profiles where created_at>now()-make_interval(days=>v_days)),
      'meetups',(select count(*) from public.meetups where created_at>now()-make_interval(days=>v_days)),
      'works',(select count(*) from public.works where created_at>now()-make_interval(days=>v_days)),
      'reports',(select count(*) from public.post_reports where created_at>now()-make_interval(days=>v_days))+(select count(*) from public.reports where created_at>now()-make_interval(days=>v_days)),
      'auto_done',(select count(*) from public.mod_items where status='auto_done' and created_at>now()-make_interval(days=>v_days)));
  elsif p_name = 'list_feedback_groups' then
    select coalesce(jsonb_agg(to_jsonb(f) order by f.count desc), '[]'::jsonb) into j from public.feedback_groups f where f.status <> 'done'; return j;
  elsif p_name = 'list_technique_candidates' then
    select coalesce(jsonb_agg(to_jsonb(c) order by c.n_users desc), '[]'::jsonb) into j from public.technique_candidates c where c.status='open'; return j;
  elsif p_name = 'list_rules' then
    select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb) into j from public.ai_rules x; return j;
  elsif p_name = 'list_auto_actions' then
    select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'action',m.action,'target',m.target,'item_id',m.item_id,'created_at',m.created_at,'reverted',m.reverted_at is not null) order by m.id desc), '[]'::jsonb) into j
      from (select * from public.mod_actions where actor='ai' and created_at > now()-interval '3 days' order by id desc limit 30) m; return j;

  -- ===== AI 단독 가능 =====
  elsif p_name = 'hide_temp' then
    v_post := (a->>'post_id')::uuid;
    select hidden, hidden_by_mod into r from public.posts where id = v_post; if not found then return jsonb_build_object('error','not_found'); end if;
    update public.posts set hidden = true, hidden_by_mod = true where id = v_post;
    insert into public.mod_actions(item_id, actor, action, target, before, after) values (v_item, p_actor, 'hide_temp', v_post::text, jsonb_build_object('hidden',r.hidden,'hidden_by_mod',r.hidden_by_mod), jsonb_build_object('hidden',true,'hidden_by_mod',true)) returning id into v_act;
    return jsonb_build_object('ok',true,'action_id',v_act);
  elsif p_name = 'add_to_feedback_group' then
    v_post := (a->>'post_id')::uuid;
    if nullif(a->>'group_id','') is not null then
      update public.feedback_groups set post_ids = case when v_post = any(post_ids) then post_ids else post_ids || v_post end, count = cardinality(case when v_post = any(post_ids) then post_ids else post_ids || v_post end) where id = (a->>'group_id')::bigint returning id into n;
    else
      insert into public.feedback_groups(title, count, post_ids, reply_draft) values (left(coalesce(a->>'title','앱 불만'),80), 1, array[v_post], nullif(a->>'reply_draft','')) returning id into n;
    end if;
    return jsonb_build_object('ok',true,'group_id',n);

  -- ===== 대표 승인 필요 =====
  elsif p_name = 'unhide' then
    v_post := (a->>'post_id')::uuid;
    select hidden, hidden_by_mod into r from public.posts where id = v_post; if not found then return jsonb_build_object('error','not_found'); end if;
    update public.posts set hidden = false, hidden_by_mod = false where id = v_post;
    insert into public.mod_actions(item_id, actor, action, target, before, after) values (v_item, p_actor, 'unhide', v_post::text, jsonb_build_object('hidden',r.hidden,'hidden_by_mod',r.hidden_by_mod), jsonb_build_object('hidden',false,'hidden_by_mod',false)) returning id into v_act;
  elsif p_name = 'send_warning' then
    v_user := (a->>'user_id')::uuid; v_txt := left(btrim(coalesce(a->>'text','')),200); if v_txt = '' then return jsonb_build_object('error','text_required'); end if;
    insert into public.notifications(recipient_id, actor_id, kind, snippet) values (v_user, jigi, 'notice', v_txt) returning id into r;
    insert into public.mod_actions(item_id, actor, action, target, after) values (v_item, p_actor, 'send_warning', v_user::text, jsonb_build_object('text',v_txt,'notification_id',r.id)) returning id into v_act;
  elsif p_name = 'restrict_posting' then
    v_user := (a->>'user_id')::uuid; v_days := least(greatest(coalesce((a->>'days')::int,7),1),30);
    select post_restricted_until as u into r from public.profiles where id = v_user; if not found then return jsonb_build_object('error','not_found'); end if;
    update public.profiles set post_restricted_until = now() + make_interval(days=>v_days) where id = v_user;
    insert into public.notifications(recipient_id, actor_id, kind, snippet) values (v_user, jigi, 'notice', format('커뮤니티 가이드라인 위반으로 %s일 동안 글쓰기가 제한돼요. 문의는 설정 › 지기에게 말하기로 남겨 주세요.', v_days));
    insert into public.mod_actions(item_id, actor, action, target, before, after) values (v_item, p_actor, 'restrict_posting', v_user::text, jsonb_build_object('until',r.u), jsonb_build_object('days',v_days)) returning id into v_act;
  elsif p_name = 'dismiss_item' then
    update public.mod_items set status='dismissed', resolved_at=now(), resolved_by=p_actor, resolution=left(coalesce(a->>'note','문제 없음'),200) where id = v_item and status='open';
    insert into public.mod_actions(item_id, actor, action, target) values (v_item, p_actor, 'dismiss_item', v_item::text) returning id into v_act;
    return jsonb_build_object('ok',true,'action_id',v_act);
  elsif p_name = 'reply_as_jigi' then
    v_post := (a->>'post_id')::uuid; v_txt := left(btrim(coalesce(a->>'text','')),500); if v_txt = '' then return jsonb_build_object('error','text_required'); end if;
    insert into public.posts(author_id, parent_id, body, mod_scanned_at) values (jigi, coalesce((select parent_id from public.posts where id=v_post), v_post), v_txt, now()) returning id into r;
    insert into public.mod_actions(item_id, actor, action, target, after) values (v_item, p_actor, 'reply_as_jigi', v_post::text, jsonb_build_object('reply_id',r.id,'text',v_txt)) returning id into v_act;
  elsif p_name = 'notify_reporter' then
    v_post := (a->>'post_id')::uuid; v_txt := left(btrim(coalesce(a->>'text','신고해 주신 내용을 확인하고 조치했어요. 알려 주셔서 고마워요.')),200);
    insert into public.notifications(recipient_id, actor_id, kind, snippet) select distinct reporter_id, jigi, 'notice', v_txt from public.post_reports where post_id = v_post;
    get diagnostics n = row_count;
    insert into public.mod_actions(item_id, actor, action, target, after) values (v_item, p_actor, 'notify_reporter', v_post::text, jsonb_build_object('count',n,'text',v_txt)) returning id into v_act;
  elsif p_name = 'link_technique_alias' then
    if not exists (select 1 from public.techniques where id = a->>'technique_id') then return jsonb_build_object('error','technique_not_found'); end if;
    select * into r from public.technique_candidates where id = (a->>'candidate_id')::bigint; if not found then return jsonb_build_object('error','not_found'); end if;
    insert into public.technique_aliases(alias, technique_id) select distinct lower(regexp_replace(v,'\s+','','g')), a->>'technique_id' from unnest(r.raw_variants || r.label) v on conflict (alias) do update set technique_id = excluded.technique_id;
    update public.technique_candidates set status='linked', alias_of=a->>'technique_id', updated_at=now() where id = r.id;
    insert into public.mod_actions(item_id, actor, action, target, before, after) values (v_item, p_actor, 'link_technique_alias', r.id::text, jsonb_build_object('status',r.status,'variants',to_jsonb(r.raw_variants || r.label)), jsonb_build_object('technique_id',a->>'technique_id')) returning id into v_act;
  elsif p_name = 'exclude_candidate' then
    update public.technique_candidates set status='excluded', updated_at=now() where id = (a->>'candidate_id')::bigint;
    insert into public.mod_actions(item_id, actor, action, target) values (v_item, p_actor, 'exclude_candidate', a->>'candidate_id') returning id into v_act;
  elsif p_name = 'save_rule' then
    if coalesce(a->>'action','') not in ('hide_temp','hide_temp+restrict7','report_only') then return jsonb_build_object('error','bad_action'); end if;
    insert into public.ai_rules(title, rule_text, condition, action, level) values (left(coalesce(a->>'title','규칙'),60), left(coalesce(a->>'rule_text',''),300), coalesce(a->'condition','{}'::jsonb), a->>'action', least(greatest(coalesce((a->>'level')::int,2),0),2)) returning id into n;
    insert into public.mod_actions(actor, action, target, after) values (p_actor, 'save_rule', n::text, a) returning id into v_act;
    return jsonb_build_object('ok',true,'rule_id',n,'action_id',v_act);
  elsif p_name = 'delete_rule' then
    select to_jsonb(x) into j from public.ai_rules x where x.id = (a->>'rule_id')::bigint; delete from public.ai_rules where id = (a->>'rule_id')::bigint;
    insert into public.mod_actions(actor, action, target, before) values (p_actor, 'delete_rule', a->>'rule_id', j) returning id into v_act;
  elsif p_name = 'set_rule_enabled' then
    update public.ai_rules set enabled = coalesce((a->>'enabled')::boolean, enabled), level = coalesce((a->>'level')::smallint, level) where id = (a->>'rule_id')::bigint;
    return jsonb_build_object('ok',true);
  elsif p_name = 'revert_action' then
    select * into r from public.mod_actions where id = (a->>'action_id')::bigint and reverted_at is null; if not found then return jsonb_build_object('error','not_found_or_reverted'); end if;
    if r.action in ('hide_temp','unhide') then update public.posts set hidden = (r.before->>'hidden')::boolean, hidden_by_mod = coalesce((r.before->>'hidden_by_mod')::boolean,false) where id = r.target::uuid;
    elsif r.action = 'restrict_posting' then update public.profiles set post_restricted_until = (r.before->>'until')::timestamptz where id = r.target::uuid;
    elsif r.action = 'send_warning' then delete from public.notifications where id = (r.after->>'notification_id')::uuid;
    elsif r.action = 'reply_as_jigi' then delete from public.posts where id = (r.after->>'reply_id')::uuid;
    elsif r.action = 'link_technique_alias' then delete from public.technique_aliases where alias in (select lower(regexp_replace(v,'\s+','','g')) from jsonb_array_elements_text(r.before->'variants') v); update public.technique_candidates set status='open', alias_of=null where id = r.target::bigint;
    elsif r.action = 'dismiss_item' then update public.mod_items set status='open', resolved_at=null, resolved_by=null, resolution=null where id = r.target::bigint;
    elsif r.action = 'delete_rule' then insert into public.ai_rules(title, rule_text, condition, action, level, enabled) values (r.before->>'title', r.before->>'rule_text', r.before->'condition', r.before->>'action', (r.before->>'level')::smallint, (r.before->>'enabled')::boolean);
    elsif r.action = 'save_rule' then delete from public.ai_rules where id = r.target::bigint;
    else return jsonb_build_object('error','cannot_revert','action',r.action); end if;
    update public.mod_actions set reverted_at = now() where id = r.id;
    if r.item_id is not null and r.action in ('hide_temp') then update public.mod_items set status='open', resolved_at=null, resolved_by=null where id = r.item_id and status='auto_done'; end if;
    insert into public.mod_actions(item_id, actor, action, target) values (r.item_id, p_actor, 'revert:'||r.action, r.id::text) returning id into v_act;
    return jsonb_build_object('ok',true,'action_id',v_act);
  else
    return jsonb_build_object('error','unknown_tool','tool',p_name);   -- 영구 정지·삭제·개인정보 조회·결제 등은 도구 자체가 없다
  end if;

  if v_item is not null and coalesce((a->>'resolve')::boolean, false) then
    update public.mod_items set status='done', resolved_at=now(), resolved_by=p_actor, resolution=coalesce(resolution||' · ','')||p_name where id = v_item and status in ('open','auto_done');
  end if;
  return jsonb_build_object('ok',true,'action_id',v_act);
end $function$;

-- join_meetup(p_meetup_id uuid, p_note text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.join_meetup(p_meetup_id uuid, p_note text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_room uuid; v_public boolean; v_cap smallint; v_cnt integer; v_starts timestamptz; v_note text := nullif(btrim(left(coalesce(p_note,''), 200)), '');
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  if not public.is_active_user() then raise exception '정지된 계정이에요'; end if;
  select room_id, is_public, capacity, participant_count, starts_at into v_room, v_public, v_cap, v_cnt, v_starts from public.meetups where id = p_meetup_id;
  if v_room is null then raise exception '모임을 찾을 수 없어요'; end if;
  if exists (select 1 from public.room_members where room_id = v_room and profile_id = auth.uid()) then return v_room; end if;
  if v_starts < now() then raise exception '이미 끝난 모임이에요'; end if;
  if not v_public then raise exception '초대된 사람만 참여할 수 있어요'; end if;
  if v_cap is not null and v_cnt >= v_cap then raise exception '정원이 찼어요'; end if;
  if v_note is not null and public.contains_banned(v_note) then raise exception '커뮤니티 가이드라인에 맞지 않는 표현이 있어요'; end if;
  insert into public.room_members (room_id, profile_id) values (v_room, auth.uid());
  insert into public.messages (room_id, sender_id, body) values (v_room, auth.uid(), '🙋 모임에 참여했어요' || coalesce(E'\n' || v_note, ''));
  return v_room;
end $function$;

-- join_supporter_room()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.join_supporter_room()
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare rid uuid; sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e'; nick text; n integer;
begin
  if (public.supporter_of(auth.uid())).id is null then raise exception '서포터만 입장할 수 있어요'; end if;
  select id into rid from public.rooms where kind = 'group' and title = '1기 서포터즈' and created_by = sup limit 1;
  if rid is null then
    insert into public.rooms(kind, title, created_by) values ('group', '1기 서포터즈', sup) returning id into rid;
    insert into public.room_members(room_id, profile_id) values (rid, sup) on conflict do nothing;
    insert into public.messages(room_id, sender_id, body, by_ai, support_seen) values (rid, sup,
      E'1기 서포터즈 방이에요. 지기 AI가 함께 있어요.\n\n이 방의 약속\n1. 서로 존댓말로, 다른 회원 이야기는 좋게만.\n2. 앱을 쓰다 불편한 점·바라는 기능은 여기 편하게 적어 주세요. 버그는 서포터 화면의 [버그 제보 · 제안]으로 보내면 채택 시 10점이에요.\n3. 사진·후기·질문 모두 환영. 광고·외부 판매 링크는 안 돼요.\n4. 이 방의 대화는 지기 AI가 매일 정리해서 대표에게 전해요(누가 무엇을 원하는지 빠짐없이 반영하려고요). 연락처·주소 같은 개인정보는 적지 말아 주세요.\n5. 점수·구간은 마이 › 설정 › 1기 서포터즈에서 확인할 수 있어요.', true, true);
  end if;
  insert into public.room_members(room_id, profile_id) values (rid, auth.uid()) on conflict do nothing;
  get diagnostics n = row_count;
  if n > 0 then
    select nickname into nick from public.profiles where id = auth.uid();
    insert into public.messages(room_id, sender_id, body, by_ai, support_seen) values (rid, sup, format('%s님, 1기 서포터즈에 오신 걸 환영해요! 🧶 위에 적힌 방의 약속을 한 번 읽어 주시고, 첫 인사 남겨 주세요. 궁금한 건 언제든 여기서 물어보셔도 돼요.', coalesce(nick,'새 서포터')), true, true);
  end if;
  return rid;
end $function$;

-- join_supporters()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.join_supporters()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c public.supporter_cohorts; s public.supporters; n integer; code text; uid uuid := auth.uid();
begin
  if uid is null then raise exception '로그인이 필요해요'; end if;
  select * into c from public.supporter_cohorts order by id desc limit 1 for update;   -- 정원 검사와 등록을 같은 잠금 안에서
  select * into s from public.supporters where user_id = uid and cohort_id = c.id;
  if s.id is not null then return public.get_supporter_status(); end if;
  select count(*) into n from public.supporters where cohort_id = c.id;
  if not c.is_open or n >= c.capacity then update public.supporter_cohorts set is_open = false where id = c.id; return jsonb_build_object('error','FULL'); end if;
  loop code := upper(substr(encode(extensions.gen_random_bytes(4),'hex'), 1, 6)); exit when not exists (select 1 from public.supporters where ref_code = code); end loop;
  insert into public.supporters(user_id, cohort_id, started_at, ends_at, ref_code) values (uid, c.id, now(), now() + interval '60 days', code);
  if n + 1 >= c.capacity then update public.supporter_cohorts set is_open = false where id = c.id; end if;
  return public.get_supporter_status();
end $function$;

-- join_waitlist()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.join_waitlist()
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ insert into public.supporter_waitlist(user_id) values (auth.uid()) on conflict do nothing $function$;

-- kb_bump(p_id bigint)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.kb_bump(p_id bigint)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ update public.support_kb set uses = uses + 1 where id = p_id $function$;

-- kst_date(t timestamp with time zone)  acl: {=X/postgres,postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.kst_date(t timestamp with time zone)
 RETURNS date
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$ select (t at time zone 'Asia/Seoul')::date $function$;

-- leave_meetup(p_meetup_id uuid, p_note text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.leave_meetup(p_meetup_id uuid, p_note text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_room uuid; v_host uuid; v_title text; v_note text := nullif(btrim(left(coalesce(p_note,''), 200)), '');
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  select room_id, created_by, title into v_room, v_host, v_title from public.meetups where id = p_meetup_id;
  if v_room is null then raise exception '모임을 찾을 수 없어요'; end if;
  if v_host = auth.uid() then raise exception '주최자는 나갈 수 없어요. 모임 취소를 이용해 주세요'; end if;
  if not exists (select 1 from public.room_members where room_id = v_room and profile_id = auth.uid()) then return; end if;
  if v_note is not null and public.contains_banned(v_note) then v_note := null; end if;
  insert into public.messages (room_id, sender_id, body) values (v_room, auth.uid(), '👋 모임 참여를 취소했어요' || coalesce(E'\n' || v_note, ''));
  delete from public.room_members where room_id = v_room and profile_id = auth.uid();
  perform public.push_notification(v_host, auth.uid(), 'meetup_leave', null, null, p_meetup_id, v_title || coalesce(' · ' || v_note, ''));
end $function$;

-- link_work_event(p_post uuid, p_event uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.link_work_event(p_post uuid, p_event uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_work uuid; v_kind text; v_app uuid;
begin
  select w.id into v_work from public.posts p join public.works w on w.id = p.work_id where p.id = p_post and w.profile_id = auth.uid();
  if v_work is null then raise exception '내 완성작품 인증이 아니에요'; end if;
  select a.id, e.kind into v_app, v_kind from public.event_applications a join public.events e on e.id = a.event_id
    where a.event_id = p_event and a.profile_id = auth.uid() and a.status in ('selected','done');
  if v_app is null then raise exception '선정된 이벤트가 아니에요'; end if;
  update public.works set event_id = p_event, sponsored = (v_kind = 'sample') where id = v_work;
  update public.event_applications set status = 'done', work_id = v_work, done_at = now() where id = v_app;
end $function$;

-- log_access(p_kind text, p_target text, p_n integer)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.log_access(p_kind text, p_target text DEFAULT NULL::text, p_n integer DEFAULT NULL::integer)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  insert into public.access_logs(actor, kind, target, n) values (auth.uid(), p_kind, left(p_target, 200), p_n) $function$;

-- log_skill_events()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.log_skill_events()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare src text; t text;
begin
  src := case when new.verified_skills is distinct from old.verified_skills then 'cert' else 'manual' end;
  if new.skills is distinct from old.skills then
    foreach t in array coalesce(new.skills,'{}') loop
      if not (t = any(coalesce(old.skills,'{}'))) then insert into public.skill_events(profile_id,kind,technique_id,source) values (new.id,'add',t,src); end if;
    end loop;
    foreach t in array coalesce(old.skills,'{}') loop
      if not (t = any(coalesce(new.skills,'{}'))) then insert into public.skill_events(profile_id,kind,technique_id,source) values (new.id,'remove',t,src); end if;
    end loop;
  end if;
  if new.level_crochet is distinct from old.level_crochet then insert into public.skill_events(profile_id,kind,craft,level,source) values (new.id,'level','crochet',new.level_crochet,src); end if;
  if new.level_knit is distinct from old.level_knit then insert into public.skill_events(profile_id,kind,craft,level,source) values (new.id,'level','knitting',new.level_knit,src); end if;
  return new;
end $function$;

-- lv_name(l integer)  acl: {=X/postgres,postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.lv_name(l integer)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$ select (array['입문','초급','중급','상급','전문'])[l]; $function$;

-- lv_of(p_user uuid, p_craft text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.lv_of(p_user uuid, p_craft text)
 RETURNS integer
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select coalesce(max(level), 0) from public.lv_stats(p_user, p_craft) where done * 2 >= total;
$function$;

-- lv_stats(p_user uuid, p_craft text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.lv_stats(p_user uuid, p_craft text)
 RETURNS TABLE(level integer, total integer, done integer)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select t.level::int, count(*)::int, count(*) filter (where t.id = any(coalesce(p.skills, '{}')))::int
  from public.techniques t cross join (select skills from public.profiles where id = p_user) p
  where t.craft = p_craft and not coalesce(t.hidden, false) group by t.level order by t.level;
$function$;

-- mark_class_paid(p_id bigint, p_paid boolean)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.mark_class_paid(p_id bigint, p_paid boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a public.class_applications; sp public.shop_posts;
begin
  select * into a from public.class_applications where id = p_id;
  if a.id is null or public.class_host(a.post_id) is distinct from auth.uid() then raise exception '클래스를 연 사람만 확인할 수 있어요'; end if;
  if a.status <> 'accepted' then raise exception '확정된 신청만 입금 확인할 수 있어요'; end if;
  update public.class_applications set paid_at = case when p_paid then now() else null end where id = a.id;
  select * into sp from public.shop_posts where id = a.post_id;
  if p_paid then insert into public.notifications(recipient_id, actor_id, kind, snippet, link) values (a.profile_id, auth.uid(), 'notice', format('「%s」 입금이 확인됐어요. 클래스에서 만나요!', left(sp.title, 40)), jsonb_build_object('type','class','id',a.post_id)); end if;
end $function$;

-- mark_solved(p_post uuid, p_reply uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.mark_solved(p_post uuid, p_reply uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a uuid; ra uuid; rp uuid;
begin
  select author_id into a from public.posts where id = p_post and parent_id is null;
  if a is null or a <> auth.uid() then raise exception '내 글만 표시할 수 있어요'; end if;
  if p_reply is not null then
    select author_id, parent_id into ra, rp from public.posts where id = p_reply;
    if rp is distinct from p_post then raise exception '이 글의 댓글이 아니에요'; end if;
  end if;
  update public.posts set solved_reply_id = p_reply where id = p_post;
  if p_reply is not null then perform public.push_notification(ra, auth.uid(), 'solved', p_reply, p_post, null, null); end if;
end $function$;

-- meetup_app_summary(p_meetup uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.meetup_app_summary(p_meetup uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'mine', (select status from public.meetup_applications where meetup_id = p_meetup and profile_id = auth.uid()),
    'waiting', case when exists (select 1 from public.meetups where id = p_meetup and created_by = auth.uid())
                    then (select count(*) from public.meetup_applications where meetup_id = p_meetup and status = 'applied') else null end) $function$;

-- meetup_applicants(p_meetup uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.meetup_applicants(p_meetup uuid)
 RETURNS TABLE(profile_id uuid, nickname text, avatar_url text, status text, note text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not exists (select 1 from public.meetups where id = p_meetup and created_by = auth.uid()) and not public.is_admin() then raise exception '개설자만 볼 수 있어요'; end if;
  return query select a.profile_id, p.nickname, p.avatar_url, a.status, a.note, a.created_at
    from public.meetup_applications a join public.profiles p on p.id = a.profile_id
    where a.meetup_id = p_meetup and a.status in ('applied','accepted') order by (a.status = 'applied') desc, a.created_at;
end $function$;

-- meetup_apply(p_meetup uuid, p_note text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.meetup_apply(p_meetup uuid, p_note text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m public.meetups; v_me uuid := auth.uid(); v_note text := nullif(btrim(coalesce(p_note,'')), ''); cur text; nick text;
begin
  if v_me is null or not public.is_active_user() then raise exception '지금은 신청할 수 없어요'; end if;
  select * into m from public.meetups where id = p_meetup;
  if m.id is null or coalesce(m.hidden,false) then raise exception '모임을 찾을 수 없어요'; end if;
  if m.join_mode <> 'apply' then raise exception '바로 참여할 수 있는 모임이에요'; end if;
  if m.created_by = v_me then raise exception '내가 연 모임이에요'; end if;
  if coalesce(m.repeat,'once') = 'once' and m.starts_at < now() then raise exception '이미 지난 모임이에요'; end if;
  if exists (select 1 from public.friendships where status = 'blocked' and ((requester_id = v_me and addressee_id = m.created_by) or (requester_id = m.created_by and addressee_id = v_me))) then raise exception '신청할 수 없어요'; end if;
  if exists (select 1 from public.room_members where room_id = m.room_id and profile_id = v_me) then raise exception '이미 참여하고 있어요'; end if;
  if length(coalesce(v_note,'')) > 200 then raise exception '한마디는 200자까지예요'; end if;
  if v_note is not null and exists (select 1 from public.banned_words b where lower(v_note) like '%'||lower(b.word)||'%') then raise exception '사용할 수 없는 표현이 들어 있어요'; end if;
  select status into cur from public.meetup_applications where meetup_id = p_meetup and profile_id = v_me;
  if cur = 'applied' then return 'applied'; end if;
  if cur = 'rejected' then raise exception '이번 모임은 참여가 어려워요'; end if;
  insert into public.meetup_applications(meetup_id, profile_id, status, note) values (p_meetup, v_me, 'applied', v_note)
    on conflict (meetup_id, profile_id) do update set status = 'applied', note = excluded.note, created_at = now(), decided_at = null;
  select nickname into nick from public.profiles where id = v_me;
  insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
    values (m.created_by, v_me, 'notice', coalesce(nick,'이웃') || '님이 모임 참여를 신청했어요: ' || left(m.title, 50), jsonb_build_object('type','meetup','id',m.id));
  return 'applied';
end $function$;

-- meetup_cancel_apply(p_meetup uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.meetup_cancel_apply(p_meetup uuid)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  update public.meetup_applications set status = 'cancelled', decided_at = now() where meetup_id = p_meetup and profile_id = auth.uid() and status = 'applied' $function$;

-- meetup_count_sync()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.meetup_count_sync()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare rid uuid := coalesce(new.room_id, old.room_id);
begin
  update public.meetups m set participant_count = (select count(*) from public.room_members rm where rm.room_id = rid) where m.room_id = rid;
  return null;
end $function$;

-- meetup_decide(p_meetup uuid, p_profile uuid, p_accept boolean)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.meetup_decide(p_meetup uuid, p_profile uuid, p_accept boolean)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m public.meetups; cur text;
begin
  select * into m from public.meetups where id = p_meetup;
  if m.id is null or m.created_by is distinct from auth.uid() then raise exception '개설자만 정할 수 있어요'; end if;
  select status into cur from public.meetup_applications where meetup_id = p_meetup and profile_id = p_profile for update;
  if cur is distinct from 'applied' then raise exception '기다리는 신청이 아니에요'; end if;
  if p_accept then
    if m.capacity is not null and coalesce(m.participant_count,0) >= m.capacity then raise exception '정원이 찼어요'; end if;
    update public.meetup_applications set status = 'accepted', decided_at = now() where meetup_id = p_meetup and profile_id = p_profile;
    insert into public.room_members(room_id, profile_id) values (m.room_id, p_profile) on conflict do nothing;
    insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
      values (p_profile, m.created_by, 'notice', '모임 참여가 확정됐어요: ' || left(m.title, 60), jsonb_build_object('type','meetup','id',m.id));
    return 'accepted';
  end if;
  update public.meetup_applications set status = 'rejected', decided_at = now() where meetup_id = p_meetup and profile_id = p_profile;
  insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
    values (p_profile, m.created_by, 'notice', '이번 모임은 함께하기 어렵게 됐어요: ' || left(m.title, 60), jsonb_build_object('type','meetup','id',m.id));
  return 'rejected';
end $function$;

-- meetup_edit(p_meetup uuid, p_title text, p_place text, p_starts_at timestamp with time zone, p_is_public boolean, p_body text, p_lat double precision, p_lng double precision, p_photos text[], p_extra jsonb)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.meetup_edit(p_meetup uuid, p_title text, p_place text, p_starts_at timestamp with time zone, p_is_public boolean, p_body text DEFAULT NULL::text, p_lat double precision DEFAULT NULL::double precision, p_lng double precision DEFAULT NULL::double precision, p_photos text[] DEFAULT NULL::text[], p_extra jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid := auth.uid(); m public.meetups; po public.posts; x jsonb := coalesce(p_extra,'{}'::jsonb);
  v_title text := left(btrim(coalesce(p_title,'')),60); v_place text := left(btrim(coalesce(p_place,'')),80); v_body text := nullif(left(btrim(coalesce(p_body,'')),300),'');
  v_bring text := nullif(left(btrim(coalesce(x->>'bring','')),120),''); v_fee text := nullif(left(btrim(coalesce(x->>'fee','')),40),'');
  v_note text; v_ref text; v_mode text; v_cap smallint := nullif(x->>'capacity','')::smallint; v_techs text[]; t text; ch text[] := '{}'; v_msg text; n int := 0;
begin
  if uid is null then raise exception '로그인이 필요해요'; end if;
  select * into m from public.meetups where id = p_meetup and created_by = uid for update;
  if not found then raise exception '모임을 연 사람만 고칠 수 있어요'; end if;
  if v_title = '' then raise exception '모임 이름을 적어 주세요'; end if;
  if v_place = '' then raise exception '장소 이름을 적어 주세요'; end if;
  if p_starts_at is null then raise exception '일시를 정해 주세요'; end if;
  if p_starts_at is distinct from m.starts_at and p_starts_at < now() then raise exception '일시를 지금 이후로 정해 주세요'; end if;
  if v_cap is not null and v_cap < m.participant_count then raise exception '정원은 지금 참여 인원(%명)보다 적게 할 수 없어요', m.participant_count; end if;
  v_note := case when x ? 'fee_note' then nullif(btrim(coalesce(x->>'fee_note','')),'') else m.fee_note end;
  v_ref  := case when x ? 'refund_note' then nullif(btrim(coalesce(x->>'refund_note','')),'') else m.refund_note end;
  v_mode := case when x->>'join_mode' in ('open','apply') then x->>'join_mode' else m.join_mode end;
  if length(coalesce(v_note,'')) > 80 or length(coalesce(v_ref,'')) > 80 then raise exception '참가비 안내는 한 줄(80자)로 적어 주세요'; end if;
  foreach t in array array[v_title, coalesce(v_body,''), coalesce(v_bring,''), coalesce(v_fee,''), coalesce(v_note,''), coalesce(v_ref,'')] loop
    if t ~* 'https?://|www\.' then raise exception '모임 안내에는 링크를 넣을 수 없어요'; end if;
    if t ~ '\d{2,6}[- ]\d{2,6}[- ]\d{2,8}' then raise exception '계좌번호는 적을 수 없어요. 채팅방에서 안내해 주세요'; end if;
    if public.contains_banned(t) then raise exception '커뮤니티 가이드라인에 맞지 않는 표현이 있어요'; end if;
  end loop;
  if public.contains_banned(v_place) then raise exception '커뮤니티 가이드라인에 맞지 않는 표현이 있어요'; end if;
  if p_lat is not null and p_lng is not null and (p_lat not between 32 and 40 or p_lng not between 123 and 133) then raise exception '위치를 다시 골라 주세요'; end if;
  v_techs := array(select tq.id from public.techniques tq where tq.id = any(array(select jsonb_array_elements_text(case when jsonb_typeof(x->'technique_ids')='array' then x->'technique_ids' else '[]'::jsonb end))) order by tq.sort limit 10);
  select * into po from public.posts where meetup_id = p_meetup and author_id = uid and parent_id is null order by created_at limit 1;
  if p_photos is not null then
    if cardinality(p_photos) > 4 then raise exception '사진은 4장까지예요'; end if;
    if not public._post_photo_ok(p_photos, coalesce(po.photos,'{}')) then raise exception '사진을 다시 올려 주세요'; end if;
  end if;
  update public.meetups set title = v_title, place_name = v_place, starts_at = p_starts_at, is_public = coalesce(p_is_public, is_public), descr = v_body,
      location = case when p_lat is not null and p_lng is not null then st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography else location end,
      address = case when x ? 'address' then left(nullif(btrim(coalesce(x->>'address','')),''),200) else address end,
      kind = case when x->>'kind' in ('free','workshop','project','swap') then x->>'kind' else kind end,
      craft = case when x->>'craft' in ('knit','crochet','both') then x->>'craft' else craft end,
      level_min = case when x ? 'level_min' then nullif(x->>'level_min','')::smallint else level_min end,
      level_max = case when x ? 'level_max' then nullif(x->>'level_max','')::smallint else level_max end,
      technique_id = case when x ? 'technique_ids' then v_techs[1] else technique_id end, technique_ids = case when x ? 'technique_ids' then v_techs else technique_ids end,
      capacity = case when x ? 'capacity' then v_cap else capacity end, fee = case when x ? 'fee' then v_fee else fee end, bring = case when x ? 'bring' then v_bring else bring end,
      duration_min = case when x ? 'duration_min' then nullif(x->>'duration_min','')::smallint else duration_min end,
      repeat = case when x->>'repeat' in ('once','weekly','biweekly','monthly') then x->>'repeat' else repeat end,
      fee_note = v_note, refund_note = v_ref, join_mode = v_mode
    where id = p_meetup;
  if po.id is not null then
    update public.posts set body = coalesce(v_body, v_title), photos = coalesce(p_photos, photos), edited_at = now(), mod_scanned_at = null where id = po.id;
  end if;
  update public.rooms set title = left(v_title, 40) where id = m.room_id and kind = 'group' and title = left(m.title, 40);
  if p_starts_at is distinct from m.starts_at then ch := ch || ('일시가 ' || to_char(p_starts_at at time zone 'Asia/Seoul', 'FMMM"월" FMDD"일" HH24:MI') || '(으)로'); end if;
  if v_place is distinct from m.place_name then ch := ch || ('장소가 ' || v_place || '(으)로'); end if;
  if (x ? 'fee' and v_fee is distinct from m.fee) or v_note is distinct from m.fee_note then ch := ch || ('참가비가 ' || coalesce(case when x ? 'fee' then v_fee else m.fee end, '없음') || coalesce(' (' || v_note || ')', '') || '(으)로'); end if;
  if cardinality(ch) > 0 and greatest(p_starts_at, m.starts_at) > now() then
    v_msg := '「' || v_title || '」 모임의 ' || array_to_string(ch, ', ') || ' 바뀌었어요. 모임 화면에서 확인해 주세요';
    insert into public.notifications(recipient_id, actor_id, kind, snippet, meetup_id)
      select q.pid, uid, 'notice', left(v_msg, 200), p_meetup
        from (select rm.profile_id pid from public.room_members rm where rm.room_id = m.room_id and rm.left_at is null
              union select a.profile_id from public.meetup_applications a where a.meetup_id = p_meetup and a.status = 'applied') q
       where q.pid <> uid;
    get diagnostics n = row_count;
  end if;
  begin perform public.jigi_call('scan'); exception when others then null; end;
  return jsonb_build_object('ok', true, 'notified', n, 'changes', to_jsonb(ch));
end $function$;

-- meetup_set_terms(p_meetup uuid, p_fee_note text, p_mode text, p_refund text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.meetup_set_terms(p_meetup uuid, p_fee_note text, p_mode text, p_refund text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m public.meetups; v_note text := nullif(btrim(coalesce(p_fee_note,'')), ''); v_ref text := nullif(btrim(coalesce(p_refund,'')), ''); v_mode text := coalesce(p_mode,'open'); t text;
begin
  select * into m from public.meetups where id = p_meetup;
  if m.id is null or m.created_by is distinct from auth.uid() then raise exception '개설자만 정할 수 있어요'; end if;
  if v_mode not in ('open','apply') then raise exception '참여 방식을 확인해 주세요'; end if;
  if length(coalesce(v_note,'')) > 80 or length(coalesce(v_ref,'')) > 80 then raise exception '한 줄(80자)로 적어 주세요'; end if;
  foreach t in array array[coalesce(v_note,''), coalesce(v_ref,'')] loop
    if t ~* 'https?://|www\.' then raise exception '링크는 넣을 수 없어요'; end if;
    if t ~ '\d{2,6}[- ]\d{2,6}[- ]\d{2,8}' then raise exception '계좌번호는 적을 수 없어요. 확정 뒤 채팅방에서 안내해 주세요'; end if;
    if exists (select 1 from public.banned_words b where lower(t) like '%'||lower(b.word)||'%') then raise exception '사용할 수 없는 표현이 들어 있어요'; end if;
  end loop;
  update public.meetups set fee_note = v_note, refund_note = v_ref, join_mode = v_mode where id = p_meetup;
end $function$;

-- mod_notify_delete(p_user uuid, p_what text, p_reason text)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.mod_notify_delete(p_user uuid, p_what text, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_txt text;
begin
  if p_user is null or p_user = auth.uid() then return; end if;
  v_txt := '운영진이 회원님의 '||p_what||'을(를) 삭제했어요. '
        || case when coalesce(trim(p_reason),'') <> '' then '사유: '||trim(p_reason) else '커뮤니티 가이드라인에 맞지 않는 내용이었어요' end
        || '. 궁금한 점은 마이 › 설정 › 지기에게 말하기로 물어봐 주세요.';
  insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
  values (p_user, 'e120eb67-b254-4008-92d8-08c95c821e9e', 'notice', left(v_txt, 300), jsonb_build_object('type','view','view','support'));
end $function$;

-- my_author_eligibility()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.my_author_eligibility()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object('adv', public.author_adv_count(auth.uid()), 'total', (select count(*) from public.works where profile_id = auth.uid()), 'needed', 3);
$function$;

-- my_class_applications()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.my_class_applications()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'post_id', a.post_id, 'status', a.status, 'host_note', a.host_note, 'created_at', a.created_at, 'title', sp.title, 'starts_at', sp.extra->>'starts_at', 'shop_id', sp.shop_id, 'author_id', sp.author_id, 'room_id', sp.room_id,
      'host', coalesce((select s.name from public.shops s where s.id = sp.shop_id), (select p.nickname from public.profiles p where p.id = sp.author_id))) order by a.created_at desc), '[]')
  from public.class_applications a join public.shop_posts sp on sp.id = a.post_id where a.profile_id = auth.uid() and a.status <> 'cancelled';
$function$;

-- my_orders()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.my_orders()
 RETURNS SETOF orders
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select * from public.orders where profile_id = auth.uid() order by created_at desc limit 50 $function$;

-- my_pattern_purchases()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.my_pattern_purchases()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('pattern_id', pp.pattern_id, 'price', pp.price, 'via', pp.via, 'created_at', pp.created_at, 'title', p.title, 'craft', p.craft, 'level', p.level, 'photos', p.photos, 'has_viewer', p.has_viewer) order by pp.created_at desc), '[]'::jsonb)
  from public.pattern_purchases pp join public.patterns p on p.id = pp.pattern_id where pp.profile_id = auth.uid() $function$;

-- my_pattern_stats()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.my_pattern_stats()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_object_agg(p.id, jsonb_build_object('saves', (select count(*) from public.pattern_saves s where s.pattern_id = p.id),
         'started', (select count(*) from public.pattern_progress g where g.pattern_id = p.id and g.prog > 0),
         'done', (select count(*) from public.pattern_progress g where g.pattern_id = p.id and g.done_at is not null))), '{}'::jsonb)
  from public.patterns p where auth.uid() is not null and p.author_id = auth.uid();
$function$;

-- my_patterns_in_progress()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.my_patterns_in_progress()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'title', p.title, 'photo', p.photos[1], 'craft', p.craft, 'level', p.level, 'techniques', to_jsonb(p.techniques),
           'prog', g.prog, 'total', t.total, 'updated_at', g.updated_at, 'done_at', g.done_at) order by g.updated_at desc), '[]'::jsonb)
  from public.pattern_progress g join public.patterns p on p.id = g.pattern_id and p.is_published and not p.hidden
  left join lateral (select coalesce(sum(jsonb_array_length(coalesce(c->'rounds','[]'::jsonb))), 0)::int total from public.pattern_contents pc, jsonb_array_elements(pc.pkg->'charts') c where pc.pattern_id = p.id) t on true
  where auth.uid() is not null and g.profile_id = auth.uid() and g.prog > 0 and g.done_at is null;
$function$;

-- my_unread_rooms()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.my_unread_rooms()
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select count(*)::int from public.room_members rm join public.rooms r on r.id = rm.room_id
  where rm.profile_id = auth.uid()
    and not exists (select 1 from public.room_members s where s.room_id = rm.room_id and s.profile_id = 'e120eb67-b254-4008-92d8-08c95c821e9e'::uuid)
    and not (rm.left_at is not null and r.kind <> 'direct')
    and exists (select 1 from public.messages m where m.room_id = rm.room_id and m.sender_id <> rm.profile_id
                and m.created_at > greatest(coalesce(rm.last_read_at, rm.joined_at), coalesce(rm.left_at, '-infinity'::timestamptz)));
$function$;

-- nearby_profiles(p_lat double precision, p_lng double precision, p_radius_m integer, p_craft craft_type, p_beginner_ok boolean)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.nearby_profiles(p_lat double precision, p_lng double precision, p_radius_m integer DEFAULT 3000, p_craft craft_type DEFAULT NULL::craft_type, p_beginner_ok boolean DEFAULT NULL::boolean)
 RETURNS TABLE(id uuid, nickname text, avatar_url text, dong_name text, lat double precision, lng double precision, craft craft_type, experience experience_level, now_making text, beginner_ok boolean, distance_m double precision, level_crochet smallint, level_knit smallint, available text[], waving boolean, is_author boolean, pattern_count integer)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  with base as (
    select p.*, st_distance(p.location, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography) as dist
    from public.profiles p
    where p.location is not null
      and p.is_visible
      and p.suspended_at is null
      and p.onboarded_at is not null
      and p.id <> auth.uid()
      and not public.is_blocked(auth.uid(), p.id)
      and (p_craft is null or p.craft = p_craft or p.craft = 'both')
      and (p_beginner_ok is null or p.beginner_ok = p_beginner_ok)
      and (p.is_author or st_dwithin(p.location, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography, p_radius_m))
  ), near as (select * from base where dist <= p_radius_m order by dist limit 200),
     far_authors as (select * from base where is_author and dist > p_radius_m order by dist limit 300)
  select
    p.id, p.nickname, p.avatar_url, p.dong_name,
    st_y(p.location::geometry), st_x(p.location::geometry),
    p.craft, p.experience, p.now_making, p.beginner_ok,
    p.dist,
    p.level_crochet, p.level_knit, p.available,
    (p.wave_until is not null and p.wave_until > now()),
    p.is_author,
    case when p.is_author then (select count(*)::int from public.patterns pt where pt.author_id = p.id and pt.is_published and not pt.hidden) else 0 end
  from (select * from near union all select * from far_authors) p
  order by 11;
$function$;

-- nearby_shops(p_lat double precision, p_lng double precision, p_radius_m integer)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.nearby_shops(p_lat double precision, p_lng double precision, p_radius_m integer DEFAULT 8000)
 RETURNS TABLE(id uuid, name text, kind text, lat double precision, lng double precision, address text, logo_url text, latest_post_at timestamp with time zone, unread boolean, following boolean, post_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select s.id, s.name, s.kind, st_y(s.location::geometry), st_x(s.location::geometry), s.address, s.logo_url,
    lp.latest, (lp.latest is not null and (r.last_read_at is null or lp.latest > r.last_read_at)) as unread,
    (f.profile_id is not null) as following, coalesce(lp.n,0)
  from public.shops s
  left join lateral (select max(created_at) latest, count(*) n from public.shop_posts p where p.shop_id = s.id and not p.hidden and (p.ends_at is null or p.ends_at > now())) lp on true
  left join public.shop_reads r on r.shop_id = s.id and r.profile_id = auth.uid()
  left join public.shop_follows f on f.shop_id = s.id and f.profile_id = auth.uid()
  where s.is_active and s.location is not null
    and ( coalesce((select c.value from public.app_config c where c.key='shops_everywhere') = 'true'::jsonb, false)
          or st_dwithin(s.location, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography, greatest(p_radius_m, s.radius_m)) )
  order by st_distance(s.location, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography)
  limit 200;
$function$;

-- next_tech(p_user uuid, p_craft text, p_level integer)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.next_tech(p_user uuid, p_craft text, p_level integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select to_jsonb(x) from (
    select t.id, t.name_ko, t.level from public.techniques t cross join (select skills from public.profiles where id = p_user) p
    where t.craft = p_craft and not coalesce(t.hidden, false) and not (t.id = any(coalesce(p.skills,'{}')))
      and (p_level is null or t.level = p_level)
    order by (coalesce(t.prereq,'{}') <@ coalesce(p.skills,'{}')) desc, t.level, t.sort limit 1) x;
$function$;

-- nickname_check(p_nick text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.nickname_check(p_nick text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_me uuid := auth.uid(); p record; k text := public._nick_key(p_nick); d int;
begin
  if v_me is null then return '로그인이 필요해요'; end if;
  if k = '' then return '닉네임을 적어 주세요'; end if;
  select nickname, onboarded_at, nickname_changed_at into p from public.profiles where id = v_me;
  if public._nick_key(p.nickname) = k and trim(p.nickname) = trim(p_nick) then return null; end if;   -- 그대로
  if exists (select 1 from public.profiles o where o.id <> v_me and o.onboarded_at is not null and o.deleted_at is null and public._nick_key(o.nickname) = k) then
    return '이미 다른 분이 쓰는 닉네임이에요. 다른 이름을 적어 주세요';
  end if;
  if p.onboarded_at is not null and p.nickname_changed_at is not null and p.nickname_changed_at > now() - interval '30 days' then
    d := greatest(1, ceil(extract(epoch from (p.nickname_changed_at + interval '30 days' - now())) / 86400)::int);
    return '닉네임은 30일에 한 번 바꿀 수 있어요 ('||d||'일 뒤에 바꿀 수 있어요)';
  end if;
  return null;
end $function$;

-- notify_followers_on_meetup()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.notify_followers_on_meetup()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.is_public and not coalesce(new.hidden,false) and exists (select 1 from public.profiles where id = new.created_by and is_author) then
    insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
      select f.profile_id, new.created_by, 'notice', '팔로우한 작가가 모임을 열었어요: ' || left(new.title, 60), jsonb_build_object('type','meetup','id',new.id)
      from public.author_follows f where f.author_id = new.created_by
        and not exists (select 1 from public.friendships fr where fr.status = 'blocked' and ((fr.requester_id = new.created_by and fr.addressee_id = f.profile_id) or (fr.requester_id = f.profile_id and fr.addressee_id = new.created_by)));
  end if;
  return null;
end $function$;

-- notify_on_friendship()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.notify_on_friendship()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if tg_op = 'INSERT' and new.status = 'pending' then
    perform public.push_notification(new.addressee_id, new.requester_id, 'friend_request', null, null, null, new.message);
  elsif tg_op = 'UPDATE' and new.status = 'accepted' and old.status is distinct from 'accepted' then
    perform public.push_notification(new.requester_id, new.addressee_id, 'friend_accept', null, null, null, null);
  end if;
  return new;
end $function$;

-- notify_on_like()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.notify_on_like()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a uuid; root uuid; b text;
begin
  if tg_op = 'INSERT' then
    select author_id, coalesce(parent_id, id), body into a, root, b from public.posts where id = new.post_id;
    perform public.push_notification(a, new.profile_id, 'like', new.post_id, root, null, b);
    return new;
  else
    delete from public.notifications where kind = 'like' and post_id = old.post_id and actor_id = old.profile_id;
    return old;
  end if;
end $function$;

-- notify_on_meetup_join()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.notify_on_meetup_join()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare mt record;
begin
  select id, created_by, title into mt from public.meetups where room_id = new.room_id;
  if mt.id is not null then
    perform public.push_notification(mt.created_by, new.profile_id, 'meetup_join', null, null, mt.id, mt.title);
  end if;
  return new;
end $function$;

-- notify_on_post()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.notify_on_post()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare parent_author uuid; m uuid; creator uuid;
begin
  if new.parent_id is not null then
    select author_id into parent_author from public.posts where id = new.parent_id;
    if parent_author is not null and not (parent_author = any(new.mentions)) then
      perform public.push_notification(parent_author, new.author_id, 'reply', new.id, new.parent_id, null, new.body);
    end if;
  end if;
  foreach m in array new.mentions loop
    perform public.push_notification(m, new.author_id, 'mention', new.id, coalesce(new.parent_id, new.id), null, new.body);
  end loop;
  if new.review_of is not null then
    select created_by into creator from public.meetups where id = new.review_of;
    perform public.push_notification(creator, new.author_id, 'review', new.id, new.id, new.review_of, new.body);
  end if;
  return new;
end $function$;

-- notify_on_reply_to()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.notify_on_reply_to()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare target uuid; root_author uuid;
begin
  begin
    if new.reply_to is null or new.parent_id is null then return null; end if;
    select author_id into target from public.posts where id = new.reply_to;
    select author_id into root_author from public.posts where id = new.parent_id;
    if target is null or target = new.author_id or target = root_author or target = any(coalesce(new.mentions,'{}')) then return null; end if;
    perform public.push_notification(target, new.author_id, 'reply', new.id, new.parent_id, null, new.body);
  exception when others then null;
  end;
  return null;
end $function$;

-- notify_on_shop_post()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.notify_on_shop_post()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.shop_id is not null then
    insert into public.notifications(recipient_id, actor_id, kind, shop_id, snippet)
      select f.profile_id, new.author_id, 'shop_post', new.shop_id, left(new.title, 80) from public.shop_follows f where f.shop_id = new.shop_id and f.profile_id is distinct from new.author_id;
  elsif new.kind = 'class' and new.author_id is not null then
    insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
      select case when fr.requester_id = new.author_id then fr.addressee_id else fr.requester_id end, new.author_id, 'notice', '작가 친구가 클래스를 열었어요: ' || left(new.title, 60), jsonb_build_object('type','profile','id',new.author_id,'tab','classes')
      from public.friendships fr where fr.status = 'accepted' and (fr.requester_id = new.author_id or fr.addressee_id = new.author_id);
    insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
      select f.profile_id, new.author_id, 'notice', '팔로우한 작가가 클래스를 열었어요: ' || left(new.title, 60), jsonb_build_object('type','profile','id',new.author_id,'tab','classes')
      from public.author_follows f where f.author_id = new.author_id
        and not exists (select 1 from public.friendships fr where fr.status in ('accepted','blocked') and ((fr.requester_id = new.author_id and fr.addressee_id = f.profile_id) or (fr.requester_id = f.profile_id and fr.addressee_id = new.author_id)));
  end if;
  return new;
end $function$;

-- nudge_first_work()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.nudge_first_work()
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid := auth.uid(); p public.profiles;
begin
  if uid is null then return false; end if;
  select * into p from public.profiles where id = uid;
  if p.onboarded_at is null or p.onboarded_at > now() - interval '2 days' then return false; end if;
  if exists (select 1 from public.works where profile_id = uid) then return false; end if;
  if exists (select 1 from public.notifications where recipient_id = uid and link->>'view' = 'cert') then return false; end if;
  insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
    values (uid, 'e120eb67-b254-4008-92d8-08c95c821e9e', 'notice', '첫 작품을 인증하면 Lv.1이 돼요. 완성한 작품 사진 한 장이면 충분해요 — 눌러서 인증하기', jsonb_build_object('type','view','view','cert'));
  return true;
end $function$;

-- onboard_step(p_step integer)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.onboard_step(p_step integer)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  update public.profiles set onboard_step = greatest(coalesce(onboard_step, 0), least(greatest(coalesce(p_step, 1), 1), 4))
  where id = auth.uid() and onboarded_at is null;
$function$;

-- open_inquiry_room(p_kind text, p_id uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.open_inquiry_room(p_kind text, p_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_me uuid := auth.uid(); v_to uuid; v_room uuid;
begin
  if v_me is null or not public.is_active_user() then raise exception '지금은 문의할 수 없어요'; end if;
  if p_kind = 'shop' then select owner_id into v_to from public.shops where id = p_id and is_active;
  elsif p_kind = 'author' then select id into v_to from public.profiles where id = p_id and is_author;
  end if;
  if v_to is null or exists (select 1 from public.profiles where id = v_to and (suspended_at is not null or deleted_at is not null)) then raise exception '지금은 문의를 받지 않는 곳이에요'; end if;
  if v_to = v_me then raise exception '내 화면이에요'; end if;
  if exists (select 1 from public.friendships where status = 'blocked' and ((requester_id = v_me and addressee_id = v_to) or (requester_id = v_to and addressee_id = v_me))) then raise exception '문의할 수 없어요'; end if;
  select r.id into v_room from public.rooms r
    join public.room_members a on a.room_id = r.id and a.profile_id = v_me
    join public.room_members b on b.room_id = r.id and b.profile_id = v_to
   where r.kind = 'direct' limit 1;
  if v_room is null then
    if (select count(*) from public.rooms where created_by = v_me and inquiry and created_at > now() - interval '1 day') >= 10 then raise exception '오늘은 문의를 더 열 수 없어요. 내일 다시 해 주세요'; end if;
    insert into public.rooms(kind, created_by, inquiry) values ('direct', v_me, true) returning id into v_room;
    insert into public.room_members(room_id, profile_id) values (v_room, v_me), (v_room, v_to);
  else
    update public.room_members set left_at = null, archived_at = null where room_id = v_room and profile_id = v_me;
  end if;
  return v_room;
end $function$;

-- open_support_room(p_support uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.open_support_room(p_support uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare rid uuid; uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not signed in'; end if;
  if uid = p_support then raise exception 'self'; end if;
  if not exists (select 1 from public.admins where profile_id = p_support) then raise exception 'no support profile'; end if;
  select r.id into rid from public.rooms r
    join public.room_members a on a.room_id = r.id and a.profile_id = uid
    join public.room_members b on b.room_id = r.id and b.profile_id = p_support
    where r.kind = 'direct' limit 1;
  if rid is null then
    insert into public.rooms(kind, created_by) values ('direct', uid) returning id into rid;
    insert into public.room_members(room_id, profile_id) values (rid, uid), (rid, p_support);
  end if;
  return rid;
end $function$;

-- partner_guide_nudge()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.partner_guide_nudge()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e'; g record; need boolean; n int := 0;
begin
  for g in select * from public.partner_guides where sent_at is not null and nudged_at is null and sent_at <= now() - interval '3 days' loop
    if g.kind = 'author' then
      need := exists (select 1 from public.profiles p where p.id = g.profile_id and p.is_author and p.deleted_at is null and p.cover_url is null);
      if need then insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
        values (g.profile_id, sup, 'remind', '작가 페이지에 대표 사진을 넣어 보세요. 사진 한 장만 넣어도 작가 페이지가 훨씬 살아나요.', jsonb_build_object('type','view','view','author_page')); end if;
    else
      need := exists (select 1 from public.shops s where s.owner_id = g.profile_id and s.is_active and s.cover_url is null);
      if need then insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
        values (g.profile_id, sup, 'remind', '가게 페이지에 매장 사진을 넣어 보세요. 사진이 있으면 이웃이 가게를 훨씬 쉽게 알아봐요.', jsonb_build_object('type','view','view','shop_edit')); end if;
    end if;
    update public.partner_guides set nudged_at = now(), nudge_sent = need where profile_id = g.profile_id and kind = g.kind;
    if need then n := n + 1; end if;
  end loop;
  return n;
end $function$;

-- partner_guide_trg()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.partner_guide_trg()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  begin
    if tg_table_name = 'profiles' then
      if new.is_author and new.deleted_at is null then perform public._partner_guide_send(new.id, 'author'); end if;
    else
      if new.owner_id is not null and new.is_active then perform public._partner_guide_send(new.owner_id, 'shop'); end if;
    end if;
  exception when others then null;   -- 안내 실패가 승인을 막지 않게
  end;
  return null;
end $function$;

-- pattern_fee_calc(p_price integer)  acl: {=X/postgres,postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres,anon=X/postgres}
CREATE OR REPLACE FUNCTION public.pattern_fee_calc(p_price integer)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object('price', p_price, 'store_fee', s, 'platform_fee', pf, 'tax', t, 'author_amt', p_price - s - pf - t)
  from (select round(p_price * 0.30)::int s) a, lateral (select round((p_price - a.s) * 0.15)::int pf) b, lateral (select round((p_price - a.s - b.pf) * 0.033)::int t) c $function$;

-- pattern_gauge_ctx(p_pattern uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.pattern_gauge_ctx(p_pattern uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pt public.patterns; k text; yg jsonb; yname text; base jsonb; mm numeric; m text[]; med record; mine jsonb;
begin
  if auth.uid() is null then return null; end if;
  select * into pt from public.patterns where id = p_pattern and ((is_published and not hidden) or author_id = auth.uid() or public.is_admin());
  if pt.id is null then return null; end if;
  k := case when pt.craft = 'knitting' then 'gauge_knit' else 'gauge_crochet' end;
  if pt.catalog_id is not null then
    select btrim(coalesce(c.brand||' ','')||c.product), to_jsonb(c)->k into yname, yg from public.yarn_catalog c where c.id = pt.catalog_id and c.merged_into is null;
  end if;
  m := regexp_match(coalesce(pt.needle_size,''), '([0-9]+(?:\.[0-9]+)?)\s*mm');
  if m is not null then mm := m[1]::numeric;
  elsif pt.craft <> 'knitting' then
    m := regexp_match(coalesce(pt.needle_size,''), '([0-9]+(?:\.5)?)/0');
    if m is not null then mm := case m[1] when '2' then 2.0 when '3' then 2.3 when '4' then 2.5 when '5' then 3.0 when '6' then 3.5 when '7' then 4.0 when '7.5' then 4.5 when '8' then 5.0 when '9' then 5.5 when '10' then 6.0 else null end; end if;
  end if;
  if pt.gauge is not null then base := pt.gauge || jsonb_build_object('src', 'author');
  elsif yg is not null then base := yg || jsonb_build_object('src', 'yarn');
  elsif mm is not null and pt.craft = 'knitting' then
    select percentile_cont(0.5) within group (order by (c.gauge_knit->>'sts')::numeric) s, percentile_cont(0.5) within group (order by (c.gauge_knit->>'rows')::numeric) r, count(*) n into med
      from public.yarn_catalog c where c.merged_into is null and (c.gauge_knit->>'needle') ~ '^[0-9]' and abs(substring(c.gauge_knit->>'needle' from '^[0-9]+(?:\.[0-9]+)?')::numeric - mm) <= 0.26;
    if med.n > 0 then base := jsonb_build_object('sts', round(med.s::numeric, 1), 'rows', round(med.r::numeric, 1), 'needle', mm||'mm', 'stitch', '메리야스', 'src', 'needle', 'n', med.n); end if;
  end if;
  select coalesce(jsonb_agg(x), '[]'::jsonb) into mine from (
    select distinct on (c.id) jsonb_build_object('name', btrim(coalesce(c.brand||' ','')||c.product)) || (to_jsonb(c)->k) x
    from public.yarn_stash s join public.yarn_catalog c on c.id = s.catalog_id
    where s.owner_id = auth.uid() and c.merged_into is null and to_jsonb(c)->k is not null order by c.id, s.created_at desc limit 6) t;
  return jsonb_strip_nulls(jsonb_build_object('craft', pt.craft, 'base', base, 'needle_mm', mm, 'needle', pt.needle_size, 'yarn', yname, 'mine', mine));
end $function$;

-- pattern_save_count()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.pattern_save_count()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if tg_op = 'INSERT' then update public.patterns set save_count = save_count + 1 where id = new.pattern_id;
  else update public.patterns set save_count = greatest(save_count - 1, 0) where id = old.pattern_id; end if;
  return null;
end $function$;

-- patterns_for_stash(p_stash uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.patterns_for_stash(p_stash uuid DEFAULT NULL::uuid)
 RETURNS TABLE(id uuid, title text, craft text, level smallint, photos text[], price integer, has_viewer boolean, match text, reason text, stash_id uuid, yarn_name text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with s as (
    select st.id, st.raw_name, st.catalog_id, coalesce(c.m_per_100g, case when st.ball_g > 0 and st.ball_m > 0 then round(st.ball_m * 100 / st.ball_g) end) mpg, c.weight_class,
           coalesce((c.gauge_crochet->>'sts')::numeric, (c.gauge_knit->>'sts')::numeric) gsts
    from public.yarn_stash st left join public.yarn_catalog c on c.id = st.catalog_id
    where st.owner_id = auth.uid() and (p_stash is null or st.id = p_stash) and st.left_balls > 0),
  cand as (
    select p.id, p.title, p.craft, p.level, p.photos, p.price, p.has_viewer, s.id stash_id, s.raw_name yarn_name,
      case when p.catalog_id is not null and p.catalog_id = s.catalog_id then 1
           when s.mpg is not null and pc.m_per_100g is not null and abs(pc.m_per_100g - s.mpg) / pc.m_per_100g <= 0.2 then 2
           when s.gsts is not null and (p.gauge->>'sts')::numeric > 0 and abs((p.gauge->>'sts')::numeric - s.gsts) / (p.gauge->>'sts')::numeric <= 0.15 then 3
           when s.weight_class is not null and p.yarn_weight is not null and (p.yarn_weight ilike '%' || split_part(s.weight_class, '(', 1) || '%' or s.weight_class ilike '%' || p.yarn_weight || '%') then 4
           else null end rank,
      case when p.catalog_id is not null and p.catalog_id = s.catalog_id then '같은 실로 만든 도안'
           when s.mpg is not null and pc.m_per_100g is not null then '굵기 비슷 · 차이 ' || round(abs(pc.m_per_100g - s.mpg) / pc.m_per_100g * 100) || '%'
           when s.gsts is not null and (p.gauge->>'sts')::numeric > 0 then '게이지 비슷 · 도안 ' || (p.gauge->>'sts') || '코 / 내 실 ' || round(s.gsts) || '코'
           else '굵기 분류가 같아요 · ' || coalesce(p.yarn_weight, '') end reason
    from s cross join public.patterns p left join public.yarn_catalog pc on pc.id = p.catalog_id
    where p.is_published and not p.hidden)
  select distinct on (c.id) c.id, c.title, c.craft, c.level, c.photos, c.price, c.has_viewer,
    case c.rank when 1 then 'same' when 2 then 'similar' when 3 then 'gauge' else 'weight' end, c.reason, c.stash_id, c.yarn_name
  from cand c where c.rank is not null order by c.id, c.rank $function$;

-- place_order(p_ship jsonb)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.place_order(p_ship jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid := auth.uid(); it record; items jsonb := '[]'::jsonb; sub int := 0; fee int; oid uuid; ono text; n int := 0;
begin
  if uid is null then raise exception 'not signed in'; end if;
  if coalesce(p_ship->>'name','') = '' or coalesce(p_ship->>'phone','') = '' or coalesce(p_ship->>'addr','') = '' then raise exception '배송지(이름·연락처·주소)를 적어 주세요'; end if;
  if not public.rate_hit('place_order', 5, 600) then raise exception '잠시 뒤 다시 시도해 주세요'; end if;
  for it in select c.product_id, c.color, c.qty, p.name, p.price, p.stock, p.is_active from public.cart_items c join public.shop_products p on p.id = c.product_id where c.profile_id = uid order by c.created_at loop
    if not it.is_active then raise exception '「%」는 지금 판매하지 않는 상품이에요', it.name; end if;
    if it.stock < it.qty then raise exception '「%」 재고가 부족해요 (남은 %볼)', it.name, it.stock; end if;
    items := items || jsonb_build_object('product_id', it.product_id, 'name', it.name, 'color', it.color, 'qty', it.qty, 'price', it.price);
    sub := sub + it.price * it.qty; n := n + 1;
    update public.shop_products set stock = stock - it.qty, updated_at = now() where id = it.product_id;
  end loop;
  if n = 0 then raise exception '장바구니가 비어 있어요'; end if;
  fee := case when sub >= 30000 then 0 else 3000 end;
  ono := 'KN' || to_char(now() at time zone 'Asia/Seoul', 'YYMMDD') || '-' || lpad((floor(random()*9000)+1000)::int::text, 4, '0');
  insert into public.orders(no, profile_id, items, subtotal, shipping_fee, total, ship_name, ship_phone, ship_addr, ship_memo, depositor)
    values (ono, uid, items, sub, fee, sub + fee, left(p_ship->>'name', 40), left(p_ship->>'phone', 30), left(p_ship->>'addr', 200), left(coalesce(p_ship->>'memo',''), 200), left(coalesce(p_ship->>'depositor', p_ship->>'name'), 40))
    returning id into oid;
  delete from public.cart_items where profile_id = uid;
  return jsonb_build_object('id', oid, 'no', ono, 'total', sub + fee, 'subtotal', sub, 'shipping_fee', fee, 'items', n);
end $function$;

-- post_archive(p_post uuid, p_on boolean)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.post_archive(p_post uuid, p_on boolean DEFAULT true)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.posts;
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  select * into r from public.posts where id = p_post and author_id = auth.uid() for update;
  if not found then raise exception '내 글만 보관할 수 있어요'; end if;
  if r.parent_id is not null then raise exception '댓글은 보관할 수 없어요'; end if;
  if r.meetup_id is not null then raise exception '모임 글은 보관할 수 없어요'; end if;
  perform set_config('knit.archiving', '1', true);
  if p_on then
    if r.archived_at is not null then return; end if;
    if r.hidden then raise exception '이미 숨겨진 글이에요'; end if;
    update public.posts set hidden = true, archived_at = now(), pinned_at = null where id = p_post;
  else
    if r.archived_at is null then raise exception '보관한 글이 아니에요'; end if;
    if r.hidden_by_mod then raise exception '운영진이 확인 중인 글은 다시 공개할 수 없어요'; end if;
    if not public.is_active_user() then raise exception '지금은 다시 공개할 수 없어요'; end if;
    update public.posts set hidden = false, archived_at = null where id = p_post;
  end if;
  perform set_config('knit.archiving', '', true);
end $function$;

-- post_like_count()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.post_like_count()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if tg_op = 'INSERT' then
    update public.posts set like_count = like_count + 1 where id = new.post_id;
  else
    update public.posts set like_count = greatest(like_count - 1, 0) where id = old.post_id;
  end if;
  return null;
end $function$;

-- post_pin(p_post uuid, p_on boolean)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.post_pin(p_post uuid, p_on boolean DEFAULT true)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.posts;
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  select * into r from public.posts where id = p_post and author_id = auth.uid() for update;
  if not found then raise exception '내 글만 고정할 수 있어요'; end if;
  if r.parent_id is not null then raise exception '댓글은 고정할 수 없어요'; end if;
  if not p_on then update public.posts set pinned_at = null where id = p_post; return; end if;
  if r.hidden then raise exception '숨겨진 글은 고정할 수 없어요'; end if;
  if r.pinned_at is not null then return; end if;
  if (select count(*) from public.posts where author_id = auth.uid() and pinned_at is not null) >= 3 then raise exception '고정은 3개까지예요. 다른 글의 고정을 먼저 풀어 주세요'; end if;
  update public.posts set pinned_at = now() where id = p_post;
end $function$;

-- post_reports_apply()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.post_reports_apply()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if (select count(*) from public.post_reports where post_id = new.post_id) >= 3 then
    update public.posts set hidden = true where id = new.post_id;
  end if;
  return null;
end $function$;

-- post_repost_apply()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.post_repost_apply()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a uuid; b text;
begin
  if tg_op = 'INSERT' then
    update public.posts set repost_count = repost_count + 1 where id = new.post_id returning author_id, body into a, b;
    perform public.push_notification(a, new.profile_id, 'repost', new.post_id, new.post_id, null, b);
    return new;
  else
    update public.posts set repost_count = greatest(repost_count - 1, 0) where id = old.post_id;
    delete from public.notifications where kind = 'repost' and post_id = old.post_id and actor_id = old.profile_id;
    return old;
  end if;
end $function$;

-- post_tags(p_body text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.post_tags(p_body text)
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  select coalesce(array_agg(t order by ord), '{}') from (
    select t, min(ord) ord from (select lower(m[1]) t, ord from regexp_matches(coalesce(p_body,''), '(?:^|\s)#([가-힣A-Za-z0-9_]{1,20})', 'g') with ordinality as x(m, ord)) a group by t order by min(ord) limit 10) s;
$function$;

-- posts_archive_guard()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.posts_archive_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if coalesce(current_setting('knit.archiving', true),'') = '1' then return new; end if;
  if old.archived_at is not null then
    if new.hidden then new.archived_at := null; else new.hidden := true; end if;
  end if;
  return new;
end $function$;

-- posts_before_insert()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.posts_before_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_until timestamptz;
begin
  select post_restricted_until into v_until from public.profiles where id = new.author_id;
  if v_until is not null and v_until > now() then raise exception '커뮤니티 가이드라인 위반으로 %까지 글쓰기가 제한돼 있어요', to_char(v_until at time zone 'Asia/Seoul', 'MM월 DD일'); end if;
  if new.dong_code is null then
    select dong_code into new.dong_code from public.profiles where id = new.author_id;
  end if;
  return new;
end $function$;

-- posts_reply_count()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.posts_reply_count()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if tg_op = 'INSERT' and new.parent_id is not null then
    update public.posts set reply_count = reply_count + 1 where id = new.parent_id;
  elsif tg_op = 'DELETE' and old.parent_id is not null then
    update public.posts set reply_count = greatest(reply_count - 1, 0) where id = old.parent_id;
  end if;
  return null;
end $function$;

-- posts_reply_to_guard()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.posts_reply_to_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t record;
begin
  if new.reply_to is null then return new; end if;
  if new.parent_id is null then new.reply_to := null; return new; end if;
  select id, parent_id, reply_to into t from public.posts where id = new.reply_to;
  if t.id is null or t.parent_id is distinct from new.parent_id then new.reply_to := null;      -- 같은 글의 댓글이 아니면 일반 댓글로
  elsif t.reply_to is not null then new.reply_to := t.reply_to; end if;                          -- 대댓글에 단 답글은 같은 윗댓글 아래로
  return new;
end $function$;

-- posts_review_count()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.posts_review_count()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare mid uuid := coalesce(new.review_of, old.review_of);
begin
  if mid is not null then
    update public.meetups set review_count = (select count(*) from public.posts where review_of = mid) where id = mid;
  end if;
  return null;
end $function$;

-- posts_set_tags()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.posts_set_tags()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v text[];
begin
  v := public.post_tags(new.body);
  if new.work_id is not null and new.parent_id is null then
    v := array(select distinct t from unnest(v || public._work_tags(new.work_id)) t limit 20);
  end if;
  new.tags := coalesce(v, '{}');
  return new;
end $function$;

-- profiles_apply_skills()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.profiles_apply_skills()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare has_c boolean; has_k boolean;
begin
  if tg_op = 'INSERT' or new.skills is distinct from old.skills then
    new.skills := array(select t.id from public.techniques t where t.id = any(new.skills) order by t.sort);
    new.level_crochet := public.compute_skill_level(new.skills, 'crochet');
    new.level_knit := public.compute_skill_level(new.skills, 'knitting');
    has_c := exists (select 1 from unnest(new.skills) s where s like 'C%');
    has_k := exists (select 1 from unnest(new.skills) s where s like 'K%');
    new.craft := case when has_c and has_k then 'both' when has_c then 'crochet' when has_k then 'knit' else new.craft end;
    if tg_op = 'UPDATE' then new.skills_updated_at := now(); end if;
  end if;
  return new;
end $function$;

-- profiles_nickname_guard()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.profiles_nickname_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare k text := public._nick_key(new.nickname); d int;
begin
  if trim(coalesce(new.nickname,'')) = trim(coalesce(old.nickname,'')) then return new; end if;
  -- 본인이 바꿀 때만 검사(운영진·서버가 고치는 경우는 통과)
  if auth.uid() is null or auth.uid() <> new.id then
    if old.onboarded_at is not null then new.nickname_changed_at := old.nickname_changed_at; end if;
    return new;
  end if;
  if exists (select 1 from public.profiles o where o.id <> new.id and o.onboarded_at is not null and o.deleted_at is null and public._nick_key(o.nickname) = k) then
    raise exception '이미 다른 분이 쓰는 닉네임이에요. 다른 이름을 적어 주세요';
  end if;
  if old.onboarded_at is not null then
    if old.nickname_changed_at is not null and old.nickname_changed_at > now() - interval '30 days' then
      d := greatest(1, ceil(extract(epoch from (old.nickname_changed_at + interval '30 days' - now())) / 86400)::int);
      raise exception '닉네임은 30일에 한 번 바꿀 수 있어요 (%일 뒤에 바꿀 수 있어요)', d;
    end if;
    new.nickname_changed_at := now();
  end if;
  return new;
end $function$;

-- purchase_pattern(p_pattern uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.purchase_pattern(p_pattern uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid := auth.uid(); p record; f jsonb; already boolean;
begin
  if uid is null then raise exception 'not signed in'; end if;
  select id, title, price, author_id, is_published, hidden into p from public.patterns where id = p_pattern;
  if p.id is null or not p.is_published or p.hidden then raise exception '구매할 수 없는 도안이에요'; end if;
  select exists(select 1 from public.pattern_purchases where profile_id = uid and pattern_id = p_pattern) into already;
  if already then return jsonb_build_object('ok', true, 'already', true); end if;
  f := public.pattern_fee_calc(p.price);
  insert into public.pattern_purchases(profile_id, pattern_id, price, store_fee, platform_fee, tax, author_amt, via)
    values (uid, p_pattern, p.price, (f->>'store_fee')::int, (f->>'platform_fee')::int, (f->>'tax')::int, (f->>'author_amt')::int, 'demo_free');
  if p.author_id is not null and p.author_id <> uid then
    insert into public.notifications(recipient_id, actor_id, kind, snippet, link) values (p.author_id, uid, 'notice', '도안 「' || p.title || '」이(가) 판매됐어요 · 작가 정산 ' || (f->>'author_amt') || '원', jsonb_build_object('type','view','view','settlement'));
  end if;
  return jsonb_build_object('ok', true, 'already', false) || f;
end $function$;

-- push_chat_payload(p_msg bigint)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.push_chat_payload(p_msg bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m public.messages; r public.rooms; who text; v_title text; v_body text; v_tokens jsonb; sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e'; v_sup boolean;
begin
  select * into m from public.messages where id = p_msg; if m.id is null then return null; end if;
  select * into r from public.rooms where id = m.room_id; if r.id is null then return null; end if;
  v_sup := exists(select 1 from public.room_members where room_id = m.room_id and profile_id = sup);
  select case when m.sender_id = sup then '뜨개동네 지기' else coalesce(nickname,'이웃') end into who from public.profiles where id = m.sender_id;
  v_body := coalesce(nullif(left(regexp_replace(coalesce(m.body,''), '\s+', ' ', 'g'), 80), ''), case when m.photo_url is not null then '사진을 보냈어요' when m.place is not null then '장소를 보냈어요' else '새 메시지' end);
  if r.kind = 'direct' then v_title := coalesce(who,'이웃');
  else v_title := coalesce(nullif(r.title,''), (select title from public.meetups where room_id = r.id order by starts_at desc limit 1), '모임 채팅'); v_body := coalesce(who,'이웃')||': '||v_body; end if;
  with tg as (
    select rm.profile_id from public.room_members rm join public.profiles p on p.id = rm.profile_id
    where rm.room_id = m.room_id and rm.profile_id <> m.sender_id and rm.profile_id <> sup and not (r.kind <> 'direct' and rm.left_at is not null)
      and p.suspended_at is null and p.deleted_at is null
      and (rm.last_read_at is null or rm.last_read_at < now() - interval '20 seconds')
      and not exists (select 1 from public.friendships f where f.status = 'blocked' and ((f.requester_id = rm.profile_id and f.addressee_id = m.sender_id) or (f.requester_id = m.sender_id and f.addressee_id = rm.profile_id)))
      and not exists (select 1 from public.chat_push_log l where l.room_id = m.room_id and l.profile_id = rm.profile_id and l.sent_at > now() - interval '60 seconds')
      and exists (select 1 from public.device_tokens d where d.profile_id = rm.profile_id and d.disabled_at is null)
  ), lg as (
    insert into public.chat_push_log(room_id, profile_id) select m.room_id, profile_id from tg
    on conflict (room_id, profile_id) do update set sent_at = now() returning profile_id
  )
  select coalesce(jsonb_agg(jsonb_build_object('token', d.token, 'bundle', d.bundle, 'platform', d.platform)), '[]'::jsonb) into v_tokens
    from public.device_tokens d where d.disabled_at is null and d.profile_id in (select profile_id from lg);
  return jsonb_build_object('title', v_title, 'body', v_body, 'kind', 'chat', 'room', m.room_id, 'support', v_sup, 'tokens', v_tokens);
end $function$;

-- push_mark(p_token text, p_ok boolean, p_dead boolean)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.push_mark(p_token text, p_ok boolean, p_dead boolean)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  update public.device_tokens set last_seen = case when p_ok then now() else last_seen end,
    fail_count = case when p_ok then 0 else fail_count + 1 end,
    disabled_at = case when p_dead or (not p_ok and fail_count + 1 >= 10) then now() else disabled_at end
  where token = lower(p_token);
$function$;

-- push_notification(p_recipient uuid, p_actor uuid, p_kind text, p_post uuid, p_root uuid, p_meetup uuid, p_snippet text)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.push_notification(p_recipient uuid, p_actor uuid, p_kind text, p_post uuid, p_root uuid, p_meetup uuid, p_snippet text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if p_recipient is null or p_recipient = p_actor then return; end if;
  if public.is_blocked(p_recipient, p_actor) then return; end if;
  insert into public.notifications(recipient_id, actor_id, kind, post_id, root_post_id, meetup_id, snippet)
  values (p_recipient, p_actor, p_kind, p_post, p_root, p_meetup, left(p_snippet, 80));
end $function$;

-- push_on_message()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.push_on_message()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.sender_id is not null and new.sender_id <> 'e120eb67-b254-4008-92d8-08c95c821e9e'::uuid then perform public.chat_push(new.id); end if;
  return null;
end $function$;

-- push_on_notification()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.push_on_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_secret text;
begin
  if new.kind = 'cheer' or coalesce(new.link->>'push','') = '0' then return null; end if;
  begin
    if exists (select 1 from public.device_tokens d where d.profile_id = new.recipient_id and d.disabled_at is null) then
      select value into v_secret from public.jigi_config where key = 'hook_secret';
      perform net.http_post(url := 'https://thfcrodfaitzrzlrxyir.supabase.co/functions/v1/push-send',
        body := jsonb_build_object('notification_id', new.id), headers := jsonb_build_object('Content-Type','application/json','x-jigi-secret', v_secret), timeout_milliseconds := 8000);
    end if;
  exception when others then null;
  end;
  return null;
end $function$;

-- push_payload(p_id uuid)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.push_payload(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n public.notifications; who text; body text; title text := '뜨개동네'; unread integer; kinds jsonb := '{
  "mention":"님이 회원님을 언급했어요","reply":"님이 댓글을 남겼어요","like":"님이 좋아해요","friend_request":"님이 친구 신청을 보냈어요","friend_accept":"님이 친구 신청을 수락했어요",
  "meetup_join":"님이 모임에 참여했어요","review":"님이 모임 후기를 남겼어요","solved":"님이 회원님의 댓글을 해결로 표시했어요","repost":"님이 회원님의 글을 리포스트했어요",
  "meetup_leave":"님이 모임 참여를 취소했어요","meetup_cancel":"님이 모임을 취소했어요","event_open":"새 이벤트가 열렸어요","event_selected":"이벤트에 선정됐어요!","event_rejected":"이번 이벤트에는 함께하지 못했어요"}';
begin
  select * into n from public.notifications where id = p_id; if n.id is null then return null; end if;
  select count(*) into unread from public.notifications where recipient_id = n.recipient_id and read_at is null;
  if n.kind = 'shop_post' then select s.name into who from public.shops s where s.id = n.shop_id; body := coalesce(who,'가게')||'에 새 소식이 올라왔어요';
  elsif n.kind in ('notice','supporter','cheer','remind') then body := coalesce(n.snippet, '새 소식이 있어요'); title := case when n.kind='supporter' then '서포터즈' when n.kind='notice' then '뜨개동네 지기' else '뜨개동네' end;
  elsif n.kind like 'event_%' then body := kinds->>n.kind; title := '이벤트';
  else select nickname into who from public.profiles where id = n.actor_id; body := coalesce(who,'이웃')||coalesce(kinds->>n.kind, '님의 새 소식');
    if n.snippet is not null and n.kind in ('mention','reply','review','notice') then body := body||': '||left(n.snippet, 60); end if;
  end if;
  return jsonb_build_object('recipient', n.recipient_id, 'title', title, 'body', body, 'badge', unread, 'kind', n.kind, 'notification_id', n.id,
    'tokens', (select coalesce(jsonb_agg(jsonb_build_object('token', d.token, 'bundle', d.bundle, 'platform', d.platform)), '[]'::jsonb) from public.device_tokens d where d.profile_id = n.recipient_id and d.disabled_at is null));
end $function$;

-- rate_hit(p_key text, p_limit integer, p_window_sec integer)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.rate_hit(p_key text, p_limit integer, p_window_sec integer DEFAULT 60)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_win timestamptz; v_n integer;
begin
  if auth.uid() is null then return false; end if;
  v_win := to_timestamp(floor(extract(epoch from now()) / greatest(p_window_sec,1)) * greatest(p_window_sec,1));
  insert into public.api_rate(profile_id, key, win, n) values (auth.uid(), left(p_key,30), v_win, 1)
    on conflict (profile_id, key, win) do update set n = public.api_rate.n + 1 returning n into v_n;
  if random() < 0.02 then delete from public.api_rate where win < now() - interval '2 days'; end if;
  return v_n <= p_limit;
end $function$;

-- recommend_patterns(p_limit integer)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.recommend_patterns(p_limit integer DEFAULT 6)
 RETURNS TABLE(id uuid, title text, craft text, level smallint, photos text[], price integer, buy_url text, yarn_weight text, needle_size text, author_id uuid, author_nickname text, new_count integer, new_techniques text[], step_up boolean, saved boolean, has_viewer boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with me as (select p.id, p.skills, p.craft, p.level_crochet, p.level_knit from public.profiles p where p.id = auth.uid()),
  cand as (
    select pt.*, case pt.craft when 'crochet' then me.level_crochet else me.level_knit end as mylv, me.skills as myskills, me.id as me_id
    from public.patterns pt, me
    where pt.is_published and not pt.hidden and pt.author_id <> me.id
      and ( (pt.craft = 'crochet' and (me.level_crochet > 0 or coalesce(me.craft::text,'crochet') in ('crochet','both')))
         or (pt.craft = 'knitting' and (me.level_knit > 0 or me.craft::text in ('knit','both'))) )
      and not public.is_blocked(me.id, pt.author_id)
  ), scored as (
    select c.*, (select array_agg(t.name_ko order by t.sort) from public.techniques t where t.id = any(c.techniques) and not (t.id = any(coalesce(c.myskills,'{}')))) as newt
    from cand c where c.level between greatest(c.mylv,1) and greatest(c.mylv,0) + 1
  )
  select s.id, s.title, s.craft, s.level, s.photos, s.price, s.buy_url, s.yarn_weight, s.needle_size,
         s.author_id, a.nickname, coalesce(cardinality(s.newt),0), coalesce(s.newt,'{}'), s.level > s.mylv,
         exists (select 1 from public.pattern_saves ps where ps.profile_id = s.me_id and ps.pattern_id = s.id), s.has_viewer
  from scored s join public.profiles a on a.id = s.author_id
  order by case when coalesce(cardinality(s.newt),0) between 1 and 2 then 0 when coalesce(cardinality(s.newt),0) = 0 then 1 else 2 end,
           md5(s.id::text || current_date::text || s.me_id::text)
  limit least(greatest(p_limit,1), 20);
$function$;

-- refresh_all_trait_index()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.refresh_all_trait_index()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; n int := 0; begin
  for r in select id from public.profiles where onboarded_at is not null loop perform public.compute_trait_index(r.id); n := n + 1; end loop; return n;
end $function$;

-- refresh_my_index()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.refresh_my_index()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ select public.compute_trait_index(auth.uid()); $function$;

-- register_device_token(p_token text, p_platform text, p_bundle text, p_version text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.register_device_token(p_token text, p_platform text DEFAULT 'ios'::text, p_bundle text DEFAULT NULL::text, p_version text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare plat text := case when p_platform = 'android' then 'android' else 'ios' end; tok text;
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  if plat = 'android' then
    if p_token is null or length(p_token) not between 32 and 1000 or p_token !~ '^[A-Za-z0-9_:\-]+$' then raise exception 'bad token'; end if;
    tok := p_token;   -- FCM 토큰은 대소문자 구분
  else
    if p_token is null or length(p_token) not between 32 and 400 or p_token !~ '^[0-9a-fA-F]+$' then raise exception 'bad token'; end if;
    tok := lower(p_token);
  end if;
  insert into public.device_tokens(token, profile_id, platform, bundle, app_version)
    values (tok, auth.uid(), plat, coalesce(nullif(p_bundle,''),'kr.co.firmtech.knitneighbors'), left(p_version,20))
    on conflict (token) do update set profile_id = excluded.profile_id, platform = excluded.platform, bundle = excluded.bundle, app_version = excluded.app_version, last_seen = now(), disabled_at = null, fail_count = 0;
end $function$;

-- reject_banned_message()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.reject_banned_message()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if public.contains_banned(new.body) then raise exception '커뮤니티 가이드라인에 맞지 않는 표현이 있어요' using errcode = 'P0001'; end if;
  return new;
end $function$;

-- reject_banned_post()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.reject_banned_post()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if public.contains_banned(new.body) then raise exception '커뮤니티 가이드라인에 맞지 않는 표현이 있어요' using errcode = 'P0001'; end if;
  return new;
end $function$;

-- reject_banned_profile()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.reject_banned_profile()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if public.contains_banned(new.nickname) or public.contains_banned(new.bio) then raise exception '커뮤니티 가이드라인에 맞지 않는 표현이 있어요' using errcode = 'P0001'; end if;
  return new;
end $function$;

-- remind_daily()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.remind_daily()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare tomorrow date := public.kst_date(now()) + 1; r record; n int := 0; host uuid; k int;
begin
  for r in select m.*, rm.profile_id uid from public.meetups m join public.room_members rm on rm.room_id = m.room_id where public.kst_date(m.starts_at) = tomorrow loop
    if public.cheer_send(r.uid, format('d1:%s', r.id), format('내일 %s ''%s'' — %s.%s', to_char(r.starts_at at time zone 'Asia/Seoul', 'HH24:MI'), r.title, coalesce(r.place_name,'장소 미정'), case when coalesce(r.bring,'') <> '' then ' 준비물: ' || r.bring else '' end), jsonb_build_object('type','meetup','id', r.id), 'remind') then n := n + 1; end if;
  end loop;
  for r in select sp.*, ca.profile_id uid from public.shop_posts sp join public.class_applications ca on ca.post_id = sp.id and ca.status = 'accepted'
      where sp.kind = 'class' and not sp.hidden and (sp.extra->>'starts_at') is not null and public.kst_date((sp.extra->>'starts_at')::timestamptz) = tomorrow loop
    if public.cheer_send(r.uid, format('d6:%s', r.id), format('내일 ''%s'' — %s.%s', r.title, coalesce(r.extra->>'place_text', r.extra->>'place', '장소는 채팅방 안내'), case when coalesce(r.extra->>'bring','') <> '' then ' 준비물: ' || (r.extra->>'bring') else '' end), jsonb_build_object('type','class','id', r.id), 'remind') then n := n + 1; end if;
  end loop;
  -- D5 입금 기한 D-1 (확정 후 pay_days 일, 미입금)
  for r in select sp.id post_id, sp.title, ca.id app_id, ca.profile_id uid, public.kst_date(ca.decided_at) + coalesce((sp.extra->>'pay_days')::int, 2) due
      from public.shop_posts sp join public.class_applications ca on ca.post_id = sp.id and ca.status = 'accepted' and ca.paid_at is null and ca.decided_at is not null
      where sp.kind = 'class' and not sp.hidden and (sp.extra->>'pay') in ('transfer','deposit') loop
    if r.due = tomorrow then
      if public.cheer_send(r.uid, format('d5:%s', r.app_id), format('''%s'' 입금 기한이 내일(%s)이에요. 이미 보내셨다면 채팅방에 알려 주세요.', r.title, to_char(r.due, 'MM월 DD일')), jsonb_build_object('type','class','id', r.post_id), 'remind') then n := n + 1; end if;
    end if;
  end loop;
  for r in select sp.id, sp.title, sp.shop_id, sp.author_id, count(*) cnt from public.shop_posts sp join public.class_applications ca on ca.post_id = sp.id and ca.status = 'applied' and ca.created_at < now() - interval '24 hours' where sp.kind = 'class' group by sp.id loop
    host := coalesce(r.author_id, (select owner_id from public.shops where id = r.shop_id)); if host is null then continue; end if;
    if public.cheer_send(host, format('f3:%s:%s', r.id, public.kst_date(now())), format('''%s'' 신청 %s건이 하루째 확인을 기다려요. 확정하면 신청자가 채팅방에 들어와요.', r.title, r.cnt), jsonb_build_object('type','class_manage','id', r.id), 'remind') then n := n + 1; end if;
  end loop;
  return jsonb_build_object('sent', n);
end $function$;

-- remind_tick()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.remind_tick()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; n int := 0;
begin
  for r in select m.*, rm.profile_id uid from public.meetups m join public.room_members rm on rm.room_id = m.room_id
      where m.starts_at + make_interval(mins => coalesce(m.duration_min, 120)) + interval '2 hours' between now() - interval '40 minutes' and now() loop
    if public.cheer_send(r.uid, format('d2:%s', r.id), format('''%s'' 어땠어요? 후기를 남기면 다음 모임에 도움이 돼요.', r.title), jsonb_build_object('type','meetup','id', r.id, 'push','0'), 'remind') then n := n + 1; end if;
  end loop; return n;
end $function$;

-- report_case_on_report()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.report_case_on_report()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

-- report_case_review(p_case bigint, p_verdict jsonb)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.report_case_review(p_case bigint, p_verdict jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c record; ttl text; nick text;
begin
  select * into c from public.report_cases where id = p_case and status in ('ask','review','hidden'); if not found then return; end if;
  update public.report_cases set status = case when status = 'hidden' then 'hidden' else 'review' end, verdict = p_verdict where id = p_case;
  select coalesce(nullif(w.title,''), left(coalesce(p.body,''), 20)), pr.nickname into ttl, nick from public.posts p left join public.works w on w.id = p.work_id join public.profiles pr on pr.id = p.author_id where p.id = c.post_id;
  insert into public.jigi_reminders(due_at, text) values (now(), '[신고 건 · 대표 확인 필요] 「'||coalesce(ttl,'')||'」(작성자 '||coalesce(nick,'')||')에 "직접 뜬 것이 아님" 신고가 있었고, 작성자가 지기 채팅으로 사진을 보내 왔습니다.'||E'\n\n'||
    'AI 가 원래 올린 사진과 새로 보낸 사진을 비교한 의견(참고용, 틀릴 수 있음):'||E'\n'||
    '· 같은 작품인가: '||coalesce(p_verdict->>'same','판단 못 함')||E'\n'||'· 원래 사진이 AI·광고 사진처럼 보이는가: '||coalesce(p_verdict->>'ai_like','판단 못 함')||E'\n'||'· 이유: '||coalesce(p_verdict->>'reason','(없음)')||E'\n\n'||
    '대표님이 하실 일: 콘솔 › 오늘 › 신고함에서 이 글을 열면 맨 위에 [직접 뜬 것 확인 · 그대로 두기] / [숨기기] 버튼이 있습니다. 누르면 작성자와 신고자에게 결과 안내가 자동으로 가고 신고가 닫힙니다. 작성자가 보낸 사진은 콘솔 › 지기 문의함의 대화에서 볼 수 있습니다.'||E'\n'||'https://yesbeyesnono.github.io/knit-neighbors/admin.html#reports');
end $function$;

-- report_case_tick()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.report_case_tick()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c record; n int := 0; ttl text; nick text;
begin
  for c in select * from public.report_cases where status = 'ask' and replied_at is null and due_at < now() loop
    perform public._report_case_close(c.id, false, 'ai', 'timeout'); n := n + 1;
    select coalesce(nullif(w.title,''), left(coalesce(p.body,''), 20)), pr.nickname into ttl, nick from public.posts p left join public.works w on w.id = p.work_id join public.profiles pr on pr.id = p.author_id where p.id = c.post_id;
    insert into public.jigi_reminders(due_at, text) values (now(), '[신고 건 · 자동 처리 보고] 「'||coalesce(ttl,'')||'」(작성자 '||coalesce(nick,'')||')에 "직접 뜬 것이 아님" 신고가 있어 작성자에게 사진을 요청했지만 3일 동안 답이 없어 **글을 임시로 숨겼습니다**. 작성자와 신고자에게 안내를 보냈습니다.'||E'\n\n'||'숨김은 임시 조치입니다. 작성자가 나중에 사진을 보내면 다시 알려 드리고, 콘솔 › 신고함의 글 상세에서 [직접 뜬 것 확인 · 그대로 두기]를 누르면 글이 다시 보입니다. 경고·인증 취소 같은 추가 조치가 필요하면 대표님이 직접 정해 주세요. 되돌리기: 콘솔 › 지기 AI 관리 › 기록.');
  end loop;
  -- 답은 왔는데(글자만) 사진이 없어 계속 열려 있는 건: 기한이 지나면 대표에게 한 번 알림
  for c in select * from public.report_cases where status = 'ask' and replied_at is not null and due_at < now() and coalesce(verdict->>'nudged','') = '' loop
    update public.report_cases set verdict = coalesce(verdict,'{}'::jsonb) || '{"nudged":"1"}'::jsonb where id = c.id;
    insert into public.jigi_reminders(due_at, text) values (now(), '[신고 건 · 대표 확인 필요] "직접 뜬 것이 아님" 신고 건에서 작성자가 지기 채팅에 답은 했지만 사진은 보내지 않은 채 3일이 지났습니다. 답 내용은 콘솔 › 지기 문의함에서 볼 수 있습니다. 콘솔 › 신고함의 글 상세에서 [그대로 두기] 또는 [숨기기]를 정해 주세요.'||E'\n'||'https://yesbeyesnono.github.io/knit-neighbors/admin.html#reports');
  end loop;
  return n;
end $function$;

-- report_feedback(p_body text, p_screenshot text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.report_feedback(p_body text, p_screenshot text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare fid bigint;
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  insert into public.feedback_reports(user_id, body, screenshot_url) values (auth.uid(), left(btrim(p_body),2000), p_screenshot) returning id into fid;
  perform public.jigi_call('feedback');
  return fid;
end $function$;

-- report_feedback(p_body text, p_screenshot text, p_kind text, p_attachments jsonb)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.report_feedback(p_body text, p_screenshot text DEFAULT NULL::text, p_kind text DEFAULT 'bug'::text, p_attachments jsonb DEFAULT '[]'::jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare fid bigint; att jsonb;
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  -- 첨부는 본인 폴더 경로만 인정(최대 5개)
  select coalesce(jsonb_agg(x), '[]'::jsonb) into att from (select x from jsonb_array_elements_text(case when jsonb_typeof(p_attachments)='array' then p_attachments else '[]'::jsonb end) x where x like auth.uid()::text || '/%' limit 5) t;
  insert into public.feedback_reports(user_id, body, screenshot_url, kind, attachments) values (auth.uid(), left(btrim(p_body),2000), p_screenshot, case when p_kind='idea' then 'idea' else 'bug' end, att) returning id into fid;
  perform public.jigi_call('feedback');
  return fid;
end $function$;

-- request_account_deletion()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.request_account_deletion()
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid := auth.uid(); v_ids uuid[]; v_fr jsonb; v_vis boolean; v_wave timestamptz; v_until timestamptz := now() + interval '20 days';
begin
  if uid is null then raise exception '로그인이 필요해요'; end if;
  if exists (select 1 from public.account_deletions where user_id = uid) then
    return (select purge_after from public.account_deletions where user_id = uid);
  end if;
  select coalesce(array_agg(id), '{}') into v_ids from public.posts where author_id = uid and coalesce(hidden, false) = false;
  update public.posts set hidden = true where id = any(v_ids);
  select coalesce(jsonb_agg(to_jsonb(f)), '[]') into v_fr from public.friendships f where f.requester_id = uid or f.addressee_id = uid;
  delete from public.friendships where requester_id = uid or addressee_id = uid;
  select is_visible, wave_until into v_vis, v_wave from public.profiles where id = uid;
  update public.profiles set deleted_at = now(), is_visible = false, wave_until = null where id = uid;
  insert into public.account_deletions(user_id, purge_after, hidden_post_ids, friendships, was_visible, wave_until)
    values (uid, v_until, v_ids, v_fr, coalesce(v_vis, false), v_wave);
  return v_until;
end $function$;

-- restore_my_account()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.restore_my_account()
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid := auth.uid(); r public.account_deletions;
begin
  if uid is null then raise exception '로그인이 필요해요'; end if;
  select * into r from public.account_deletions where user_id = uid;
  if not found then update public.profiles set deleted_at = null where id = uid; return false; end if;
  update public.posts set hidden = false where id = any(r.hidden_post_ids) and author_id = uid;
  insert into public.friendships select * from jsonb_populate_recordset(null::public.friendships, r.friendships) on conflict do nothing;
  update public.profiles set deleted_at = null, is_visible = r.was_visible, wave_until = r.wave_until where id = uid;
  delete from public.account_deletions where user_id = uid;
  return true;
end $function$;

-- revoke_points(p_kind text, p_ref_table text, p_ref_id text)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.revoke_points(p_kind text, p_ref_table text, p_ref_id text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare e public.point_events;
begin
  select * into e from public.point_events where kind = p_kind and ref_table = p_ref_table and ref_id = p_ref_id;
  if e.id is null then return 0; end if;
  if exists (select 1 from public.point_events where kind = p_kind||'_revoke' and ref_table = p_ref_table and ref_id = p_ref_id) then return 0; end if;
  insert into public.point_events(supporter_id, user_id, kind, points, ref_table, ref_id, kst_date, segment) values (e.supporter_id, e.user_id, p_kind||'_revoke', -e.points, p_ref_table, p_ref_id, e.kst_date, e.segment);
  return -e.points;
end $function$;

-- room_archive(p_room uuid, p_on boolean)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.room_archive(p_room uuid, p_on boolean DEFAULT true)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  update public.room_members set archived_at = case when p_on then now() else null end where room_id = p_room and profile_id = auth.uid();
  return found;
end $function$;

-- room_leave(p_room uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.room_leave(p_room uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e'; r public.rooms;
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  select * into r from public.rooms where id = p_room;
  if r.id is null or not exists (select 1 from public.room_members where room_id = p_room and profile_id = auth.uid()) then raise exception '대화방을 찾을 수 없어요'; end if;
  if exists (select 1 from public.room_members where room_id = p_room and profile_id = sup) then raise exception '지기 채팅은 나갈 수 없어요'; end if;
  if r.kind <> 'direct' then
    if exists (select 1 from public.meetups m where m.room_id = p_room and (coalesce(m.repeat,'once') <> 'once' or m.starts_at + make_interval(mins => coalesce(m.duration_min,120)) > now())) then
      raise exception '아직 끝나지 않은 모임이에요. 모임에서 참여 취소를 먼저 해 주세요';
    end if;
    if exists (select 1 from public.shop_posts sp where sp.room_id = p_room and sp.kind = 'class' and (sp.extra->>'starts_at') is not null
               and (sp.extra->>'starts_at')::timestamptz + make_interval(mins => coalesce((sp.extra->>'duration_min')::int,120)) > now()) then
      raise exception '아직 끝나지 않은 클래스예요. 신청 취소를 먼저 해 주세요';
    end if;
  end if;
  update public.room_members set left_at = now(), archived_at = null where room_id = p_room and profile_id = auth.uid();
  return true;
end $function$;

-- room_members_meetup_gate()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.room_members_meetup_gate()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if exists (select 1 from public.meetups m where m.room_id = new.room_id and m.join_mode = 'apply' and m.created_by <> new.profile_id)
     and not exists (select 1 from public.meetups m join public.meetup_applications a on a.meetup_id = m.id
                      where m.room_id = new.room_id and a.profile_id = new.profile_id and a.status = 'accepted') then
    raise exception '이 모임은 참여 신청 뒤 개설자가 확정하면 들어올 수 있어요. 앱을 최신 버전으로 업데이트해 주세요';
  end if;
  return new;
end $function$;

-- set_author_cover(p_url text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.set_author_cover(p_url text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v text := nullif(btrim(coalesce(p_url,'')), '');
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and is_author and suspended_at is null) then raise exception '작가만 넣을 수 있어요'; end if;
  if not public._own_storage_url(v) then raise exception '사진을 다시 올려 주세요'; end if;
  update public.profiles set cover_url = v where id = auth.uid();
end $function$;

-- set_author_link(p_link text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.set_author_link(p_link text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v text := nullif(btrim(coalesce(p_link,'')), '');
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and is_author and suspended_at is null) then raise exception '작가만 링크를 넣을 수 있어요'; end if;
  if v is not null and v !~* '^https?://' then raise exception '링크는 https://로 시작해야 해요'; end if;
  if v is not null and exists (select 1 from public.banned_words b where lower(v) like '%'||lower(b.word)||'%') then raise exception '사용할 수 없는 표현이 들어 있어요'; end if;
  update public.profiles set author_link = v where id = auth.uid();
end $function$;

-- set_author_links(p_links jsonb)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.set_author_links(p_links jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v text; arr text[] := '{}';
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and is_author and suspended_at is null) then raise exception '작가만 링크를 넣을 수 있어요'; end if;
  if p_links is not null and jsonb_typeof(p_links) <> 'array' then raise exception '링크 형식이 맞지 않아요'; end if;
  for v in select btrim(x) from jsonb_array_elements_text(coalesce(p_links,'[]'::jsonb)) x loop
    if v = '' then continue; end if;
    if length(v) > 300 or v !~* '^https?://[^\s<>"'']+$' then raise exception '링크는 https://로 시작해야 해요'; end if;
    if exists (select 1 from public.banned_words b where lower(v) like '%'||lower(b.word)||'%') then raise exception '사용할 수 없는 표현이 들어 있어요'; end if;
    if not (v = any(arr)) then arr := arr || v; end if;
  end loop;
  if coalesce(array_length(arr,1),0) > 3 then raise exception '링크는 3개까지 넣을 수 있어요'; end if;
  update public.profiles set author_links = case when array_length(arr,1) is null then null else to_jsonb(arr) end, author_link = arr[1] where id = auth.uid();
  return to_jsonb(arr);
end $function$;

-- set_event_shipping(p_event uuid, p_name text, p_phone text, p_zip text, p_addr text, p_memo text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.set_event_shipping(p_event uuid, p_name text, p_phone text, p_zip text, p_addr text, p_memo text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_app uuid;
begin
  select a.id into v_app from public.event_applications a join public.events e on e.id = a.event_id
    where a.event_id = p_event and a.profile_id = auth.uid() and a.status = 'selected' and e.needs_shipping;
  if v_app is null then raise exception '선정된 이벤트에서만 배송지를 입력할 수 있어요'; end if;
  if btrim(coalesce(p_name,'')) = '' or btrim(coalesce(p_phone,'')) = '' or btrim(coalesce(p_addr,'')) = '' then raise exception '이름·연락처·주소를 입력해 주세요'; end if;
  insert into public.event_shipping(application_id, profile_id, name, phone, zip, addr, memo)
    values (v_app, auth.uid(), left(btrim(p_name),30), left(btrim(p_phone),20), left(btrim(coalesce(p_zip,'')),10), left(btrim(p_addr),200), nullif(left(btrim(coalesce(p_memo,'')),100),''))
    on conflict (application_id) do update set name = excluded.name, phone = excluded.phone, zip = excluded.zip, addr = excluded.addr, memo = excluded.memo
      where public.event_shipping.shipped_at is null;
  if not found then raise exception '이미 발송돼서 바꿀 수 없어요'; end if;
end $function$;

-- set_fuzzy_location(p_lat double precision, p_lng double precision)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.set_fuzzy_location(p_lat double precision, p_lng double precision)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  cell constant double precision := 0.0018;   -- 약 200m
  snapped_lat double precision;
  snapped_lng double precision;
begin
  snapped_lat := floor(p_lat / cell) * cell + cell / 2;
  snapped_lng := floor(p_lng / cell) * cell + cell / 2;
  update public.profiles
     set location = st_setsrid(st_makepoint(snapped_lng, snapped_lat), 4326)::geography
   where id = auth.uid();
end $function$;

-- set_meetup_location(p_meetup uuid, p_lat double precision, p_lng double precision, p_address text, p_place text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.set_meetup_location(p_meetup uuid, p_lat double precision, p_lng double precision, p_address text DEFAULT NULL::text, p_place text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if p_lat is null or p_lng is null or p_lat not between 32 and 40 or p_lng not between 123 and 133 then raise exception '위치를 다시 골라 주세요'; end if;
  update public.meetups set location = st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography,
         address = left(nullif(btrim(coalesce(p_address,'')), ''), 200), place_name = coalesce(nullif(btrim(coalesce(p_place,'')), ''), place_name)
   where id = p_meetup and created_by = auth.uid();
  if not found then raise exception '주최자만 장소를 바꿀 수 있어요'; end if;
end $function$;

-- set_pattern_pkg(p_id uuid, p_pkg jsonb)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.set_pattern_pkg(p_id uuid, p_pkg jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare owner uuid;
begin
  select author_id into owner from public.patterns where id = p_id;
  if owner is null then raise exception '도안을 찾을 수 없어요'; end if;
  if not (public.is_admin() or (owner = auth.uid() and exists (select 1 from public.profiles where id = auth.uid() and is_author and suspended_at is null))) then
    raise exception '내 도안에만 첨부할 수 있어요'; end if;
  if p_pkg is null then
    delete from public.pattern_contents where pattern_id = p_id;
    update public.patterns set has_viewer = false, updated_at = now() where id = p_id;
    return;
  end if;
  if coalesce(p_pkg->>'app','') <> 'knitup-pattern-package' or jsonb_typeof(p_pkg->'charts') <> 'array' or jsonb_array_length(p_pkg->'charts') = 0 then
    raise exception 'knitup 도안 패키지 형식이 아니에요'; end if;
  if pg_column_size(p_pkg) > 3000000 then raise exception '패키지가 너무 커요 (3MB 이하)'; end if;
  insert into public.pattern_contents(pattern_id, pkg) values (p_id, p_pkg)
    on conflict (pattern_id) do update set pkg = excluded.pkg, updated_at = now();
  update public.patterns set has_viewer = true, updated_at = now() where id = p_id;
end $function$;

-- set_referrer(p_code text, p_nickname text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.set_referrer(p_code text DEFAULT NULL::text, p_nickname text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid := auth.uid(); p public.profiles; inviter uuid; src text;
begin
  if uid is null then raise exception '로그인이 필요해요'; end if;
  select * into p from public.profiles where id = uid;
  if p.referred_by is not null then return jsonb_build_object('error','ALREADY'); end if;
  if p.created_at < now() - interval '1 day' then return jsonb_build_object('error','NOT_NEW'); end if;
  if nullif(btrim(coalesce(p_code,'')),'') is not null then select s.user_id into inviter from public.supporters s where s.ref_code = upper(btrim(p_code)); src := 'link';
  elsif nullif(btrim(coalesce(p_nickname,'')),'') is not null then select id into inviter from public.profiles where lower(nickname) = lower(btrim(p_nickname)) limit 1; src := 'manual'; end if;
  if inviter is null then return jsonb_build_object('error','NOT_FOUND'); end if;
  if inviter = uid then return jsonb_build_object('error','SELF'); end if;
  update public.profiles set referred_by = inviter where id = uid;
  insert into public.referrals(inviter_user_id, invitee_user_id, source) values (inviter, uid, src) on conflict (invitee_user_id) do nothing;
  return jsonb_build_object('ok', true, 'inviter', (select nickname from public.profiles where id = inviter));
end $function$;

-- set_updated_at()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  new.updated_at := now();
  return new;
end $function$;

-- shop_posts_class_changed()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.shop_posts_class_changed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid := auth.uid(); ch text[] := '{}'; v_ts timestamptz; v_msg text; o jsonb := coalesce(old.extra,'{}'::jsonb); e jsonb := coalesce(new.extra,'{}'::jsonb);
  won constant text := 'FM999,999,999';
begin
  if new.kind <> 'class' or uid is null then return null; end if;
  begin v_ts := (e->>'starts_at')::timestamptz; exception when others then v_ts := null; end;
  if (e->>'starts_at') is distinct from (o->>'starts_at') and v_ts is not null then ch := ch || ('일시가 ' || to_char(v_ts at time zone 'Asia/Seoul', 'FMMM"월" FMDD"일" HH24:MI') || '(으)로'); end if;
  if (e->>'place_text') is distinct from (o->>'place_text') or (e->>'place') is distinct from (o->>'place') then ch := ch || ('장소가 ' || coalesce(nullif(e->>'place_text',''), case when e->>'place'='online' then '온라인' else '새 장소' end) || '(으)로'); end if;
  if (e->>'fee') is distinct from (o->>'fee') or (e->>'material_fee') is distinct from (o->>'material_fee') or (e->>'material') is distinct from (o->>'material') then
    ch := ch || ('수강료가 ' || case when (e->>'fee') ~ '^[0-9]+$' then to_char((e->>'fee')::numeric, won) || '원' else coalesce(e->>'fee','') end
      || case when e->>'material' = 'extra' and (e->>'material_fee') ~ '^[0-9]+$' then ' + 재료비 ' || to_char((e->>'material_fee')::numeric, won) || '원' when e->>'material' = 'incl' then ' (재료비 포함)' else '' end || '(으)로');
  end if;
  if cardinality(ch) = 0 or (v_ts is not null and v_ts < now()) then return null; end if;
  v_msg := '「' || left(new.title, 40) || '」 클래스의 ' || array_to_string(ch, ', ') || ' 바뀌었어요. 클래스 안내를 확인해 주세요';
  insert into public.notifications(recipient_id, actor_id, kind, snippet, link)
    select a.profile_id, uid, 'notice', left(v_msg, 200), jsonb_build_object('type','class','id',new.id)
      from public.class_applications a where a.post_id = new.id and a.status in ('applied','accepted') and a.profile_id <> uid;
  return null;
end $function$;

-- shop_stats(p_days integer)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.shop_stats(p_days integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare out jsonb;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  select jsonb_build_object(
    'orders', count(*) filter (where status <> 'cancelled'),
    'revenue', coalesce(sum(total) filter (where status in ('paid','shipped','done')), 0),
    'pending', count(*) filter (where status = 'pending_payment'),
    'to_ship', count(*) filter (where status = 'paid'),
    'shipped', count(*) filter (where status = 'shipped'),
    'cancelled', count(*) filter (where status = 'cancelled'),
    'balls', coalesce((select sum((x->>'qty')::int) from public.orders o2, jsonb_array_elements(o2.items) x where o2.status in ('paid','shipped','done') and o2.created_at >= now() - make_interval(days => p_days)), 0)
  ) into out from public.orders where created_at >= now() - make_interval(days => p_days);
  return out;
end $function$;

-- stash_apply_read(p_id uuid, p_json jsonb, p_ok boolean)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.stash_apply_read(p_id uuid, p_json jsonb, p_ok boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.yarn_stash; v_name text; v_color text; cid uuid; num constant text := '^[0-9]{1,5}(\.[0-9]{1,2})?$'; v_hex text; v_g numeric; v_m numeric; v_f jsonb; spec_cid uuid; v_tx jsonb;
begin
  select * into s from public.yarn_stash where id = p_id for update;
  if s.id is null then return; end if;
  if not p_ok then update public.yarn_stash set read_status = 'failed', read_json = p_json where id = p_id; return; end if;
  v_name := nullif(left(btrim(concat_ws(' ', nullif(btrim(coalesce(p_json->>'brand','')),''), nullif(btrim(coalesce(p_json->>'product','')),''))),60),'');
  v_color := nullif(left(btrim(concat_ws(' ', nullif(btrim(coalesce(p_json->>'color_no','')),''), coalesce(nullif(btrim(coalesce(p_json->>'color_name','')),''), nullif(btrim(coalesce(p_json->>'color_guess','')),'')))),40),'');
  v_tx := case when jsonb_typeof(p_json->'texture') = 'object' then nullif(jsonb_strip_nulls(jsonb_build_object(
      'halo',      case when p_json->'texture'->>'halo'      in ('none','light','fuzzy') then p_json->'texture'->>'halo' end,
      'twist',     case when p_json->'texture'->>'twist'     in ('tight','loose','none') then p_json->'texture'->>'twist' end,
      'shape',     case when p_json->'texture'->>'shape'     in ('plain','boucle','chenille','tape','cord') then p_json->'texture'->>'shape' end,
      'thickness', case when p_json->'texture'->>'thickness' in ('fine','medium','bulky') then p_json->'texture'->>'thickness' end)), '{}'::jsonb) end;
  v_hex := case when (p_json->>'color_hex') ~ '^#[0-9a-fA-F]{6}$' then lower(p_json->>'color_hex') end;
  v_g := case when (p_json->>'ball_g') ~ num and (p_json->>'ball_g')::numeric > 0 then (p_json->>'ball_g')::numeric end;
  v_m := case when (p_json->>'ball_m') ~ num and (p_json->>'ball_m')::numeric > 0 then (p_json->>'ball_m')::numeric end;
  v_f := case when jsonb_typeof(p_json->'fibers')='object' and pg_column_size(p_json->'fibers') <= 300 then p_json->'fibers' end;
  -- 이름을 못 읽었거나 이름으로 사전에 없으면 규격으로 찾기 (회원이 이름을 직접 고쳤으면 그 이름 존중)
  if not ('raw_name' = any(s.edited)) and (v_name is null or not exists (select 1 from public.yarn_catalog c where c.norm_keys @> array[public.yarn_norm(v_name)])) then
    spec_cid := public.yarn_match_spec_one(p_json->>'brand', coalesce(s.ball_g, v_g), coalesce(s.ball_m, v_m), coalesce(s.fibers, v_f), p_json->>'color_no');
    if spec_cid is not null then
      if v_name is not null then perform public.yarn_add_alias(spec_cid, v_name); end if;
      select coalesce(c.brand||' ','')||c.product into v_name from public.yarn_catalog c where c.id = spec_cid;
    end if;
  end if;
  if v_name is null then update public.yarn_stash set read_status = 'failed', read_json = p_json where id = p_id; return; end if;
  update public.yarn_stash set read_status = 'done', read_json = p_json,
    raw_name = case when 'raw_name' = any(edited) then raw_name else v_name end,
    color    = case when 'color' = any(edited) then color else coalesce(v_color, color) end,
    color_hex  = case when 'color' = any(edited) or v_hex is null then color_hex else array[v_hex] end,
    color_mode = case when 'color' = any(edited) or v_hex is null then color_mode else 'solid' end,
    brand = case when 'brand' = any(edited) then brand else coalesce(nullif(left(btrim(p_json->>'brand'), 40), ''), brand) end,
    ball_g   = case when 'ball_g' = any(edited) or v_g is null then ball_g else v_g end,
    ball_m   = case when 'ball_m' = any(edited) or v_m is null then ball_m else v_m end,
    fibers   = case when 'fibers' = any(edited) or v_f is null then fibers else v_f end,
    texture  = case when 'texture' = any(edited) or v_tx is null then texture else v_tx end
    where id = p_id returning * into s;
  cid := public.yarn_log_entry(null, jsonb_strip_nulls(jsonb_build_object('name', s.raw_name, 'brand', p_json->>'brand', 'color', s.color, 'color_no', p_json->>'color_no', 'ball_g', s.ball_g, 'ball_m', s.ball_m, 'fibers', s.fibers, 'color_hex', to_jsonb(s.color_hex), 'color_mode', s.color_mode, 'color_families', to_jsonb(s.color_families))), null, null, null, null, null);
  update public.yarn_entries set source = 'stash' where id = (select max(id) from public.yarn_entries where catalog_id = cid and work_id is null and source = 'work');
  update public.yarn_stash set catalog_id = cid where id = p_id;
end $function$;

-- stash_consume(p_work uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.stash_consume(p_work uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare w public.works; y jsonb; s public.yarn_stash; v_balls numeric; v_take numeric; n integer := 0;
begin
  select * into w from public.works where id = p_work;
  if w.id is null or (auth.uid() is not null and w.profile_id <> auth.uid()) then return 0; end if;
  for y in select * from jsonb_array_elements(coalesce(w.yarns,'[]'::jsonb)) loop
    continue when (y->>'stash_id') is null or (y->>'amount') is null;
    select * into s from public.yarn_stash where id = (y->>'stash_id')::uuid and owner_id = w.profile_id for update;
    continue when s.id is null;
    continue when exists (select 1 from public.yarn_stash_log l where l.stash_id = s.id and l.work_id = p_work);
    if y->>'unit' = 'g' then
      if coalesce((y->>'ball_g')::numeric, s.ball_g, 0) <= 0 then continue; end if;
      v_balls := (y->>'amount')::numeric / coalesce((y->>'ball_g')::numeric, s.ball_g);
    else v_balls := (y->>'amount')::numeric; end if;
    v_take := round(least(s.left_balls, greatest(v_balls, 0)), 2);
    update public.yarn_stash set left_balls = left_balls - v_take where id = s.id;
    insert into public.yarn_stash_log(stash_id, work_id, delta) values (s.id, p_work, -v_take);
    n := n + 1;
  end loop;
  return n;
end $function$;

-- stash_link_catalog(p_id uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.stash_link_catalog(p_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.yarn_stash; cid uuid;
begin
  select * into s from public.yarn_stash where id = p_id and owner_id = auth.uid();
  if s.id is null or s.raw_name is null or s.catalog_id is not null then return s.catalog_id; end if;
  cid := public.yarn_log_entry(null, jsonb_strip_nulls(jsonb_build_object('name', s.raw_name, 'color', s.color, 'ball_g', s.ball_g, 'ball_m', s.ball_m, 'fiber', s.fiber, 'fibers', s.fibers, 'weight', s.weight)), null, null, null, null, null);
  update public.yarn_entries set source = 'stash' where id = (select max(id) from public.yarn_entries where catalog_id = cid and work_id is null and source = 'work');
  update public.yarn_stash set catalog_id = cid where id = p_id;
  return cid;
end $function$;

-- stash_restore(p_work uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.stash_restore(p_work uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; n integer := 0;
begin
  if auth.uid() is not null and not public.is_admin() and not exists (select 1 from public.works where id = p_work and profile_id = auth.uid()) then return 0; end if;
  for r in select * from public.yarn_stash_log where work_id = p_work loop
    update public.yarn_stash set left_balls = least(999, left_balls - r.delta) where id = r.stash_id;
    delete from public.yarn_stash_log where id = r.id; n := n + 1;
  end loop;
  return n;
end $function$;

-- studio_claim_code()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.studio_claim_code()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c text; uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  delete from public.studio_inbox where expires_at < now() - interval '1 day';
  delete from public.studio_inbox where profile_id = uid and pkg is null;
  loop
    c := lpad((floor(random()*1000000))::int::text, 6, '0');
    exit when not exists (select 1 from public.studio_inbox where code = c and pkg is null and expires_at > now());
  end loop;
  insert into public.studio_inbox(profile_id, code) values (uid, c);
  return c;
end $function$;

-- studio_inbox_take()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.studio_inbox_take()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; uid uuid := auth.uid();
begin
  if uid is null then return null; end if;
  select * into r from public.studio_inbox where profile_id = uid and pkg is not null and claimed_at > now() - interval '7 days' order by claimed_at desc limit 1;
  if r.id is null then return null; end if;
  delete from public.studio_inbox where id = r.id;
  return jsonb_build_object('title', r.title, 'meta', r.meta, 'pkg', r.pkg, 'at', r.claimed_at);
end $function$;

-- studio_submit(p_code text, p_title text, p_meta jsonb, p_pkg jsonb)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres,anon=X/postgres}
CREATE OR REPLACE FUNCTION public.studio_submit(p_code text, p_title text, p_meta jsonb, p_pkg jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare rid uuid;
begin
  if p_code !~ '^[0-9]{6}$' then return false; end if;
  if p_pkg is null or jsonb_typeof(p_pkg) <> 'object' or coalesce(p_pkg->>'app','') <> 'knitup-pattern-package' or jsonb_typeof(p_pkg->'charts') <> 'array' or jsonb_array_length(p_pkg->'charts') = 0 then return false; end if;
  if length(p_pkg::text) > 3*1024*1024 then return false; end if;
  select id into rid from public.studio_inbox where code = p_code and pkg is null and expires_at > now() order by created_at desc limit 1;
  if rid is null then return false; end if;
  update public.studio_inbox set title = left(coalesce(p_title,''), 80), meta = p_meta, pkg = p_pkg, claimed_at = now() where id = rid;
  return true;
end $function$;

-- studio_yarn_search(p_q text, p_craft text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres,anon=X/postgres}
CREATE OR REPLACE FUNCTION public.studio_yarn_search(p_q text, p_craft text DEFAULT 'crochet'::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when length(btrim(coalesce(p_q,''))) < 2 then '[]'::jsonb else coalesce(jsonb_agg(x), '[]'::jsonb) end from (
    select jsonb_build_object(
      'name',   btrim(coalesce(c.brand||' ','')||c.product),
      'sts',    g->'sts',
      'rows',   g->'rows',
      'needle', g->>'needle',
      'stitch', g->>'stitch') x
    from public.yarn_catalog c
    cross join lateral (select case when p_craft = 'knitting' then c.gauge_knit else c.gauge_crochet end g) gg
    where c.merged_into is null and public.yarn_norm(p_q) is not null and g is not null
      and exists (select 1 from unnest(c.norm_keys || public.yarn_norm(coalesce(c.brand,'')||c.product) || public.yarn_norm(coalesce(c.brand,'')||coalesce(c.product_en,''))
          || coalesce((select array_agg(public.yarn_norm(a.alias||c.product)) from public.yarn_brand_aliases a where a.brand = c.brand), '{}')) kk where kk like '%'||public.yarn_norm(p_q)||'%')
    order by (c.status='verified') desc, c.uses desc, c.id limit 8) t;
$function$;

-- submit_survey(p_survey integer, p_answers jsonb)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.submit_survey(p_survey integer, p_answers jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sv public.surveys; rid bigint;
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  select * into sv from public.surveys where id = p_survey; if sv.id is null then raise exception '설문이 없어요'; end if;
  if now() < sv.opens_at or now() > sv.closes_at then raise exception '응답 기간이 아니에요'; end if;
  insert into public.survey_responses(survey_id, user_id, answers) values (p_survey, auth.uid(), coalesce(p_answers,'{}')) on conflict (survey_id, user_id) do nothing returning id into rid;
  if rid is null then return 0; end if;
  return public.award_points(auth.uid(), 'survey', 'surveys', p_survey::text);
end $function$;

-- support_deliver(p_ticket bigint, p_text text, p_close boolean)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.support_deliver(p_ticket bigint, p_text text, p_close boolean DEFAULT false)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t public.support_tickets; mid bigint; sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e';
begin
  select * into t from public.support_tickets where id = p_ticket; if t.id is null then return null; end if;
  if btrim(coalesce(p_text,'')) <> '' then
    insert into public.messages(room_id, sender_id, body, by_ai, support_seen) values (t.room_id, sup, left(btrim(p_text),1000), false, true) returning id into mid;
    update public.room_members set last_read_at = now() where room_id = t.room_id and profile_id = sup;
  end if;
  update public.support_tickets set admin_answer = coalesce(nullif(btrim(p_text),''), admin_answer), answered_at = now(),
    status = case when p_close then 'closed' else 'answered' end, closed_at = case when p_close then now() else closed_at end,
    followup_at = case when p_close then null else now() + interval '1 day' end, updated_at = now() where id = p_ticket;
  insert into public.support_events(ticket_id, actor, kind, body) values (p_ticket, 'admin', case when p_close then 'close' else 'answer' end, left(coalesce(p_text,''),1000));
  update public.mod_items set status='done', resolved_at=now(), resolved_by='admin', resolution='답변(텔레그램)' where kind='support' and target_id = p_ticket::text and status='open';
  if mid is not null then perform public.chat_push(mid); end if;
  return mid;
end $function$;

-- support_msg(p_user uuid, p_key text, p_body text)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.support_msg(p_user uuid, p_key text, p_body text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e'; rid uuid;
begin
  if p_user is null or p_user = sup then return false; end if;
  if exists (select 1 from public.cheer_log where user_id = p_user and key = p_key) then return false; end if;
  select r.id into rid from public.rooms r join public.room_members a on a.room_id = r.id and a.profile_id = p_user join public.room_members b on b.room_id = r.id and b.profile_id = sup where r.kind = 'direct' limit 1;
  if rid is null then
    insert into public.rooms(kind, created_by) values ('direct', p_user) returning id into rid;
    insert into public.room_members(room_id, profile_id) values (rid, p_user), (rid, sup);
  end if;
  insert into public.messages(room_id, sender_id, body, by_ai) values (rid, sup, p_body, true);
  insert into public.cheer_log(user_id, key, kind, body, sent_at) values (p_user, p_key, 'support', p_body, now());
  return true;
end $function$;

-- support_on_message()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.support_on_message()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

-- supporter_cheer(p_sid bigint, p_seg smallint)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.supporter_cheer(p_sid bigint, p_seg smallint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.supporters; pts integer; th integer; k text; msg text;
begin
  if p_seg not in (1,2) then return; end if;
  select * into s from public.supporters where id = p_sid;
  select coalesce(sum(points),0) into pts from public.point_events where supporter_id = p_sid and segment = p_seg;
  foreach th in array array[30,60,90] loop
    if pts >= th then k := format('seg%s_%s', p_seg, th);
      if not exists (select 1 from public.supporter_notices where supporter_id = p_sid and notice_key = k) then
        insert into public.supporter_notices(supporter_id, notice_key) values (p_sid, k);
        msg := case when th = 90 then format('%s구간 %s점! 100점까지 %s점 남았어요. 설문 하나면 10점이에요 🧶', p_seg, pts, greatest(100-pts,0)) when th = 60 then format('%s구간 %s점 — 절반을 넘었어요. 이 속도면 충분해요!', p_seg, pts) else format('%s구간 %s점 달성! 잘 하고 계세요.', p_seg, pts) end;
        insert into public.notifications(recipient_id, actor_id, kind, snippet) values (s.user_id, 'e120eb67-b254-4008-92d8-08c95c821e9e', 'supporter', msg);
      end if;
    end if;
  end loop;
end $function$;

-- supporter_invite_notice()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.supporter_invite_notice()
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid := auth.uid(); st jsonb; p public.profiles; sup constant uuid := 'e120eb67-b254-4008-92d8-08c95c821e9e';
begin
  if uid is null then return false; end if;
  st := public.get_supporter_status();
  if coalesce((st->>'supporter')::boolean, false) or not coalesce((st->>'is_open')::boolean, false) then return false; end if;
  if exists (select 1 from public.notifications where recipient_id = uid and kind = 'supporter' and snippet like '1기 서포터즈 모집 중%') then return false; end if;
  select * into p from public.profiles where id = uid;
  if p.onboarded_at is null then return false; end if;
  if not (exists (select 1 from public.posts where author_id = uid) or exists (select 1 from public.works where profile_id = uid)
          or exists (select 1 from public.messages where sender_id = uid) or public.kst_date(now()) > public.kst_date(p.created_at)) then return false; end if;
  insert into public.notifications(recipient_id, actor_id, kind, snippet)
    values (uid, sup, 'supporter', format('1기 서포터즈 모집 중 · 60일 동안 함께 앱을 키워 주실 분을 모셔요. 뱃지·매거진·실 키트 보상, 잔여 %s명 — 눌러서 신청하기', coalesce(st->>'remaining','-')));
  return true;
end $function$;

-- supporter_of(p_user uuid)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.supporter_of(p_user uuid)
 RETURNS supporters
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select s.* from public.supporters s
  where coalesce((select (value)::text = 'true' from public.app_config where key = 'supporters_enabled'), true)
    and s.user_id = p_user and s.status = 'active' order by s.id desc limit 1
$function$;

-- supporter_on_post()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.supporter_on_post()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare parent_author uuid;
begin
  if tg_op = 'INSERT' then
    if new.parent_id is null then
      if new.work_id is null and new.meetup_id is null and new.review_of is null then perform public.award_points(new.author_id, 'post', 'posts', new.id::text, new.created_at); end if;
    else
      select author_id into parent_author from public.posts where id = new.parent_id;
      if parent_author is distinct from new.author_id then perform public.award_points(new.author_id, 'comment', 'posts', new.id::text, new.created_at); end if;
    end if;
    return null;
  else
    perform public.revoke_points('post', 'posts', old.id::text); perform public.revoke_points('comment', 'posts', old.id::text); return old;
  end if;
end $function$;

-- supporter_on_work()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.supporter_on_work()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if tg_op = 'INSERT' then perform public.award_points(new.profile_id, 'work_verified', 'works', new.id::text, new.created_at); return null;
  else perform public.revoke_points('work_verified', 'works', old.id::text); return old; end if;
end $function$;

-- supporter_segment(p_started timestamp with time zone, p_at timestamp with time zone)  acl: {=X/postgres,postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.supporter_segment(p_started timestamp with time zone, p_at timestamp with time zone DEFAULT now())
 RETURNS smallint
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$ select case when (public.kst_date(p_at) - public.kst_date(p_started)) between 0 and 29 then 1 when (public.kst_date(p_at) - public.kst_date(p_started)) between 30 and 59 then 2 else 0 end::smallint $function$;

-- supporter_stats()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.supporter_stats()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'cohort', c.name, 'capacity', c.capacity, 'is_open', c.is_open,
    'joined', (select count(*) from public.supporters s where s.cohort_id = c.id),
    'active', (select count(*) from public.supporters s where s.cohort_id = c.id and s.status = 'active'),
    'new_today', (select count(*) from public.supporters s where s.cohort_id = c.id and public.kst_date(s.started_at) = public.kst_date(now())),
    'points_today', (select coalesce(sum(points),0) from public.point_events where kst_date = public.kst_date(now())),
    'tiers', (select coalesce(jsonb_object_agg(tier, n), '{}') from (select tier, count(*) n from public.supporters where cohort_id = c.id and tier is not null group by tier) x),
    'open_feedback', (select count(*) from public.feedback_reports where status = 'open'),
    'waitlist', (select count(*) from public.supporter_waitlist))
  from public.supporter_cohorts c where (auth.uid() is null or public.is_admin()) order by c.id desc limit 1 $function$;

-- sync_last_seen()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.sync_last_seen()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n int;
begin
  with s as (
    select user_id, max(greatest(coalesce(refreshed_at at time zone 'UTC', 'epoch'::timestamptz), coalesce(updated_at, 'epoch'::timestamptz), coalesce(created_at, 'epoch'::timestamptz))) as t
    from auth.sessions group by user_id)
  update public.profiles p set last_seen_at = least(s.t, now())
    from s where p.id = s.user_id and s.t > 'epoch'::timestamptz and (p.last_seen_at is null or p.last_seen_at < s.t - interval '10 minutes');
  get diagnostics n = row_count;
  return n;
end $function$;

-- tag_info(p_tag text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.tag_info(p_tag text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with ps as (select p.id, p.tags, p.created_at from public.posts p where p.parent_id is null and not coalesce(p.hidden,false) and p.tags @> array[lower(p_tag)])
  select jsonb_build_object('tag', lower(p_tag), 'n', (select count(*) from ps), 'week', (select count(*) from ps where created_at > now() - interval '7 days'),
    'related', coalesce((select jsonb_agg(t order by n desc, t) from (select t, count(*) n from ps, unnest(ps.tags) t where t <> lower(p_tag) and not exists (select 1 from public.tag_hidden h where h.tag = t) group by t order by count(*) desc, t limit 5) r), '[]'::jsonb));
$function$;

-- tag_popular(p_limit integer)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.tag_popular(p_limit integer DEFAULT 8)
 RETURNS TABLE(tag text, n bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select t, count(*) from public.posts p, unnest(public.post_tags(p.body)) t
  where p.parent_id is null and not coalesce(p.hidden,false) and p.created_at > now() - interval '60 days' and cardinality(p.tags) > 0
    and not exists (select 1 from public.tag_hidden h where h.tag = t)
  group by t having count(*) >= 2 order by count(*) desc, t limit greatest(1, least(coalesce(p_limit,8), 20));
$function$;

-- tag_suggest(p_q text, p_limit integer)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.tag_suggest(p_q text, p_limit integer DEFAULT 6)
 RETURNS TABLE(tag text, n bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select t, count(*) from public.posts p, unnest(p.tags) t
  where p.parent_id is null and not coalesce(p.hidden,false) and t like lower(regexp_replace(coalesce(p_q,''), '[^가-힣A-Za-z0-9_]', '', 'g')) || '%'
    and not exists (select 1 from public.tag_hidden h where h.tag = t)
  group by t order by count(*) desc, t limit greatest(1, least(coalesce(p_limit,6), 10));
$function$;

-- unregister_device_token(p_token text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.unregister_device_token(p_token text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  delete from public.device_tokens where token = lower(p_token) and profile_id = auth.uid();
$function$;

-- work_set_tech_photos(p_post uuid, p_items jsonb)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.work_set_tech_photos(p_post uuid, p_items jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare w record; it jsonb; ts text[]; outj jsonb := '[]'::jsonb; n int := 0;
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  select wk.id, wk.techniques, coalesce(po.photos, wk.photos) as photos into w
    from public.posts po join public.works wk on wk.id = po.work_id
   where po.id = p_post and wk.profile_id = auth.uid();
  if not found then raise exception '내 완성작품 인증이 아니에요'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then raise exception '형식이 맞지 않아요'; end if;
  for it in select * from jsonb_array_elements(p_items) loop
    exit when n >= 3;
    continue when not ((it->>'photo') = any(w.photos));          -- 이 인증에 올린 사진만
    select coalesce(array_agg(distinct x), '{}') into ts from jsonb_array_elements_text(coalesce(it->'techniques','[]'::jsonb)) x where x = any(w.techniques);   -- 이 인증의 기법만
    continue when cardinality(ts) = 0;
    outj := outj || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('photo', it->>'photo', 'techniques', to_jsonb(ts), 'memo', nullif(left(btrim(coalesce(it->>'memo','')), 80), ''))));
    n := n + 1;
  end loop;
  update public.works set tech_photos = case when n > 0 then outj else null end where id = w.id;
  return n;
end $function$;

-- works_apply_cert()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.works_apply_cert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pid uuid := coalesce(new.profile_id, old.profile_id); v_ver text[]; v_cnt integer; v_lv integer;
begin
  select coalesce(array_agg(distinct t), '{}'), count(distinct w.id) into v_ver, v_cnt
    from public.works w left join lateral unnest(w.techniques) t on true where w.profile_id = pid;
  select count(distinct (w.created_at at time zone 'Asia/Seoul')::date) into v_lv from public.works w where w.profile_id = pid;
  v_ver := array(select x from unnest(v_ver) x where x is not null);
  update public.profiles p set verified_skills = v_ver, cert_count = v_cnt, act_level = v_lv,
    skills = (select array(select distinct s from unnest(p.skills || public.expand_prereqs(v_ver)) s))
    where p.id = pid;
  return null;
end $function$;

-- works_stash_restore()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.works_stash_restore()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin perform public.stash_restore(old.id); return old; end $function$;

-- yarn_add_alias(p_catalog uuid, p_alias text)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.yarn_add_alias(p_catalog uuid, p_alias text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare a text := left(btrim(coalesce(p_alias,'')), 60); k text; c public.yarn_catalog;
begin
  if a = '' then return; end if;
  select * into c from public.yarn_catalog where id = p_catalog; if c.id is null then return; end if;
  k := public.yarn_norm(a); if k is null or length(k) < 2 then return; end if;
  update public.yarn_catalog set
    aliases = case when not (a = any(coalesce(aliases,'{}'))) and cardinality(coalesce(aliases,'{}')) < 40 then coalesce(aliases,'{}') || a else aliases end,
    norm_keys = (select array_agg(distinct x) from unnest(coalesce(norm_keys,'{}') || array[k, public.yarn_norm(coalesce(c.brand,'')||a)]) x where x is not null),
    updated_at = now()
  where id = p_catalog;
end $function$;

-- yarn_auto_merge(p_from uuid, p_into uuid, p_reason text)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.yarn_auto_merge(p_from uuid, p_into uuid, p_reason text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare f public.yarn_catalog; t public.yarn_catalog;
begin
  if p_from = p_into then return false; end if;
  select * into f from public.yarn_catalog where id = p_from and merged_into is null and status = 'auto' for update;
  select * into t from public.yarn_catalog where id = p_into and merged_into is null and status = 'verified' for update;
  if f.id is null or t.id is null then return false; end if;
  -- 안전 조건을 함수 안에서도 다시 확인: 브랜드가 같고(둘 다 있음), 1볼 무게가 둘 다 있으며 10% 안, 길이는 둘 다 있을 때 10% 안
  -- 회원이 적어 생긴 후보는 brand 가 비고 이름 안에 브랜드가 들어 있다("올림푸스 금표40수 …") → 이름이 그 브랜드(또는 별칭)로 시작하면 같은 브랜드로 본다
  if t.brand is null then return false; end if;
  if f.brand is not null then
    if public.yarn_norm(f.brand) is distinct from public.yarn_norm(t.brand) then return false; end if;
  elsif not (public.yarn_norm(f.product) like public.yarn_norm(t.brand) || '%'
        or exists (select 1 from public.yarn_brand_aliases ba where ba.brand = t.brand and public.yarn_norm(f.product) like public.yarn_norm(ba.alias) || '%')) then return false;
  end if;
  if f.ball_g is null or t.ball_g is null or abs(f.ball_g - t.ball_g) > t.ball_g * 0.1 then return false; end if;
  if f.ball_m is not null and t.ball_m is not null and abs(f.ball_m - t.ball_m) > t.ball_m * 0.1 then return false; end if;
  update public.yarn_entries set catalog_id = p_into where catalog_id = p_from;
  update public.yarn_stash set catalog_id = p_into where catalog_id = p_from;
  update public.yarn_sellers s set catalog_id = p_into where catalog_id = p_from and not exists (select 1 from public.yarn_sellers x where x.catalog_id = p_into and x.shop = s.shop);
  delete from public.yarn_sellers where catalog_id = p_from;
  insert into public.yarn_colors(catalog_id, no, name, photo, color_hex, color_mode) select p_into, no, name, photo, color_hex, color_mode from public.yarn_colors where catalog_id = p_from on conflict do nothing;
  delete from public.yarn_colors where catalog_id = p_from;
  update public.yarn_catalog x set aliases = array(select distinct a from unnest(x.aliases || f.aliases) a), norm_keys = array(select distinct a from unnest(x.norm_keys || f.norm_keys) a), uses = x.uses + f.uses, updated_at = now() where x.id = p_into;
  update public.yarn_catalog set merged_into = p_into, updated_at = now() where id = p_from;
  insert into public.admin_logs(admin_id, action, target_type, target_id, detail) values ('e120eb67-b254-4008-92d8-08c95c821e9e', 'yarn_merge', 'yarn', p_from::text, jsonb_build_object('into', p_into, 'auto', true, 'reason', p_reason));
  return true;
end $function$;

-- yarn_brand_of(p text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.yarn_brand_of(p text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select coalesce(
    (select brand from public.yarn_catalog where merged_into is null and brand is not null and public.yarn_norm(brand) = public.yarn_norm(p) limit 1),
    (select brand from public.yarn_brand_aliases where public.yarn_norm(alias) = public.yarn_norm(p) limit 1),
    (select brand from public.yarn_brand_aliases where public.yarn_norm(p) like public.yarn_norm(alias)||'%' and length(public.yarn_norm(alias)) >= 4 order by length(alias) desc limit 1));
$function$;

-- yarn_brands()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.yarn_brands()
 RETURNS TABLE(brand text, n integer, aliases text[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select c.brand, count(*)::int,
         coalesce((select array_agg(a.alias order by a.alias) from public.yarn_brand_aliases a where a.brand = c.brand), '{}'::text[])
  from public.yarn_catalog c
  where c.status = 'verified' and c.merged_into is null and coalesce(btrim(c.brand), '') <> ''
  group by c.brand
  order by 2 desc, 1;
$function$;

-- yarn_catalog_import(p jsonb)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.yarn_catalog_import(p jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare y jsonb; cid uuid; k text; al text[]; n int := 0; c text; per numeric;
begin
  if auth.uid() is not null and not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  for y in select * from jsonb_array_elements(p) loop
    k := public.yarn_norm(coalesce(y->>'b','') || (y->>'p'));
    if k is null or exists (select 1 from public.yarn_catalog t where t.norm_keys @> array[k]) then continue; end if;
    al := array(select distinct left(btrim(x),60) from unnest(array[y->>'p', y->>'e', nullif(coalesce(y->>'b','')||' '||(y->>'p'), ' '||(y->>'p'))] || array(select jsonb_array_elements_text(coalesce(y->'a','[]'::jsonb)))) x where x is not null and btrim(x) <> '');
    per := case when (y->>'g')::numeric > 0 and (y->>'m')::numeric > 0 then (y->>'m')::numeric / (y->>'g')::numeric * 100 end;
    insert into public.yarn_catalog(brand, product, product_en, aliases, norm_keys, ball_g, ball_m, weight_class, fiber_main, fibers, status, shop, source_url, season, needle_knit, needle_crochet, gauge, put_up)
    values (nullif(y->>'b',''), left(y->>'p',60), y->>'e', al, array(select distinct public.yarn_norm(a) from unnest(al) a where public.yarn_norm(a) is not null),
      (y->>'g')::numeric, (y->>'m')::numeric,
      case when per is null then null when per >= 600 then '레이스·극세' when per >= 350 then '합세(Fingering)' when per >= 250 then '중세(Sport)' when per >= 200 then '합태(DK)' when per >= 120 then '병태(Worsted)' when per >= 60 then '극태(Bulky)' else '초극태' end,
      y->>'fm', case when jsonb_typeof(y->'f')='object' then y->'f' end, 'verified', y->>'s', y->>'u', y->>'se', y->>'nk', y->>'nc', left(y->>'ga',60), y->>'pu')
    returning id into cid;
    for c in select jsonb_array_elements_text(coalesce(y->'c','[]'::jsonb)) loop
      insert into public.yarn_colors(catalog_id, no, name) values (cid, nullif(split_part(c,'|',1),''), left(split_part(c,'|',2),40)) on conflict do nothing;
    end loop;
    n := n + 1;
  end loop;
  return n;
end $function$;

-- yarn_catalog_name(p_id uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.yarn_catalog_name(p_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select btrim(coalesce(c.brand||' ','')||c.product) from public.yarn_catalog c where auth.uid() is not null and c.id = p_id $function$;

-- yarn_colors_of(p_catalog uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.yarn_colors_of(p_catalog uuid)
 RETURNS TABLE(no text, name text, family text, photo text, color_hex text[], color_mode text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select c.no, c.name, c.family, c.photo, c.color_hex::text[], c.color_mode from public.yarn_colors c
  where auth.uid() is not null and c.catalog_id = p_catalog order by c.id limit 200 $function$;

-- yarn_colors_set_family()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.yarn_colors_set_family()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin if new.family is null then new.family := public.color_family(new.name); end if; return new; end $function$;

-- yarn_entries_set_family()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.yarn_entries_set_family()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  new.color_hex := public.color_hex_clean(new.color_hex);
  new.color_families := public.color_families_clean(new.color_families);
  if new.color_hex is null then new.color_mode := null; end if;
  new.color_family := coalesce(new.color_families[1], public.color_family(new.color));
  return new;
end $function$;

-- yarn_fiber_combo(f jsonb, fallback text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.yarn_fiber_combo(f jsonb, fallback text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select coalesce(
    case when jsonb_typeof(f)='object' then
      (select string_agg(s.k, '+' order by s.v desc, s.k) from (select key k, value::numeric v from jsonb_each_text(f) where value ~ '^[0-9]+(\.[0-9]+)?$' and value::numeric >= 5) s)
    end, nullif(btrim(fallback),''), '(소재 미상)');
$function$;

-- yarn_fiber_norm(f jsonb)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.yarn_fiber_norm(f jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select case when jsonb_typeof(f) <> 'object' then f else coalesce((
    select jsonb_object_agg(k, v) from (
      select case
        when k0 ~ '(울|wool|메리노|merino|램스|lamb|양모|알파카|alpaca)' and k0 !~ '(알파카|alpaca)' then '울'
        when k0 ~ '(알파카|alpaca)' then '알파카'
        when k0 ~ '(면|cotton|코튼)' then '면'
        when k0 ~ '(아크릴|acryl)' then '아크릴'
        when k0 ~ '(나일론|nylon|폴리아미드|polyamide)' then '나일론'
        when k0 ~ '(폴리|polyester|poly)' then '폴리에스터'
        when k0 ~ '(모헤어|mohair)' then '모헤어'
        when k0 ~ '(실크|silk|견)' then '실크'
        when k0 ~ '(린넨|linen|마)' then '린넨'
        when k0 ~ '(레이온|rayon|viscose|비스코스|인견|모달|modal|텐셀|tencel)' then '레이온'
        when k0 ~ '(캐시미어|cashmere)' then '캐시미어'
        when k0 ~ '(앙고라|angora)' then '앙고라'
        when k0 ~ '(대나무|bamboo|밤부)' then '대나무'
        when k0 ~ '(종이|paper|페이퍼|한지)' then '종이'
        when k0 ~ '(메탈|metal|루렉스|lurex)' then '메탈릭'
        else k0 end k, sum(v) v
      from (select lower(regexp_replace(key,'[\s()（）\-_/]','','g')) k0, case when value ~ '^[0-9]+(\.[0-9]+)?$' then value::numeric else 0 end v from jsonb_each_text(f)) s group by 1) t), '{}'::jsonb) end;
$function$;

-- yarn_gauge_search(p_q text, p_craft text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.yarn_gauge_search(p_q text, p_craft text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(x), '[]'::jsonb) from (
    select jsonb_build_object('id', c.id, 'name', btrim(coalesce(c.brand||' ','')||c.product)) || (case when p_craft = 'knitting' then c.gauge_knit else c.gauge_crochet end) x
    from public.yarn_catalog c
    where auth.uid() is not null and c.merged_into is null and public.yarn_norm(p_q) is not null
      and (case when p_craft = 'knitting' then c.gauge_knit else c.gauge_crochet end) is not null
      and exists (select 1 from unnest(c.norm_keys || public.yarn_norm(coalesce(c.brand,'')||c.product) || public.yarn_norm(coalesce(c.brand,'')||coalesce(c.product_en,''))
          || coalesce((select array_agg(public.yarn_norm(a.alias||c.product)) from public.yarn_brand_aliases a where a.brand = c.brand), '{}')) kk where kk like '%'||public.yarn_norm(p_q)||'%')
    order by (c.status='verified') desc, c.uses desc, c.id limit 8) t;
$function$;

-- yarn_guess(p_name text, p_ball_g numeric, p_ball_m numeric, p_color_no text, p_limit integer)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.yarn_guess(p_name text, p_ball_g numeric DEFAULT NULL::numeric, p_ball_m numeric DEFAULT NULL::numeric, p_color_no text DEFAULT NULL::text, p_limit integer DEFAULT 3)
 RETURNS TABLE(id uuid, name text, ball_g numeric, ball_m numeric, weight text, fiber text, fibers jsonb, uses integer, verified boolean, score numeric, photo text, color_hex text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with q as (select public.yarn_norm(p_name) n, nullif(regexp_replace(coalesce(p_color_no,''), '[^0-9A-Za-z]', '', 'g'), '') cn),
  c as (
    select c.*, greatest(public._bigram_dice(q.n, public.yarn_norm(coalesce(c.brand,'')||c.product)), public._bigram_dice(q.n, public.yarn_norm(c.product)),
        coalesce((select max(public._bigram_dice(q.n, k)) from unnest(c.norm_keys) k), 0)) s, q.n qn, q.cn
    from public.yarn_catalog c, q
    where auth.uid() is not null and q.n is not null and length(q.n) >= 3 and c.status = 'verified' and c.merged_into is null
  ), r as (
    select c.*, c.s
      + case when p_ball_g is not null and c.ball_g is not null and abs(c.ball_g - p_ball_g) <= c.ball_g * 0.1 then 0.08 else 0 end
      + case when p_ball_m is not null and c.ball_m is not null and abs(c.ball_m - p_ball_m) <= c.ball_m * 0.1 then 0.08 else 0 end
      + case when c.cn is not null and exists (select 1 from public.yarn_colors yc where yc.catalog_id = c.id and regexp_replace(coalesce(yc.no,''), '[^0-9A-Za-z]', '', 'g') = c.cn) then 0.1 else 0 end as sc
    from c where c.s >= 0.45 and not (c.qn = any(c.norm_keys))
  )
  select r.id, btrim(coalesce(r.brand||' ','')||r.product), r.ball_g, r.ball_m, r.weight_class, r.fiber_main, r.fibers, r.uses, true, round(r.sc, 2),
    (select yc.photo from public.yarn_colors yc where yc.catalog_id = r.id and yc.photo is not null order by yc.id limit 1),
    (select yc.color_hex[1] from public.yarn_colors yc where yc.catalog_id = r.id and yc.color_hex is not null order by yc.id limit 1)
  from r order by r.sc desc, r.uses desc limit greatest(1, least(coalesce(p_limit,3), 5));
$function$;

-- yarn_guess_confirm(p_name text, p_catalog uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.yarn_guess_confirm(p_name text, p_catalog uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_norm text := public.yarn_norm(p_name); v_raw text := left(btrim(coalesce(p_name,'')), 60); n int;
begin
  if auth.uid() is null or v_norm is null or length(v_norm) < 3 then return false; end if;
  if p_catalog is not null and not exists (select 1 from public.yarn_catalog where id = p_catalog and status = 'verified' and merged_into is null) then return false; end if;
  if (select count(*) from public.yarn_guess_log where profile_id = auth.uid() and created_at > now() - interval '1 day') >= 40 then return false; end if;
  insert into public.yarn_guess_log(norm_name, raw_name, catalog_id, picked, profile_id) values (v_norm, v_raw, p_catalog, p_catalog is not null, auth.uid());
  if p_catalog is null then return true; end if;
  select count(distinct profile_id) into n from public.yarn_guess_log where norm_name = v_norm and catalog_id = p_catalog and picked;
  if n >= 2 then
    update public.yarn_catalog set norm_keys = array(select distinct k from unnest(norm_keys || v_norm) k), aliases = array(select distinct a from unnest(aliases || v_raw) a), updated_at = now()
      where id = p_catalog and not (v_norm = any(norm_keys));
  end if;
  return true;
end $function$;

-- yarn_log_entry(p_work uuid, y jsonb, p_needles jsonb, p_gauge text, p_tech text[], p_item text, p_level smallint)  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.yarn_log_entry(p_work uuid, y jsonb, p_needles jsonb, p_gauge text, p_tech text[], p_item text, p_level smallint)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare k text := public.yarn_norm(y->>'name'); cid uuid; craft text; hx text[]; fams text[]; v_fam text;
begin
  if k is null then return null; end if;
  select c.id into cid from public.yarn_catalog c where c.norm_keys @> array[k] order by (c.merged_into is null) desc, c.status desc, c.uses desc limit 1;
  if cid is not null then select coalesce(c.merged_into, c.id) into cid from public.yarn_catalog c where c.id = cid; end if;
  if cid is null then
    cid := public.yarn_match_spec_one(nullif(y->>'brand',''), nullif(y->>'ball_g','')::numeric, nullif(y->>'ball_m','')::numeric, case when jsonb_typeof(y->'fibers')='object' then y->'fibers' end, nullif(y->>'color_no',''));
    if cid is not null then perform public.yarn_add_alias(cid, y->>'name'); end if;
  end if;
  if cid is null then
    insert into public.yarn_catalog(product, aliases, norm_keys) values (left(btrim(y->>'name'),60), array[left(btrim(y->>'name'),60)], array[k]) returning id into cid;
  end if;
  select case when bool_or(t.craft='crochet') and not bool_or(t.craft='knitting') then 'crochet' when bool_or(t.craft='knitting') and not bool_or(t.craft='crochet') then 'knitting' else 'both' end
    into craft from public.techniques t where t.id = any(coalesce(p_tech,'{}'));
  if jsonb_typeof(y->'color_hex')='array' then select array_agg(e) into hx from jsonb_array_elements_text(y->'color_hex') e; end if;
  if jsonb_typeof(y->'color_families')='array' then select array_agg(e) into fams from jsonb_array_elements_text(y->'color_families') e; end if;
  insert into public.yarn_entries(catalog_id, work_id, raw_name, norm_name, color, amount, unit, ball_g, ball_m, weight, fiber, fibers, rating, rating_reason, needles, gauge, techniques, craft, item_type, maker_level, color_hex, color_mode, color_families)
  values (cid, p_work, left(btrim(y->>'name'),60), k, y->>'color', (y->>'amount')::numeric, y->>'unit', (y->>'ball_g')::numeric, (y->>'ball_m')::numeric, y->>'weight', y->>'fiber',
          case when jsonb_typeof(y->'fibers')='object' then y->'fibers' end, (y->>'rating')::smallint, y->>'rating_reason', coalesce(p_needles,'[]'), p_gauge, coalesce(p_tech,'{}'), craft, p_item, p_level,
          hx, case when y->>'color_mode' in ('solid','gradient','mix','melange') then y->>'color_mode' end, fams);
  update public.yarn_catalog c set uses = c.uses + 1, updated_at = now(),
      aliases = case when not (left(btrim(y->>'name'),60) = any(c.aliases)) and cardinality(c.aliases) < 30 then c.aliases || left(btrim(y->>'name'),60) else c.aliases end,
      ball_g = case when c.status='auto' then coalesce((select mode() within group (order by e.ball_g) from public.yarn_entries e where e.catalog_id=c.id and e.ball_g is not null), c.ball_g) else c.ball_g end,
      ball_m = case when c.status='auto' then coalesce((select mode() within group (order by e.ball_m) from public.yarn_entries e where e.catalog_id=c.id and e.ball_m is not null), c.ball_m) else c.ball_m end,
      weight_class = case when c.status='auto' then coalesce((select mode() within group (order by e.weight) from public.yarn_entries e where e.catalog_id=c.id and e.weight is not null), c.weight_class) else c.weight_class end,
      fiber_main = case when c.status='auto' then coalesce((select mode() within group (order by e.fiber) from public.yarn_entries e where e.catalog_id=c.id and e.fiber is not null), c.fiber_main) else c.fiber_main end,
      fibers = case when c.status='auto' and c.fibers is null and jsonb_typeof(y->'fibers')='object' then y->'fibers' else c.fibers end
    where c.id = cid;
  return cid;
end $function$;

-- yarn_match_spec(p_brand text, p_g numeric, p_m numeric, p_fibers jsonb, p_color text, p_limit integer)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.yarn_match_spec(p_brand text, p_g numeric, p_m numeric, p_fibers jsonb, p_color text, p_limit integer DEFAULT 3)
 RETURNS TABLE(id uuid, name text, score integer)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with b as (select public.yarn_brand_of(p_brand) brand), pf as (select public.yarn_fiber_norm(p_fibers) f),
  c as (
    select t.id, coalesce(t.brand||' ','')||t.product name, public.yarn_fiber_norm(t.fibers) tf,
      case when (select brand from b) is not null and t.brand = (select brand from b) then 30 else 0 end s_brand,
      case when p_g is null or t.ball_g is null then 0 when abs(t.ball_g - p_g) <= greatest(p_g*0.1, 2) then 25 else -100 end s_g,
      case when p_m is null or t.ball_m is null then 0 when abs(t.ball_m - p_m) <= greatest(p_m*0.12, 5) then 25 else -100 end s_m,
      case when nullif(btrim(p_color),'') is not null and exists (select 1 from public.yarn_colors yc where yc.catalog_id = t.id and yc.no = btrim(p_color)) then 15 else 0 end s_col
    from public.yarn_catalog t where t.merged_into is null and t.status = 'verified'
      and ((select brand from b) is null or t.brand = (select brand from b))
  ), c2 as (
    select c.*, case when jsonb_typeof((select f from pf)) <> 'object' or (select f from pf) = '{}' or c.tf is null or c.tf = '{}' then 0
        when (select count(*) from jsonb_object_keys((select f from pf))) = (select count(*) from jsonb_object_keys(c.tf))
             and not exists (select 1 from jsonb_each_text((select f from pf)) x where not (c.tf ? x.key) or abs((c.tf->>x.key)::numeric - x.value::numeric) > 15) then 20
        when exists (select 1 from jsonb_each_text((select f from pf)) x where c.tf ? x.key) then 5 else -100 end s_fib from c
  )
  select id, name, (s_brand+s_g+s_m+s_fib+s_col)::int from c2
  where s_g >= 0 and s_m >= 0 and s_fib >= 0 and (s_g + s_m + s_fib + s_col) >= 25
  order by 3 desc, name limit p_limit;
$function$;

-- yarn_match_spec_one(p_brand text, p_g numeric, p_m numeric, p_fibers jsonb, p_color text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.yarn_match_spec_one(p_brand text, p_g numeric, p_m numeric, p_fibers jsonb, p_color text)
 RETURNS uuid
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with r as (select * from public.yarn_match_spec(p_brand, p_g, p_m, p_fibers, p_color, 2) order by score desc)
  select (array_agg(r.id order by r.score desc))[1] from r
  having max(r.score) >= case when public.yarn_brand_of(p_brand) is not null then 70 else 85 end
     and (count(*) = 1 or max(r.score) - min(r.score) >= 15);
$function$;

-- yarn_norm(p text)  acl: {=X/postgres,postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.yarn_norm(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select nullif(regexp_replace(regexp_replace(lower(coalesce(p,'')), '([0-9]+\s*(g|그램|볼))', '', 'g'), '[^0-9a-z가-힣ぁ-んァ-ヶ一-龥]', '', 'g'), '');
$function$;

-- yarn_parse_gauge(p text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.yarn_parse_gauge(p text)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
declare out jsonb := '{}'; pat constant text := '([0-9]+(?:\.[0-9]+)?)(?:\s*[~-]\s*[0-9]+(?:\.[0-9]+)?)?\s*코\s*[x×X*]?\s*([0-9]+(?:\.[0-9]+)?)(?:\s*[~-]\s*[0-9]+(?:\.[0-9]+)?)?\s*단';
  parts text[]; ms text[][]; i int; seg text; prefix text; tail text; m text[]; needle text; craft text; stitch text; nd text[];
begin
  if p is null or btrim(p) = '' then return null; end if;
  parts := regexp_split_to_array(p, pat);
  select array_agg(x) into ms from regexp_matches(p, pat, 'g') x;
  if ms is null then return null; end if;
  for i in 1..array_length(ms,1) loop
    m := array[ms[i][1], ms[i][2]];
    prefix := parts[i]; if i > 1 then prefix := regexp_replace(prefix, '^\s*\([^)]*\)?', ''); end if;
    nd := regexp_match(coalesce(parts[i+1],''), '^\s*(\([^)]*\)?)'); tail := coalesce(nd[1], '');
    seg := prefix || ' ' || tail;
    nd := regexp_match(seg, '([0-9]+(?:\.[0-9]+)?(?:\s*[~-]\s*[0-9]+(?:\.[0-9]+)?)?\s*mm)'); needle := nd[1];
    if needle is null then nd := regexp_match(seg, '([0-9]+/0호?(?:\s*[~-]\s*[0-9]+/0호?)?)'); needle := nd[1]; if needle is not null and needle !~ '호' then needle := needle || '호'; end if; end if;
    if needle is null then nd := regexp_match(seg, '(레이스\s*[0-9]+호)'); needle := nd[1]; end if;
    if needle is null then nd := regexp_match(seg, '코바늘\s*([0-9]+호)'); needle := nd[1]; end if;
    if needle is not null then needle := regexp_replace(regexp_replace(needle, '\s+', '', 'g'), '^레이스', '레이스 '); end if;
    stitch := case when seg ~ '메리야스' then '메리야스' when seg ~ '한길\s*긴뜨기|한길긴' then '한길긴뜨기' when seg ~ '긴뜨기' then '긴뜨기' when seg ~ '짧은뜨기' then '짧은뜨기' when seg ~ '고무' then '고무뜨기' when seg ~ '무늬' then '무늬' else null end;
    craft := case when seg ~ '코바늘' or needle ~ '/0|레이스' or stitch in ('한길긴뜨기','긴뜨기','짧은뜨기') then 'crochet' else 'knit' end;
    if craft = 'crochet' and stitch = '메리야스' then stitch := null; end if;
    if not (out ? ('gauge_'||craft)) then
      out := out || jsonb_build_object('gauge_'||craft, jsonb_strip_nulls(jsonb_build_object('needle', needle, 'sts', m[1]::numeric, 'rows', m[2]::numeric, 'stitch', coalesce(stitch, case when craft='knit' then '메리야스' else '한길긴뜨기' end), 'size', '10x10')));
    end if;
  end loop;
  return nullif(out, '{}');
end $function$;

-- yarn_popular()  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.yarn_popular()
 RETURNS TABLE(id uuid, name text, ball_g numeric, ball_m numeric, weight text, fiber text, fibers jsonb, uses integer, verified boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select c.id, btrim(coalesce(c.brand||' ','')||c.product), c.ball_g, c.ball_m, c.weight_class, c.fiber_main, c.fibers, c.uses, c.status = 'verified'
  from public.yarn_catalog c where auth.uid() is not null and c.merged_into is null and c.uses > 0 order by c.uses desc limit 12 $function$;

-- yarn_similar(p_catalog uuid, p_name text, p_limit integer)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.yarn_similar(p_catalog uuid DEFAULT NULL::uuid, p_name text DEFAULT NULL::text, p_limit integer DEFAULT 8)
 RETURNS TABLE(id uuid, name text, ball_g numeric, ball_m numeric, m_per_100g numeric, weight text, fiber text, uses integer, liked integer, disliked integer, diff_pct numeric, same_fiber boolean, texture text, use_tags text[], shared_uses text[], fiber_sim numeric, score numeric, verdict text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with base as (
    select c.* from public.yarn_catalog c
    where auth.uid() is not null and c.merged_into is null
      and (c.id = p_catalog or (p_catalog is null and c.norm_keys @> array[public.yarn_norm(p_name)]))
    order by c.uses desc limit 1),
  cand as (
    select c.id, btrim(coalesce(c.brand||' ','')||c.product) as nm, c.ball_g, c.ball_m, c.m_per_100g, c.weight_class, c.fiber_main, c.uses, c.texture, c.use_tags,
      (c.fiber_main is not distinct from b.fiber_main) as samef,
      array(select u from unnest(c.use_tags) u where u = any(b.use_tags)) as shared, cardinality(b.use_tags) as b_n,
      case when c.fibers is not null and b.fibers is not null
           then (select coalesce(sum(least((c.fibers->>k)::numeric, (b.fibers->>k)::numeric)),0) / 100 from jsonb_object_keys(c.fibers) k where b.fibers ? k)
           when c.fiber_main is not distinct from b.fiber_main then 0.8 else 0.2 end as fsim,
      case when c.m_per_100g is not null and b.m_per_100g is not null then round(abs(c.m_per_100g - b.m_per_100g) / b.m_per_100g * 100, 1) end as dpct
    from base b join public.yarn_catalog c on c.id <> b.id and c.merged_into is null
     and c.texture is not distinct from b.texture
     and c.use_tags && b.use_tags),
  scored as (
    select k.*, (k.fsim * 0.5 + (cardinality(k.shared)::numeric / greatest(k.b_n,1)) * 0.2 + (1 - least(coalesce(k.dpct, 25), 30) / 30) * 0.3) as sc
    from cand k where k.dpct is null or k.dpct <= 30)
  select s.id, s.nm, s.ball_g, s.ball_m, s.m_per_100g, s.weight_class, s.fiber_main, s.uses,
         (select count(*)::int from public.yarn_entries e where e.catalog_id=s.id and e.rating=1),
         (select count(*)::int from public.yarn_entries e where e.catalog_id=s.id and e.rating=-1),
         s.dpct, s.samef, s.texture, s.use_tags, s.shared, round(s.fsim, 2), round(s.sc, 3),
         case when s.fsim >= 0.7 and coalesce(s.dpct, 99) <= 10 then '거의 같은 느낌'
              when s.fsim >= 0.5 and coalesce(s.dpct, 99) <= 20 then '비슷한 느낌'
              when s.dpct is null then '재질은 맞아요 · 굵기 확인 필요'
              when s.fsim < 0.5 then '용도는 같지만 소재가 달라요'
              else '재질은 맞아요 · 굵기가 달라요' end
  from scored s order by s.sc desc limit least(greatest(p_limit,1), 20);
$function$;

-- yarn_spec(p_id uuid)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.yarn_spec(p_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_strip_nulls(jsonb_build_object('needle_knit', needle_knit, 'needle_crochet', needle_crochet, 'gauge_knit', gauge_knit, 'gauge_crochet', gauge_crochet, 'gauge', gauge, 'season', season, 'texture', texture, 'use_tags', to_jsonb(use_tags)))
  from public.yarn_catalog where id = p_id and merged_into is null;
$function$;

-- yarn_stash_fill()  acl: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.yarn_stash_fill()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  new.color_hex := public.color_hex_clean(new.color_hex);
  new.color_families := public.color_families_clean(new.color_families);
  if new.color_hex is null then new.color_mode := null; end if;
  new.color_family := coalesce(new.color_families[1], case when new.color is not null then public.color_family(new.color) end);
  if new.left_balls <= 0 then new.finished_at := coalesce(new.finished_at, now()); else new.finished_at := null; end if;
  if tg_op = 'INSERT' and (select count(*) from public.yarn_stash s where s.owner_id = new.owner_id) >= 500 then raise exception '내 실함은 500개까지 담을 수 있어요'; end if;
  return new;
end $function$;

-- yarn_suggest(p_q text)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.yarn_suggest(p_q text)
 RETURNS TABLE(id uuid, name text, ball_g numeric, ball_m numeric, weight text, fiber text, fibers jsonb, uses integer, verified boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with q as (select public.yarn_norm(p_q) as n)
  select c.id, btrim(coalesce(c.brand||' ','')||c.product), c.ball_g, c.ball_m, c.weight_class, c.fiber_main, c.fibers, c.uses, c.status='verified'
  from public.yarn_catalog c, q
  where auth.uid() is not null and c.merged_into is null and q.n is not null
    and exists (
      select 1 from unnest(
        c.norm_keys
        || public.yarn_norm(coalesce(c.brand,'')||c.product)
        || public.yarn_norm(coalesce(c.brand,'')||coalesce(c.product_en,''))
        || coalesce((select array_agg(public.yarn_norm(a.alias||c.product)) || array_agg(public.yarn_norm(a.alias||coalesce(c.product_en,'')))
                     from public.yarn_brand_aliases a where a.brand = c.brand), '{}')
      ) k where k like '%'||q.n||'%')
  order by (public.yarn_norm(c.brand) like '%'||q.n||'%' or public.yarn_norm(coalesce(c.brand,'')||c.product) like q.n||'%'
            or exists (select 1 from public.yarn_brand_aliases a where a.brand = c.brand and public.yarn_norm(a.alias) like '%'||q.n||'%')) desc,
           (c.status='verified') desc, c.uses desc limit 8;
$function$;

-- yarn_suggest_page(p_q text, p_offset integer)  acl: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.yarn_suggest_page(p_q text, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, name text, ball_g numeric, ball_m numeric, weight text, fiber text, fibers jsonb, uses integer, verified boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with q as (select public.yarn_norm(p_q) as n)
  select c.id, btrim(coalesce(c.brand||' ','')||c.product), c.ball_g, c.ball_m, c.weight_class, c.fiber_main, c.fibers, c.uses, c.status='verified'
  from public.yarn_catalog c, q
  where auth.uid() is not null and c.merged_into is null and q.n is not null
    and exists (
      select 1 from unnest(
        c.norm_keys
        || public.yarn_norm(coalesce(c.brand,'')||c.product)
        || public.yarn_norm(coalesce(c.brand,'')||coalesce(c.product_en,''))
        || coalesce((select array_agg(public.yarn_norm(a.alias||c.product)) || array_agg(public.yarn_norm(a.alias||coalesce(c.product_en,'')))
                     from public.yarn_brand_aliases a where a.brand = c.brand), '{}')
      ) k where k like '%'||q.n||'%')
  order by (public.yarn_norm(c.brand) like '%'||q.n||'%' or public.yarn_norm(coalesce(c.brand,'')||c.product) like q.n||'%'
            or exists (select 1 from public.yarn_brand_aliases a where a.brand = c.brand and public.yarn_norm(a.alias) like '%'||q.n||'%')) desc,
           (c.status='verified') desc, c.uses desc, c.brand, c.product, c.id
  offset greatest(coalesce(p_offset,0),0) limit 9
$function$;
