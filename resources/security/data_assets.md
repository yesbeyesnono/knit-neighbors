# 정보 자산 분류표 — 뜨개동네 (2026-09-30 초안, schema 66 기준)

"유출 시 무엇이 나갔는지"를 말하려면 ① 무엇이 어디에 있는지(이 표) ② 뚫린 열쇠로 어디까지 갈 수 있는지(권한 구조) ③ 실제로 무엇을 읽어 갔는지(접근 기록)가 필요하다.
이 표는 ①이고, ②는 `supabase/tests/permissions_test.sql` 로 검증하며, ③은 `access_logs`(우리 DB, 1년) + Supabase 로그(7일)다.
새 테이블·버킷을 만들면 여기 한 줄 추가. 새 마이그레이션마다 permissions_test.sql 재실행.

## 등급 정의

| 등급 | 뜻 | 유출 시 |
|---|---|---|
| **1급 개인정보** | 한 사람을 특정하거나 연락할 수 있는 것 | 인지 후 72시간 안에 본인 통지(개인정보보호법 §34), 1천 명 이상이면 개인정보보호위원회·KISA 신고 |
| **2급 회원 생성물** | 회원이 만든 것. 닉네임과 묶이면 개인의 활동이 드러남 | 본인 통지. 공개 설정된 것(글·작품)은 통지 대상 아님 |
| **3급 회사 자산** | 회사가 모으고 다듬은 데이터·로직 | 영업비밀 대응. 회원 통지 의무 없음 |
| **4급 공개** | 누구나 볼 수 있게 설계된 것 | 조치 없음 |

## 자산 목록

| 등급 | 자산 | 저장 위치 | 볼 수 있는 사람 | 보관 | 비고 |
|---|---|---|---|---|---|
| 1 | 이메일·로그인 제공자·마지막 로그인 | `auth.users` | 관리자(`admin_find_users`, 열람 기록) | 계정 삭제 시 삭제 | 앱은 본인 이메일만 |
| 1 | 이벤트 배송지(이름·연락처·주소) | `event_shipping` | 본인, 관리자(`admin_event_apps`, 열람 기록) | 발송 30일 뒤 자동 삭제 | 선정자만 입력 |
| 1 | 가게 등록 신청(상호·주소·이메일·연락처·사업자번호·등록증 사진) | `shop_claims`, 버킷 `shop-docs`(비공개) | 본인, 관리자 | 승인 시 등록증 삭제 | AI(Anthropic/OpenRouter)가 등록증을 읽음 |
| 1 | 지기 문의 내용·티켓·AI 요약 | `support_tickets`, `messages`(지기 방), `support_events` | 본인, 관리자 | 서비스 기간 | 텔레그램으로 대표에게 전달(이메일·전화 마스킹) |
| 1 | 버그 제보·스크린샷 | `feedback_reports`, 버킷 `feedback`(비공개) | 본인, 관리자 | 서비스 기간 | |
| 1 | 푸시 기기 토큰 | `device_tokens` | 본인(읽기), 서버 | 로그아웃·삭제 시 제거 | 토큰만으로 개인 특정 불가하나 기기 식별자 |
| 1 | 작가 신청(실명·링크) | `author_applications` | 본인, 관리자 | 서비스 기간 | |
| 2 | 1:1·단체 채팅, 채팅 사진 | `rooms`·`room_members`·`messages`, 버킷 `chat-photos`(비공개) | 방 구성원, 관리자(신고 건만 보는 원칙) | 서비스 기간 | AI는 신고된 메시지 한 건만 읽음 |
| 2 | 내 실함(볼밴드 사진·실·남은 볼) | `yarn_stash`·`yarn_stash_log`, 버킷 `bands`(비공개) | 본인, 관리자 | 서비스 기간 | 볼밴드 사진은 AI가 읽음. 규격은 익명 통계(`yarn_entries`)로 |
| 2 | 위치(200m 격자 중심)·동네 | `profiles.location`·`dong_*` | 로그인 회원(지도, `is_visible` 일 때) | 서비스 기간 | 정확한 위치는 저장하지 않음 |
| 2 | 프로필(닉네임·사진·MBTI·경력·소개·기법·단계) | `profiles`, 버킷 `avatars`(공개) | 로그인 회원 | 계정 삭제 시 삭제 | 서버 계산값(레벨·Index·작가)은 회원이 못 고침 |
| 2 | 알림·활동·친구·차단 | `notifications`·`friendships`·`skill_events`·`point_events` | 본인(친구 관계는 양쪽) | 서비스 기간 | |
| 2 | 이벤트·클래스·모임 신청 | `event_applications`·`class_applications`·`room_members` | 본인, 호스트(클래스), 관리자 | 서비스 기간 | |
| 2 | 서포터 활동·추천인 | `supporters`·`referrals`·`survey_responses` | 본인, 관리자 | 서비스 기간 | |
| 3 | **실 사전**(1,156종 규격·소재·촉감·용도) | `yarn_catalog` | 관리자(직접), 회원은 함수 `yarn_suggest`(8건)·`yarn_popular`·`yarn_similar` 로만 | 영구 | 2026-09-30 직접 조회 차단 |
| 3 | 실 색상(30,505건, 실물 사진 18,784장) | `yarn_colors`, 버킷 `yarn-colors`(공개 사진) | 관리자(직접), 회원은 `yarn_colors_of`(실 하나씩) | 영구 | 사진 URL 은 공개(앱이 직접 그림) |
| 3 | 판매처·브랜드 별칭 | `yarn_sellers`·`yarn_brand_aliases` | 관리자 | 영구 | |
| 3 | 실 사용 원문·통계(익명) | `yarn_entries` | 관리자 | 영구 | 회원 식별 없음 |
| 3 | 수요 분석·매칭 규칙·추천 로직 | DB 함수(`admin_yarn_demand`·`yarn_match_spec`·`compute_trait_index` 등) | 관리자 | 영구 | 코드는 저장소(`supabase_schema.sql`) |
| 3 | 유료·비공개 도안 내용 | `pattern_contents` | 작가 본인, 구매자(예정), 관리자 | 영구 | 무료 공개 도안만 회원 열람 |
| 3 | 지기 AI 규칙·지식 창고·브리핑 | `ai_rules`·`support_kb`·`ai_briefings`·`mod_*` | 관리자 | 영구 | |
| 3 | 운영 기록 | `admin_logs`·`mod_actions`·`access_logs` | 관리자 | 영구(access_logs 400일) | 삭제 불가 |
| 4 | 기법 사전·기호 | `techniques`·`technique_aliases`, `docs/` | 로그인 회원 | 영구 | 앱 코드에 라이브러리 포함 |
| 4 | 공개 글·작품·모임·가게·클래스 | `posts`·`works`·`meetups`·`shops`·`shop_posts`·`patterns`, 버킷 `posts`·`works`·`shops`(공개) | 로그인 회원(사진 URL 은 누구나) | 서비스 기간 | 삭제·숨김은 본인·관리자 |
| 4 | 앱 설정 | `app_config` | 누구나(anon) | | 최소 버전 등 |

## 열쇠(자격증명)와 닿는 범위 — "뚫리면 어디까지"

| 열쇠 | 있는 곳 | 닿는 범위 | 방어 |
|---|---|---|---|
| 회원 세션(JWT) | 회원 기기 | 그 회원의 것 + 공개 데이터. RLS 가 상한 | 구글·애플 로그인, RLS·GRANT(permissions_test) |
| 관리자 계정(3명) | 관리자의 구글·애플 계정 | 콘솔 전부(1급 포함), 단 삭제·정지는 기록됨 | 2단계 인증(대표), `admins` 변경 즉시 텔레그램, admin_logs·access_logs |
| publishable(anon) key | 앱 코드(공개) | RLS 안에서만 — anon 은 app_config 뿐 | 비밀 아님. 권한은 RLS 가 정함 |
| service_role key | Supabase Secrets(Edge Function) | **전부**, 로그 없음 | 어떤 파일·채팅에도 적지 않음. 노출 시 대시보드에서 재발급 |
| Supabase 대시보드 | 대표 계정 | 전부 + 백업·설정 | 2단계 인증 |
| GitHub 저장소 | 대표 계정 | 앱 코드 = 회원 브라우저에서 실행되는 것 전부(세션 탈취 가능) | 2단계 인증, 협업자 최소 |
| Codemagic·Apple·Google Cloud | 대표 계정 | 빌드·배포·OAuth | 2단계 인증 |
| 텔레그램 봇 토큰 | Supabase Secrets | 대표 채팅으로 메시지 보내기(조치 실행은 웹훅 시크릿+chat_id 필요) | `jigi-guard` 매시 확인, 노출 시 BotFather 재발급 |
| AI 키(Anthropic/OpenRouter) | Supabase Secrets | 요금 | 노출 시 재발급 |

## 접근 기록 — "실제로 무엇을 읽어 갔는가"

- `access_logs`(400일): 관리자가 이메일(`find_users`)·배송지(`event_shipping`)를 연 기록. 확장 시 `log_access(kind, target, n)` 한 줄.
- `admin_logs`(영구): 관리자의 조치(숨김·정지·승인·공지·관리자 추가/삭제).
- `mod_actions`(영구): 지기 AI·대표 버튼 조치 + 되돌리기.
- Supabase 로그(7일): API·Auth·Storage·DB 요청 전부. 사고 의심 시 **즉시** 대시보드 › Logs 에서 내보내 보관(7일 지나면 사라짐).
- 없는 것: 회원이 공개 데이터를 얼마나 긁어 갔는지(7일 로그로만), service_role 사용 기록(Edge Function 로그 7일).

## 점검 주기

- 마이그레이션마다: `permissions_test.sql` 4블록, Supabase 어드바이저(security).
- 매달: access_logs 이상 여부(누가 몇 번), admins 목록, Secrets 목록, 협업자 목록.
- 출시 전: 이 표를 회원 안내 페이지(공개)·내부 관리 지침(비공개)으로 옮김.
