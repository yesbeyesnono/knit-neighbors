# 사용법 카드 그림(완성작품 인증 5장) — 시안 HTML(resources/mockups/cert_guide_series_20261115.html)의 SVG 를 꺼내 docs/guides/cert-N.svg 로 저장
# 실행: python tools/gen-guide-art.py   (그림을 고치려면 시안 HTML 의 SVG 를 고친 뒤 다시 실행)
import io, os, re
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
s = io.open(os.path.join(root, 'resources', 'mockups', 'cert_guide_series_20261115.html'), encoding='utf-8').read()
arts = re.findall(r'<div class="art" style="background:(#[0-9A-Fa-f]{6})"><svg width="230" height="150" viewBox="0 0 230 150">(.*?)</svg></div>', s, re.S)
assert len(arts) == 5, len(arts)
out = os.path.join(root, 'docs', 'guides'); os.makedirs(out, exist_ok=True)
for i, (bg, body) in enumerate(arts, 1):
    svg = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="-45 -14 320 178" width="640" height="356"><rect x="-45" y="-14" width="320" height="178" fill="{bg}"/>{body.strip()}</svg>\n'
    io.open(os.path.join(out, f'cert-{i}.svg'), 'w', encoding='utf-8', newline='').write(svg)
print('ok', len(arts))
