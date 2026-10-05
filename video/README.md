# 뜨개동네 소개 영상 (Remotion)

- `KnitIntro16x9` 1920×1080 · 30fps · 1350프레임(45초) — 투자사 미팅용
- `KnitIntro9x16` 1080×1920 — 같은 장면·타이밍의 세로판(보정 뒤 마무리)
- 장면 구간은 `src/theme.ts` `SCENES`, 색은 앱 팔레트(`C`)
- 글꼴: Noto Sans KR(OFL) — `npm install` 때 `tools/fetch-fonts.mjs`가 public/fonts 에 내려받음. 제목 로고는 앱의 털실체 엔진(`src/tsfont.js`, docs/index.html 복사본)

```
npm install
npx remotion studio            # 미리보기(타임라인)
npm run stills                 # 장면별 정지 화면 → out/
npm run render                 # MP4 → out/knit-intro-16x9.mp4
```
