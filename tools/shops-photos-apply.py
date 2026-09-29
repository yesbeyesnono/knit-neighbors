# photos.json → admin_yarn_photos_apply 용 JSON (<out>/photos_apply.json)
#  · 같은 (site, product, no) 는 마지막 것만 · 파일이 실제로 있는 것만
#  · 실행 순서: python tools/upload-yarn-colors.py <out>/photos → 이 스크립트 → python tools/upload-file.py <out>/photos_apply.json photos_apply.json application/json yarn-import
#    → SQL: select net.http_get('https://<proj>.supabase.co/storage/v1/object/public/yarn-import/photos_apply.json'); (잠시 뒤) select public.admin_yarn_photos_apply(content::jsonb) from net._http_response where id=<id>;
# 사용: python tools/shops-photos-apply.py <out폴더>
import io, os, sys, json
OUT = sys.argv[1]
res = json.load(io.open(os.path.join(OUT, 'photos.json'), encoding='utf-8'))
seen = {}
for r in res:
    if not os.path.exists(os.path.join(OUT, 'photos', r['file'].replace('/', os.sep))): continue
    seen[(r['site'], r['product'], r['no'] or r['name'])] = r
items = [{'brand': r['brand'], 'product': r['product'], 'no': r['no'], 'name': r['name'], 'file': r['file'], 'hex': r['hex'], 'mode': r['mode']} for r in seen.values()]
io.open(os.path.join(OUT, 'photos_apply.json'), 'w', encoding='utf-8').write(json.dumps(items, ensure_ascii=False))
io.open(os.path.join(OUT, 'photos_files.txt'), 'w', encoding='utf-8').write('\n'.join(r['file'] for r in seen.values()))   # upload-yarn-colors.py 2번째 인자
print('items', len(items), 'of', len(res))
