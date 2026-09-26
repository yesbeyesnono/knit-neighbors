# 서포터즈 시스템 — 사전 조사 (supporters_spec.md 0-1)

2026-09-26 · 지시서 `knitup/docs/supporters_spec.md` 기준. **멈춤 조건 2가지에 걸려 조사까지만 하고 멈춤** (아래 "멈춤 사유").

## 저장소·DB 실제 구조 (지시서 이름 → 실제)
| 지시서 | 실제 |
|---|---|
| `comments` 테이블 | 없음. 댓글 = `posts` 행 중 `parent_id`가 있는 것(답글). "본인 글에 단 댓글"은 `posts.parent_id → posts.author_id = 본인` 으로 판정 |
| `works` 작품 인증 | `works`(profile_id, photos, techniques…) + 인증 글 `posts.work_id`. 생성은 RPC `create_work`. **승인 단계 없음** — 올리는 즉시 인증으로 계산(`works_apply_cert` 트리거가 `profiles.cert_count`·`act_level` 갱신) |
| 프로필 완성 | `profiles.onboarded_at`(온보딩 3단계에서 `saveProfile()`이 찍음) + `terms_agreed_at`. 별도 `profile_completed` 컬럼 없음 |
| 앱 실행 시 check-in | 없음. 로그인 뒤 `loadMe()`가 호출됨(index.html) — 여기서 `check_in()` RPC를 부르면 됨 |
| 지기(AI) 채팅 | 지기 계정 `SUPPORT_ID = e120eb67-…` 과의 1:1 방. 회원 메시지 → DB 트리거 `support_on_message` → Edge Function `supabase/functions/jigi/index.ts` route `support`(`supportScan`). 안내 카드는 `sendSup()`으로 지기 메시지(`messages.by_ai`)를 넣는 방식 — 버튼형 카드는 현재 없음(메시지에 링크/명령어로 대체하거나 앱에 카드 렌더 추가 필요) |
| 관리자 AI(텔레그램) | 같은 파일 `jigi/index.ts`: `tgHook()`(버튼=`mod_pending` 1회용 토큰 → `runPending()`), 알림 `tgSend()`, 아침 브리핑 `brief()`. 버그 제보 [채택]/[반려] 버튼은 `pending()` + `runPending()` 단계에 새 step 이름을 추가하는 방식으로 붙임(예: 지기 응대의 `support_send`) |
| 단체방 | `rooms.kind='group'` + `room_members`. 서포터 전용방은 지기 계정이 만든 group 방 1개를 재사용 |
| 가입 화면 | 온보딩 3단계(`#v-onboard .obs[data-s="3"]`, 닉네임·경력·시간·약관). "추천인 닉네임(선택)" 칸은 여기에 추가. 링크 `?ref=`는 `EDITION` 판정처럼 `location.search`에서 읽어 localStorage에 보관 후 가입 시 저장 |
| 홈 배너 | 커뮤니티 상단 이벤트 줄 `#evStrip`(`loadEvents`) 위에 배너 추가 가능. "베타 운영 중"은 `.top` 아래 띠 |
| 마이그레이션 | **`supabase/migrations/` 폴더 없음.** 지금까지 모든 DB 변경은 Supabase MCP `apply_migration`으로 운영 프로젝트 `thfcrodfaitzrzlrxyir`에 직접 적용하고 `supabase_schema.sql`에 기록해 왔음(CLAUDE.md 원칙: 추가만) |
| 테스트 | 기존 자동 테스트 없음. 검증은 롤백 DO 블록(`set local role authenticated` + `raise exception 'RESULT(rolled back)'`)을 운영 DB에서 돌려 왔음 |
| 시간 기준 | `act_level`이 이미 `Asia/Seoul` 날짜 기준 — 같은 방식(`created_at at time zone 'Asia/Seoul'`)::date |
| 배지 | 프로필에 `is_author`(작가 배지 `.authbadge`)가 있음. "1기 서포터" 배지는 `profiles.supporter_badge text` 추가 + `lvBadge()` 옆에 표시하면 됨(컬럼 단위 grant 규칙: 회원이 못 바꾸게 grant 안 함) |

## 재사용할 기존 부품
- 하루 한도·KST 계산: `works_apply_cert`(act_level) 방식
- 1회용 버튼 토큰: `mod_pending` + `runPending()` (jigi/index.ts)
- 회원 알림: `notifications`(kind 확장 필요 — check 제약 `notifications_kind_check`에 `supporter` 추가)
- 관리자 로그: `admin_log()` · 관리자 판정: `is_admin()`
- 이벤트/체험단(`events`, `event_applications`) — 신청·선정·배송지 구조가 비슷하므로 실물 보상 발송 기록에 `event_shipping` 패턴 재사용 가능

## 멈춤 사유 (지시서 §5)
1. **운영 DB 직접 쓰기 필요**: 지시서는 마이그레이션을 로컬(`supabase start`) 또는 개발 브랜치에서만 실행하라고 하지만, 이 PC에는 Supabase CLI·Docker가 없고 저장소에 `supabase/migrations/`도 없다. 개발 브랜치(Supabase Branching)는 유료 과금 항목이라 대표 승인 없이 만들 수 없다. 테스트 SQL도 실행할 곳이 없다.
2. **작품 인증 AI 진위 판별 흐름이 코드에 없음**: 지시서의 `work_verified`(관리자 AI 승인 시 10점)는 "승인" 이벤트를 전제로 하는데, 현재 앱은 인증 글을 올리면 바로 인증으로 계산한다(진위 검증은 CLAUDE.md '보류' 항목). 연결할 승인 이벤트가 없다.

## 진행 시 필요한 결정
- (1) 마이그레이션 실행 위치: ① 지금까지처럼 운영 DB에 추가만 적용(테스트는 롤백 블록) — 지시서 규칙과 어긋남 ② Supabase 개발 브랜치 생성(과금) ③ Docker + CLI 설치 후 로컬 실행
- (2) `work_verified` 적립 시점: ① 인증 글 작성 즉시(현재 구조) ② 관리자(대표)가 콘솔/텔레그램에서 [승인] 누른 시점 — 간단한 수동 승인 버튼을 새로 만들면 됨 ③ 진위 판별 AI를 먼저 만든 뒤
