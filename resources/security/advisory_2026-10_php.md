# 과기정통부 PHP 취약점 보도자료(2026-10-22) 검토 → 뜨개동네 적용 정리

작성 2026-10-23. 원문: 과기정통부·KISA 보도자료 「PHP 보안 취약점 관련 긴급 보안 업데이트 및 기술적 조치 당부」 + 붙임 「PHP 취약점(PHP2Shell) 기업 보안 대응 수칙」. 참고 링크 5개를 전부 읽고 정리했다.

## 1. 무슨 일인가 (사실 요약)

| 항목 | 내용 |
|---|---|
| 취약점 | CVE-2026-109618 (메모리 부족 처리 중 메모리 손상 → 원격 코드 실행), CVE-2026-109619 (요청이 끝난 뒤 남은 전역 상태를 다음 요청이 재사용 → 원격 코드 실행). 둘 다 CVSS v4 9.2 '치명' |
| 영향 | PHP 8.2.35 / 8.3.36 / 8.4.27 / 8.5.12 **미만** 전부. 8.1 이하는 공식 지원 종료(최소 백포트만 제공). 웹 요청을 받는 모든 실행 방식(mod_php·PHP-FPM·php-cgi·FrankenPHP·LiteSpeed) — mod_php 가 가장 위험(앱 코드가 돌기 전에 공격 가능) |
| 조치 | 업데이트가 유일한 완전한 해결. 임시 완화: `memory_limit=-1`(php_admin_value), `post_max_size` 축소, 프런트(WAF·프록시)에서 요청 크기·multipart 파트 수·헤더 수·중첩 깊이 제한, `session.upload_progress.enabled=0`, PHP 8.5 는 `fatal_error_backtraces=0`, 적용 뒤 워커 전부 재시작 |
| 정부 | 민간 사이버위기 경보 '관심'→'주의'(10/22 12:00). 피해 시 보호나라 118 신고. PoC 라고 돌아다니는 파일은 악성코드 가능성 — 버전 확인·로그 점검으로 판단 |
| 출처 | php.net 2026-10-21 릴리스 공지 · GHSA-w8hw-w9fx-j79w · GHSA-6wmf-4rv5-p3rp · NCSC-NL/php2shell(운영 정보 모음, PoC 아님) · KISA 보호나라 공지 nttId=72227 |

## 2. 뜨개동네는 직접 영향이 있는가 — **없음**

| 우리 구성 | 실행 환경 | PHP 사용 | 판단 |
|---|---|---|---|
| 앱·관리자 콘솔·법적 문서 (`docs/`) | GitHub Pages 정적 파일 | 없음 | 영향 없음 |
| DB·인증·Storage | Supabase (Postgres 17.6, 서울) | 없음 | 영향 없음 |
| 서버 로직 (jigi·jigi-remind·read-band·push-send·pattern-ai) | Supabase Edge Functions (Deno) | 없음 | 영향 없음 |
| iOS·Android 앱 | Capacitor 8 WebView | 없음 | 영향 없음 |
| 빌드 | Codemagic | 없음 | 영향 없음 |
| knitup Studio | GitHub Pages 정적 + 별도 Supabase | 없음 | 영향 없음 |

저장소 전체에서 `php` 검색 결과는 package-lock 과 기호 검수 HTML 의 문자열뿐(코드 아님).

**확인이 필요한 곳(대표)**: 회사 홈페이지·외주 제작 쇼핑몰·네이버/카페24·그누보드·워드프레스로 만든 페이지가 있으면 그 호스팅사에 "PHP 8.2.35/8.3.36/8.4.27/8.5.12 이상으로 업데이트했는지" 확인. firmtech.co.kr·knitup.kr 은 이 PC에서 접속되지 않아 확인하지 못함. 협력 쇼핑몰 4곳(쎄비·앵콜스·바늘이야기·청송)은 우리와 서버 연동이 없고(공개 상품 목록을 수집한 것뿐) 그쪽 운영은 각 업체 몫.

## 3. 대응 수칙 8개를 우리 앱에 옮기면

보도자료의 수칙은 PHP 서버용이지만 "인터넷 접점 자산을 즉시 식별·패치·감시·인증정보 교체·사고 대응"이라는 원칙은 그대로 적용된다.

| 수칙 | 우리 상황 | 할 일 |
|---|---|---|
| 1. 자산 식별 | `resources/security/data_assets.md`(등급·열쇠별 범위) 있음. 런타임 목록은 위 표 | 이 문서 2절 표를 data_assets.md 에 '실행 환경' 절로 합치기 (완료: 아래 5절) |
| 2. 즉시 업데이트 + 재시작 | Postgres·Edge 런타임은 Supabase 가 패치. 우리가 관리하는 건 npm 의존성(Capacitor)뿐 | `npm audit` 를 월 1회 + 빌드 전 실행. 2026-10-23: 고위험 1(brace-expansion, 빌드 도구) `npm audit fix` 로 해결, 중간 3(uuid ← @capacitor/cli, 개발 도구) 은 메이저 업그레이드 필요라 다음 Capacitor 업데이트 때 |
| 3. 지원 끝난 구버전 금지 | Postgres 17 (지원 중), Capacitor 8 (최신), Deno 는 Supabase 관리 | `app_config.min_version` 으로 구버전 앱 차단 — 서버 함수 호환 깨는 변경 때 사용 |
| 4. 프런트에서 요청 제한(WAF 역할) | Supabase 게이트웨이가 기본 보호. Edge Function 은 `req.json()` 으로 바로 파싱하고 크기 제한 없음. rate_hit 는 read-band·pattern-ai·place_order 에만 | Edge Function 공통: Content-Length 상한(예: 64KB, 사진은 Storage 경유라 본문은 작음)·JSON 깊이 제한, jigi 외부 route(scan 등) 에도 rate_hit. (후속 작업 후보) |
| 5. 업데이트 후 로그 점검 | `access_logs`(1급 데이터 열람), `admin_logs`, `mod_actions`, Supabase 로그(7일), jigi-guard(텔레그램 웹훅 매시 점검) | 주 1회 '이상 접근' 점검 크론: 같은 IP/계정의 비정상 호출 수, 실패한 RPC 급증, 관리자 함수 호출 이력 → 텔레그램 요약(개발 후보 목록에 이미 있음: 이상 접근 감지) |
| 6. 중요 인증정보 교체 | 열쇠 목록은 data_assets.md 46절. 교체 주기 없음 | **교체 주기 정하기**: service_role·Edge Secrets(API 키·TG 토큰)·Apple 시크릿(2027-03 만료)·Google 클라이언트 시크릿 → 6개월, 노출 의심 즉시. TG 봇 토큰은 대표 결정으로 유지 중(jigi-guard 로 감시) |
| 7. 침해사고 대응 순서 | 문서 없음 | 아래 4절 '사고 대응 카드'를 기준 문서로 둠 |
| 8. 출처 불명 PoC 실행 금지 | 해당 없음 | 저장소·PC 에 외부 PoC 내려받지 않음. 취약점 판단은 버전·로그로 |

## 4. 사고 대응 카드 (뜨개동네판, 보도자료 7번 수칙을 옮김)

1. **격리** — 서버를 끄지 말고 접점만 막는다: Supabase › Settings › API 에서 anon/publishable 키 **회전**(앱은 새 키로 재배포), 의심 Edge Function 은 즉시 재배포해 중지(빈 함수). DB 는 유지(증거).
2. **신고** — 개인정보 유출 의심이면 개인정보보호위원회(72시간 내)·KISA 보호나라 118. 회원에게 알릴 문구는 대표 승인 뒤.
3. **증거 확보** — Supabase 로그(API·Postgres·Edge) 는 보존 기간이 짧으니 즉시 내보내기, `access_logs`·`admin_logs`·`mod_actions` 덤프, 의심 계정·시각 기록.
4. **조치** — 열쇠 전부 교체(service_role·Edge Secrets·OAuth 시크릿·APNs/FCM), 관리자 계정 비밀번호·2단계 인증, 권한 테스트 4블록 재실행, 변경 내역 `supabase_schema.sql` 에 기록.

## 5. 이번에 바로 한 것 (2026-10-23)

- Supabase 보안 어드바이저 실행 → 치명·오류 없음. 경고 처리: 트리거 함수 5개(`cheer_on_*`)에 남아 있던 anon/authenticated execute 회수, `search_path` 미고정 함수 5개 고정(마이그레이션 `security_lint_2026_10_23`). 남은 경고는 설계상 의도(관리자 함수는 안에서 `is_admin()` 검사, Studio 2개 함수는 anon 허용, `pg_net` 은 Supabase 기본 위치).
- `npm audit fix`: 고위험 1건 해결.
- 저장소 비밀 검색: 키 값 없음(Google Maps 키는 공개 키이며 도메인 제한, 정상).

## 6. 대표가 할 것

1. Supabase › Authentication › Password › **Leaked password protection 켜기**(어드바이저 경고, 대시보드에서만 가능. 로그인은 Google/Apple 이라 영향 없음).
2. 회사 홈페이지·외주 쇼핑몰 PHP 여부 → 호스팅사에 업데이트 확인(2절).
3. 2단계 인증(구글·Supabase·GitHub·Apple·Codemagic) — 기존 '남은 일'과 동일.
4. 열쇠 교체 주기(6개월) 확정 → 첫 교체일 정하기.
