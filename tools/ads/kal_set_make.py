# 받는 곳마다 '함께 뜨기' 제안 세트(영상 + 한 장 제안서)를 만든다.
#   python -X utf8 tools/ads/kal_set_make.py <세트 폴더> <작업 폴더> "이름|종류" ["이름|종류" ...]
#   종류: author(작가) · yarn(실 가게) · shop(공방 — 기본)
# 영상은 종류별로 전체를 한 번만 찍어 두고(작업 폴더/base_종류), 이름이 나오는 두 장면만 받는 곳마다 다시 찍어 끼운다.
# 음악: resources/ads/kal_film/bgm_happy_ukulele_song.mp3 (Pixabay — 저장소에는 올리지 않음)
import os, shutil, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FF = 'C:/Users/yesbe/AppData/Local/Microsoft/WinGet/Links/ffmpeg.exe'
SPEED, FPS, DUR = 1.44, 30, 69.5
NAME_PARTS = [(9, 14.5), (31.5, 40)]          # 이름이 보이는 장면(원래 시간, 초)
out_root, work = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
bgm = os.path.join(ROOT, 'resources/ads/kal_film/bgm_happy_ukulele_song.mp3')

def capture(dst, shop, kind, a, b):
    env = dict(os.environ, KAL_SHOP=shop)
    if kind in ('author', 'yarn'): env['KAL_KIND'] = kind
    else: env.pop('KAL_KIND', None)
    r = subprocess.run(['node', 'tools/ads/kal_film_capture.mjs', dst, str(FPS), str(a), str(b), str(SPEED)], cwd=ROOT, env=env, capture_output=True, text=True, encoding='utf-8')
    if r.returncode: raise SystemExit(r.stderr[-800:])

for item in sys.argv[3:]:
    name, _, kind = item.partition('|'); kind = kind or 'shop'
    base = os.path.join(work, 'base_' + kind)
    if not os.path.isdir(base) or len(os.listdir(base)) < 1400:
        shutil.rmtree(base, ignore_errors=True); capture(base, '공방', kind, 0, DUR); print('바탕', kind, len(os.listdir(base)), flush=True)
    tmp = os.path.join(work, 'one'); shutil.rmtree(tmp, ignore_errors=True); shutil.copytree(base, tmp)
    for a, b in NAME_PARTS: capture(tmp, name, kind, a, b)
    dst = os.path.join(out_root, name); os.makedirs(dst, exist_ok=True)
    n = len(os.listdir(tmp)); length = n / FPS
    r = subprocess.run([FF, '-y', '-loglevel', 'error', '-framerate', str(FPS), '-i', os.path.join(tmp, 'f_%05d.jpg'), '-i', bgm, '-map', '0:v', '-map', '1:a',
                        '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '18', '-preset', 'slow',
                        '-af', 'volume=0.7,afade=t=in:d=0.4,afade=t=out:st=%.2f:d=2.6' % (length - 2.67), '-t', '%.2f' % length,
                        '-c:a', 'aac', '-b:a', '160k', '-movflags', '+faststart', os.path.join(dst, '함께뜨기_소개영상.mp4')], capture_output=True, text=True)
    if r.returncode: raise SystemExit(r.stderr[-800:])
    r = subprocess.run([sys.executable, '-X', 'utf8', 'tools/ads/kal_proposal_shot.py', dst, name] + ([kind] if kind in ('author', 'yarn') else []), cwd=ROOT, capture_output=True, text=True, encoding='utf-8')
    if r.returncode: raise SystemExit(r.stderr[-800:])
    print('끝', name, kind, n, '프레임', sorted(os.listdir(dst)), flush=True)
shutil.rmtree(os.path.join(work, 'one'), ignore_errors=True)
