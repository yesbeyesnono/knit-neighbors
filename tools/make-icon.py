# 앱 아이콘·스플래시 생성 (PIL). 실행: python tools/make-icon.py  →  resources/icon.png, resources/splash.png
# 모티프: 흰 바탕에 검정 실뭉치(원 + 감긴 실 곡선) — Threads 톤(흑백)과 맞춤
from PIL import Image, ImageDraw
import math, os

os.makedirs('resources', exist_ok=True)

def yarn_ball(size, fg='#000000', bg='#ffffff', pad_ratio=0.16):
    img = Image.new('RGB', (size, size), bg)
    d = ImageDraw.Draw(img)
    cx = cy = size / 2
    r = size * (0.5 - pad_ratio)
    # 실뭉치 본체
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fg)
    # 감긴 실: 흰 곡선 여러 가닥 (본체 위에 살짝 기울어진 타원 호)
    stroke = max(2, int(size * 0.028))
    for k, (ang, ry) in enumerate([(-28, 0.62), (-10, 0.80), (12, 0.90), (34, 0.74), (52, 0.50)]):
        layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        rx = r * 0.98
        ryy = r * ry
        ld.ellipse([cx - rx, cy - ryy, cx + rx, cy + ryy], outline=bg, width=stroke)
        layer = layer.rotate(ang, resample=Image.BICUBIC, center=(cx, cy))
        # 본체 원 밖은 지움
        mask = Image.new('L', (size, size), 0)
        ImageDraw.Draw(mask).ellipse([cx - r + stroke, cy - r + stroke, cx + r - stroke, cy + r - stroke], fill=255)
        img.paste(layer, (0, 0), Image.composite(layer.split()[3], Image.new('L', (size, size), 0), mask))
    # 풀린 실 끝: 오른쪽 아래로 흘러나오는 곡선 (검정)
    pts = []
    for t in range(0, 101):
        u = t / 100
        x = cx + r * 0.55 + u * (size * 0.34 - r * 0.55)
        y = cy + r * 0.62 + math.sin(u * math.pi) * size * 0.06 + u * size * 0.05
        pts.append((x, y))
    d.line(pts, fill=fg, width=stroke, joint='curve')
    return img

icon = yarn_ball(1024)
icon.save('resources/icon.png')
# 스플래시 2732×2732 (Capacitor assets 권장), 가운데 아이콘
splash = Image.new('RGB', (2732, 2732), '#ffffff')
small = yarn_ball(900, pad_ratio=0.12)
splash.paste(small, ((2732 - 900) // 2, (2732 - 900) // 2))
splash.save('resources/splash.png')
# 다크 스플래시(선택)
splash_d = Image.new('RGB', (2732, 2732), '#111111')
small_d = yarn_ball(900, fg='#ffffff', bg='#111111', pad_ratio=0.12)
splash_d.paste(small_d, ((2732 - 900) // 2, (2732 - 900) // 2))
splash_d.save('resources/splash-dark.png')
print('ok: resources/icon.png, splash.png, splash-dark.png')
