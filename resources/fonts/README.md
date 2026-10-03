# 털실체 (Teolsil) — 뜨개동네 제목 글꼴

- 파일: `Teolsil-Regular.ttf/.woff2`(획 95/1000) · `Teolsil-Bold.ttf/.woff2`(획 120/1000, 2026-10-03 대표 확정)
- 원본은 폰트 파일이 아니라 `docs/index.html`의 **털실체 엔진(`TS`)**이다. 글자 모양을 고치려면 엔진을 고치고 다시 빌드한다(폰트 파일을 직접 편집하지 말 것).
- 빌드: `node tools/font/export-glyphs.js 95 g95.json` → `python tools/font/build-teolsil.py g95.json Regular resources/fonts` (Bold는 120). 필요 패키지: fonttools·shapely·brotli·svgpathtools. 전체 11,184 글리프에 각 10분쯤
- 규격: UPM 1000, 어센더 880 / 디센더 -120, 한글 자폭 1000(ㅣ 홀로는 860), 공백 360, 가운뎃점 460. 모노라인·끝 반원. 자간은 폰트에 없음 — CSS `letter-spacing:-0.01em`으로(앱 제목 규격 -1%)
- 글자: 한글 음절 11,172 + 숫자 0~9 + 가운뎃점(U+00B7) + 공백. **라틴·기호 없음** → `font-family: Teolsil, 기존 글꼴` 순서로 두면 라틴은 다음 글꼴로 넘어간다
- Bold(120)는 엔진의 굵은 글자 보정(겹자음 틈·받침 상자·ㅎ/ㅊ 세로 꼭지)이 적용된 모양이라 Regular와 자모 상자가 조금 다르다
- 저작권: Firmtech(뜨개동네) 소유. 외부 배포·판매 전에는 OFL 등 라이선스 결정 필요
- 다음 단계 후보: 코바늘 기호 글리프(SYMLIB 94종, 사용자 영역 U+E000~) · 라틴 소문자 · 앱을 SVG 엔진 대신 @font-face 로 전환
