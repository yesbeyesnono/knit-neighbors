# 뜨개동네 브랜드 자산 (명함·인쇄용)

`python tools/brand-assets.py` 로 만든다(앱 아이콘 `tools/make-icon.py` 와 같은 실뭉치 기하, 글자는 털실체 Bold 외곽선 path — 폰트 설치 없이 열림).
색: 바탕 #EDF2DD · 실뭉치 #3F4F22 · 글자 #3C4043 (앱 피스타치오 팔레트)

| 파일 | 용도 |
|---|---|
| `icon-square.svg/.png` | 스토어와 같은 정사각 아이콘(바탕색 포함) |
| `icon-rounded.svg/.png`, `icon-rounded@3x.png` | 모서리 둥근 아이콘(iOS 곡률) — 명함에 '앱 아이콘'으로 보일 때. @3x = 3072px 인쇄용 |
| `icon-mark.svg/.png` | 실뭉치만, 투명 바탕(감긴 실 틈도 뚫림) — 명함 바탕색 위에 올릴 때 |
| `logo-horizontal.svg/.png`, `@3x` | 실뭉치 + 뜨개동네 가로 조합, 투명 바탕 |
| `logo-vertical.svg/.png` | 세로 조합, 투명 바탕 |

인쇄소에는 SVG(벡터)를 주는 게 가장 선명하다. SVG 를 못 받으면 @3x PNG(300dpi 기준 약 26cm 폭).
