# @capacitor/assets 대체: resources/icon.png → Android 런처 아이콘(legacy + adaptive) 생성
# 실행: python tools/android-icons.py
from PIL import Image, ImageDraw
import os

SRC = 'resources/icon.png'
RES = 'android/app/src/main/res'
DENS = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
src = Image.open(SRC).convert('RGBA')

for d, px in DENS.items():
    folder = os.path.join(RES, f'mipmap-{d}'); os.makedirs(folder, exist_ok=True)
    legacy = src.resize((px, px), Image.LANCZOS)
    legacy.save(os.path.join(folder, 'ic_launcher.png'))
    # 둥근 아이콘
    mask = Image.new('L', (px, px), 0); ImageDraw.Draw(mask).ellipse([0, 0, px - 1, px - 1], fill=255)
    rnd = Image.new('RGBA', (px, px), (0, 0, 0, 0)); rnd.paste(legacy, (0, 0), mask); rnd.save(os.path.join(folder, 'ic_launcher_round.png'))
    # adaptive foreground: 108dp 캔버스에 66dp 안전 영역 → 아이콘을 62%로 중앙 배치, 배경은 흰색
    fg_px = int(px * 108 / 48)
    fg = Image.new('RGBA', (fg_px, fg_px), (0, 0, 0, 0))
    inner = int(fg_px * 0.62); icon = src.resize((inner, inner), Image.LANCZOS)
    fg.paste(icon, ((fg_px - inner) // 2, (fg_px - inner) // 2), icon)
    fg.save(os.path.join(folder, 'ic_launcher_foreground.png'))

# adaptive icon xml + 배경색
os.makedirs(os.path.join(RES, 'mipmap-anydpi-v26'), exist_ok=True)
xml = '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
'''
for name in ('ic_launcher.xml', 'ic_launcher_round.xml'):
    open(os.path.join(RES, 'mipmap-anydpi-v26', name), 'w', encoding='utf-8').write(xml)
os.makedirs(os.path.join(RES, 'values'), exist_ok=True)
open(os.path.join(RES, 'values', 'ic_launcher_background.xml'), 'w', encoding='utf-8').write(
    '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">#FFFFFF</color>\n</resources>\n')
# 스플래시 (drawable) — 흰 바탕 중앙 아이콘
for d, px in {'mdpi': 320, 'hdpi': 480, 'xhdpi': 720, 'xxhdpi': 1080, 'xxxhdpi': 1440}.items():
    folder = os.path.join(RES, f'drawable-{d}'); os.makedirs(folder, exist_ok=True)
    sp = Image.new('RGB', (px, px), '#ffffff'); ic = src.resize((px // 3, px // 3), Image.LANCZOS)
    sp.paste(ic, ((px - px // 3) // 2, (px - px // 3) // 2), ic); sp.save(os.path.join(folder, 'splash.png'))
print('android icons written')
