create policy "access_logs_admin_read" on public.access_logs for SELECT to authenticated using (is_admin());
create policy "account_deletions_own" on public.account_deletions for SELECT to authenticated using ((user_id = auth.uid()));
create policy "admin_logs_select" on public.admin_logs for SELECT to authenticated using (is_admin());
create policy "admins_admin_select" on public.admins for SELECT to authenticated using (is_admin());
create policy "ai_briefings_admin_read" on public.ai_briefings for SELECT to authenticated using (is_admin());
create policy "ai_rules_admin_read" on public.ai_rules for SELECT to authenticated using (is_admin());
create policy "app_config_read" on public.app_config for SELECT to anon,authenticated using (true);
create policy "author_app_delete" on public.author_applications for DELETE to authenticated using (((profile_id = ( SELECT auth.uid() AS uid)) AND (status = 'pending'::text)));
create policy "author_app_select" on public.author_applications for SELECT to authenticated using (((profile_id = ( SELECT auth.uid() AS uid)) OR is_admin()));
create policy "author_follows_own_delete" on public.author_follows for DELETE to public using ((profile_id = ( SELECT auth.uid() AS uid)));
create policy "author_follows_own_insert" on public.author_follows for INSERT to public with check (((profile_id = ( SELECT auth.uid() AS uid)) AND is_active_user() AND (EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = author_follows.author_id) AND p.is_author AND (p.suspended_at IS NULL) AND (p.deleted_at IS NULL)))) AND (NOT is_blocked(profile_id, author_id))));
create policy "author_follows_own_select" on public.author_follows for SELECT to public using (((profile_id = ( SELECT auth.uid() AS uid)) OR (author_id = ( SELECT auth.uid() AS uid)) OR is_admin()));
create policy "bad_words_admin_read" on public.bad_words for SELECT to authenticated using (is_admin());
create policy "banned_words_admin_write" on public.banned_words for ALL to authenticated using (is_admin()) with check (is_admin());
create policy "banned_words_read" on public.banned_words for SELECT to authenticated using (true);
create policy "broadcast_segments_admin" on public.broadcast_segments for ALL to public using (is_admin()) with check (is_admin());
create policy "broadcasts_admin" on public.broadcasts for ALL to public using (is_admin()) with check (is_admin());
create policy "cart_own" on public.cart_items for ALL to authenticated using ((profile_id = ( SELECT auth.uid() AS uid))) with check ((profile_id = ( SELECT auth.uid() AS uid)));
create policy "class_apps_select" on public.class_applications for SELECT to authenticated using (((profile_id = ( SELECT auth.uid() AS uid)) OR (class_host(post_id) = ( SELECT auth.uid() AS uid)) OR is_admin()));
create policy "color_lexicon_read" on public.color_lexicon for SELECT to authenticated using (true);
create policy "device_tokens_own" on public.device_tokens for SELECT to authenticated using ((profile_id = ( SELECT auth.uid() AS uid)));
create policy "dong_fix_log_admin" on public.dong_fix_log for SELECT to authenticated using (is_admin());
create policy "event_apps_select" on public.event_applications for SELECT to authenticated using (((profile_id = ( SELECT auth.uid() AS uid)) OR is_admin()));
create policy "event_ship_select" on public.event_shipping for SELECT to authenticated using (((profile_id = ( SELECT auth.uid() AS uid)) OR is_admin()));
create policy "events_select" on public.events for SELECT to authenticated using (((status <> 'draft'::text) OR is_admin()));
create policy "feedback_groups_admin_read" on public.feedback_groups for SELECT to authenticated using (is_admin());
create policy "feedback_own" on public.feedback_reports for SELECT to authenticated using (((user_id = ( SELECT auth.uid() AS uid)) OR is_admin()));
create policy "friendships_admin_select" on public.friendships for SELECT to authenticated using (is_admin());
create policy "friendships_delete_own_request" on public.friendships for DELETE to authenticated using (((requester_id = ( SELECT auth.uid() AS uid)) AND (status = 'pending'::friendship_status)));
create policy "friendships_insert" on public.friendships for INSERT to authenticated with check (((requester_id = ( SELECT auth.uid() AS uid)) AND (status = 'pending'::friendship_status)));
create policy "friendships_select" on public.friendships for SELECT to authenticated using (((requester_id = ( SELECT auth.uid() AS uid)) OR (addressee_id = ( SELECT auth.uid() AS uid))));
create policy "friendships_update" on public.friendships for UPDATE to authenticated using (((addressee_id = ( SELECT auth.uid() AS uid)) OR (requester_id = ( SELECT auth.uid() AS uid)))) with check ((((addressee_id = ( SELECT auth.uid() AS uid)) AND (status = ANY (ARRAY['accepted'::friendship_status, 'declined'::friendship_status, 'blocked'::friendship_status]))) OR ((requester_id = ( SELECT auth.uid() AS uid)) AND (status = 'blocked'::friendship_status))));
create policy "jigi_reminders_admin_read" on public.jigi_reminders for SELECT to authenticated using (is_admin());
create policy "meetup_applications_select" on public.meetup_applications for SELECT to public using (((profile_id = ( SELECT auth.uid() AS uid)) OR is_admin() OR (EXISTS ( SELECT 1
   FROM meetups m
  WHERE ((m.id = meetup_applications.meetup_id) AND (m.created_by = ( SELECT auth.uid() AS uid)))))));
create policy "meetups_admin_select" on public.meetups for SELECT to authenticated using (is_admin());
create policy "meetups_delete_creator" on public.meetups for DELETE to authenticated using ((created_by = ( SELECT auth.uid() AS uid)));
create policy "meetups_select" on public.meetups for SELECT to authenticated using ((((NOT hidden) AND (is_public OR is_room_member(room_id))) OR (created_by = ( SELECT auth.uid() AS uid))));
create policy "meetups_update_creator" on public.meetups for UPDATE to authenticated using ((created_by = ( SELECT auth.uid() AS uid))) with check ((created_by = ( SELECT auth.uid() AS uid)));
create policy "messages_admin_select" on public.messages for SELECT to authenticated using (is_admin());
create policy "messages_insert" on public.messages for INSERT to authenticated with check (((sender_id = ( SELECT auth.uid() AS uid)) AND is_room_member(room_id) AND is_active_user()));
create policy "messages_select" on public.messages for SELECT to authenticated using (is_room_member(room_id));
create policy "mod_actions_admin_read" on public.mod_actions for SELECT to authenticated using (is_admin());
create policy "mod_items_admin_read" on public.mod_items for SELECT to authenticated using (is_admin());
create policy "news_read" on public.news_posts for SELECT to authenticated using ((active AND (published_at <= now())));
create policy "notif_delete" on public.notifications for DELETE to authenticated using ((recipient_id = ( SELECT auth.uid() AS uid)));
create policy "notif_select" on public.notifications for SELECT to authenticated using ((recipient_id = ( SELECT auth.uid() AS uid)));
create policy "notif_update" on public.notifications for UPDATE to authenticated using ((recipient_id = ( SELECT auth.uid() AS uid))) with check ((recipient_id = ( SELECT auth.uid() AS uid)));
create policy "notifications_admin_select" on public.notifications for SELECT to authenticated using (is_admin());
create policy "orders_own_select" on public.orders for SELECT to authenticated using (((profile_id = ( SELECT auth.uid() AS uid)) OR is_admin()));
create policy "pattern_contents_select" on public.pattern_contents for SELECT to authenticated using ((is_admin() OR (EXISTS ( SELECT 1
   FROM patterns p
  WHERE ((p.id = pattern_contents.pattern_id) AND ((p.author_id = ( SELECT auth.uid() AS uid)) OR (p.is_published AND (NOT p.hidden) AND ((p.price = 0) OR (EXISTS ( SELECT 1
           FROM pattern_purchases pp
          WHERE ((pp.pattern_id = p.id) AND (pp.profile_id = ( SELECT auth.uid() AS uid)))))))))))));
create policy "pattern_progress_own" on public.pattern_progress for ALL to authenticated using ((profile_id = ( SELECT auth.uid() AS uid))) with check ((profile_id = ( SELECT auth.uid() AS uid)));
create policy "purchases_select" on public.pattern_purchases for SELECT to authenticated using (((profile_id = ( SELECT auth.uid() AS uid)) OR is_admin() OR (EXISTS ( SELECT 1
   FROM patterns p
  WHERE ((p.id = pattern_purchases.pattern_id) AND (p.author_id = ( SELECT auth.uid() AS uid)))))));
create policy "pattern_saves_own" on public.pattern_saves for ALL to authenticated using ((profile_id = ( SELECT auth.uid() AS uid))) with check ((profile_id = ( SELECT auth.uid() AS uid)));
create policy "patterns_delete_own" on public.patterns for DELETE to authenticated using ((author_id = ( SELECT auth.uid() AS uid)));
create policy "patterns_select" on public.patterns for SELECT to authenticated using (((is_published AND (NOT hidden)) OR (author_id = ( SELECT auth.uid() AS uid)) OR is_admin()));
create policy "points_own" on public.point_events for SELECT to authenticated using (((user_id = ( SELECT auth.uid() AS uid)) OR is_admin()));
create policy "post_likes_admin_select" on public.post_likes for SELECT to authenticated using (is_admin());
create policy "post_likes_delete_own" on public.post_likes for DELETE to authenticated using ((profile_id = ( SELECT auth.uid() AS uid)));
create policy "post_likes_insert_own" on public.post_likes for INSERT to authenticated with check ((profile_id = ( SELECT auth.uid() AS uid)));
create policy "post_likes_select" on public.post_likes for SELECT to authenticated using (true);
create policy "post_reports_admin_select" on public.post_reports for SELECT to authenticated using (is_admin());
create policy "post_reports_insert" on public.post_reports for INSERT to authenticated with check (((reporter_id = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM posts p
  WHERE ((p.id = post_reports.post_id) AND (p.author_id <> ( SELECT auth.uid() AS uid)))))));
create policy "post_reposts_delete_own" on public.post_reposts for DELETE to authenticated using ((profile_id = ( SELECT auth.uid() AS uid)));
create policy "post_reposts_insert_own" on public.post_reposts for INSERT to authenticated with check (((profile_id = ( SELECT auth.uid() AS uid)) AND is_active_user() AND (EXISTS ( SELECT 1
   FROM posts p
  WHERE ((p.id = post_reposts.post_id) AND (p.parent_id IS NULL) AND (p.author_id <> ( SELECT auth.uid() AS uid)))))));
create policy "post_reposts_select" on public.post_reposts for SELECT to authenticated using (true);
create policy "posts_admin_select" on public.posts for SELECT to authenticated using (is_admin());
create policy "posts_delete_own" on public.posts for DELETE to authenticated using ((author_id = ( SELECT auth.uid() AS uid)));
create policy "posts_insert_own" on public.posts for INSERT to authenticated with check (((author_id = ( SELECT auth.uid() AS uid)) AND (meetup_id IS NULL) AND (work_id IS NULL) AND (review_of IS NULL) AND is_active_user()));
create policy "posts_select" on public.posts for SELECT to authenticated using ((((NOT hidden) OR (author_id = ( SELECT auth.uid() AS uid))) AND (NOT is_blocked(( SELECT auth.uid() AS uid), author_id)) AND (EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = posts.author_id) AND (p.suspended_at IS NULL) AND ((NOT p.is_test) OR ( SELECT is_test_user(( SELECT auth.uid() AS uid)) AS is_test_user)))))));
create policy "profiles_admin_select" on public.profiles for SELECT to authenticated using (is_admin());
create policy "profiles_select" on public.profiles for SELECT to authenticated using (((id = ( SELECT auth.uid() AS uid)) OR ((suspended_at IS NULL) AND (NOT is_blocked(( SELECT auth.uid() AS uid), id)))));
create policy "profiles_update_own" on public.profiles for UPDATE to authenticated using ((id = ( SELECT auth.uid() AS uid))) with check ((id = ( SELECT auth.uid() AS uid)));
create policy "referrals_own" on public.referrals for SELECT to authenticated using (((inviter_user_id = ( SELECT auth.uid() AS uid)) OR (invitee_user_id = ( SELECT auth.uid() AS uid)) OR is_admin()));
create policy "report_cases_admin_select" on public.report_cases for SELECT to authenticated using (is_admin());
create policy "reports_admin_select" on public.reports for SELECT to authenticated using (is_admin());
create policy "reports_insert" on public.reports for INSERT to authenticated with check (((reporter_id = ( SELECT auth.uid() AS uid)) AND (reporter_id <> reported_id)));
create policy "room_members_admin_select" on public.room_members for SELECT to authenticated using (is_admin());
create policy "room_members_insert" on public.room_members for INSERT to authenticated with check ((((profile_id = ( SELECT auth.uid() AS uid)) AND is_room_creator(room_id)) OR (is_room_member(room_id) AND is_friend(( SELECT auth.uid() AS uid), profile_id))));
create policy "room_members_leave" on public.room_members for DELETE to authenticated using ((profile_id = ( SELECT auth.uid() AS uid)));
create policy "room_members_select" on public.room_members for SELECT to authenticated using (is_room_member(room_id));
create policy "room_members_update_own" on public.room_members for UPDATE to authenticated using ((profile_id = ( SELECT auth.uid() AS uid)));
create policy "rooms_admin_select" on public.rooms for SELECT to authenticated using (is_admin());
create policy "rooms_insert_group" on public.rooms for INSERT to authenticated with check (((kind = 'group'::room_kind) AND (created_by = ( SELECT auth.uid() AS uid))));
create policy "rooms_select" on public.rooms for SELECT to authenticated using (is_room_member(id));
create policy "rooms_update_creator" on public.rooms for UPDATE to authenticated using ((created_by = ( SELECT auth.uid() AS uid)));
create policy "shop_claims_delete" on public.shop_claims for DELETE to authenticated using (((profile_id = ( SELECT auth.uid() AS uid)) AND (status = 'pending'::text)));
create policy "shop_claims_insert" on public.shop_claims for INSERT to authenticated with check (((profile_id = ( SELECT auth.uid() AS uid)) AND (status = 'pending'::text) AND (decided_by IS NULL) AND (decided_at IS NULL) AND (reject_reason IS NULL)));
create policy "shop_claims_select" on public.shop_claims for SELECT to authenticated using (((profile_id = ( SELECT auth.uid() AS uid)) OR is_admin()));
create policy "shop_follows_own" on public.shop_follows for ALL to authenticated using ((profile_id = ( SELECT auth.uid() AS uid))) with check ((profile_id = ( SELECT auth.uid() AS uid)));
create policy "shop_follows_shop_owner_select" on public.shop_follows for SELECT to authenticated using (((EXISTS ( SELECT 1
   FROM shops s
  WHERE ((s.id = shop_follows.shop_id) AND (s.owner_id = ( SELECT auth.uid() AS uid))))) OR is_admin()));
create policy "shop_posts_delete_author" on public.shop_posts for DELETE to authenticated using (((shop_id IS NULL) AND (author_id = ( SELECT auth.uid() AS uid))));
create policy "shop_posts_delete_owner" on public.shop_posts for DELETE to authenticated using ((EXISTS ( SELECT 1
   FROM shops s
  WHERE ((s.id = shop_posts.shop_id) AND (s.owner_id = ( SELECT auth.uid() AS uid))))));
create policy "shop_posts_insert_author" on public.shop_posts for INSERT to authenticated with check (((shop_id IS NULL) AND (kind = 'class'::text) AND (author_id = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = ( SELECT auth.uid() AS uid)) AND p.is_author AND (p.suspended_at IS NULL))))));
create policy "shop_posts_insert_owner" on public.shop_posts for INSERT to authenticated with check (((author_id = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM shops s
  WHERE ((s.id = shop_posts.shop_id) AND (s.owner_id = ( SELECT auth.uid() AS uid)) AND s.is_active)))));
create policy "shop_posts_select" on public.shop_posts for SELECT to authenticated using (((NOT hidden) OR (EXISTS ( SELECT 1
   FROM shops s
  WHERE ((s.id = shop_posts.shop_id) AND (s.owner_id = ( SELECT auth.uid() AS uid))))) OR is_admin()));
create policy "shop_posts_update_author" on public.shop_posts for UPDATE to authenticated using (((shop_id IS NULL) AND (author_id = ( SELECT auth.uid() AS uid))));
create policy "shop_posts_update_owner" on public.shop_posts for UPDATE to authenticated using ((EXISTS ( SELECT 1
   FROM shops s
  WHERE ((s.id = shop_posts.shop_id) AND (s.owner_id = ( SELECT auth.uid() AS uid))))));
create policy "products_select" on public.shop_products for SELECT to authenticated using ((is_active OR is_admin()));
create policy "shop_reads_admin_select" on public.shop_reads for SELECT to authenticated using (is_admin());
create policy "shop_reads_own" on public.shop_reads for ALL to authenticated using ((profile_id = ( SELECT auth.uid() AS uid))) with check ((profile_id = ( SELECT auth.uid() AS uid)));
create policy "shops_select" on public.shops for SELECT to authenticated using ((is_active OR (owner_id = ( SELECT auth.uid() AS uid)) OR is_admin()));
create policy "shops_update_owner" on public.shops for UPDATE to authenticated using ((owner_id = ( SELECT auth.uid() AS uid))) with check ((owner_id = ( SELECT auth.uid() AS uid)));
create policy "skill_events_admin_select" on public.skill_events for SELECT to authenticated using (is_admin());
create policy "studio_inbox_owner_delete" on public.studio_inbox for DELETE to authenticated using ((profile_id = auth.uid()));
create policy "studio_inbox_owner_select" on public.studio_inbox for SELECT to authenticated using ((profile_id = auth.uid()));
create policy "support_events_admin_read" on public.support_events for SELECT to authenticated using (is_admin());
create policy "support_kb_admin_read" on public.support_kb for SELECT to authenticated using (is_admin());
create policy "support_kb_candidates_admin_read" on public.support_kb_candidates for SELECT to authenticated using (is_admin());
create policy "support_tickets_admin_read" on public.support_tickets for SELECT to authenticated using (is_admin());
create policy "cohorts_read" on public.supporter_cohorts for SELECT to authenticated using (true);
create policy "notices_own" on public.supporter_notices for SELECT to authenticated using (is_admin());
create policy "waitlist_own" on public.supporter_waitlist for SELECT to authenticated using (((user_id = ( SELECT auth.uid() AS uid)) OR is_admin()));
create policy "supporters_own" on public.supporters for SELECT to authenticated using (((user_id = ( SELECT auth.uid() AS uid)) OR is_admin()));
create policy "responses_own" on public.survey_responses for SELECT to authenticated using (((user_id = ( SELECT auth.uid() AS uid)) OR is_admin()));
create policy "surveys_read" on public.surveys for SELECT to authenticated using (true);
create policy "tag_hidden_read" on public.tag_hidden for SELECT to authenticated using (true);
create policy "technique_aliases_admin_read" on public.technique_aliases for SELECT to authenticated using (is_admin());
create policy "technique_aliases_read" on public.technique_aliases for SELECT to authenticated using (true);
create policy "technique_candidates_admin_read" on public.technique_candidates for SELECT to authenticated using (is_admin());
create policy "techniques_read" on public.techniques for SELECT to authenticated using (true);
create policy "works_admin_select" on public.works for SELECT to authenticated using (is_admin());
create policy "works_delete_own" on public.works for DELETE to authenticated using ((profile_id = ( SELECT auth.uid() AS uid)));
create policy "works_select" on public.works for SELECT to authenticated using ((NOT is_blocked(( SELECT auth.uid() AS uid), profile_id)));
create policy "yba_admin" on public.yarn_brand_aliases for ALL to authenticated using (is_admin()) with check (is_admin());
create policy "yba_admin_read" on public.yarn_brand_aliases for SELECT to authenticated using (is_admin());
create policy "yarn_catalog_admin_read" on public.yarn_catalog for SELECT to authenticated using (is_admin());
create policy "yarn_colors_admin_read" on public.yarn_colors for SELECT to authenticated using (is_admin());
create policy "yarn_colors_admin_write" on public.yarn_colors for ALL to authenticated using (is_admin()) with check (is_admin());
create policy "yarn_entries_admin" on public.yarn_entries for SELECT to authenticated using (is_admin());
create policy "ys_admin" on public.yarn_sellers for ALL to authenticated using (is_admin()) with check (is_admin());
create policy "ys_admin_read" on public.yarn_sellers for SELECT to authenticated using (is_admin());
create policy "stash_admin_select" on public.yarn_stash for SELECT to authenticated using (is_admin());
create policy "stash_own" on public.yarn_stash for ALL to authenticated using ((owner_id = ( SELECT auth.uid() AS uid))) with check ((owner_id = ( SELECT auth.uid() AS uid)));
create policy "stash_log_select" on public.yarn_stash_log for SELECT to authenticated using ((is_admin() OR (EXISTS ( SELECT 1
   FROM yarn_stash s
  WHERE ((s.id = yarn_stash_log.stash_id) AND (s.owner_id = ( SELECT auth.uid() AS uid)))))));
create policy "bands_admin_read" on storage.objects for SELECT to authenticated using (((bucket_id = 'bands'::text) AND is_admin()));
create policy "bands_own_all" on storage.objects for ALL to authenticated using (((bucket_id = 'bands'::text) AND ((storage.foldername(name))[1] = (( SELECT auth.uid() AS uid))::text))) with check (((bucket_id = 'bands'::text) AND ((storage.foldername(name))[1] = (( SELECT auth.uid() AS uid))::text)));
create policy "feedback_own_insert" on storage.objects for INSERT to authenticated with check (((bucket_id = 'feedback'::text) AND ((storage.foldername(name))[1] = (( SELECT auth.uid() AS uid))::text)));
create policy "feedback_read" on storage.objects for SELECT to authenticated using (((bucket_id = 'feedback'::text) AND (((storage.foldername(name))[1] = (( SELECT auth.uid() AS uid))::text) OR is_admin())));
create policy "shops_bucket_del" on storage.objects for DELETE to authenticated using (((bucket_id = 'shops'::text) AND (EXISTS ( SELECT 1
   FROM shops s
  WHERE (((s.id)::text = (storage.foldername(objects.name))[1]) AND (s.owner_id = auth.uid()))))));
create policy "shops_bucket_del_admin" on storage.objects for DELETE to authenticated using (((bucket_id = 'shops'::text) AND is_admin()));
create policy "shops_bucket_ins" on storage.objects for INSERT to authenticated with check (((bucket_id = 'shops'::text) AND (EXISTS ( SELECT 1
   FROM shops s
  WHERE (((s.id)::text = (storage.foldername(objects.name))[1]) AND (s.owner_id = auth.uid()))))));
create policy "shops_bucket_read" on storage.objects for SELECT to public using ((bucket_id = 'shops'::text));
create policy "shops_bucket_upd" on storage.objects for UPDATE to authenticated using (((bucket_id = 'shops'::text) AND (EXISTS ( SELECT 1
   FROM shops s
  WHERE (((s.id)::text = (storage.foldername(objects.name))[1]) AND (s.owner_id = auth.uid()))))));
create policy "storage_chat_photos_admin_read" on storage.objects for SELECT to authenticated using (((bucket_id = 'chat-photos'::text) AND is_admin()));
create policy "storage_chat_photos_read" on storage.objects for SELECT to authenticated using (((bucket_id = 'chat-photos'::text) AND is_room_member(((storage.foldername(name))[2])::uuid)));
create policy "storage_delete_own_folder" on storage.objects for DELETE to authenticated using (((storage.foldername(name))[1] = (( SELECT auth.uid() AS uid))::text));
create policy "storage_insert_own_folder" on storage.objects for INSERT to authenticated with check (((bucket_id = ANY (ARRAY['avatars'::text, 'works'::text, 'chat-photos'::text])) AND ((storage.foldername(name))[1] = (( SELECT auth.uid() AS uid))::text)));
create policy "storage_posts_delete_own" on storage.objects for DELETE to authenticated using (((bucket_id = 'posts'::text) AND ((storage.foldername(name))[1] = (( SELECT auth.uid() AS uid))::text)));
create policy "storage_posts_insert_own" on storage.objects for INSERT to authenticated with check (((bucket_id = 'posts'::text) AND ((storage.foldername(name))[1] = (( SELECT auth.uid() AS uid))::text)));
create policy "storage_posts_read" on storage.objects for SELECT to public using ((bucket_id = 'posts'::text));
create policy "storage_public_read" on storage.objects for SELECT to public using ((bucket_id = ANY (ARRAY['avatars'::text, 'works'::text])));
create policy "storage_shop_docs_delete" on storage.objects for DELETE to authenticated using (((bucket_id = 'shop-docs'::text) AND (((storage.foldername(name))[1] = (( SELECT auth.uid() AS uid))::text) OR is_admin())));
create policy "storage_shop_docs_insert" on storage.objects for INSERT to authenticated with check (((bucket_id = 'shop-docs'::text) AND ((storage.foldername(name))[1] = (( SELECT auth.uid() AS uid))::text)));
create policy "storage_shop_docs_read" on storage.objects for SELECT to authenticated using (((bucket_id = 'shop-docs'::text) AND (((storage.foldername(name))[1] = (( SELECT auth.uid() AS uid))::text) OR is_admin())));
create policy "storage_update_own_folder" on storage.objects for UPDATE to authenticated using (((storage.foldername(name))[1] = (( SELECT auth.uid() AS uid))::text));
create policy "yarn_colors_admin_write" on storage.objects for ALL to authenticated using (((bucket_id = 'yarn-colors'::text) AND is_admin())) with check (((bucket_id = 'yarn-colors'::text) AND is_admin()));
create policy "yarn_colors_read" on storage.objects for SELECT to public using ((bucket_id = 'yarn-colors'::text));
create policy "yarn_import_read" on storage.objects for SELECT to public using ((bucket_id = 'yarn-import'::text));
