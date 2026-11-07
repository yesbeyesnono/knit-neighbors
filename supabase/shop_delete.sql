-- 85. 가게 삭제 (마이그레이션 shop_delete, 2026-11-07 대표 "가게를 삭제하는 기능이 빠졌다")
--   delete_my_shop(p_shop): 오너 본인. 모집 중(마감 전·시작 전)인 클래스에 확정 수강생이 있으면 거부.
--     가게·소식·클래스·신청·팔로우·열람·알림(shop_id) cascade, shop_claims.shop_id 는 set null.
--     Storage 'shops/<id>/…' 는 함수가 못 지움(Supabase protect_delete: storage.objects 직접 delete 금지) → 앱·콘솔이 rpc 전에 Storage API 로 list→remove(보강 shop_delete_fix).
--     반환 {ok,name}. 앱: 내 가게 관리 시트 맨 아래 [가게 삭제] → '삭제' 입력 확인.
--   admin_delete_shop(p_shop, p_reason, p_notify): 관리자. admin_log 'delete_shop', p_notify 면 오너에게 mod_notify_delete.
--     콘솔 › 파트너 가게 › 가게 패널 [가게 삭제]. storage 정책 shops_bucket_del_admin(관리자가 shops 버킷 삭제 가능).

create or replace function public.delete_my_shop(p_shop uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
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
end $$;
revoke all on function public.delete_my_shop(uuid) from public, anon;
grant execute on function public.delete_my_shop(uuid) to authenticated;

create or replace function public.admin_delete_shop(p_shop uuid, p_reason text default null, p_notify boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare v_owner uuid; v_name text;
begin
  if not public.is_admin() then raise exception '관리자만 가능합니다'; end if;
  select owner_id, name into v_owner, v_name from public.shops where id = p_shop;
  if v_name is null then raise exception '가게를 찾을 수 없어요'; end if;
  perform public.admin_log('delete_shop', 'shop', p_shop::text, jsonb_build_object('reason', p_reason, 'notify', p_notify, 'name', v_name, 'owner', v_owner));
  if p_notify then perform public.mod_notify_delete(v_owner, '가게('||v_name||')', p_reason); end if;
  delete from public.shops where id = p_shop;
end $$;
revoke all on function public.admin_delete_shop(uuid, text, boolean) from public, anon;
grant execute on function public.admin_delete_shop(uuid, text, boolean) to authenticated;

drop policy if exists shops_bucket_del_admin on storage.objects;
create policy shops_bucket_del_admin on storage.objects for delete to authenticated
  using (bucket_id = 'shops' and public.is_admin());
