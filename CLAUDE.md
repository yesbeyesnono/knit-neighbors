# 뜨개동네 (knit-neighbors) 작업 지침 · 인수인계

## 응답 규칙 (대표 지시)
- 설명은 짧게, 결과만 1~3줄. 원인 분석은 요청 시에만.
- 수정 후에는 Claude가 직접 커밋·푸시한다(이 저장소 한정). 커밋 메시지 끝에 Co-Authored-By 줄.
- 실제 사용자 데이터는 건드리지 않는다. 테스트는 demo1~6@knit.local(비번 knit1234)만 사용하고 테스트 흔적은 지운다.
- 색상·디자인 큰 변경은 대표가 목업으로 확정한 뒤에만. (2026-09-17 가을·올리브 팔레트 시도 → "눈이 아프다"로 전부 되돌림. 현재 흑백 Threads 톤 유지)
- **플랫폼 우선순위(2026-09-18 대표 지시)**: 지금은 아이폰(iOS·TestFlight) 위주로 진행. Android 빌드·Play 업로드는 iOS가 어느 정도 다듬어진 뒤 한 번에 진행 — 그 전에는 Android 빌드/업로드를 제안하거나 실행하지 않는다.
- 패치는 파이썬 스크립트를 **파일로 저장해 실행**(Bash heredoc은 역슬래시·따옴표가 깨짐).

## 구조
- 앱 본체: `docs/index.html` 단일 파일(HTML+CSS+JS). GitHub Pages(main /docs) → https://yesbeyesnono.github.io/knit-neighbors/
- 관리자 콘솔: `docs/admin.html` → …/knit-neighbors/admin.html (관리자: knitup.official, yesbeyesnono, cocos.jay)
- 법적 문서: `docs/privacy.html` · `terms.html` · `guidelines.html` · `delete-account.html`
- 아이콘: `docs/icons/<key>.svg` 20종 + `nav-*.svg`(인라인 삽입) · 스펙 `resources/icons/ICONS.md` · `ICON_IMAGES=true`
- 시·도 경계: `docs/kr-provinces.json` (관리자 인포그래픽)
- DB 스키마 기록: `supabase_schema.sql` (섹션 0~28, 마이그레이션과 1:1)
- 네이티브: Capacitor 8 (`capacitor.config.json`, `android/`, `ios/`), appId `kr.co.firmtech.knitneighbors`
- iOS 빌드: Codemagic(`codemagic.yaml`, 워크플로 ios-testflight). main 푸시 → GitHub 웹훅(id 679395520) → 자동 빌드 → TestFlight(앱 이름 KOAP, 내부 테스터 그룹)
- Android: JDK 21(Temurin) + SDK `C:/Android/Sdk`. `npx cap sync android` → `cd android && ./gradlew bundleRelease --no-daemon` → `android/app/build/outputs/bundle/release/app-release.aab`. 업로드 키 `android/keys/upload-keystore.jks`(gitignore, 백업 필요). Play 내부 테스트에 versionCode 1 올라감, 현재 코드 versionCode 2(1.0.1)
- 검증용 스테이징: `knitup/docs/knit.html`(+admin.html, icons/, kr-provinces.json) 복사 후 knitup 폴더의 launch.json `knitup-static`(127.0.0.1:8765)로 확인. Google Maps 키가 이 주소를 허용함. knitup 폴더에서는 git 명령 금지.

## 백엔드 (Supabase)
- 프로젝트 `thfcrodfaitzrzlrxyir` (Pro, 서울). publishable key는 index.html/admin.html에 있음.
- 로그인: Google OAuth + Apple(Services ID kr.co.firmtech.knitneighbors.web, 시크릿 만료 **2027-03-13**, `tools/apple-secret.js`로 재발급). 네이티브는 PKCE + `knitneighbors://auth`.
- 주요 테이블: profiles(skills, level_*, wave_until, location=200m 격자 중심 고정), posts(parent_id, mentions, solved_reply_id, hidden), works(yarn_name/weight/needle), meetups, rooms/room_members/messages(photo_url=chat-photos 경로), friendships, notifications, skill_events, shops/shop_posts/shop_reads/shop_follows, shop_claims(가게 등록 신청), patterns/pattern_saves(도안·찜), author_applications(작가 신청), admins/admin_logs, reports/post_reports, banned_words, techniques(60)
- 원칙: 모든 테이블 RLS. SECURITY DEFINER 함수는 만들 때 `revoke ... from public, anon` 후 필요한 역할에만 grant(기본 권한도 PUBLIC 차단으로 바꿔 둠). 관리자 기능은 `is_admin()` 검사 + `admin_log` 기록. profiles는 **컬럼 단위 UPDATE grant**(서버 계산값·is_author 위조 방지) — 컬럼을 추가하면 사용자가 고칠 것만 grant.
- 지기(운영진) 계정 = knitup.official 프로필 `e120eb67-b254-4008-92d8-08c95c821e9e`(닉네임 '뜨개동네 지기'). 앱 `SUPPORT_ID`.
- 파트너 가게: 쎄비하우스 등록됨(`002ce2de-e380-4bb5-ae38-d5ee1feb076c`, 성수 연무장5가길 28). 오너 계정 미지정.

## 앱 기능 요약
지도(이웃·모임·가게 핀, 필터: 전체/친구 찾는 이웃/모임/가게/비슷한 수준/시간 맞음/친구, 같은 지점 핀 분산) · 커뮤니티(추천 랭킹·최신·모임·작품·동네·친구, 인라인 답글, @멘션, 해결됐어요, 리포스트=저장 겸 프로필 공개·외부 공유는 ··· 메뉴) · ＋ 작성(글/작품 인증/모임/가게 소식/후기) · 채팅(카카오식 입력, 사진 전송, 뜨개동네 지기 고정 채널) · 마이(🔔 활동, 프로필, 뜨개 친구 찾기(손 들기 14일), 설정: 내 뜨개 단계·현위치로 동네 다시 설정·지기에게 말하기·약관·계정 삭제) · 신고/차단/금칙어/약관 동의

## 가게·도안·작가 (2026-09-18)
- 가게 가입: 개인 가입 → 설정 › 우리 가게 등록 신청(사업자등록증 사진, 비공개 버킷 shop-docs) 또는 오너 없는 가게 화면 › 이 가게 주인이에요 → 관리자 콘솔 › 파트너 가게에서 승인(서류 자동 삭제) → 좌표 입력·공개
- 도안 추천: `recommend_patterns`(내 단계~+1, 새 기법 1~2개 우선). 피드 6번째 글 뒤·작품 인증 직후·내 단계 화면·설정 › 찜한 도안. 결제는 외부 링크만(앱 내 결제 없음). **등록된 도안이 없으면 카드가 안 보임** — 관리자 콘솔 › 도안에서 등록
- 작가: 작품 인증 3개 이상 → 설정 › 작가 신청 → 콘솔 › 작가 신청 승인 → ＋ › 도안 / 설정 › 내 도안. 지도 작가 핀 색 #8a6d1a(2026-09-18 대표 확정), 인증 3개 기준 확정
- **데모 도안 14개**(표지 그림 `docs/patterns/demo-*.svg`, 작가: demo2 코바늘요정·demo3 킨텍스뜨개·지기, 판매 링크 없음). 출시 전 삭제: `delete from patterns where photos[1] like '%/patterns/demo-%'` + `docs/patterns/demo-*.svg` 제거

## 남은 일
- 대표: 2단계 인증(구글·Supabase·GitHub·Apple·Codemagic), 구글 클라이언트 시크릿 재발급, Play Console에 versionCode 2 .aab 업로드·데이터 보안 설문, App Store 테스트 정보 입력, 앱 아이콘(1024 PNG) 전달, 쎄비하우스 오너 계정·링크 입력
- 개발 후보: 이상 접근 감지·사고 대응 문서, PITR 백업, 스토어 스크린샷·설명, 공유 링크, 고유 아이디(@handle), '지금 이 근처' 임시 위치, 관리자 PNG 내보내기
- 출시 전: demo1~6 데이터 삭제, 데모 도안 14개 삭제(위 참고), 법률 검토, 위치기반서비스 신고 대상 확인
