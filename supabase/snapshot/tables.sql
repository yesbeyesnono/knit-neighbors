-- 표 101개: 칸·제약·RLS·권한. (만드는 순서와 외래 키 순서는 보장하지 않음 — 복구할 때는 supabase_migrations 기록이 원본)

create table access_logs (
  id bigint not null default nextval('access_logs_id_seq'::regclass),
  actor uuid,
  kind text not null,
  target text,
  n integer,
  created_at timestamp with time zone not null default now()
);
alter table access_logs add constraint access_logs_pkey PRIMARY KEY (id);
alter table access_logs enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table account_deletions (
  user_id uuid not null,
  requested_at timestamp with time zone not null default now(),
  purge_after timestamp with time zone not null,
  hidden_post_ids uuid[] not null default '{}'::uuid[],
  friendships jsonb not null default '[]'::jsonb,
  was_visible boolean not null default false,
  wave_until timestamp with time zone,
  purged_at timestamp with time zone
);
alter table account_deletions add constraint account_deletions_pkey PRIMARY KEY (user_id);
alter table account_deletions add constraint account_deletions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table account_deletions enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table admin_logs (
  id bigint not null default nextval('admin_logs_id_seq'::regclass),
  admin_id uuid not null,
  action text not null,
  target_type text,
  target_id text,
  detail jsonb,
  created_at timestamp with time zone not null default now()
);
alter table admin_logs add constraint admin_logs_pkey PRIMARY KEY (id);
alter table admin_logs enable row level security;
-- acl: {postgres=arwdDxtm/postgres,authenticated=arwdm/postgres,service_role=arwdDxtm/postgres}

create table admins (
  profile_id uuid not null,
  added_by uuid,
  added_at timestamp with time zone not null default now()
);
alter table admins add constraint admins_pkey PRIMARY KEY (profile_id);
alter table admins add constraint admins_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table admins enable row level security;
-- acl: {postgres=arwdDxtm/postgres,authenticated=arwdm/postgres,service_role=arwdDxtm/postgres}

create table ai_briefings (
  date date not null,
  body jsonb not null,
  sent_at timestamp with time zone
);
alter table ai_briefings add constraint ai_briefings_pkey PRIMARY KEY (date);
alter table ai_briefings enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table ai_rules (
  id bigint not null default nextval('ai_rules_id_seq'::regclass),
  title text not null,
  rule_text text not null,
  condition jsonb not null default '{}'::jsonb,
  action text not null,
  level smallint not null default 2,
  enabled boolean not null default true,
  created_at timestamp with time zone not null default now()
);
alter table ai_rules add constraint ai_rules_level_check CHECK ((level = ANY (ARRAY[0, 1, 2])));
alter table ai_rules add constraint ai_rules_pkey PRIMARY KEY (id);
alter table ai_rules enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table api_rate (
  profile_id uuid not null,
  key text not null,
  win timestamp with time zone not null,
  n integer not null default 0
);
alter table api_rate add constraint api_rate_pkey PRIMARY KEY (profile_id, key, win);
alter table api_rate add constraint api_rate_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table api_rate enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}

create table app_config (
  key text not null,
  value jsonb not null,
  updated_at timestamp with time zone not null default now()
);
alter table app_config add constraint app_config_pkey PRIMARY KEY (key);
alter table app_config enable row level security;
-- acl: {postgres=arwdDxtm/postgres,authenticated=rm/postgres,service_role=arwdDxtm/postgres,anon=r/postgres}

create table author_applications (
  id uuid not null default gen_random_uuid(),
  profile_id uuid not null,
  real_name text not null,
  link text,
  note text,
  status text not null default 'pending'::text,
  reject_reason text,
  decided_by uuid,
  decided_at timestamp with time zone,
  created_at timestamp with time zone not null default now()
);
alter table author_applications add constraint author_applications_decided_by_fkey FOREIGN KEY (decided_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table author_applications add constraint author_applications_link_check CHECK (((link IS NULL) OR ((char_length(link) <= 300) AND (link ~* '^https?://'::text))));
alter table author_applications add constraint author_applications_note_check CHECK ((char_length(note) <= 1000));
alter table author_applications add constraint author_applications_pkey PRIMARY KEY (id);
alter table author_applications add constraint author_applications_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table author_applications add constraint author_applications_real_name_check CHECK (((char_length(real_name) >= 1) AND (char_length(real_name) <= 40)));
alter table author_applications add constraint author_applications_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])));
alter table author_applications enable row level security;
-- acl: {postgres=arwdDxtm/postgres,authenticated=rdm/postgres,service_role=arwdDxtm/postgres}

create table author_follows (
  profile_id uuid not null,
  author_id uuid not null,
  created_at timestamp with time zone not null default now()
);
alter table author_follows add constraint author_follows_author_id_fkey FOREIGN KEY (author_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table author_follows add constraint author_follows_check CHECK ((profile_id <> author_id));
alter table author_follows add constraint author_follows_pkey PRIMARY KEY (profile_id, author_id);
alter table author_follows add constraint author_follows_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table author_follows enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=ard/postgres}

create table bad_words (
  word text not null,
  category text not null default 'abuse'::text,
  created_at timestamp with time zone not null default now()
);
alter table bad_words add constraint bad_words_pkey PRIMARY KEY (word);
alter table bad_words add constraint bad_words_word_check CHECK (((char_length(word) >= 1) AND (char_length(word) <= 30)));
alter table bad_words enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table banned_words (
  word text not null
);
alter table banned_words add constraint banned_words_pkey PRIMARY KEY (word);
alter table banned_words enable row level security;
-- acl: {postgres=arwdDxtm/postgres,authenticated=arwdm/postgres,service_role=arwdDxtm/postgres}

create table broadcast_segments (
  id bigint not null default nextval('broadcast_segments_id_seq'::regclass),
  name text not null,
  filter jsonb not null default '{}'::jsonb,
  exclude jsonb not null default '{}'::jsonb,
  limit_n integer,
  random_pick boolean not null default false,
  created_by uuid,
  created_at timestamp with time zone not null default now()
);
alter table broadcast_segments add constraint broadcast_segments_name_check CHECK (((char_length(name) >= 1) AND (char_length(name) <= 40)));
alter table broadcast_segments add constraint broadcast_segments_name_key UNIQUE (name);
alter table broadcast_segments add constraint broadcast_segments_pkey PRIMARY KEY (id);
alter table broadcast_segments enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=arwd/postgres}

create table broadcasts (
  id bigint not null default nextval('broadcasts_id_seq'::regclass),
  created_by uuid,
  name text,
  body text not null,
  channels text[] not null default '{notify}'::text[],
  link jsonb,
  filter jsonb not null default '{}'::jsonb,
  exclude jsonb not null default '{}'::jsonb,
  limit_n integer,
  random_pick boolean not null default false,
  schedule_at timestamp with time zone,
  repeat text not null default 'none'::text,
  status text not null default 'sent'::text,
  target_count integer,
  sent_count integer,
  sent_at timestamp with time zone,
  last_error text,
  created_at timestamp with time zone not null default now()
);
alter table broadcasts add constraint broadcasts_body_check CHECK (((char_length(body) >= 1) AND (char_length(body) <= 300)));
alter table broadcasts add constraint broadcasts_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table broadcasts add constraint broadcasts_pkey PRIMARY KEY (id);
alter table broadcasts add constraint broadcasts_repeat_check CHECK ((repeat = ANY (ARRAY['none'::text, 'weekly'::text, 'monthly'::text])));
alter table broadcasts add constraint broadcasts_status_check CHECK ((status = ANY (ARRAY['scheduled'::text, 'sending'::text, 'sent'::text, 'cancelled'::text, 'test'::text, 'failed'::text])));
alter table broadcasts enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=arwd/postgres}

create table cart_items (
  profile_id uuid not null,
  product_id uuid not null,
  color text not null default ''::text,
  qty integer not null,
  created_at timestamp with time zone not null default now()
);
alter table cart_items add constraint cart_items_pkey PRIMARY KEY (profile_id, product_id, color);
alter table cart_items add constraint cart_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES shop_products(id) ON DELETE CASCADE;
alter table cart_items add constraint cart_items_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table cart_items add constraint cart_items_qty_check CHECK (((qty > 0) AND (qty <= 99)));
alter table cart_items enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=arwd/postgres}

create table chat_flags (
  id bigint not null,
  message_id bigint not null,
  room_id uuid not null,
  sender_id uuid,
  level text not null,
  rules text[] not null default '{}'::text[],
  warn text,
  ai jsonb,
  status text not null default 'open'::text,
  resolution text,
  resolved_by uuid,
  resolved_at timestamp with time zone,
  alerted_at timestamp with time zone,
  created_at timestamp with time zone not null default now()
);
alter table chat_flags add constraint chat_flags_level_check CHECK ((level = ANY (ARRAY['urgent'::text, 'check'::text, 'info'::text])));
alter table chat_flags add constraint chat_flags_message_id_fkey FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE;
alter table chat_flags add constraint chat_flags_message_id_key UNIQUE (message_id);
alter table chat_flags add constraint chat_flags_pkey PRIMARY KEY (id);
alter table chat_flags add constraint chat_flags_status_check CHECK ((status = ANY (ARRAY['open'::text, 'ok'::text, 'actioned'::text])));
alter table chat_flags add constraint chat_flags_warn_check CHECK ((warn = ANY (ARRAY['money'::text, 'offapp'::text])));
alter table chat_flags enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}

create table chat_push_log (
  room_id uuid not null,
  profile_id uuid not null,
  sent_at timestamp with time zone not null default now()
);
alter table chat_push_log add constraint chat_push_log_pkey PRIMARY KEY (room_id, profile_id);
alter table chat_push_log enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}

create table cheer_log (
  user_id uuid not null,
  key text not null,
  kind text not null default 'cheer'::text,
  body text,
  link jsonb,
  queued boolean not null default false,
  created_at timestamp with time zone not null default now(),
  sent_at timestamp with time zone
);
alter table cheer_log add constraint cheer_log_pkey PRIMARY KEY (user_id, key);
alter table cheer_log add constraint cheer_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table cheer_log enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}

create table class_applications (
  id bigint not null default nextval('class_applications_id_seq'::regclass),
  post_id uuid not null,
  profile_id uuid not null,
  status text not null default 'applied'::text,
  note text,
  host_note text,
  created_at timestamp with time zone not null default now(),
  decided_at timestamp with time zone,
  paid_at timestamp with time zone
);
alter table class_applications add constraint class_applications_host_note_check CHECK ((char_length(host_note) <= 300));
alter table class_applications add constraint class_applications_note_check CHECK ((char_length(note) <= 300));
alter table class_applications add constraint class_applications_pkey PRIMARY KEY (id);
alter table class_applications add constraint class_applications_post_id_fkey FOREIGN KEY (post_id) REFERENCES shop_posts(id) ON DELETE CASCADE;
alter table class_applications add constraint class_applications_post_id_profile_id_key UNIQUE (post_id, profile_id);
alter table class_applications add constraint class_applications_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table class_applications add constraint class_applications_status_check CHECK ((status = ANY (ARRAY['applied'::text, 'accepted'::text, 'rejected'::text, 'cancelled'::text])));
alter table class_applications enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table color_lexicon (
  token text not null,
  family text not null,
  canonical_ko text not null
);
alter table color_lexicon add constraint color_lexicon_pkey PRIMARY KEY (token);
alter table color_lexicon enable row level security;
-- acl: {postgres=arwdDxtm/postgres,authenticated=rm/postgres,service_role=arwdDxtm/postgres}

create table ddeuchin_claims (
  id bigint not null default nextval('ddeuchin_claims_id_seq'::regclass),
  post_id uuid not null,
  author_id uuid not null,
  friend_id uuid,
  pair text,
  status text not null,
  reason text,
  ai text,
  ai_note text,
  created_at timestamp with time zone not null default now(),
  decided_at timestamp with time zone,
  sent_at timestamp with time zone
);
alter table ddeuchin_claims add constraint ddeuchin_claims_ai_check CHECK ((ai = ANY (ARRAY['pass'::text, 'unsure'::text])));
alter table ddeuchin_claims add constraint ddeuchin_claims_author_id_fkey FOREIGN KEY (author_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table ddeuchin_claims add constraint ddeuchin_claims_friend_id_fkey FOREIGN KEY (friend_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table ddeuchin_claims add constraint ddeuchin_claims_pkey PRIMARY KEY (id);
alter table ddeuchin_claims add constraint ddeuchin_claims_post_id_fkey FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE;
alter table ddeuchin_claims add constraint ddeuchin_claims_post_id_key UNIQUE (post_id);
alter table ddeuchin_claims add constraint ddeuchin_claims_status_check CHECK ((status = ANY (ARRAY['review'::text, 'ok'::text, 'sent'::text, 'excluded'::text])));
alter table ddeuchin_claims enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}

create table demo_2026_10_09 (
  tbl text,
  row jsonb,
  archived_at timestamp with time zone default now()
);
-- acl: {postgres=arwdDxtm/postgres}

create table device_tokens (
  token text not null,
  profile_id uuid not null,
  platform text not null default 'ios'::text,
  bundle text not null default 'kr.co.firmtech.knitneighbors'::text,
  app_version text,
  created_at timestamp with time zone not null default now(),
  last_seen timestamp with time zone not null default now(),
  disabled_at timestamp with time zone,
  fail_count integer not null default 0
);
alter table device_tokens add constraint device_tokens_pkey PRIMARY KEY (token);
alter table device_tokens add constraint device_tokens_platform_check CHECK ((platform = ANY (ARRAY['ios'::text, 'android'::text])));
alter table device_tokens add constraint device_tokens_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table device_tokens enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table dong_fix_log (
  profile_id uuid not null,
  tried text not null,
  ok boolean not null,
  note text,
  tried_at timestamp with time zone not null default now()
);
alter table dong_fix_log add constraint dong_fix_log_pkey PRIMARY KEY (profile_id);
alter table dong_fix_log add constraint dong_fix_log_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table dong_fix_log enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table event_applications (
  id uuid not null default gen_random_uuid(),
  event_id uuid not null,
  profile_id uuid not null,
  note text,
  level_at integer not null default 0,
  status text not null default 'applied'::text,
  work_id uuid,
  created_at timestamp with time zone not null default now(),
  decided_at timestamp with time zone,
  done_at timestamp with time zone
);
alter table event_applications add constraint event_applications_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE;
alter table event_applications add constraint event_applications_event_id_profile_id_key UNIQUE (event_id, profile_id);
alter table event_applications add constraint event_applications_pkey PRIMARY KEY (id);
alter table event_applications add constraint event_applications_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table event_applications add constraint event_applications_status_check CHECK ((status = ANY (ARRAY['applied'::text, 'selected'::text, 'rejected'::text, 'cancelled'::text, 'done'::text])));
alter table event_applications add constraint event_applications_work_id_fkey FOREIGN KEY (work_id) REFERENCES works(id) ON DELETE SET NULL;
alter table event_applications enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table event_shipping (
  application_id uuid not null,
  profile_id uuid not null,
  name text not null,
  phone text not null,
  zip text,
  addr text not null,
  memo text,
  created_at timestamp with time zone not null default now(),
  shipped_at timestamp with time zone
);
alter table event_shipping add constraint event_shipping_application_id_fkey FOREIGN KEY (application_id) REFERENCES event_applications(id) ON DELETE CASCADE;
alter table event_shipping add constraint event_shipping_pkey PRIMARY KEY (application_id);
alter table event_shipping add constraint event_shipping_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table event_shipping enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table events (
  id uuid not null default gen_random_uuid(),
  title text not null,
  body text,
  photo text,
  kind text not null default 'general'::text,
  min_level integer not null default 0,
  capacity integer,
  select_mode text not null default 'admin'::text,
  apply_from timestamp with time zone not null default now(),
  apply_until timestamp with time zone not null,
  cert_due date,
  needs_shipping boolean not null default false,
  catalog_id uuid,
  status text not null default 'draft'::text,
  announced_at timestamp with time zone,
  created_by uuid,
  created_at timestamp with time zone not null default now()
);
alter table events add constraint events_capacity_check CHECK ((capacity > 0));
alter table events add constraint events_catalog_id_fkey FOREIGN KEY (catalog_id) REFERENCES yarn_catalog(id) ON DELETE SET NULL;
alter table events add constraint events_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table events add constraint events_kind_check CHECK ((kind = ANY (ARRAY['invite'::text, 'sample'::text, 'general'::text])));
alter table events add constraint events_min_level_check CHECK ((min_level >= 0));
alter table events add constraint events_pkey PRIMARY KEY (id);
alter table events add constraint events_select_mode_check CHECK ((select_mode = ANY (ARRAY['admin'::text, 'first'::text, 'lottery'::text])));
alter table events add constraint events_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'open'::text, 'closed'::text])));
alter table events add constraint events_title_check CHECK (((char_length(title) >= 1) AND (char_length(title) <= 60)));
alter table events enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table feedback_groups (
  id bigint not null default nextval('feedback_groups_id_seq'::regclass),
  title text not null,
  count integer not null default 0,
  post_ids uuid[] not null default '{}'::uuid[],
  status text not null default 'open'::text,
  reply_draft text,
  created_at timestamp with time zone not null default now()
);
alter table feedback_groups add constraint feedback_groups_pkey PRIMARY KEY (id);
alter table feedback_groups add constraint feedback_groups_status_check CHECK ((status = ANY (ARRAY['open'::text, 'queued'::text, 'done'::text])));
alter table feedback_groups enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table feedback_reports (
  id bigint not null default nextval('feedback_reports_id_seq'::regclass),
  user_id uuid not null,
  body text not null,
  screenshot_url text,
  status text not null default 'open'::text,
  admin_note text,
  decided_at timestamp with time zone,
  tg_message_id bigint,
  created_at timestamp with time zone not null default now(),
  kind text not null default 'bug'::text,
  attachments jsonb not null default '[]'::jsonb
);
alter table feedback_reports add constraint feedback_reports_body_check CHECK (((char_length(body) >= 5) AND (char_length(body) <= 2000)));
alter table feedback_reports add constraint feedback_reports_kind_check CHECK ((kind = ANY (ARRAY['bug'::text, 'idea'::text])));
alter table feedback_reports add constraint feedback_reports_pkey PRIMARY KEY (id);
alter table feedback_reports add constraint feedback_reports_status_check CHECK ((status = ANY (ARRAY['open'::text, 'accepted'::text, 'rejected'::text])));
alter table feedback_reports add constraint feedback_reports_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table feedback_reports enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table friend_recs (
  id bigint not null,
  profile_id uuid not null,
  rec_id uuid,
  day date not null,
  score integer not null default 0,
  near text,
  reasons jsonb not null default '[]'::jsonb,
  items jsonb not null default '[]'::jsonb,
  created_at timestamp with time zone not null default now(),
  rerolls integer not null default 0,
  pushed_at timestamp with time zone
);
alter table friend_recs add constraint friend_recs_pkey PRIMARY KEY (id);
alter table friend_recs add constraint friend_recs_profile_id_day_key UNIQUE (profile_id, day);
alter table friend_recs add constraint friend_recs_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table friend_recs add constraint friend_recs_rec_id_fkey FOREIGN KEY (rec_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table friend_recs enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}

create table friendships (
  requester_id uuid not null,
  addressee_id uuid not null,
  status friendship_status not null default 'pending'::friendship_status,
  message text,
  created_at timestamp with time zone not null default now(),
  responded_at timestamp with time zone,
  reminded_at timestamp with time zone,
  chat_nudged_at timestamp with time zone
);
alter table friendships add constraint friendships_addressee_id_fkey FOREIGN KEY (addressee_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table friendships add constraint friendships_check CHECK ((requester_id <> addressee_id));
alter table friendships add constraint friendships_message_check CHECK (((message IS NULL) OR (char_length(message) <= 100)));
alter table friendships add constraint friendships_pkey PRIMARY KEY (requester_id, addressee_id);
alter table friendships add constraint friendships_requester_id_fkey FOREIGN KEY (requester_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table friendships enable row level security;
-- acl: {postgres=arwdDxtm/postgres,authenticated=arwdm/postgres,service_role=arwdDxtm/postgres}

create table jigi_chat (
  id bigint not null default nextval('jigi_chat_id_seq'::regclass),
  channel text not null,
  role text not null,
  content jsonb not null,
  created_at timestamp with time zone not null default now()
);
alter table jigi_chat add constraint jigi_chat_pkey PRIMARY KEY (id);
alter table jigi_chat enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}

create table jigi_config (
  key text not null,
  value text not null
);
alter table jigi_config add constraint jigi_config_pkey PRIMARY KEY (key);
alter table jigi_config enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}

create table jigi_reminders (
  id bigint not null default nextval('jigi_reminders_id_seq'::regclass),
  due_at timestamp with time zone not null,
  text text not null,
  sent_at timestamp with time zone,
  created_at timestamp with time zone not null default now()
);
alter table jigi_reminders add constraint jigi_reminders_pkey PRIMARY KEY (id);
alter table jigi_reminders add constraint jigi_reminders_text_check CHECK ((char_length(text) <= 8000));
alter table jigi_reminders enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table meetup_applications (
  meetup_id uuid not null,
  profile_id uuid not null,
  status text not null default 'applied'::text,
  note text,
  created_at timestamp with time zone not null default now(),
  decided_at timestamp with time zone
);
alter table meetup_applications add constraint meetup_applications_meetup_id_fkey FOREIGN KEY (meetup_id) REFERENCES meetups(id) ON DELETE CASCADE;
alter table meetup_applications add constraint meetup_applications_pkey PRIMARY KEY (meetup_id, profile_id);
alter table meetup_applications add constraint meetup_applications_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table meetup_applications add constraint meetup_applications_status_check CHECK ((status = ANY (ARRAY['applied'::text, 'accepted'::text, 'rejected'::text, 'cancelled'::text])));
alter table meetup_applications enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table meetups (
  id uuid not null default gen_random_uuid(),
  room_id uuid not null,
  created_by uuid,
  title text not null,
  place_name text not null,
  location geography(Point,4326),
  starts_at timestamp with time zone not null,
  is_public boolean not null default false,
  created_at timestamp with time zone not null default now(),
  participant_count integer not null default 0,
  descr text,
  kind text not null default 'free'::text,
  craft text,
  level_min smallint,
  level_max smallint,
  technique_id text,
  capacity smallint,
  fee text,
  bring text,
  duration_min smallint,
  repeat text not null default 'once'::text,
  review_count integer not null default 0,
  address text,
  mod_scanned_at timestamp with time zone,
  technique_ids text[] not null default '{}'::text[],
  hidden boolean not null default false,
  fee_note text,
  refund_note text,
  join_mode text not null default 'open'::text,
  nearby_notified_at timestamp with time zone
);
alter table meetups add constraint meetups_address_check CHECK (((address IS NULL) OR (char_length(address) <= 200)));
alter table meetups add constraint meetups_bring_check CHECK (((bring IS NULL) OR (char_length(bring) <= 120)));
alter table meetups add constraint meetups_capacity_check CHECK (((capacity IS NULL) OR ((capacity >= 2) AND (capacity <= 100))));
alter table meetups add constraint meetups_craft_check CHECK (((craft IS NULL) OR (craft = ANY (ARRAY['knit'::text, 'crochet'::text, 'both'::text]))));
alter table meetups add constraint meetups_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table meetups add constraint meetups_descr_check CHECK (((descr IS NULL) OR (char_length(descr) <= 300)));
alter table meetups add constraint meetups_duration_min_check CHECK (((duration_min IS NULL) OR ((duration_min >= 30) AND (duration_min <= 480))));
alter table meetups add constraint meetups_fee_check CHECK (((fee IS NULL) OR (char_length(fee) <= 40)));
alter table meetups add constraint meetups_join_mode_chk CHECK ((join_mode = ANY (ARRAY['open'::text, 'apply'::text])));
alter table meetups add constraint meetups_kind_check CHECK ((kind = ANY (ARRAY['free'::text, 'workshop'::text, 'project'::text, 'swap'::text])));
alter table meetups add constraint meetups_level_max_check CHECK (((level_max IS NULL) OR ((level_max >= 1) AND (level_max <= 5))));
alter table meetups add constraint meetups_level_min_check CHECK (((level_min IS NULL) OR ((level_min >= 1) AND (level_min <= 5))));
alter table meetups add constraint meetups_pkey PRIMARY KEY (id);
alter table meetups add constraint meetups_repeat_check CHECK ((repeat = ANY (ARRAY['once'::text, 'weekly'::text, 'biweekly'::text, 'monthly'::text])));
alter table meetups add constraint meetups_room_id_fkey FOREIGN KEY (room_id) REFERENCES rooms(id) ON DELETE CASCADE;
alter table meetups add constraint meetups_technique_id_fkey FOREIGN KEY (technique_id) REFERENCES techniques(id);
alter table meetups add constraint meetups_title_check CHECK ((char_length(title) <= 60));
alter table meetups enable row level security;
-- acl: {postgres=arwdDxtm/postgres,authenticated=arwdm/postgres,service_role=arwdDxtm/postgres}

create table member_notes (
  profile_id uuid not null,
  memo text,
  tags text[] not null default '{}'::text[],
  updated_at timestamp with time zone not null default now(),
  updated_by uuid
);
alter table member_notes add constraint member_notes_pkey PRIMARY KEY (profile_id);
alter table member_notes add constraint member_notes_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table member_notes enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}

create table messages (
  id bigint not null,
  room_id uuid not null,
  sender_id uuid not null,
  body text,
  photo_url text,
  place jsonb,
  created_at timestamp with time zone not null default now(),
  by_ai boolean not null default false,
  support_seen boolean not null default false,
  card jsonb
);
alter table messages add constraint messages_body_check CHECK (((body IS NULL) OR (char_length(body) <= 2000)));
alter table messages add constraint messages_check CHECK (((body IS NOT NULL) OR (photo_url IS NOT NULL) OR (place IS NOT NULL)));
alter table messages add constraint messages_pkey PRIMARY KEY (id);
alter table messages add constraint messages_room_id_fkey FOREIGN KEY (room_id) REFERENCES rooms(id) ON DELETE CASCADE;
alter table messages add constraint messages_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table messages enable row level security;
-- acl: {postgres=arwdDxtm/postgres,authenticated=arwdm/postgres,service_role=arwdDxtm/postgres}

create table mod_actions (
  id bigint not null default nextval('mod_actions_id_seq'::regclass),
  item_id bigint,
  actor text not null,
  action text not null,
  target text,
  before jsonb,
  after jsonb,
  created_at timestamp with time zone not null default now(),
  reverted_at timestamp with time zone
);
alter table mod_actions add constraint mod_actions_actor_check CHECK ((actor = ANY (ARRAY['ai'::text, 'admin'::text])));
alter table mod_actions add constraint mod_actions_item_id_fkey FOREIGN KEY (item_id) REFERENCES mod_items(id) ON DELETE SET NULL;
alter table mod_actions add constraint mod_actions_pkey PRIMARY KEY (id);
alter table mod_actions enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table mod_items (
  id bigint not null default nextval('mod_items_id_seq'::regclass),
  kind text not null,
  target_type text not null,
  target_id text not null,
  author_id uuid,
  severity text not null default 'today'::text,
  summary text not null,
  evidence jsonb not null default '{}'::jsonb,
  ai_suggestion jsonb,
  status text not null default 'open'::text,
  auto_action text,
  created_at timestamp with time zone not null default now(),
  resolved_at timestamp with time zone,
  resolved_by text,
  resolution text,
  tg_message_id bigint
);
alter table mod_items add constraint mod_items_author_id_fkey FOREIGN KEY (author_id) REFERENCES profiles(id) ON DELETE SET NULL;
alter table mod_items add constraint mod_items_kind_check CHECK ((kind = ANY (ARRAY['abuse'::text, 'spam'::text, 'scam'::text, 'app_complaint'::text, 'risk'::text, 'report'::text, 'tech_candidate'::text, 'yarn_review'::text, 'support'::text, 'shop_claim'::text, 'other'::text])));
alter table mod_items add constraint mod_items_pkey PRIMARY KEY (id);
alter table mod_items add constraint mod_items_resolved_by_check CHECK ((resolved_by = ANY (ARRAY['ai'::text, 'admin'::text])));
alter table mod_items add constraint mod_items_severity_check CHECK ((severity = ANY (ARRAY['urgent'::text, 'today'::text, 'info'::text])));
alter table mod_items add constraint mod_items_status_check CHECK ((status = ANY (ARRAY['open'::text, 'auto_done'::text, 'done'::text, 'dismissed'::text])));
alter table mod_items add constraint mod_items_target_type_check CHECK ((target_type = ANY (ARRAY['post'::text, 'meetup'::text, 'user'::text, 'message'::text, 'technique'::text, 'yarn'::text, 'group'::text, 'shop_claim'::text])));
alter table mod_items enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table mod_pending (
  token text not null default encode(gen_random_bytes(9), 'hex'::text),
  item_id bigint,
  label text,
  steps jsonb not null,
  heavy boolean not null default false,
  confirmed boolean not null default false,
  used_at timestamp with time zone,
  expires_at timestamp with time zone not null default (now() + '3 days'::interval),
  created_at timestamp with time zone not null default now()
);
alter table mod_pending add constraint mod_pending_item_id_fkey FOREIGN KEY (item_id) REFERENCES mod_items(id) ON DELETE CASCADE;
alter table mod_pending add constraint mod_pending_pkey PRIMARY KEY (token);
alter table mod_pending enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}

create table news_posts (
  id uuid not null default gen_random_uuid(),
  kind text not null default 'notice'::text,
  version text,
  title text not null,
  body text not null,
  image_url text,
  src text,
  active boolean not null default true,
  published_at timestamp with time zone not null default now(),
  created_at timestamp with time zone not null default now(),
  created_by uuid,
  btn text,
  link jsonb
);
alter table news_posts add constraint news_posts_body_check CHECK (((char_length(body) >= 1) AND (char_length(body) <= 1000)));
alter table news_posts add constraint news_posts_image_url_check CHECK (((image_url IS NULL) OR (image_url ~ '^https://app\.knitup\.co\.kr/images/[A-Za-z0-9._-]+\.(jpg|jpeg|png|webp)$'::text)));
alter table news_posts add constraint news_posts_kind_check CHECK ((kind = ANY (ARRAY['notice'::text, 'update'::text])));
alter table news_posts add constraint news_posts_link_chk CHECK (((link IS NULL) OR ((jsonb_typeof(link) = 'object'::text) AND ((link ->> 'type'::text) = ANY (ARRAY['view'::text, 'post'::text, 'event'::text, 'meetup'::text])))));
alter table news_posts add constraint news_posts_pkey PRIMARY KEY (id);
alter table news_posts add constraint news_posts_src_key UNIQUE (src);
alter table news_posts add constraint news_posts_title_check CHECK (((char_length(title) >= 1) AND (char_length(title) <= 60)));
alter table news_posts enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table notifications (
  id uuid not null default gen_random_uuid(),
  recipient_id uuid not null,
  actor_id uuid,
  kind text not null,
  post_id uuid,
  root_post_id uuid,
  meetup_id uuid,
  snippet text,
  read_at timestamp with time zone,
  created_at timestamp with time zone not null default now(),
  shop_id uuid,
  event_id uuid,
  broadcast_id bigint,
  link jsonb,
  clicked_at timestamp with time zone
);
alter table notifications add constraint notifications_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table notifications add constraint notifications_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE;
alter table notifications add constraint notifications_kind_check CHECK ((kind = ANY (ARRAY['mention'::text, 'reply'::text, 'like'::text, 'friend_request'::text, 'friend_accept'::text, 'meetup_join'::text, 'review'::text, 'solved'::text, 'notice'::text, 'shop_post'::text, 'repost'::text, 'meetup_leave'::text, 'meetup_cancel'::text, 'event_open'::text, 'event_selected'::text, 'event_rejected'::text, 'supporter'::text, 'cheer'::text, 'remind'::text])));
alter table notifications add constraint notifications_meetup_id_fkey FOREIGN KEY (meetup_id) REFERENCES meetups(id) ON DELETE CASCADE;
alter table notifications add constraint notifications_pkey PRIMARY KEY (id);
alter table notifications add constraint notifications_post_id_fkey FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE;
alter table notifications add constraint notifications_recipient_id_fkey FOREIGN KEY (recipient_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table notifications add constraint notifications_root_post_id_fkey FOREIGN KEY (root_post_id) REFERENCES posts(id) ON DELETE CASCADE;
alter table notifications add constraint notifications_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES shops(id) ON DELETE CASCADE;
alter table notifications enable row level security;
-- acl: {postgres=arwdDxtm/postgres,authenticated=arwdm/postgres,service_role=arwdDxtm/postgres}

create table orders (
  id uuid not null default gen_random_uuid(),
  no text not null,
  profile_id uuid not null,
  status text not null default 'pending_payment'::text,
  items jsonb not null,
  subtotal integer not null,
  shipping_fee integer not null default 0,
  total integer not null,
  ship_name text,
  ship_phone text,
  ship_addr text,
  ship_memo text,
  pay_method text not null default 'bank'::text,
  depositor text,
  paid_at timestamp with time zone,
  shipped_at timestamp with time zone,
  tracking text,
  note text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);
alter table orders add constraint orders_no_key UNIQUE (no);
alter table orders add constraint orders_pkey PRIMARY KEY (id);
alter table orders add constraint orders_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table orders add constraint orders_status_check CHECK ((status = ANY (ARRAY['pending_payment'::text, 'paid'::text, 'shipped'::text, 'done'::text, 'cancelled'::text])));
alter table orders enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table partner_guides (
  profile_id uuid not null,
  kind text not null,
  sent_at timestamp with time zone,
  msg_id bigint,
  nudged_at timestamp with time zone,
  nudge_sent boolean not null default false,
  seeded boolean not null default false,
  created_at timestamp with time zone not null default now()
);
alter table partner_guides add constraint partner_guides_kind_check CHECK ((kind = ANY (ARRAY['author'::text, 'shop'::text])));
alter table partner_guides add constraint partner_guides_pkey PRIMARY KEY (profile_id, kind);
alter table partner_guides add constraint partner_guides_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table partner_guides enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}

create table partner_invite_hits (
  invite_id uuid not null,
  profile_id uuid not null,
  via text not null,
  created_at timestamp with time zone not null default now()
);
alter table partner_invite_hits add constraint partner_invite_hits_invite_id_fkey FOREIGN KEY (invite_id) REFERENCES partner_invites(id) ON DELETE CASCADE;
alter table partner_invite_hits add constraint partner_invite_hits_pkey PRIMARY KEY (invite_id, profile_id);
alter table partner_invite_hits add constraint partner_invite_hits_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table partner_invite_hits enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}

create table partner_invites (
  id uuid not null default gen_random_uuid(),
  kind text not null,
  name text not null,
  memo text,
  sent_at timestamp with time zone,
  profile_id uuid,
  created_by uuid,
  created_at timestamp with time zone not null default now(),
  keys text[]
);
alter table partner_invites add constraint partner_invites_kind_check CHECK ((kind = ANY (ARRAY['author'::text, 'shop'::text])));
alter table partner_invites add constraint partner_invites_memo_check CHECK (((memo IS NULL) OR (char_length(memo) <= 300)));
alter table partner_invites add constraint partner_invites_name_check CHECK (((char_length(name) >= 1) AND (char_length(name) <= 40)));
alter table partner_invites add constraint partner_invites_pkey PRIMARY KEY (id);
alter table partner_invites add constraint partner_invites_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE SET NULL;
alter table partner_invites enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}

create table pattern_contents (
  pattern_id uuid not null,
  pkg jsonb not null,
  updated_at timestamp with time zone not null default now()
);
alter table pattern_contents add constraint pattern_contents_pattern_id_fkey FOREIGN KEY (pattern_id) REFERENCES patterns(id) ON DELETE CASCADE;
alter table pattern_contents add constraint pattern_contents_pkey PRIMARY KEY (pattern_id);
alter table pattern_contents enable row level security;
-- acl: {postgres=arwdDxtm/postgres,authenticated=rm/postgres,service_role=arwdDxtm/postgres}

create table pattern_progress (
  profile_id uuid not null,
  pattern_id uuid not null,
  prog integer not null default 0,
  updated_at timestamp with time zone not null default now(),
  done_at timestamp with time zone
);
alter table pattern_progress add constraint pattern_progress_pattern_id_fkey FOREIGN KEY (pattern_id) REFERENCES patterns(id) ON DELETE CASCADE;
alter table pattern_progress add constraint pattern_progress_pkey PRIMARY KEY (profile_id, pattern_id);
alter table pattern_progress add constraint pattern_progress_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table pattern_progress add constraint pattern_progress_prog_check CHECK (((prog >= 0) AND (prog <= 100000)));
alter table pattern_progress enable row level security;
-- acl: {postgres=arwdDxtm/postgres,authenticated=arwdm/postgres,service_role=arwdDxtm/postgres}

create table pattern_purchases (
  profile_id uuid not null,
  pattern_id uuid not null,
  price integer not null,
  store_fee integer not null,
  platform_fee integer not null,
  tax integer not null,
  author_amt integer not null,
  via text not null default 'demo_free'::text,
  created_at timestamp with time zone not null default now()
);
alter table pattern_purchases add constraint pattern_purchases_pattern_id_fkey FOREIGN KEY (pattern_id) REFERENCES patterns(id) ON DELETE CASCADE;
alter table pattern_purchases add constraint pattern_purchases_pkey PRIMARY KEY (profile_id, pattern_id);
alter table pattern_purchases add constraint pattern_purchases_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table pattern_purchases enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table pattern_saves (
  profile_id uuid not null,
  pattern_id uuid not null,
  created_at timestamp with time zone not null default now()
);
alter table pattern_saves add constraint pattern_saves_pattern_id_fkey FOREIGN KEY (pattern_id) REFERENCES patterns(id) ON DELETE CASCADE;
alter table pattern_saves add constraint pattern_saves_pkey PRIMARY KEY (profile_id, pattern_id);
alter table pattern_saves add constraint pattern_saves_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table pattern_saves enable row level security;
-- acl: {postgres=arwdDxtm/postgres,authenticated=arwdm/postgres,service_role=arwdDxtm/postgres}

create table patterns (
  id uuid not null default gen_random_uuid(),
  author_id uuid not null,
  title text not null,
  descr text,
  craft text not null,
  level smallint not null,
  techniques text[] not null default '{}'::text[],
  photos text[] not null default '{}'::text[],
  yarn_weight text,
  needle_size text,
  price integer not null default 0,
  buy_url text,
  is_published boolean not null default true,
  hidden boolean not null default false,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  save_count integer not null default 0,
  has_viewer boolean not null default false,
  gauge jsonb,
  catalog_id uuid
);
alter table patterns add constraint patterns_author_id_fkey FOREIGN KEY (author_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table patterns add constraint patterns_buy_url_check CHECK (((buy_url IS NULL) OR (buy_url ~* '^https?://'::text)));
alter table patterns add constraint patterns_catalog_id_fkey FOREIGN KEY (catalog_id) REFERENCES yarn_catalog(id) ON DELETE SET NULL;
alter table patterns add constraint patterns_craft_check CHECK ((craft = ANY (ARRAY['crochet'::text, 'knitting'::text])));
alter table patterns add constraint patterns_descr_check CHECK ((char_length(descr) <= 2000));
alter table patterns add constraint patterns_level_check CHECK (((level >= 1) AND (level <= 5)));
alter table patterns add constraint patterns_pkey PRIMARY KEY (id);
alter table patterns add constraint patterns_price_check CHECK ((price >= 0));
alter table patterns add constraint patterns_title_check CHECK (((char_length(title) >= 1) AND (char_length(title) <= 80)));
alter table patterns enable row level security;
-- acl: {postgres=arwdDxtm/postgres,authenticated=rdm/postgres,service_role=arwdDxtm/postgres}

create table point_events (
  id bigint not null default nextval('point_events_id_seq'::regclass),
  supporter_id bigint not null,
  user_id uuid not null,
  kind text not null,
  points integer not null,
  ref_table text not null,
  ref_id text not null,
  kst_date date not null,
  segment smallint not null,
  created_at timestamp with time zone not null default now()
);
alter table point_events add constraint point_events_kind_ref_table_ref_id_key UNIQUE (kind, ref_table, ref_id);
alter table point_events add constraint point_events_pkey PRIMARY KEY (id);
alter table point_events add constraint point_events_segment_check CHECK ((segment = ANY (ARRAY[1, 2])));
alter table point_events add constraint point_events_supporter_id_fkey FOREIGN KEY (supporter_id) REFERENCES supporters(id) ON DELETE CASCADE;
alter table point_events enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table post_likes (
  post_id uuid not null,
  profile_id uuid not null,
  created_at timestamp with time zone not null default now()
);
alter table post_likes add constraint post_likes_pkey PRIMARY KEY (post_id, profile_id);
alter table post_likes add constraint post_likes_post_id_fkey FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE;
alter table post_likes add constraint post_likes_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table post_likes enable row level security;
-- acl: {postgres=arwdDxtm/postgres,authenticated=arwdm/postgres,service_role=arwdDxtm/postgres}

create table post_reports (
  post_id uuid not null,
  reporter_id uuid not null,
  reason report_reason not null,
  detail text,
  created_at timestamp with time zone not null default now(),
  reviewed_at timestamp with time zone,
  mod_seen boolean not null default false
);
alter table post_reports add constraint post_reports_detail_check CHECK (((detail IS NULL) OR (char_length(detail) <= 500)));
alter table post_reports add constraint post_reports_pkey PRIMARY KEY (post_id, reporter_id);
alter table post_reports add constraint post_reports_post_id_fkey FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE;
alter table post_reports add constraint post_reports_reporter_id_fkey FOREIGN KEY (reporter_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table post_reports enable row level security;
-- acl: {postgres=arwdDxtm/postgres,authenticated=arwdm/postgres,service_role=arwdDxtm/postgres}

create table post_reposts (
  post_id uuid not null,
  profile_id uuid not null,
  created_at timestamp with time zone not null default now()
);
alter table post_reposts add constraint post_reposts_pkey PRIMARY KEY (post_id, profile_id);
alter table post_reposts add constraint post_reposts_post_id_fkey FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE;
alter table post_reposts add constraint post_reposts_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table post_reposts enable row level security;
-- acl: {postgres=arwdDxtm/postgres,authenticated=ardm/postgres,service_role=arwdDxtm/postgres}

create table posts (
  id uuid not null default gen_random_uuid(),
  author_id uuid not null,
  parent_id uuid,
  body text,
  photos text[] not null default '{}'::text[],
  dong_code text,
  reply_count integer not null default 0,
  like_count integer not null default 0,
  created_at timestamp with time zone not null default now(),
  meetup_id uuid,
  work_id uuid,
  review_of uuid,
  hidden boolean not null default false,
  mentions uuid[] not null default '{}'::uuid[],
  solved_reply_id uuid,
  repost_count integer not null default 0,
  hidden_by_mod boolean not null default false,
  mod_scanned_at timestamp with time zone,
  tags text[] not null default '{}'::text[],
  reply_to uuid,
  edited_at timestamp with time zone,
  archived_at timestamp with time zone,
  pinned_at timestamp with time zone,
  video jsonb
);
alter table posts add constraint posts_author_id_fkey FOREIGN KEY (author_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table posts add constraint posts_body_check CHECK (((body IS NULL) OR (char_length(body) <= 500)));
alter table posts add constraint posts_check CHECK (((body IS NOT NULL) OR (cardinality(photos) > 0)));
alter table posts add constraint posts_meetup_id_fkey FOREIGN KEY (meetup_id) REFERENCES meetups(id) ON DELETE SET NULL;
alter table posts add constraint posts_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES posts(id) ON DELETE CASCADE;
alter table posts add constraint posts_photos_check CHECK ((cardinality(photos) <= 4));
alter table posts add constraint posts_pkey PRIMARY KEY (id);
alter table posts add constraint posts_reply_to_fkey FOREIGN KEY (reply_to) REFERENCES posts(id) ON DELETE SET NULL;
alter table posts add constraint posts_review_of_fkey FOREIGN KEY (review_of) REFERENCES meetups(id) ON DELETE SET NULL;
alter table posts add constraint posts_solved_reply_id_fkey FOREIGN KEY (solved_reply_id) REFERENCES posts(id) ON DELETE SET NULL;
alter table posts add constraint posts_work_id_fkey FOREIGN KEY (work_id) REFERENCES works(id) ON DELETE SET NULL;
alter table posts enable row level security;
-- acl: {postgres=arwdDxtm/postgres,authenticated=arwdm/postgres,service_role=arwdDxtm/postgres}

create table profiles (
  id uuid not null,
  nickname text not null,
  avatar_url text,
  dong_code text,
  dong_name text,
  location geography(Point,4326),
  dong_verified_at timestamp with time zone,
  mbti character(4),
  craft craft_type,
  experience experience_level,
  now_making text,
  now_making_photo text,
  stuck_on text,
  bio text,
  available text[] not null default '{}'::text[],
  beginner_ok boolean not null default false,
  is_visible boolean not null default true,
  suspended_at timestamp with time zone,
  onboarded_at timestamp with time zone,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  skills text[] not null default '{}'::text[],
  level_crochet smallint not null default 0,
  level_knit smallint not null default 0,
  skills_updated_at timestamp with time zone,
  verified_skills text[] not null default '{}'::text[],
  cert_count integer not null default 0,
  terms_agreed_at timestamp with time zone,
  wave_until timestamp with time zone,
  is_author boolean not null default false,
  author_since timestamp with time zone,
  author_link text,
  act_level integer not null default 0,
  post_restricted_until timestamp with time zone,
  referred_by uuid,
  supporter_badge text,
  idx_connect smallint not null default 0,
  idx_host smallint not null default 0,
  idx_skill smallint not null default 0,
  trait text not null default 'new'::text,
  idx_updated_at timestamp with time zone,
  last_seen_at timestamp with time zone,
  deleted_at timestamp with time zone,
  chat_restricted_until timestamp with time zone,
  nickname_changed_at timestamp with time zone,
  cover_url text,
  author_links jsonb,
  is_test boolean not null default false,
  onboard_step smallint,
  rec_off boolean not null default false,
  rec_want text[] not null default '{}'::text[],
  rec_want_text text,
  rec_want_ai jsonb,
  rec_want_at timestamp with time zone,
  feature_off boolean not null default false
);
alter table profiles add constraint profiles_author_link_check CHECK (((author_link IS NULL) OR ((char_length(author_link) <= 300) AND (author_link ~* '^https?://'::text))));
alter table profiles add constraint profiles_bio_check CHECK (((bio IS NULL) OR (char_length(bio) <= 300)));
alter table profiles add constraint profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table profiles add constraint profiles_mbti_check CHECK (((mbti IS NULL) OR (mbti ~ '^[EI][NS][TF][JP]$'::text)));
alter table profiles add constraint profiles_nickname_check CHECK (((char_length(nickname) >= 1) AND (char_length(nickname) <= 20)));
alter table profiles add constraint profiles_now_making_check CHECK (((now_making IS NULL) OR (char_length(now_making) <= 40)));
alter table profiles add constraint profiles_partner_guide TRIGGER DEFERRABLE INITIALLY DEFERRED;
alter table profiles add constraint profiles_pkey PRIMARY KEY (id);
alter table profiles add constraint profiles_referred_by_fkey FOREIGN KEY (referred_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table profiles add constraint profiles_stuck_on_check CHECK (((stuck_on IS NULL) OR (char_length(stuck_on) <= 100)));
alter table profiles enable row level security;
-- acl: {postgres=arwdDxtm/postgres,authenticated=rdm/postgres,service_role=arwdDxtm/postgres}

create table referrals (
  id bigint not null default nextval('referrals_id_seq'::regclass),
  inviter_user_id uuid not null,
  invitee_user_id uuid not null,
  source text not null,
  status text not null default 'pending'::text,
  confirmed_at timestamp with time zone,
  created_at timestamp with time zone not null default now()
);
alter table referrals add constraint referrals_invitee_user_id_fkey FOREIGN KEY (invitee_user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table referrals add constraint referrals_invitee_user_id_key UNIQUE (invitee_user_id);
alter table referrals add constraint referrals_inviter_user_id_fkey FOREIGN KEY (inviter_user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table referrals add constraint referrals_pkey PRIMARY KEY (id);
alter table referrals add constraint referrals_source_check CHECK ((source = ANY (ARRAY['link'::text, 'manual'::text])));
alter table referrals add constraint referrals_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'confirmed'::text, 'rejected'::text])));
alter table referrals enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table report_cases (
  id bigint not null,
  post_id uuid not null,
  author_id uuid not null,
  status text not null default 'ask'::text,
  asked_at timestamp with time zone not null default now(),
  due_at timestamp with time zone not null default (now() + '3 days'::interval),
  replied_at timestamp with time zone,
  reply_msg bigint,
  verdict jsonb,
  hidden_by_case boolean not null default false,
  decided_by text,
  closed_at timestamp with time zone,
  created_at timestamp with time zone not null default now()
);
alter table report_cases add constraint report_cases_author_id_fkey FOREIGN KEY (author_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table report_cases add constraint report_cases_pkey PRIMARY KEY (id);
alter table report_cases add constraint report_cases_post_id_fkey FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE;
alter table report_cases add constraint report_cases_status_check CHECK ((status = ANY (ARRAY['ask'::text, 'review'::text, 'ok'::text, 'hidden'::text, 'closed'::text])));
alter table report_cases enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table reports (
  id bigint not null,
  reporter_id uuid not null,
  reported_id uuid not null,
  reason report_reason not null,
  detail text,
  message_id bigint,
  created_at timestamp with time zone not null default now(),
  reviewed_at timestamp with time zone,
  mod_seen boolean not null default false
);
alter table reports add constraint reports_detail_check CHECK (((detail IS NULL) OR (char_length(detail) <= 500)));
alter table reports add constraint reports_message_id_fkey FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE SET NULL;
alter table reports add constraint reports_pkey PRIMARY KEY (id);
alter table reports add constraint reports_reported_id_fkey FOREIGN KEY (reported_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table reports add constraint reports_reporter_id_fkey FOREIGN KEY (reporter_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table reports add constraint reports_reporter_id_reported_id_key UNIQUE (reporter_id, reported_id);
alter table reports enable row level security;
-- acl: {postgres=arwdDxtm/postgres,authenticated=arwdm/postgres,service_role=arwdDxtm/postgres}

create table room_members (
  room_id uuid not null,
  profile_id uuid not null,
  joined_at timestamp with time zone not null default now(),
  last_read_at timestamp with time zone not null default now(),
  archived_at timestamp with time zone,
  left_at timestamp with time zone
);
alter table room_members add constraint room_members_pkey PRIMARY KEY (room_id, profile_id);
alter table room_members add constraint room_members_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table room_members add constraint room_members_room_id_fkey FOREIGN KEY (room_id) REFERENCES rooms(id) ON DELETE CASCADE;
alter table room_members enable row level security;
-- acl: {postgres=arwdDxtm/postgres,authenticated=arwdm/postgres,service_role=arwdDxtm/postgres}

create table rooms (
  id uuid not null default gen_random_uuid(),
  kind room_kind not null,
  title text,
  created_by uuid,
  created_at timestamp with time zone not null default now(),
  inquiry boolean not null default false
);
alter table rooms add constraint rooms_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table rooms add constraint rooms_pkey PRIMARY KEY (id);
alter table rooms add constraint rooms_title_check CHECK (((title IS NULL) OR (char_length(title) <= 40)));
alter table rooms enable row level security;
-- acl: {postgres=arwdDxtm/postgres,authenticated=arwdm/postgres,service_role=arwdDxtm/postgres}

create table shop_claims (
  id uuid not null default gen_random_uuid(),
  profile_id uuid not null,
  shop_id uuid,
  name text not null,
  kind text not null default 'yarn'::text,
  address text,
  phone text,
  biz_no text,
  doc_path text,
  note text,
  status text not null default 'pending'::text,
  reject_reason text,
  decided_by uuid,
  decided_at timestamp with time zone,
  created_at timestamp with time zone not null default now(),
  email text,
  links jsonb not null default '{}'::jsonb,
  lat double precision,
  lng double precision,
  ai_check jsonb,
  ai_status text,
  tg_message_id bigint
);
alter table shop_claims add constraint shop_claims_address_check CHECK ((char_length(address) <= 200));
alter table shop_claims add constraint shop_claims_ai_status_check CHECK ((ai_status = ANY (ARRAY['match'::text, 'mismatch'::text, 'unreadable'::text, 'skipped'::text])));
alter table shop_claims add constraint shop_claims_biz_no_check CHECK ((char_length(biz_no) <= 20));
alter table shop_claims add constraint shop_claims_decided_by_fkey FOREIGN KEY (decided_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table shop_claims add constraint shop_claims_email_check CHECK ((char_length(email) <= 120));
alter table shop_claims add constraint shop_claims_kind_check CHECK ((kind = ANY (ARRAY['yarn'::text, 'studio'::text, 'cafe'::text, 'other'::text])));
alter table shop_claims add constraint shop_claims_name_check CHECK (((char_length(name) >= 1) AND (char_length(name) <= 60)));
alter table shop_claims add constraint shop_claims_note_check CHECK ((char_length(note) <= 500));
alter table shop_claims add constraint shop_claims_phone_check CHECK ((char_length(phone) <= 30));
alter table shop_claims add constraint shop_claims_pkey PRIMARY KEY (id);
alter table shop_claims add constraint shop_claims_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table shop_claims add constraint shop_claims_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES shops(id) ON DELETE SET NULL;
alter table shop_claims add constraint shop_claims_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])));
alter table shop_claims enable row level security;
-- acl: {postgres=arwdDxtm/postgres,authenticated=arwdm/postgres,service_role=arwdDxtm/postgres}

create table shop_follows (
  profile_id uuid not null,
  shop_id uuid not null,
  created_at timestamp with time zone not null default now()
);
alter table shop_follows add constraint shop_follows_pkey PRIMARY KEY (profile_id, shop_id);
alter table shop_follows add constraint shop_follows_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table shop_follows add constraint shop_follows_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES shops(id) ON DELETE CASCADE;
alter table shop_follows enable row level security;
-- acl: {postgres=arwdDxtm/postgres,authenticated=arwdm/postgres,service_role=arwdDxtm/postgres}

create table shop_post_comments (
  id uuid not null default gen_random_uuid(),
  post_id uuid not null,
  author_id uuid not null,
  body text not null,
  created_at timestamp with time zone not null default now()
);
alter table shop_post_comments add constraint shop_post_comments_author_id_fkey FOREIGN KEY (author_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table shop_post_comments add constraint shop_post_comments_body_check CHECK (((char_length(btrim(body)) >= 1) AND (char_length(btrim(body)) <= 300)));
alter table shop_post_comments add constraint shop_post_comments_pkey PRIMARY KEY (id);
alter table shop_post_comments add constraint shop_post_comments_post_id_fkey FOREIGN KEY (post_id) REFERENCES shop_posts(id) ON DELETE CASCADE;
alter table shop_post_comments enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=rd/postgres}

create table shop_post_likes (
  post_id uuid not null,
  profile_id uuid not null,
  created_at timestamp with time zone not null default now()
);
alter table shop_post_likes add constraint shop_post_likes_pkey PRIMARY KEY (post_id, profile_id);
alter table shop_post_likes add constraint shop_post_likes_post_id_fkey FOREIGN KEY (post_id) REFERENCES shop_posts(id) ON DELETE CASCADE;
alter table shop_post_likes add constraint shop_post_likes_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table shop_post_likes enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table shop_posts (
  id uuid not null default gen_random_uuid(),
  shop_id uuid,
  author_id uuid,
  kind text not null default 'notice'::text,
  title text not null,
  body text,
  photos text[] not null default '{}'::text[],
  ends_at timestamp with time zone,
  hidden boolean not null default false,
  created_at timestamp with time zone not null default now(),
  extra jsonb not null default '{}'::jsonb,
  room_id uuid,
  edited_at timestamp with time zone,
  link text,
  like_count integer not null default 0,
  comment_count integer not null default 0
);
alter table shop_posts add constraint shop_posts_author_id_fkey FOREIGN KEY (author_id) REFERENCES profiles(id) ON DELETE SET NULL;
alter table shop_posts add constraint shop_posts_kind_check CHECK ((kind = ANY (ARRAY['sale'::text, 'new'::text, 'meetup'::text, 'class'::text, 'notice'::text])));
alter table shop_posts add constraint shop_posts_link_chk CHECK (((link IS NULL) OR ((kind <> 'class'::text) AND (char_length(link) <= 300) AND (link ~ '^https://[A-Za-z0-9.-]+\.[A-Za-z]{2,}([/?#][^[:space:]<>"'']*)?$'::text))));
alter table shop_posts add constraint shop_posts_owner_chk CHECK (((shop_id IS NOT NULL) OR ((author_id IS NOT NULL) AND (kind = 'class'::text))));
alter table shop_posts add constraint shop_posts_pkey PRIMARY KEY (id);
alter table shop_posts add constraint shop_posts_room_id_fkey FOREIGN KEY (room_id) REFERENCES rooms(id) ON DELETE SET NULL;
alter table shop_posts add constraint shop_posts_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES shops(id) ON DELETE CASCADE;
alter table shop_posts enable row level security;
-- acl: {postgres=arwdDxtm/postgres,authenticated=arwdm/postgres,service_role=arwdDxtm/postgres}

create table shop_products (
  id uuid not null default gen_random_uuid(),
  catalog_id uuid,
  name text not null,
  brand text,
  descr text,
  price integer not null,
  stock integer not null default 0,
  ball_g numeric,
  ball_m numeric,
  photo text,
  colors jsonb not null default '[]'::jsonb,
  is_active boolean not null default true,
  sort integer not null default 0,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);
alter table shop_products add constraint shop_products_catalog_id_fkey FOREIGN KEY (catalog_id) REFERENCES yarn_catalog(id) ON DELETE SET NULL;
alter table shop_products add constraint shop_products_pkey PRIMARY KEY (id);
alter table shop_products add constraint shop_products_price_check CHECK ((price >= 0));
alter table shop_products add constraint shop_products_stock_check CHECK ((stock >= 0));
alter table shop_products enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table shop_reads (
  profile_id uuid not null,
  shop_id uuid not null,
  last_read_at timestamp with time zone not null default now()
);
alter table shop_reads add constraint shop_reads_pkey PRIMARY KEY (profile_id, shop_id);
alter table shop_reads add constraint shop_reads_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table shop_reads add constraint shop_reads_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES shops(id) ON DELETE CASCADE;
alter table shop_reads enable row level security;
-- acl: {postgres=arwdDxtm/postgres,authenticated=arwdm/postgres,service_role=arwdDxtm/postgres}

create table shops (
  id uuid not null default gen_random_uuid(),
  owner_id uuid,
  name text not null,
  kind text not null default 'yarn'::text,
  descr text,
  address text,
  location geography(Point,4326),
  phone text,
  hours text,
  links jsonb not null default '{}'::jsonb,
  logo_url text,
  radius_m integer not null default 5000,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  cover_url text
);
alter table shops add constraint shops_cover_url_own CHECK (_own_storage_url(cover_url));
alter table shops add constraint shops_kind_check CHECK ((kind = ANY (ARRAY['yarn'::text, 'studio'::text, 'cafe'::text, 'other'::text])));
alter table shops add constraint shops_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE SET NULL;
alter table shops add constraint shops_owner_id_key UNIQUE (owner_id);
alter table shops add constraint shops_partner_guide TRIGGER DEFERRABLE INITIALLY DEFERRED;
alter table shops add constraint shops_pkey PRIMARY KEY (id);
alter table shops enable row level security;
-- acl: {postgres=arwdDxtm/postgres,authenticated=ardm/postgres,service_role=arwdDxtm/postgres}

create table skill_events (
  id bigint not null default nextval('skill_events_id_seq'::regclass),
  profile_id uuid not null,
  kind text not null,
  technique_id text,
  craft text,
  level smallint,
  source text,
  created_at timestamp with time zone not null default now()
);
alter table skill_events add constraint skill_events_kind_check CHECK ((kind = ANY (ARRAY['add'::text, 'remove'::text, 'level'::text])));
alter table skill_events add constraint skill_events_pkey PRIMARY KEY (id);
alter table skill_events add constraint skill_events_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table skill_events enable row level security;
-- acl: {postgres=arwdDxtm/postgres,authenticated=arwdm/postgres,service_role=arwdDxtm/postgres}

create table storage_trash (
  id bigint not null,
  bucket text not null,
  path text not null,
  reason text,
  created_at timestamp with time zone not null default now(),
  done_at timestamp with time zone,
  tries integer not null default 0
);
alter table storage_trash add constraint storage_trash_bucket_path_key UNIQUE (bucket, path);
alter table storage_trash add constraint storage_trash_pkey PRIMARY KEY (id);
alter table storage_trash enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}

create table studio_inbox (
  id uuid not null default gen_random_uuid(),
  profile_id uuid not null,
  code text not null,
  title text,
  meta jsonb,
  pkg jsonb,
  created_at timestamp with time zone not null default now(),
  expires_at timestamp with time zone not null default (now() + '00:10:00'::interval),
  claimed_at timestamp with time zone
);
alter table studio_inbox add constraint studio_inbox_pkey PRIMARY KEY (id);
alter table studio_inbox add constraint studio_inbox_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table studio_inbox enable row level security;
-- acl: {postgres=arwdDxtm/postgres,authenticated=arwdDxtm/postgres,service_role=arwdDxtm/postgres}

create table support_events (
  id bigint not null default nextval('support_events_id_seq'::regclass),
  ticket_id bigint,
  actor text not null,
  kind text not null,
  body text,
  created_at timestamp with time zone not null default now()
);
alter table support_events add constraint support_events_actor_check CHECK ((actor = ANY (ARRAY['member'::text, 'ai'::text, 'admin'::text, 'system'::text])));
alter table support_events add constraint support_events_pkey PRIMARY KEY (id);
alter table support_events add constraint support_events_ticket_id_fkey FOREIGN KEY (ticket_id) REFERENCES support_tickets(id) ON DELETE CASCADE;
alter table support_events enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table support_kb (
  id bigint not null default nextval('support_kb_id_seq'::regclass),
  kind text not null,
  category text not null default '기타'::text,
  q text not null,
  a text not null,
  enabled boolean not null default true,
  uses integer not null default 0,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);
alter table support_kb add constraint support_kb_kind_check CHECK ((kind = ANY (ARRAY['faq'::text, 'term'::text, 'check'::text])));
alter table support_kb add constraint support_kb_pkey PRIMARY KEY (id);
alter table support_kb enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table support_kb_candidates (
  id bigint not null default nextval('support_kb_candidates_id_seq'::regclass),
  kind text not null,
  category text not null default '기타'::text,
  q text not null,
  a text not null,
  evidence jsonb not null default '{}'::jsonb,
  status text not null default 'open'::text,
  created_at timestamp with time zone not null default now(),
  decided_at timestamp with time zone
);
alter table support_kb_candidates add constraint support_kb_candidates_kind_check CHECK ((kind = ANY (ARRAY['faq'::text, 'term'::text, 'check'::text])));
alter table support_kb_candidates add constraint support_kb_candidates_pkey PRIMARY KEY (id);
alter table support_kb_candidates add constraint support_kb_candidates_status_check CHECK ((status = ANY (ARRAY['open'::text, 'approved'::text, 'rejected'::text])));
alter table support_kb_candidates enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table support_tickets (
  id bigint not null default nextval('support_tickets_id_seq'::regclass),
  room_id uuid not null,
  profile_id uuid,
  status text not null default 'open'::text,
  category text not null default '기타'::text,
  urgency text not null default 'today'::text,
  summary text not null default ''::text,
  detail jsonb not null default '{}'::jsonb,
  turns integer not null default 0,
  admin_answer text,
  answered_by uuid,
  answered_at timestamp with time zone,
  followup_at timestamp with time zone,
  closed_at timestamp with time zone,
  resolution text,
  tg_message_id bigint,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);
alter table support_tickets add constraint support_tickets_pkey PRIMARY KEY (id);
alter table support_tickets add constraint support_tickets_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE SET NULL;
alter table support_tickets add constraint support_tickets_room_id_fkey FOREIGN KEY (room_id) REFERENCES rooms(id) ON DELETE CASCADE;
alter table support_tickets add constraint support_tickets_status_check CHECK ((status = ANY (ARRAY['open'::text, 'waiting_admin'::text, 'answered'::text, 'closed'::text])));
alter table support_tickets add constraint support_tickets_urgency_check CHECK ((urgency = ANY (ARRAY['urgent'::text, 'today'::text, 'info'::text])));
alter table support_tickets enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table supporter_cohorts (
  id integer not null default nextval('supporter_cohorts_id_seq'::regclass),
  name text not null,
  capacity integer not null default 100,
  is_open boolean not null default true,
  created_at timestamp with time zone not null default now()
);
alter table supporter_cohorts add constraint supporter_cohorts_pkey PRIMARY KEY (id);
alter table supporter_cohorts enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table supporter_notices (
  id bigint not null default nextval('supporter_notices_id_seq'::regclass),
  supporter_id bigint not null,
  notice_key text not null,
  sent_at timestamp with time zone not null default now()
);
alter table supporter_notices add constraint supporter_notices_pkey PRIMARY KEY (id);
alter table supporter_notices add constraint supporter_notices_supporter_id_fkey FOREIGN KEY (supporter_id) REFERENCES supporters(id) ON DELETE CASCADE;
alter table supporter_notices add constraint supporter_notices_supporter_id_notice_key_key UNIQUE (supporter_id, notice_key);
alter table supporter_notices enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table supporter_waitlist (
  id bigint not null default nextval('supporter_waitlist_id_seq'::regclass),
  user_id uuid not null,
  created_at timestamp with time zone not null default now()
);
alter table supporter_waitlist add constraint supporter_waitlist_pkey PRIMARY KEY (id);
alter table supporter_waitlist add constraint supporter_waitlist_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table supporter_waitlist add constraint supporter_waitlist_user_id_key UNIQUE (user_id);
alter table supporter_waitlist enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table supporters (
  id bigint not null default nextval('supporters_id_seq'::regclass),
  user_id uuid not null,
  cohort_id integer not null,
  started_at timestamp with time zone not null default now(),
  ends_at timestamp with time zone not null,
  status text not null default 'active'::text,
  tier text,
  ref_code text not null,
  finalized_at timestamp with time zone,
  reward_note text
);
alter table supporters add constraint supporters_cohort_id_fkey FOREIGN KEY (cohort_id) REFERENCES supporter_cohorts(id);
alter table supporters add constraint supporters_pkey PRIMARY KEY (id);
alter table supporters add constraint supporters_ref_code_key UNIQUE (ref_code);
alter table supporters add constraint supporters_status_check CHECK ((status = ANY (ARRAY['active'::text, 'completed'::text, 'withdrawn'::text])));
alter table supporters add constraint supporters_tier_check CHECK ((tier = ANY (ARRAY['basic'::text, 'excellent'::text, 'mvp'::text, 'none'::text])));
alter table supporters add constraint supporters_user_id_cohort_id_key UNIQUE (user_id, cohort_id);
alter table supporters add constraint supporters_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table supporters enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table survey_responses (
  id bigint not null default nextval('survey_responses_id_seq'::regclass),
  survey_id integer not null,
  user_id uuid not null,
  answers jsonb not null default '{}'::jsonb,
  created_at timestamp with time zone not null default now()
);
alter table survey_responses add constraint survey_responses_pkey PRIMARY KEY (id);
alter table survey_responses add constraint survey_responses_survey_id_fkey FOREIGN KEY (survey_id) REFERENCES surveys(id) ON DELETE CASCADE;
alter table survey_responses add constraint survey_responses_survey_id_user_id_key UNIQUE (survey_id, user_id);
alter table survey_responses add constraint survey_responses_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table survey_responses enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table surveys (
  id integer not null default nextval('surveys_id_seq'::regclass),
  cohort_id integer not null,
  round smallint not null,
  title text not null default ''::text,
  opens_at timestamp with time zone not null default now(),
  closes_at timestamp with time zone not null default (now() + '14 days'::interval),
  questions jsonb not null default '[]'::jsonb
);
alter table surveys add constraint surveys_cohort_id_fkey FOREIGN KEY (cohort_id) REFERENCES supporter_cohorts(id);
alter table surveys add constraint surveys_cohort_id_round_key UNIQUE (cohort_id, round);
alter table surveys add constraint surveys_pkey PRIMARY KEY (id);
alter table surveys add constraint surveys_round_check CHECK (((round >= 1) AND (round <= 4)));
alter table surveys enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table tag_hidden (
  tag text not null,
  created_at timestamp with time zone not null default now(),
  created_by uuid
);
alter table tag_hidden add constraint tag_hidden_pkey PRIMARY KEY (tag);
alter table tag_hidden enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table technique_aliases (
  alias text not null,
  technique_id text not null,
  created_at timestamp with time zone not null default now()
);
alter table technique_aliases add constraint technique_aliases_pkey PRIMARY KEY (alias);
alter table technique_aliases add constraint technique_aliases_technique_id_fkey FOREIGN KEY (technique_id) REFERENCES techniques(id) ON DELETE CASCADE;
alter table technique_aliases enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table technique_candidates (
  id bigint not null default nextval('technique_candidates_id_seq'::regclass),
  label text not null,
  norm text not null,
  raw_variants text[] not null default '{}'::text[],
  n_inputs integer not null default 0,
  n_users integer not null default 0,
  sample_work_ids uuid[] not null default '{}'::uuid[],
  ai_verdict text,
  alias_of text,
  confidence numeric(3,2),
  evidence_links text[] not null default '{}'::text[],
  reason text,
  status text not null default 'open'::text,
  updated_at timestamp with time zone not null default now()
);
alter table technique_candidates add constraint technique_candidates_ai_verdict_check CHECK ((ai_verdict = ANY (ARRAY['alias'::text, 'new'::text, 'not_technique'::text, 'unknown'::text])));
alter table technique_candidates add constraint technique_candidates_alias_of_fkey FOREIGN KEY (alias_of) REFERENCES techniques(id) ON DELETE SET NULL;
alter table technique_candidates add constraint technique_candidates_norm_key UNIQUE (norm);
alter table technique_candidates add constraint technique_candidates_pkey PRIMARY KEY (id);
alter table technique_candidates add constraint technique_candidates_status_check CHECK ((status = ANY (ARRAY['open'::text, 'linked'::text, 'registered'::text, 'excluded'::text])));
alter table technique_candidates enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table techniques (
  id text not null,
  craft text not null,
  name_ko text not null,
  level smallint not null,
  category text not null,
  prereq text[] not null default '{}'::text[],
  descr text,
  symbol text,
  sort smallint default ((level * 100) + (substr(id, 2))::integer),
  name_ja text,
  name_en text,
  abbr text,
  aliases text[] not null default '{}'::text[],
  hidden boolean not null default false,
  merged_into text
);
alter table techniques add constraint techniques_craft_check CHECK ((craft = ANY (ARRAY['crochet'::text, 'knitting'::text])));
alter table techniques add constraint techniques_level_check CHECK (((level >= 1) AND (level <= 5)));
alter table techniques add constraint techniques_pkey PRIMARY KEY (id);
alter table techniques enable row level security;
-- acl: {postgres=arwdDxtm/postgres,authenticated=rm/postgres,service_role=arwdDxtm/postgres}

create table video_uploads (
  uid text not null,
  owner uuid,
  created_at timestamp with time zone not null default now(),
  ready_at timestamp with time zone,
  duration numeric
);
alter table video_uploads add constraint video_uploads_pkey PRIMARY KEY (uid);
alter table video_uploads enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}

create table work_reviews (
  id bigint not null,
  work_id uuid,
  profile_id uuid,
  admin_id uuid,
  action text not null,
  round integer not null default 1,
  note text,
  raw_note text,
  reason text,
  ai_used boolean not null default false,
  snapshot jsonb not null default '{}'::jsonb,
  source text not null default 'console'::text,
  created_at timestamp with time zone not null default now(),
  ai_action text
);
alter table work_reviews add constraint work_reviews_action_check CHECK ((action = ANY (ARRAY['approve'::text, 'fix'::text, 'reject'::text])));
alter table work_reviews add constraint work_reviews_pkey PRIMARY KEY (id);
alter table work_reviews add constraint work_reviews_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE SET NULL;
alter table work_reviews add constraint work_reviews_work_id_fkey FOREIGN KEY (work_id) REFERENCES works(id) ON DELETE SET NULL;
alter table work_reviews enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}

create table works (
  id uuid not null default gen_random_uuid(),
  profile_id uuid not null,
  photo_url text not null,
  title text,
  yarn_info text,
  pattern_source text,
  created_at timestamp with time zone not null default now(),
  photos text[] not null default '{}'::text[],
  techniques text[] not null default '{}'::text[],
  note text,
  custom_techniques text[] not null default '{}'::text[],
  yarn_name text,
  yarn_weight text,
  needle_size text,
  yarns jsonb not null default '[]'::jsonb,
  needles jsonb not null default '[]'::jsonb,
  gauge text,
  finished_size text,
  item_type text,
  event_id uuid,
  sponsored boolean not null default false,
  tech_scanned_at timestamp with time zone,
  tech_photos jsonb,
  review_status text not null default 'approved'::text,
  review_note text,
  reviewed_at timestamp with time zone,
  reviewed_by uuid,
  submitted_at timestamp with time zone,
  review_alerted_at timestamp with time zone,
  fix_reminded_at timestamp with time zone,
  took text,
  knowhow text,
  regret text,
  feature boolean not null default true,
  featured_at timestamp with time zone
);
alter table works add constraint works_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE SET NULL;
alter table works add constraint works_finished_size_check CHECK (((finished_size IS NULL) OR (char_length(finished_size) <= 60)));
alter table works add constraint works_gauge_check CHECK (((gauge IS NULL) OR (char_length(gauge) <= 60)));
alter table works add constraint works_item_type_check CHECK (((item_type IS NULL) OR (char_length(item_type) <= 20)));
alter table works add constraint works_note_check CHECK (((note IS NULL) OR (char_length(note) <= 300)));
alter table works add constraint works_pkey PRIMARY KEY (id);
alter table works add constraint works_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table works add constraint works_review_status_chk CHECK ((review_status = ANY (ARRAY['pending'::text, 'fix'::text, 'approved'::text, 'rejected'::text])));
alter table works add constraint works_story_chk CHECK ((((took IS NULL) OR (took = ANY (ARRAY['1d'::text, '3d'::text, '1w'::text, '2w'::text, '1m'::text, 'long'::text]))) AND ((knowhow IS NULL) OR (char_length(knowhow) <= 500)) AND ((regret IS NULL) OR (char_length(regret) <= 300)) AND ((review_note IS NULL) OR (char_length(review_note) <= 300))));
alter table works add constraint works_title_check CHECK (((title IS NULL) OR (char_length(title) <= 60)));
alter table works enable row level security;
-- acl: {postgres=arwdDxtm/postgres,authenticated=arwdm/postgres,service_role=arwdDxtm/postgres}

create table yarn_asks (
  id bigint not null default nextval('yarn_asks_id_seq'::regclass),
  profile_id uuid not null,
  work_id uuid,
  items jsonb not null,
  status text not null default 'asked'::text,
  turns integer not null default 0,
  asked_at timestamp with time zone not null default now(),
  answered_at timestamp with time zone,
  answer jsonb,
  result jsonb
);
alter table yarn_asks add constraint yarn_asks_pkey PRIMARY KEY (id);
alter table yarn_asks add constraint yarn_asks_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table yarn_asks add constraint yarn_asks_status_check CHECK ((status = ANY (ARRAY['asked'::text, 'done'::text, 'unknown'::text, 'expired'::text])));
alter table yarn_asks add constraint yarn_asks_work_id_fkey FOREIGN KEY (work_id) REFERENCES works(id) ON DELETE SET NULL;
alter table yarn_asks enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table yarn_brand_aliases (
  brand text not null,
  alias text not null,
  created_at timestamp with time zone not null default now()
);
alter table yarn_brand_aliases add constraint yarn_brand_aliases_pkey PRIMARY KEY (brand, alias);
alter table yarn_brand_aliases enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=arwd/postgres}

create table yarn_catalog (
  id uuid not null default gen_random_uuid(),
  brand text,
  product text not null,
  aliases text[] not null default '{}'::text[],
  norm_keys text[] not null default '{}'::text[],
  ball_g numeric,
  ball_m numeric,
  m_per_100g numeric default 
CASE
    WHEN ((ball_g > (0)::numeric) AND (ball_m > (0)::numeric)) THEN round(((ball_m / ball_g) * (100)::numeric))
    ELSE NULL::numeric
END,
  weight_class text,
  fiber_main text,
  fibers jsonb,
  status text not null default 'auto'::text,
  merged_into uuid,
  uses integer not null default 0,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  shop text,
  source_url text,
  season text,
  needle_knit text,
  needle_crochet text,
  gauge text,
  put_up text,
  product_en text,
  texture text,
  use_tags text[] not null default '{}'::text[],
  gauge_knit jsonb,
  gauge_crochet jsonb,
  weight_est boolean not null default false
);
alter table yarn_catalog add constraint yarn_catalog_brand_check CHECK ((char_length(brand) <= 40));
alter table yarn_catalog add constraint yarn_catalog_merged_into_fkey FOREIGN KEY (merged_into) REFERENCES yarn_catalog(id) ON DELETE SET NULL;
alter table yarn_catalog add constraint yarn_catalog_pkey PRIMARY KEY (id);
alter table yarn_catalog add constraint yarn_catalog_product_check CHECK (((char_length(product) >= 1) AND (char_length(product) <= 60)));
alter table yarn_catalog add constraint yarn_catalog_season_check CHECK (((season IS NULL) OR (season = ANY (ARRAY['여름'::text, '겨울'::text, '사계절'::text]))));
alter table yarn_catalog add constraint yarn_catalog_status_check CHECK ((status = ANY (ARRAY['auto'::text, 'verified'::text])));
alter table yarn_catalog add constraint yarn_catalog_texture_check CHECK (((texture IS NULL) OR (texture = ANY (ARRAY['일반사'::text, '모헤어·헤일로'::text, '부클·퍼'::text, '셔닐·벨벳·수면사'::text, '테이프·라피아·페이퍼'::text, '패브릭얀·코드'::text, '수세미사'::text, '메탈릭'::text]))));
alter table yarn_catalog enable row level security;
-- acl: {postgres=arwdDxtm/postgres,authenticated=rm/postgres,service_role=arwdDxtm/postgres}

create table yarn_colors (
  id bigint not null,
  catalog_id uuid not null,
  no text,
  name text not null,
  family text,
  photo text,
  color_hex text[],
  color_mode text
);
alter table yarn_colors add constraint yarn_colors_catalog_id_fkey FOREIGN KEY (catalog_id) REFERENCES yarn_catalog(id) ON DELETE CASCADE;
alter table yarn_colors add constraint yarn_colors_catalog_id_no_name_key UNIQUE (catalog_id, no, name);
alter table yarn_colors add constraint yarn_colors_color_mode_chk CHECK (((color_mode IS NULL) OR (color_mode = ANY (ARRAY['solid'::text, 'gradient'::text, 'mix'::text, 'melange'::text]))));
alter table yarn_colors add constraint yarn_colors_pkey PRIMARY KEY (id);
alter table yarn_colors enable row level security;
-- acl: {postgres=arwdDxtm/postgres,authenticated=arwdm/postgres,service_role=arwdDxtm/postgres}

create table yarn_entries (
  id bigint not null,
  catalog_id uuid,
  work_id uuid,
  raw_name text not null,
  norm_name text,
  color text,
  amount numeric,
  unit text,
  ball_g numeric,
  ball_m numeric,
  weight text,
  fiber text,
  fibers jsonb,
  rating smallint,
  rating_reason text,
  needles jsonb not null default '[]'::jsonb,
  gauge text,
  techniques text[] not null default '{}'::text[],
  craft text,
  item_type text,
  maker_level smallint,
  created_at timestamp with time zone not null default now(),
  color_family text,
  source text not null default 'work'::text,
  color_hex text[],
  color_mode text,
  color_families text[]
);
alter table yarn_entries add constraint yarn_entries_catalog_id_fkey FOREIGN KEY (catalog_id) REFERENCES yarn_catalog(id) ON DELETE SET NULL;
alter table yarn_entries add constraint yarn_entries_color_mode_chk CHECK (((color_mode IS NULL) OR (color_mode = ANY (ARRAY['solid'::text, 'gradient'::text, 'mix'::text, 'melange'::text]))));
alter table yarn_entries add constraint yarn_entries_pkey PRIMARY KEY (id);
alter table yarn_entries add constraint yarn_entries_rating_check CHECK ((rating = ANY (ARRAY['-1'::integer, 0, 1])));
alter table yarn_entries add constraint yarn_entries_work_id_fkey FOREIGN KEY (work_id) REFERENCES works(id) ON DELETE SET NULL;
alter table yarn_entries enable row level security;
-- acl: {postgres=arwdDxtm/postgres,authenticated=rm/postgres,service_role=arwdDxtm/postgres}

create table yarn_guess_log (
  id bigint not null,
  norm_name text not null,
  raw_name text not null,
  catalog_id uuid,
  picked boolean not null,
  profile_id uuid,
  created_at timestamp with time zone not null default now()
);
alter table yarn_guess_log add constraint yarn_guess_log_catalog_id_fkey FOREIGN KEY (catalog_id) REFERENCES yarn_catalog(id) ON DELETE CASCADE;
alter table yarn_guess_log add constraint yarn_guess_log_pkey PRIMARY KEY (id);
alter table yarn_guess_log enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}

create table yarn_sellers (
  id bigint not null default nextval('yarn_sellers_id_seq'::regclass),
  catalog_id uuid not null,
  shop text not null,
  url text,
  price integer,
  put_up text,
  in_stock boolean,
  checked_at timestamp with time zone default now(),
  created_at timestamp with time zone default now()
);
alter table yarn_sellers add constraint yarn_sellers_catalog_id_fkey FOREIGN KEY (catalog_id) REFERENCES yarn_catalog(id) ON DELETE CASCADE;
alter table yarn_sellers add constraint yarn_sellers_catalog_id_shop_key UNIQUE (catalog_id, shop);
alter table yarn_sellers add constraint yarn_sellers_pkey PRIMARY KEY (id);
alter table yarn_sellers enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=arwd/postgres}

create table yarn_stash (
  id uuid not null default gen_random_uuid(),
  owner_id uuid not null default auth.uid(),
  catalog_id uuid,
  raw_name text,
  color text,
  color_family text,
  ball_g numeric(7,2),
  ball_m numeric(7,2),
  fiber text,
  fibers jsonb,
  weight text,
  bought_balls numeric(6,2) not null default 1,
  left_balls numeric(6,2) not null default 1,
  band_photo text,
  read_status text not null default 'manual'::text,
  read_json jsonb,
  edited text[] not null default '{}'::text[],
  created_at timestamp with time zone not null default now(),
  finished_at timestamp with time zone,
  color_hex text[],
  color_mode text,
  color_families text[],
  band_photo2 text,
  texture jsonb,
  brand text
);
alter table yarn_stash add constraint yarn_stash_ball_g_check CHECK ((ball_g > (0)::numeric));
alter table yarn_stash add constraint yarn_stash_ball_m_check CHECK ((ball_m > (0)::numeric));
alter table yarn_stash add constraint yarn_stash_bought_balls_check CHECK ((bought_balls >= (0)::numeric));
alter table yarn_stash add constraint yarn_stash_catalog_id_fkey FOREIGN KEY (catalog_id) REFERENCES yarn_catalog(id) ON DELETE SET NULL;
alter table yarn_stash add constraint yarn_stash_color_check CHECK ((char_length(color) <= 40));
alter table yarn_stash add constraint yarn_stash_color_mode_chk CHECK (((color_mode IS NULL) OR (color_mode = ANY (ARRAY['solid'::text, 'gradient'::text, 'mix'::text, 'melange'::text]))));
alter table yarn_stash add constraint yarn_stash_fiber_check CHECK ((char_length(fiber) <= 20));
alter table yarn_stash add constraint yarn_stash_left_balls_check CHECK ((left_balls >= (0)::numeric));
alter table yarn_stash add constraint yarn_stash_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table yarn_stash add constraint yarn_stash_pkey PRIMARY KEY (id);
alter table yarn_stash add constraint yarn_stash_raw_name_check CHECK ((char_length(raw_name) <= 60));
alter table yarn_stash add constraint yarn_stash_read_status_check CHECK ((read_status = ANY (ARRAY['pending'::text, 'done'::text, 'failed'::text, 'manual'::text])));
alter table yarn_stash add constraint yarn_stash_weight_check CHECK ((char_length(weight) <= 20));
alter table yarn_stash enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=arwd/postgres}

create table yarn_stash_log (
  id bigint not null default nextval('yarn_stash_log_id_seq'::regclass),
  stash_id uuid not null,
  work_id uuid,
  delta numeric(6,2) not null,
  created_at timestamp with time zone not null default now()
);
alter table yarn_stash_log add constraint yarn_stash_log_pkey PRIMARY KEY (id);
alter table yarn_stash_log add constraint yarn_stash_log_stash_id_fkey FOREIGN KEY (stash_id) REFERENCES yarn_stash(id) ON DELETE CASCADE;
alter table yarn_stash_log add constraint yarn_stash_log_stash_id_work_id_key UNIQUE (stash_id, work_id);
alter table yarn_stash_log enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}

create table yarn_web_lookup (
  catalog_id uuid not null,
  checked_at timestamp with time zone not null default now(),
  result text not null,
  filled jsonb,
  source_url text,
  note text
);
alter table yarn_web_lookup add constraint yarn_web_lookup_catalog_id_fkey FOREIGN KEY (catalog_id) REFERENCES yarn_catalog(id) ON DELETE CASCADE;
alter table yarn_web_lookup add constraint yarn_web_lookup_pkey PRIMARY KEY (catalog_id);
alter table yarn_web_lookup add constraint yarn_web_lookup_result_check CHECK ((result = ANY (ARRAY['filled'::text, 'partial'::text, 'not_found'::text, 'merged'::text, 'skipped'::text])));
alter table yarn_web_lookup enable row level security;
-- acl: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}

