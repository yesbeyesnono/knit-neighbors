-- access-logs-clean
select cron.schedule('access-logs-clean', '30 18 1 * *', $cron$delete from public.access_logs where created_at < now() - interval '400 days'$cron$);
-- account-purge
select cron.schedule('account-purge', '30 18 * * *', $cron$select public.jigi_remind_call('purge') where exists (select 1 from public.account_deletions where purged_at is null and purge_after <= now())$cron$);
-- broadcast-run-due
select cron.schedule('broadcast-run-due', '*/5 * * * *', $cron$select public.broadcast_run_due()$cron$);
-- cheer-daily
select cron.schedule('cheer-daily', '30 23 * * *', $cron$select public.cheer_daily()$cron$);
-- cron-log-clean
select cron.schedule('cron-log-clean', '50 18 * * *', $cron$delete from cron.job_run_details where start_time < now() - interval '14 days'$cron$);
-- dong-fix
select cron.schedule('dong-fix', '20 * * * *', $cron$select public.dong_fix_call() where exists (select 1 from public.dong_autofix_candidates())$cron$);
-- friend-chat-nudge
select cron.schedule('friend-chat-nudge', '0 1 * * *', $cron$select public.friend_chat_nudge()$cron$);
-- friend-rec-weekly
select cron.schedule('friend-rec-weekly', '0 1 * * 6', $cron$select public.friend_rec_weekly()$cron$);
-- friend-remind
select cron.schedule('friend-remind', '30 0-12 * * *', $cron$select public.friend_request_remind()$cron$);
-- jigi-brief
select cron.schedule('jigi-brief', '0 23 * * *', $cron$select public.jigi_call('brief')$cron$);
-- jigi-clean
select cron.schedule('jigi-clean', '15 20 * * *', $cron$delete from public.mod_pending where expires_at < now(); delete from public.jigi_chat where created_at < now() - interval '30 days'$cron$);
-- jigi-guard
select cron.schedule('jigi-guard', '7 * * * *', $cron$select public.jigi_remind_call('guard')$cron$);
-- jigi-remind
select cron.schedule('jigi-remind', '*/5 * * * *', $cron$select public.jigi_remind_call('tick')$cron$);
-- jigi-scan
select cron.schedule('jigi-scan', '*/10 * * * *', $cron$select public.jigi_call('scan')$cron$);
-- jigi-support-followup
select cron.schedule('jigi-support-followup', '0 1 * * *', $cron$select public.jigi_call('support_followup')$cron$);
-- jigi-support-learn
select cron.schedule('jigi-support-learn', '0 22 * * 0', $cron$select public.jigi_call('support_learn')$cron$);
-- jigi-support-sweep
select cron.schedule('jigi-support-sweep', '*/10 * * * *', $cron$select public.jigi_call('support')$cron$);
-- jigi-tech
select cron.schedule('jigi-tech', '30 19 * * *', $cron$select public.jigi_call('tech')$cron$);
-- jigi-yarn
select cron.schedule('jigi-yarn', '0 20 * * *', $cron$select public.jigi_call('yarn')$cron$);
-- last-seen-sync
select cron.schedule('last-seen-sync', '12 * * * *', $cron$select public.sync_last_seen()$cron$);
-- meetup-nearby
select cron.schedule('meetup-nearby', '*/10 * * * *', $cron$select public.meetup_nearby_notify()$cron$);
-- partner-guide-nudge
select cron.schedule('partner-guide-nudge', '0 1 * * *', $cron$select public.partner_guide_nudge()$cron$);
-- partner-invite-watch
select cron.schedule('partner-invite-watch', '*/10 * * * *', $cron$select public.partner_invite_watch()$cron$);
-- remind-daily
select cron.schedule('remind-daily', '0 9 * * *', $cron$select public.remind_daily()$cron$);
-- remind-tick
select cron.schedule('remind-tick', '*/30 * * * *', $cron$select public.remind_tick()$cron$);
-- report-case-tick
select cron.schedule('report-case-tick', '7 * * * *', $cron$select public.report_case_tick()$cron$);
-- storage-sweep
select cron.schedule('storage-sweep', '10 * * * *', $cron$select public.jigi_remind_call('sweep')$cron$);
-- trait-index-nightly
select cron.schedule('trait-index-nightly', '40 15 * * *', $cron$select public.refresh_all_trait_index()$cron$);
-- work-review-alert
select cron.schedule('work-review-alert', '*/15 * * * *', $cron$select public.work_review_alert()$cron$);
-- work-review-daily
select cron.schedule('work-review-daily', '0 0 * * *', $cron$select public.work_review_daily()$cron$);
