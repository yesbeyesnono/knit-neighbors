# 뜨개동네 (knit-neighbors) 작업 지침 · 인수인계

## 응답 규칙 (대표 지시)
- 설명은 짧게, 결과만 1~3줄. 원인 분석은 요청 시에만.
- 수정 후에는 Claude가 직접 커밋·푸시한다(이 저장소 한정). 커밋 메시지 끝에 Co-Authored-By 줄.
- 실제 사용자 데이터는 건드리지 않는다. 테스트는 demo1~6@knit.local(비번 knit1234)만 사용하고 테스트 흔적은 지운다.
- 색상·디자인 큰 변경은 대표가 목업으로 확정한 뒤에만. (2026-09-17 가을·올리브 팔레트 시도 → "눈이 아프다"로 전부 되돌림. 현재 흑백 Threads 톤 유지)
- **플랫폼 우선순위(2026-09-18 대표 지시)**: 지금은 아이폰(iOS·TestFlight) 위주로 진행. Android 빌드·Play 업로드는 iOS가 어느 정도 다듬어진 뒤 한 번에 진행 — 그 전에는 Android 빌드/업로드를 제안하거나 실행하지 않는다.
- 패치는 파이썬 스크립트를 **파일로 저장해 실행**(Bash heredoc은 역슬래시·따옴표가 깨짐).

## 에디션 — V1(full) / V2(meet) (2026-09-19 대표 확정)
- **코드는 하나**, `docs/edition.js`의 `KN_EDITION`으로 나눈다. index.html의 `FULL` 상수로 분기. 브랜치를 가르지 말 것.
  - **meet = V2 공개 앱**(App Store, 뉴스레터 구독자 대상, 만남 중심). full에서 뺀 것: ① '다음에 떠보면 좋아요' 추천 카드(피드·마이·작품 인증 후) ② 설정 › 찜한 도안 ③ 도안 등록 과정(＋ › 도안, 설정 › 내 도안, 프로필 도안 탭) ④ 내 뜨개 단계 아래 '내 단계에 맞는 도안'. **작가 신청·지도 작가 핀·작가 링크(프로필의 인스타그램 등)는 meet에도 있음**
  - **full = V1 Lab**(VC 시연, 계속 실험). 기준점 태그 `v1-full-2026-09-19`
  - 새 기능을 만들 때: 공개해도 되는지 대표에게 확인 전에는 `FULL`로 감쌀 것
- 저장소의 edition.js 기본값은 meet(= GitHub Pages 웹 기본). 웹에서 full 보기: 주소 뒤 `?edition=full`(브라우저에 기억, `?edition=meet`로 복귀). 네이티브는 빌드가 넣은 값 고정
- Codemagic 워크플로(2026-09-19 전환 완료): `ios-public`(meet, 기존 Bundle ID `kr.co.firmtech.knitneighbors` = App Store Connect 앱 **KOAP**, **수동 실행만** — App Store 제출용) · `ios-lab`(full, `kr.co.firmtech.knitneighbors.lab` = 앱 **뜨개동네 Lab**, main 푸시마다 자동, 복귀 주소 `knitneighborslab://auth` — Supabase Redirect URL 등록됨). 빌드 번호는 시각 기반(yymmddHHMM). KOAP에 예전에 올라간 full 빌드는 심사에 제출하지 말 것(반드시 ios-public 빌드를 고를 것)
- **작업·배포 흐름(2026-09-19 대표 지시)**: 앞으로는 주로 V2(공개 앱)를 개선한다. 수정 → main 푸시(→ Lab 자동 빌드로 먼저 확인 가능) → 대표가 **"V2 올려줘"**라고 하면 Claude가 `git tag v2-YYYYMMDD-N && git push origin <태그>` → `ios-public` 자동 빌드 → KOAP TestFlight. 대표가 말하기 전에는 v2 태그를 붙이지 않는다(공개 앱 배포 시점은 대표가 정함). 수정 보고 때 "V2에 반영되는 수정인지(공통) / Lab 전용(FULL)인지"를 한 줄로 밝힐 것. App Store 심사 제출 버튼은 대표가 누른다
- 공개 후 원칙: DB 변경은 추가만(옛 앱 버전이 계속 동작해야 함), 기존 컬럼·함수 삭제 금지. 구버전 차단은 `app_config.min_version`
- 공개 전 할 일: demo1~6 계정 데이터 삭제(데모 도안은 지기 소유로 옮겨 Lab 시연용으로 유지), APP_VERSION·MARKETING_VERSION 정리

## 구조
- 앱 본체: `docs/index.html` 단일 파일(HTML+CSS+JS). GitHub Pages(main /docs) → https://yesbeyesnono.github.io/knit-neighbors/
- 관리자 콘솔: `docs/admin.html` → …/knit-neighbors/admin.html (관리자: knitup.official, yesbeyesnono, cocos.jay)
- 법적 문서: `docs/privacy.html` · `terms.html` · `guidelines.html` · `delete-account.html`
- 아이콘: `docs/icons/<key>.svg` 20종 + `nav-*.svg`(인라인 삽입) · 스펙 `resources/icons/ICONS.md` · `ICON_IMAGES=true`
- 시·도 경계: `docs/kr-provinces.json` (관리자 인포그래픽)
- DB 스키마 기록: `supabase_schema.sql` (섹션 0~30, 마이그레이션과 1:1)
- 네이티브: Capacitor 8 (`capacitor.config.json`, `android/`, `ios/`), appId `kr.co.firmtech.knitneighbors`
- iOS 빌드: Codemagic(`codemagic.yaml`). main 푸시 → GitHub 웹훅(id 679395520) → `ios-lab` 자동 빌드 → TestFlight '뜨개동네 Lab'. 공개 앱(KOAP)은 `ios-public` 수동 실행. 자세한 내용은 위 '에디션' 절
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
지도(이웃·모임·가게 핀, 필터: 전체/친구 찾는 이웃/모임/가게/비슷한 수준/시간 맞음/친구, 같은 지점 핀 분산) · 커뮤니티(추천 랭킹·최신·모임·작품·동네·친구, 인라인 답글, @멘션, 해결됐어요, 리포스트=저장 겸 프로필 공개·외부 공유는 ··· 메뉴) · ＋ 작성(글/작품 인증/모임/가게 소식/후기) · 채팅(카카오식 입력, 사진 전송, 뜨개동네 지기 고정 채널) · 마이(🔔 활동, 맨 위 도안 추천 → 탭. 친구 줄(친구 수·받은 신청)은 채팅 탭 맨 위로 이동. 프로필·프로필 편집·뜨개 친구 찾기(손 들기 14일)는 설정 안으로 이동(2026-09-18), 설정: 내 뜨개 단계(knitup식 가로 기법 맵: 단계별 열 + 선행 기법 연결선, 옆으로 스크롤)·현위치로 동네 다시 설정·지기에게 말하기·약관·계정 삭제) · 신고/차단/금칙어/약관 동의

## 가게·도안·작가 (2026-09-18)
- 가게 가입: 개인 가입 → 설정 › 우리 가게 등록 신청(사업자등록증 사진, 비공개 버킷 shop-docs) 또는 오너 없는 가게 화면 › 이 가게 주인이에요 → 관리자 콘솔 › 파트너 가게에서 승인(서류 자동 삭제) → 좌표 입력·공개
- 도안 추천: `recommend_patterns`(내 단계~+1, 새 기법 1~2개 우선). 피드 6번째 글 뒤·작품 인증 직후·내 단계 화면·설정 › 찜한 도안. 결제는 외부 링크만(앱 내 결제 없음). **등록된 도안이 없으면 카드가 안 보임** — 관리자 콘솔 › 도안에서 등록
- 작가: 작품 인증 3개 이상 → 설정 › 작가 신청 → 콘솔 › 작가 신청 승인 → ＋ › 도안 / 설정 › 내 도안. 지도 작가 핀 색 #8a6d1a(2026-09-18 대표 확정), 인증 3개 기준 확정
- **데모 도안 14개**(표지 그림 `docs/patterns/demo-*.svg`, 작가: demo2 코바늘요정·demo3 킨텍스뜨개·지기, 판매 링크 없음). 출시 전 삭제: `delete from patterns where photos[1] like '%/patterns/demo-%'` + `docs/patterns/demo-*.svg` 제거

## 유료 도안·정산 방향 (2026-09-19 대표 확정)
- 회사가 판매자(작가는 이용허락), 작가 정산 = 판매가 − Apple 수수료 − 플랫폼 15% → **3.3% 원천징수** 후 지급. 가격은 **티어 중 선택**(IAP 티어 상품). 순서: ① knitup 뷰어 연동(완료) → ② IAP 티어·구매 내역·환불 → ③ 작가 정산 정보·월 정산 → ④ 통신판매업·약관
- knitup 뷰어: `docs/viewer.html` = `node tools/build-viewer.js` 로 `knitup/docs/app_v9.html`의 VIEWER_SIZE_HTML 에서 생성(직접 수정 금지, 빌드 스크립트를 고칠 것). 앱은 sandbox+srcdoc iframe 으로 열고 postMessage(knitup-pkg / kn-prog / kn-close). 실 소요량 카드·AI 사이즈 변환 대화는 예시 데이터·모자 전용이라 숨김
- 작가는 도안 등록 폼에서 knitup 에디터의 `.knitup-pkg.json` 첨부 → `pattern_contents`. 무료 도안만 누구나 열람, 유료는 구매 기능 전까지 작가 본인·관리자만

## 남은 일
- 대표: 2단계 인증(구글·Supabase·GitHub·Apple·Codemagic), 구글 클라이언트 시크릿 재발급, Play Console에 versionCode 2 .aab 업로드·데이터 보안 설문, App Store 테스트 정보 입력, 앱 아이콘(1024 PNG) 전달, 쎄비하우스 오너 계정·링크 입력
- 개발 후보: 이상 접근 감지·사고 대응 문서, PITR 백업, 스토어 스크린샷·설명, 공유 링크, 고유 아이디(@handle), '지금 이 근처' 임시 위치, 관리자 PNG 내보내기
- 출시 전: demo1~6 데이터 삭제, 데모 도안 14개 삭제(위 참고), 법률 검토, 위치기반서비스 신고 대상 확인
