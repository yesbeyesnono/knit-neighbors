# Supabase Storage 키는 한글 불가(InvalidKey) → photos_apply.json 의 file 을 ASCII 이름으로 바꿔 복사
#   <site>/<md5(product|no)[:16]>.jpg 로 <out>/photos_ascii/ 에 복사, photos_apply.json·photos_files.txt 를 새 이름으로 덮어씀
# 사용: python tools/shops-photos-ascii.py <out폴더>  (shops-photos-apply.py 다음, upload-yarn-colors.py <out>/photos_ascii <out>/photos_files.txt 전에)
import io, os, sys, json, hashlib, shutil
OUT = sys.argv[1]
items = json.load(io.open(os.path.join(OUT, 'photos_apply.json'), encoding='utf-8'))
dst_root = os.path.join(OUT, 'photos_ascii'); n = 0
for it in items:
    site = it['file'].split('/')[0]
    if all(ord(ch) < 128 for ch in it['file']): new = it['file']
    else: new = f"{site}/{hashlib.md5((it['product'] + '|' + (it['no'] or it['name'] or '')).encode('utf-8')).hexdigest()[:16]}.jpg"
    src = os.path.join(OUT, 'photos', it['file'].replace('/', os.sep)); dst = os.path.join(dst_root, new.replace('/', os.sep))
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if not os.path.exists(dst): shutil.copyfile(src, dst); n += 1
    it['file'] = new
io.open(os.path.join(OUT, 'photos_apply.json'), 'w', encoding='utf-8').write(json.dumps(items, ensure_ascii=False))
io.open(os.path.join(OUT, 'photos_files.txt'), 'w', encoding='utf-8').write('\n'.join(it['file'] for it in items))
print('copied', n, 'items', len(items), 'unique files', len({it['file'] for it in items}))
