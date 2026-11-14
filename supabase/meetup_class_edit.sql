-- schema 111 (2026-11-14) 모임 수정 · 클래스 수정 알림
-- 대표 확정: 참가비·수강료는 신청자가 있어도 바꿀 수 있다. 일시·장소·비용이 바뀌면 참여자·신청자에게 앱이 자동으로 알린다(🔔+푸시).
create or replace function public.meetup_edit(p_meetup uuid, p_title text, p_place text, p_starts_at timestamptz, p_is_public boolean,
  p_body text default null, p_lat double precision default null, p_lng double precision default null, p_photos text[] default null, p_extra jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $$
declare uid uuid := auth.uid(); m public.meetups; po public.posts; x jsonb := coalesce(p_extra,'{}'::jsonb);
  v_title text := left(btrim(coalesce(p_title,'')),60); v_place text := left(btrim(coalesce(p_place,'')),80); v_body text := nullif(left(btrim(coalesce(p_body,'')),300),'');
  v_bring text := nullif(left(btrim(coalesce(x->>'bring','')),120),''); v_fee text := nullif(left(btrim(coalesce(x->>'fee','')),40),'');
  v_note text; v_ref text; v_mode text; v_cap smallint := nullif(x->>'capacity','')::smallint; v_techs text[]; v_loc geography; t text; ch text[] := '{}'; v_msg text; n int := 0;
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
  v_loc := m.location;
  if p_lat is not null and p_lng is not null then
    if p_lat not between 32 and 40 or p_lng not between 123 and 133 then raise exception '위치를 다시 골라 주세요'; end if;
    v_loc := st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography;
  end if;
  v_techs := array(select tq.id from public.techniques tq where tq.id = any(array(select jsonb_array_elements_text(case when jsonb_typeof(x->'technique_ids')='array' then x->'technique_ids' else '[]'::jsonb end))) order by tq.sort limit 10);
  select * into po from public.posts where meetup_id = p_meetup and author_id = uid and parent_id is null order by created_at limit 1;
  if p_photos is not null then
    if cardinality(p_photos) > 4 then raise exception '사진은 4장까지예요'; end if;
    if not public._post_photo_ok(p_photos, coalesce(po.photos,'{}')) then raise exception '사진을 다시 올려 주세요'; end if;
  end if;
  update public.meetups set title = v_title, place_name = v_place, location = v_loc, starts_at = p_starts_at, is_public = coalesce(p_is_public, is_public), descr = v_body,
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
  -- 참여자·신청자에게 알림: 일시·장소·참가비가 바뀐 경우만
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
end $$;
revoke all on function public.meetup_edit(uuid, text, text, timestamptz, boolean, text, double precision, double precision, text[], jsonb) from public, anon;
grant execute on function public.meetup_edit(uuid, text, text, timestamptz, boolean, text, double precision, double precision, text[], jsonb) to authenticated;

-- 클래스(shop_posts kind class): 호스트는 기존 정책으로 직접 고친다. 일시·장소·수강료가 바뀌면 신청자(확인 대기·확정)에게 알림
create or replace function public.shop_posts_class_changed() returns trigger language plpgsql security definer set search_path to 'public' as $$
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
end $$;
revoke all on function public.shop_posts_class_changed() from public, anon, authenticated;
drop trigger if exists shop_posts_class_changed on public.shop_posts;
create trigger shop_posts_class_changed after update of extra on public.shop_posts for each row execute function public.shop_posts_class_changed();
alter table public.shop_posts add column if not exists edited_at timestamptz;
