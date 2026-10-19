-- 75. 커머스 데모(Lab) — 2026-10-19 대표 지시: 작가 설명회용. 실 판매(무통장) + 도안 구매(임시 무료) + 작가 정산 + 실함→뜰 수 있는 도안
--   원칙: 가격·수수료·재고·주문 금액은 전부 서버 함수가 계산(클라이언트 값 불신). 배송지는 1급 데이터(본인·관리자만, 관리자 조회는 log_access).
--   돈 흐름(도안): 판매가 → 스토어 수수료 30% → 플랫폼 15% → 원천징수 3.3% → 작가 지급 (pattern_fee_calc). 지금은 via='demo_free'(실결제 없음)

-- ---------- 실 판매 상품 ----------
create table if not exists public.shop_products (
  id uuid primary key default gen_random_uuid(),
  catalog_id uuid references public.yarn_catalog(id) on delete set null,
  name text not null, brand text, descr text,
  price int not null check (price >= 0), stock int not null default 0 check (stock >= 0),
  ball_g numeric, ball_m numeric, photo text,
  colors jsonb not null default '[]'::jsonb,          -- [{no,name,photo,hex}]
  is_active boolean not null default true, sort int not null default 0,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now());
alter table public.shop_products enable row level security;
revoke all on public.shop_products from anon, authenticated;
grant select on public.shop_products to authenticated;   -- 쓰기는 admin_product_upsert/admin_product_delete 로만(보완 마이그레이션 commerce_demo_v1_fix)
grant all on public.shop_products to service_role;
drop policy if exists products_select on public.shop_products;
create policy products_select on public.shop_products for select to authenticated using (is_active or public.is_admin());

create table if not exists public.cart_items (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  product_id uuid not null references public.shop_products(id) on delete cascade,
  color text not null default '',
  qty int not null check (qty > 0 and qty <= 99),
  created_at timestamptz not null default now(),
  primary key (profile_id, product_id, color));
alter table public.cart_items enable row level security;
revoke all on public.cart_items from anon, authenticated;
grant select, insert, update, delete on public.cart_items to authenticated;
grant all on public.cart_items to service_role;
drop policy if exists cart_own on public.cart_items;
create policy cart_own on public.cart_items for all to authenticated using (profile_id = (select auth.uid())) with check (profile_id = (select auth.uid()));

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  no text not null unique,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending_payment' check (status in ('pending_payment','paid','shipped','done','cancelled')),
  items jsonb not null,                                -- [{product_id,name,color,qty,price}]
  subtotal int not null, shipping_fee int not null default 0, total int not null,
  ship_name text, ship_phone text, ship_addr text, ship_memo text,
  pay_method text not null default 'bank', depositor text,
  paid_at timestamptz, shipped_at timestamptz, tracking text, note text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now());
alter table public.orders enable row level security;
revoke all on public.orders from anon, authenticated;
grant select on public.orders to authenticated;
grant all on public.orders to service_role;
drop policy if exists orders_own_select on public.orders;
create policy orders_own_select on public.orders for select to authenticated using (profile_id = (select auth.uid()) or public.is_admin());
create index if not exists orders_profile_idx on public.orders(profile_id, created_at desc);

-- 주문 만들기: 장바구니 → 서버가 가격·재고·배송비 계산 → 주문 + 재고 차감 + 장바구니 비움
create or replace function public.place_order(p_ship jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
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
end $$;
revoke all on function public.place_order(jsonb) from public, anon; grant execute on function public.place_order(jsonb) to authenticated;

create or replace function public.cancel_my_order(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare o record; x jsonb;
begin
  select * into o from public.orders where id = p_id and profile_id = auth.uid();
  if o.id is null then raise exception '주문을 찾을 수 없어요'; end if;
  if o.status <> 'pending_payment' then raise exception '입금 확인 전 주문만 취소할 수 있어요'; end if;
  for x in select * from jsonb_array_elements(o.items) loop update public.shop_products set stock = stock + (x->>'qty')::int where id = (x->>'product_id')::uuid; end loop;
  update public.orders set status = 'cancelled', updated_at = now() where id = p_id;
end $$;
revoke all on function public.cancel_my_order(uuid) from public, anon; grant execute on function public.cancel_my_order(uuid) to authenticated;

create or replace function public.my_orders()
returns setof public.orders language sql security definer set search_path = public as $$
  select * from public.orders where profile_id = auth.uid() order by created_at desc limit 50 $$;
revoke all on function public.my_orders() from public, anon; grant execute on function public.my_orders() to authenticated;

-- 관리자: 주문 목록(배송지 포함 → 접근 기록) · 상태 변경(입금 확인 → paid, 발송 → shipped(+송장), 완료, 취소(재고 복원)) · 매출 요약
create or replace function public.admin_orders(p_status text default null, p_limit int default 100)
returns jsonb language plpgsql security definer set search_path = public as $$
declare out jsonb;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  perform public.log_access('orders', coalesce(p_status, 'all'), p_limit);
  select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'no', o.no, 'status', o.status, 'items', o.items, 'subtotal', o.subtotal, 'shipping_fee', o.shipping_fee, 'total', o.total,
      'ship_name', o.ship_name, 'ship_phone', o.ship_phone, 'ship_addr', o.ship_addr, 'ship_memo', o.ship_memo, 'depositor', o.depositor, 'paid_at', o.paid_at, 'shipped_at', o.shipped_at, 'tracking', o.tracking, 'note', o.note,
      'created_at', o.created_at, 'nickname', pr.nickname) order by o.created_at desc), '[]'::jsonb) into out
    from (select * from public.orders where p_status is null or status = p_status order by created_at desc limit p_limit) o left join public.profiles pr on pr.id = o.profile_id;
  return out;
end $$;
revoke all on function public.admin_orders(text, int) from public, anon; grant execute on function public.admin_orders(text, int) to authenticated;

create or replace function public.admin_order_set(p_id uuid, p_status text, p_tracking text default null, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
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
end $$;
revoke all on function public.admin_order_set(uuid, text, text, text) from public, anon; grant execute on function public.admin_order_set(uuid, text, text, text) to authenticated;

create or replace function public.admin_product_upsert(p jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
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
end $$;
revoke all on function public.admin_product_upsert(jsonb) from public, anon; grant execute on function public.admin_product_upsert(jsonb) to authenticated;

create or replace function public.shop_stats(p_days int default 30)
returns jsonb language plpgsql security definer set search_path = public as $$
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
end $$;
revoke all on function public.shop_stats(int) from public, anon; grant execute on function public.shop_stats(int) to authenticated;

-- ---------- 도안 구매(임시 무료) · 정산 ----------
create table if not exists public.pattern_purchases (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  pattern_id uuid not null references public.patterns(id) on delete cascade,
  price int not null, store_fee int not null, platform_fee int not null, tax int not null, author_amt int not null,
  via text not null default 'demo_free',
  created_at timestamptz not null default now(),
  primary key (profile_id, pattern_id));
alter table public.pattern_purchases enable row level security;
revoke all on public.pattern_purchases from anon, authenticated;
grant select on public.pattern_purchases to authenticated;
grant all on public.pattern_purchases to service_role;
drop policy if exists purchases_select on public.pattern_purchases;
create policy purchases_select on public.pattern_purchases for select to authenticated
  using (profile_id = (select auth.uid()) or public.is_admin() or exists (select 1 from public.patterns p where p.id = pattern_id and p.author_id = (select auth.uid())));

-- 수수료 계산(대표 확정 2026-09-19): 판매가 − 스토어 30% − 플랫폼 15%(스토어 공제 후) − 원천징수 3.3% → 작가 지급
create or replace function public.pattern_fee_calc(p_price int)
returns jsonb language sql immutable as $$
  select jsonb_build_object('price', p_price, 'store_fee', s, 'platform_fee', pf, 'tax', t, 'author_amt', p_price - s - pf - t)
  from (select round(p_price * 0.30)::int s) a, lateral (select round((p_price - a.s) * 0.15)::int pf) b, lateral (select round((p_price - a.s - b.pf) * 0.033)::int t) c $$;
grant execute on function public.pattern_fee_calc(int) to authenticated, anon;

create or replace function public.purchase_pattern(p_pattern uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
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
end $$;
revoke all on function public.purchase_pattern(uuid) from public, anon; grant execute on function public.purchase_pattern(uuid) to authenticated;

-- 구매한 유료 도안도 뷰어 열람 가능
drop policy if exists pattern_contents_select on public.pattern_contents;
create policy pattern_contents_select on public.pattern_contents for select to authenticated
  using (public.is_admin() or exists (select 1 from public.patterns p where p.id = pattern_contents.pattern_id
    and (p.author_id = (select auth.uid()) or (p.is_published and not p.hidden and (p.price = 0 or exists (select 1 from public.pattern_purchases pp where pp.pattern_id = p.id and pp.profile_id = (select auth.uid())))))));

create or replace function public.my_pattern_purchases()
returns jsonb language sql security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('pattern_id', pp.pattern_id, 'price', pp.price, 'via', pp.via, 'created_at', pp.created_at, 'title', p.title, 'craft', p.craft, 'level', p.level, 'photos', p.photos, 'has_viewer', p.has_viewer) order by pp.created_at desc), '[]'::jsonb)
  from public.pattern_purchases pp join public.patterns p on p.id = pp.pattern_id where pp.profile_id = auth.uid() $$;
revoke all on function public.my_pattern_purchases() from public, anon; grant execute on function public.my_pattern_purchases() to authenticated;

-- 작가 정산 미리보기: 월별 판매 수·매출·작가 지급액 + 최근 판매 10건(구매자 닉네임만)
create or replace function public.author_settlement()
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); out jsonb;
begin
  if uid is null then raise exception 'not signed in'; end if;
  select jsonb_build_object(
    'months', coalesce((select jsonb_agg(m order by m->>'month' desc) from (select jsonb_build_object('month', to_char(pp.created_at at time zone 'Asia/Seoul', 'YYYY-MM'), 'n', count(*), 'gross', sum(pp.price), 'store_fee', sum(pp.store_fee), 'platform_fee', sum(pp.platform_fee), 'tax', sum(pp.tax), 'author_amt', sum(pp.author_amt)) m
        from public.pattern_purchases pp join public.patterns p on p.id = pp.pattern_id where p.author_id = uid group by 1) q), '[]'::jsonb),   -- (보완: 월 문자열로 group by — commerce_demo_v1_fix 에서 서브쿼리로 고침)
    'total', coalesce((select jsonb_build_object('n', count(*), 'gross', sum(pp.price), 'author_amt', sum(pp.author_amt)) from public.pattern_purchases pp join public.patterns p on p.id = pp.pattern_id where p.author_id = uid), '{}'::jsonb),
    'recent', coalesce((select jsonb_agg(jsonb_build_object('title', p.title, 'price', pp.price, 'author_amt', pp.author_amt, 'buyer', pr.nickname, 'via', pp.via, 'created_at', pp.created_at) order by pp.created_at desc)
        from (select * from public.pattern_purchases pp0 where exists (select 1 from public.patterns p0 where p0.id = pp0.pattern_id and p0.author_id = uid) order by pp0.created_at desc limit 10) pp join public.patterns p on p.id = pp.pattern_id left join public.profiles pr on pr.id = pp.profile_id), '[]'::jsonb),
    'by_pattern', coalesce((select jsonb_agg(jsonb_build_object('pattern_id', p.id, 'title', p.title, 'price', p.price, 'n', c.n, 'author_amt', c.amt) order by c.n desc) from public.patterns p join lateral (select count(*) n, coalesce(sum(author_amt),0) amt from public.pattern_purchases where pattern_id = p.id) c on true where p.author_id = uid and c.n > 0), '[]'::jsonb),
    'payout_day', to_char((date_trunc('month', now() at time zone 'Asia/Seoul') + interval '1 month 14 days')::date, 'YYYY-MM-DD')
  ) into out;
  return out;
end $$;
revoke all on function public.author_settlement() from public, anon; grant execute on function public.author_settlement() to authenticated;

create or replace function public.admin_pattern_sales(p_month text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  return coalesce((select jsonb_agg(r order by r->>'author_amt' desc) from (
    select jsonb_build_object('author_id', p.author_id, 'author', pr.nickname, 'n', count(*), 'gross', sum(pp.price), 'store_fee', sum(pp.store_fee), 'platform_fee', sum(pp.platform_fee), 'tax', sum(pp.tax), 'author_amt', sum(pp.author_amt)) r
    from public.pattern_purchases pp join public.patterns p on p.id = pp.pattern_id left join public.profiles pr on pr.id = p.author_id
    where p_month is null or to_char(pp.created_at at time zone 'Asia/Seoul', 'YYYY-MM') = p_month group by p.author_id, pr.nickname) q), '[]'::jsonb);
end $$;
revoke all on function public.admin_pattern_sales(text) from public, anon; grant execute on function public.admin_pattern_sales(text) to authenticated;

-- ---------- 내 실함 → 이 실로 뜰 수 있는 도안 ----------
--   같은 실(catalog 일치) > 굵기 비슷(100g당 m ±20%) > 게이지 비슷(코 ±15%) > 굵기 분류 이름 일치
create or replace function public.patterns_for_stash(p_stash uuid default null)
returns table (id uuid, title text, craft text, level smallint, photos text[], price int, has_viewer boolean, match text, reason text, stash_id uuid, yarn_name text)
language sql security definer set search_path = public as $$
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
  from cand c where c.rank is not null order by c.id, c.rank $$;
revoke all on function public.patterns_for_stash(uuid) from public, anon; grant execute on function public.patterns_for_stash(uuid) to authenticated;

-- 보완(commerce_demo_v1_fix): shop_products 는 authenticated 읽기만, 쓰기는 관리자 함수
create or replace function public.admin_product_delete(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  delete from public.shop_products where id = p_id;
  perform public.admin_log('product_delete', 'product', p_id::text, null);
end $$;
revoke all on function public.admin_product_delete(uuid) from public, anon; grant execute on function public.admin_product_delete(uuid) to authenticated;
