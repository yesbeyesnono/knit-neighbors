-- 147. 완성작품 인증 판단 기록 (2026-11-19 대표 지시: "내가 직접 보고 작성하는 내용을 잘 정리해 data 화 → 나중에 자동 집행")
--   work_reviews: 승인·보완 요청·반려 한 번마다 한 줄. 그때의 인증 모습(snapshot) + 회원에게 나간 글(note) + 대표가 처음 적은 글(raw_note) + 고른 사유(reason) + AI 다듬기 사용 여부
--   admin_work_review 는 그대로(같은 인자) — 끝에 기록 한 줄을 남기고 결과에 review(기록 번호)를 함께 돌려준다
--   admin_work_review_meta(p_review, p_meta): 콘솔이 방금 남긴 기록에 대표 원문·사유·AI 사용 여부를 덧붙임(본인이 10분 안에 한 것만)
--   회원이 쓴 긴 글(노하우 등)은 담지 않고 길이만 담는다(탈퇴·삭제 뒤에도 남는 표라서). 사진은 work_id 로 찾아본다

create table if not exists public.work_reviews (
  id bigint generated always as identity primary key,
  work_id uuid references public.works(id) on delete set null,
  profile_id uuid references public.profiles(id) on delete set null,
  admin_id uuid,
  action text not null check (action in ('approve','fix','reject')),
  round int not null default 1,
  note text,
  raw_note text,
  reason text,
  ai_used boolean not null default false,
  snapshot jsonb not null default '{}'::jsonb,
  source text not null default 'console',
  created_at timestamptz not null default now()
);
create index if not exists work_reviews_work_idx on public.work_reviews(work_id, created_at);
alter table public.work_reviews enable row level security;
revoke all on public.work_reviews from anon, authenticated;
grant all on public.work_reviews to service_role;

create or replace function public._work_review_snap(p_work uuid) returns jsonb
language sql stable security definer set search_path to 'public' as $$
  select jsonb_build_object(
    'title', left(coalesce(w.title,''), 80), 'item_type', w.item_type,
    'techs', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name_ko, 'level', t.level, 'craft', t.craft) order by t.sort), '[]'::jsonb) from public.techniques t where t.id = any(w.techniques)),
    'max_level', (select max(t.level) from public.techniques t where t.id = any(w.techniques)),
    'custom_n', coalesce(array_length(w.custom_techniques, 1), 0),
    'photos_n', coalesce(array_length(w.photos, 1), 0),
    'tagged_n', case when jsonb_typeof(w.tech_photos) = 'array' then jsonb_array_length(w.tech_photos) else 0 end,
    'no_story', (w.took is null and w.knowhow is null), 'took', w.took,
    'knowhow_len', char_length(coalesce(w.knowhow,'')), 'regret_len', char_length(coalesce(w.regret,'')),
    'has_yarn', (w.yarns is not null and jsonb_typeof(w.yarns) = 'array' and jsonb_array_length(w.yarns) > 0) or coalesce(w.yarn_info,'') <> '',
    'sponsored', coalesce(w.sponsored, false),
    'status_before', w.review_status, 'submitted_at', w.submitted_at,
    'member', jsonb_build_object('level_crochet', p.level_crochet, 'level_knit', p.level_knit, 'cert_count', p.cert_count, 'is_author', coalesce(p.is_author, false),
                                 'days', greatest(0, (extract(epoch from now() - p.created_at) / 86400)::int)))
  from public.works w left join public.profiles p on p.id = w.profile_id where w.id = p_work;
$$;
revoke all on function public._work_review_snap(uuid) from public, anon, authenticated;
grant execute on function public._work_review_snap(uuid) to service_role;

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
      values (w.profile_id, sup, 'notice', v_post, left(v_title||' 완성작품 인증이 커뮤니티에 올라갔어요. 적어 주신 이야기가 같은 작품을 뜨는 분께 큰 도움이 될 거예요.', 300),
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
    values (w.id, w.profile_id, auth.uid(), p_action, (select count(*) + 1 from public.work_reviews r where r.work_id = w.id), case when p_action = 'approve' then null else v_note end, coalesce(v_snap, '{}'::jsonb))
    returning id into v_rev;
  return jsonb_build_object('ok', true, 'status', (select review_status from public.works where id = w.id), 'review', v_rev);
end $function$;

create or replace function public.admin_work_review_meta(p_review bigint, p_meta jsonb) returns boolean
language plpgsql security definer set search_path to 'public' as $$
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  update public.work_reviews set
      raw_note = nullif(left(btrim(coalesce(p_meta->>'raw','')), 600), ''),
      reason   = nullif(left(btrim(coalesce(p_meta->>'reason','')), 40), ''),
      ai_used  = coalesce((p_meta->>'ai')::boolean, false)
    where id = p_review and admin_id = auth.uid() and created_at > now() - interval '10 minutes';
  return found;
end $$;
revoke all on function public.admin_work_review_meta(bigint, jsonb) from public, anon;
grant execute on function public.admin_work_review_meta(bigint, jsonb) to authenticated, service_role;

-- 지금까지의 판단(콘솔 기록 admin_logs)을 옮겨 둔다 — 그때의 인증 모습은 남아 있지 않아 지금 모습으로 채움(source = backfill)
insert into public.work_reviews(work_id, profile_id, admin_id, action, round, note, snapshot, source, created_at)
select w.id, coalesce(w.profile_id, case when (l.detail->>'profile') ~ '^[0-9a-f-]{36}$' and exists (select 1 from public.profiles p where p.id = (l.detail->>'profile')::uuid) then (l.detail->>'profile')::uuid end),
       l.admin_id, substr(l.action, 6),
       row_number() over (partition by l.target_id order by l.created_at),
       nullif(l.detail->>'note', ''), coalesce(public._work_review_snap(w.id), jsonb_build_object('title', l.detail->>'title')), 'backfill', l.created_at
from public.admin_logs l left join public.works w on w.id::text = l.target_id
where l.action in ('work_approve','work_fix','work_reject') and l.target_type = 'work'
  and not exists (select 1 from public.work_reviews r where r.source = 'backfill')
order by l.created_at;
