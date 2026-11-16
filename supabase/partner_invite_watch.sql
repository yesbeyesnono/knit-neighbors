-- schema 132 (2026-11-16): 초대한 분과 비슷한 이름·계정으로 가입하면 대표에게 알림
-- 초대 기록(partner_invites) 중 아직 회원과 연결하지 않은 것에 대해, 닉네임이나 이메일 앞부분이 비슷한 가입이 생기면
-- 텔레그램으로 한 번 알린다(jigi_reminders). 알림에는 닉네임·가입 시각만 넣고 이메일은 넣지 않는다.
-- 닉네임이 이름의 일부일 때는 닉네임이 그 낱말 길이의 절반 이상이어야 한다(짧은 닉네임이 긴 계정 이름에 우연히 들어가는 것을 거름).

alter table public.partner_invites add column if not exists keys text[];   -- 이름 말고 더 찾아볼 낱말(인스타그램 계정 등)

create table if not exists public.partner_invite_hits (
  invite_id uuid not null references public.partner_invites(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  via text not null,                       -- nickname | email
  created_at timestamptz not null default now(),
  primary key (invite_id, profile_id)
);
alter table public.partner_invite_hits enable row level security;
revoke all on public.partner_invite_hits from anon, authenticated;
grant all on public.partner_invite_hits to service_role;

create or replace function public.partner_invite_watch() returns int
language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  for r in
    with inv as (
      select i.id, i.kind, i.name, k.key,
             lower(regexp_replace(k.key, '\s+', '', 'g')) as nk,
             regexp_replace(lower(k.key), '[^a-z0-9]', '', 'g') as ak,
             (lower(k.key) ~ '^[a-z0-9._ -]+$') as is_ascii
        from public.partner_invites i
        cross join lateral unnest(array[i.name] || coalesce(i.keys, '{}')) as k(key)
       where i.profile_id is null and btrim(coalesce(k.key, '')) <> ''
    ), cand as (
      select p.id, p.nickname, p.created_at,
             lower(regexp_replace(coalesce(p.nickname, ''), '\s+', '', 'g')) as nn,
             regexp_replace(lower(split_part(coalesce(u.email, ''), '@', 1)), '[^a-z0-9]', '', 'g') as el
        from public.profiles p join auth.users u on u.id = p.id
       where p.deleted_at is null and not coalesce(p.is_test, false)
    ), m as (
      select distinct on (inv.id, c.id) inv.id as invite_id, inv.kind, inv.name, c.id as profile_id, c.nickname, c.created_at,
             case when char_length(inv.nk) >= 2 and char_length(c.nn) >= 2
                       and (c.nn like '%' || inv.nk || '%' or (char_length(c.nn) >= 3 and char_length(c.nn) * 2 >= char_length(inv.nk) and inv.nk like '%' || c.nn || '%')) then 'nickname'
                  else 'email' end as via
        from inv join cand c on
             (char_length(inv.nk) >= 2 and char_length(c.nn) >= 2
                and (c.nn like '%' || inv.nk || '%' or (char_length(c.nn) >= 3 and char_length(c.nn) * 2 >= char_length(inv.nk) and inv.nk like '%' || c.nn || '%')))
          or (inv.is_ascii and char_length(inv.ak) >= 5 and c.el like '%' || inv.ak || '%')
       where not exists (select 1 from public.partner_invite_hits h where h.invite_id = inv.id and h.profile_id = c.id)
       order by inv.id, c.id, 7 desc
    )
    select * from m order by created_at
  loop
    insert into public.partner_invite_hits(invite_id, profile_id, via) values (r.invite_id, r.profile_id, r.via) on conflict do nothing;
    if not found then continue; end if;
    n := n + 1;
    insert into public.jigi_reminders(due_at, text) values (now(),
      '🔔 초대하신 분으로 보이는 가입이 있어요'||E'\n\n'||
      '초대 기록: '||r.name||' ('||case r.kind when 'shop' then '공방·가게' else '작가' end||')'||E'\n'||
      '가입한 회원: 닉네임 「'||coalesce(nullif(btrim(r.nickname), ''), '아직 없음')||'」 · 가입 '||to_char(r.created_at at time zone 'Asia/Seoul', 'MM-DD HH24:MI')||E'\n'||
      '비슷한 점: '||case r.via when 'nickname' then '닉네임이 초대 기록의 이름과 비슷해요.' else '가입한 이메일 주소의 앞부분이 초대 기록에 적어 둔 계정 이름과 비슷해요(이메일 주소는 이 알림에 적지 않아요).' end||E'\n\n'||
      '왜 알려 드리나요: 대표님이 초대장을 보낸 분과 비슷한 닉네임·이메일로 가입이 생기면 알려 달라고 하셨어요. 이름이 비슷할 뿐 같은 분인지는 제가 알 수 없으니, 프로필과 올린 글을 보고 확인해 주세요.'||E'\n\n'||
      '지금 하실 수 있는 일:'||E'\n'||
      '① 콘솔 › 초대·안내에서 「'||r.name||'」 줄의 ''닉네임 연결''에 이 닉네임을 넣으면 초대와 회원이 이어지고, 이 초대에 대한 알림은 더 오지 않아요.'||E'\n'||
      case r.kind when 'shop' then '② 가게는 그분이 앱에서 가게 등록을 신청하시면 승인 알림이 따로 와요.'
                  else '② 같은 분이 맞으면 콘솔 › 회원에서 이 닉네임을 찾아 작가로 지정해 주세요. 지정하는 순간 작가 사용법 안내가 그분께 자동으로 가요.' end||E'\n\n'||
      '참고: 같은 초대·같은 회원에 대해서는 한 번만 알려요.');
  end loop;
  return n;
end $$;
revoke all on function public.partner_invite_watch() from public, anon, authenticated;

select cron.unschedule('partner-invite-watch') where exists (select 1 from cron.job where jobname = 'partner-invite-watch');
select cron.schedule('partner-invite-watch', '*/10 * * * *', $$select public.partner_invite_watch()$$);   -- 10분마다
