# normalized.json → admin_yarn_bulk_upsert 호출용 SQL 조각(<out>/import_NN.sql). 실행은 Supabase MCP execute_sql 로(관리자 권한 = postgres)
# 사용: python tools/shops-import.py <out폴더> [chunk=30]
import io, os, sys, json, re
OUT = sys.argv[1]; CH = int(sys.argv[2]) if len(sys.argv) > 2 else 30
rows = json.load(io.open(os.path.join(OUT, 'normalized.json'), encoding='utf-8'))
def q(s): return s.replace("'", "''")
items = []
for r in rows:
    if r.get('bundle') and not r.get('colors'): pass
    aliases = [r['raw_title']] + ([r['product_en']] if r.get('product_en') else [])
    aliases = [re.sub(r'\s*[-|]\s*(쎄비 SEVY|앵콜스 ANCALLS|바늘이야기)\s*$', '', a)[:60] for a in aliases if a]
    items.append({'brand': r['brand'], 'product': r['product'], 'product_en': r.get('product_en'), 'aliases': aliases, 'g': r['g'], 'm': r['m'], 'fibers': r['fibers'], 'fiber_main': r['fiber_main'],
                  'weight_class': (None if (r['g'] and r['m']) else r.get('weight_class')), 'season': r['season'], 'needle_knit': r['needle_knit'], 'needle_crochet': r['needle_crochet'], 'gauge': r['gauge'], 'put_up': (r.get('put_ups') or [None])[0],
                  'texture': r['texture'], 'use_tags': r['use_tags'], 'shop': r['shop'], 'url': r['url'],
                  'colors': [{'no': c['no'], 'name': c['name']} for c in r['colors'][:200]], 'sellers': r['sellers']})
io.open(os.path.join(OUT, 'import_items.json'), 'w', encoding='utf-8').write(json.dumps(items, ensure_ascii=False))
n = 0
for i in range(0, len(items), CH):
    chunk = items[i:i + CH]
    sql = "select public.admin_yarn_bulk_upsert('" + q(json.dumps(chunk, ensure_ascii=False)) + "'::jsonb);"
    io.open(os.path.join(OUT, f'import_{n:02d}.sql'), 'w', encoding='utf-8').write(sql); n += 1
print('items', len(items), 'chunks', n)
