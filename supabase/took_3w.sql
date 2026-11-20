-- 158. 걸린 시간에 '3주'(3w) 받기 (2026-11-20 대표 확정 시안 took_scale_v2 C안 — 마이그레이션 took_3w)
--   앱의 고르는 칸이 하루 · 1주 · 2주 · 3주 · 한 달 · 더 오래 로 바뀜(막대가 오른쪽으로 갈수록 높아짐). '2~3일'(3d)은 새로 고를 수 없지만 옛 답은 그대로 둔다
alter table public.works drop constraint if exists works_story_chk;
alter table public.works add constraint works_story_chk check ((took is null or took in ('1d','3d','1w','2w','3w','1m','long')) and (knowhow is null or char_length(knowhow) <= 500) and (regret is null or char_length(regret) <= 300) and (review_note is null or char_length(review_note) <= 300));

create or replace function public.work_set_story(p_post uuid, p_story jsonb)
 returns void language plpgsql security definer set search_path to 'public' as $function$
declare v_work uuid; v_took text := nullif(btrim(coalesce(p_story->>'took','')), '');
  v_know text := nullif(left(btrim(coalesce(p_story->>'knowhow','')), 500), ''); v_reg text := nullif(left(btrim(coalesce(p_story->>'regret','')), 300), '');
  v_how text; v_note text; s public.work_sources;
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  select w.id into v_work from public.posts po join public.works w on w.id = po.work_id where po.id = p_post and w.profile_id = auth.uid();
  if v_work is null then raise exception '내 완성작품 인증이 아니에요'; end if;
  if v_took is not null and v_took not in ('1d','3d','1w','2w','3w','1m','long') then v_took := null; end if;
  if public.contains_banned(coalesce(v_know,'')||' '||coalesce(v_reg,'')) then raise exception '커뮤니티 가이드라인에 맞지 않는 표현이 있어요'; end if;
  update public.works set took = v_took, knowhow = v_know, regret = v_reg where id = v_work;
  if p_story ? 'how' then
    v_how := nullif(btrim(coalesce(p_story->>'how','')), '');
    if v_how is not null and v_how not in ('pattern','video','class','original') then v_how := null; end if;
    if v_how in ('pattern','video','class') then
      begin select * into s from public.work_sources where id = (p_story->>'src')::uuid; exception when others then s := null; end;
      if s.id is not null and s.merged_into is not null then select * into s from public.work_sources where id = s.merged_into; end if;
      if s.id is null or s.kind <> v_how or s.status = 'excluded' then v_how := null; s := null; end if;   -- 고르지 않았으면 비워 둔다
    elsif v_how = 'original' then
      v_note := nullif(left(btrim(coalesce(p_story->>'note','')), 60), '');
      if v_note is not null and (public.contains_banned(v_note) or v_note ~* '(https?:|www\.|@)') then raise exception '한 줄 설명에 쓸 수 없는 표현이 있어요'; end if;
    end if;
    update public.works set made_how = v_how, source_id = case when v_how in ('pattern','video','class') then s.id end, source_note = case when v_how = 'original' then v_note end,
      pattern_source = case when v_how in ('pattern','video','class') then nullif(btrim(s.maker || ' · ' || s.title, ' ·'), '') when v_how = 'original' then '창작' end
    where id = v_work;
  end if;
end $function$;
