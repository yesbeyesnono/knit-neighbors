-- 169. 가게 등록을 승인하면 좌표가 없어도 켜진 채로 만든다 (2026-11-26 대표 지시)
--   전: 신청에 좌표가 없으면 is_active=false 로 만들어져, 콘솔에서 좌표를 넣어도 꺼진 채였고 사용법 안내도 나가지 않았다
--   후: 승인 = 켜짐(사용법 안내가 바로 나감). 지도 핀은 좌표가 생기는 순간 보인다(nearby_shops 가 location is not null 을 봄)
--   _decide_shop_claim 의 한 곳만 바꾼다(나머지는 그대로) — 권한은 create or replace 라 그대로
do $$
declare d text;
begin
  d := pg_get_functiondef('public._decide_shop_claim(uuid, boolean, text, uuid, text)'::regprocedure);
  if position('loc, loc is not null)' in d) = 0 then raise exception '바꿀 자리를 찾지 못했습니다'; end if;
  execute replace(d, 'loc, loc is not null)', 'loc, true)');
end $$;
