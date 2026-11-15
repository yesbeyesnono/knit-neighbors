# 서버 구조 사본 (읽기용)

Supabase 프로젝트의 표·함수·권한·트리거·예약 작업을 그대로 뽑아 둔 사본이다. **회원 데이터와 비밀 값은 들어 있지 않다.**
서버를 다른 곳에 다시 세우거나, 다른 개발자·AI 가 구조를 읽어야 할 때 쓴다. 실제 원본은 Supabase 안의 마이그레이션 기록이다.

- `functions.sql` 함수 전체 · `tables.sql` 표(칸·제약·RLS·권한) · `indexes.sql` · `policies.sql` · `triggers.sql` · `cron.sql` 예약 작업
- `misc.json` 칼럼 단위 권한·저장 칸(버킷)·확장·마이그레이션 목록 · `app_config.json` 앱 설정 값

새로 뜨는 법: `tools/backup/snapshot.sql` 을 Supabase SQL Editor 에서 실행 → 결과 JSON 을 파일로 저장 → `python tools/backup/make_snapshot.py <파일>`.
큰 서버 변경 뒤에 한 번씩 새로 뜬다. (뜬 날: 2026-11-16, 함수 363 · 표 93 · 정책 158 · 트리거 75 · 예약 작업 23)
