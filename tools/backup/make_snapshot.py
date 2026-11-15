# 서버 구조 스냅숏: Supabase 에서 뽑은 JSON(구조만, 회원 데이터 없음)을 사람이 읽고 다시 만들 수 있는 파일들로 나눈다.
#   쓰는 법: python tools/backup/make_snapshot.py <execute_sql 결과가 저장된 파일>
#   뽑는 SQL 은 supabase/snapshot/README.md 맨 아래에 있다. 결과는 supabase/snapshot/ 에 쓰인다(이 저장소는 공개이므로 비밀 값이 섞이면 멈춘다).
import io, json, re, sys, os
src = sys.argv[1]
raw = io.open(src, encoding='utf-8').read()
try:
    raw = json.loads(raw)['result']
except Exception:
    pass
a = raw.index('[{'); b = raw.rindex('}]') + 2
snap = json.loads(raw[a:b])[0]
snap = snap.get('snapshot', snap)
OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'supabase', 'snapshot')
os.makedirs(OUT, exist_ok=True)
SECRET = re.compile(r'eyJ[A-Za-z0-9_-]{20,}|sb_secret_[A-Za-z0-9_-]+|Bearer [A-Za-z0-9._-]{30,}|\b\d{8,10}:[A-Za-z0-9_-]{30,}|-----BEGIN [A-Z ]*PRIVATE KEY')
def w(name, text):
    m = SECRET.search(text)
    if m: raise SystemExit('비밀 값처럼 보이는 글자가 있어 멈춤: %s … %s' % (name, m.group(0)[:12]))
    io.open(os.path.join(OUT, name), 'w', encoding='utf-8', newline='\n').write(text)
    print(name, len(text))
# 함수
fs = snap['functions'] or []
w('functions.sql', '-- public 스키마 함수 %d개 (pg_get_functiondef 그대로). 권한(acl)은 각 함수 위 주석\n\n' % len(fs) + '\n\n'.join('-- %s(%s)  acl: %s\n%s;' % (f['name'], f['args'], f['acl'], f['def'].rstrip()) for f in fs) + '\n')
# 표
ts = snap['tables'] or []
out = ['-- 표 %d개: 칸·제약·RLS·권한. (만드는 순서와 외래 키 순서는 보장하지 않음 — 복구할 때는 supabase_migrations 기록이 원본)\n' % len(ts)]
for t in ts:
    cols = ',\n'.join('  %s %s%s%s' % (c['n'], c['ty'], ' not null' if c['nn'] else '', (' default ' + c['def']) if c.get('def') else '') for c in (t['cols'] or []))
    out.append('create table %s (\n%s\n);' % (t['t'], cols))
    for c in (t.get('cons') or []): out.append('alter table %s add constraint %s %s;' % (t['t'], c['n'], c['def']))
    if t['rls']: out.append('alter table %s enable row level security;' % t['t'])
    out.append('-- acl: %s\n' % t['acl'])
w('tables.sql', '\n'.join(out) + '\n')
w('indexes.sql', '\n'.join(x + ';' for x in (snap['indexes'] or [])) + '\n')
ps = snap['policies'] or []
w('policies.sql', '\n'.join('create policy "%s" on %s.%s for %s to %s%s%s;' % (p['n'], p['s'], p['t'], p['cmd'], (p['roles'] or '{public}').strip('{}'), (' using (%s)' % p['using']) if p.get('using') else '', (' with check (%s)' % p['check']) if p.get('check') else '') for p in ps) + '\n')
w('triggers.sql', '\n'.join(x + ';' for x in (snap['triggers'] or [])) + '\n')
w('cron.sql', '\n'.join("-- %s%s\nselect cron.schedule('%s', '%s', $cron$%s$cron$);" % (c['job'], '' if c['active'] else ' (꺼짐)', c['job'], c['schedule'], c['command']) for c in (snap['cron'] or [])) + '\n')
w('misc.json', json.dumps({k: snap.get(k) for k in ('col_grants', 'buckets', 'extensions', 'views', 'types', 'migrations')}, ensure_ascii=False, indent=1) + '\n')
w('app_config.json', json.dumps(snap.get('app_config'), ensure_ascii=False, indent=1) + '\n')
print('ok: functions %d, tables %d, policies %d, triggers %d, cron %d' % (len(fs), len(ts), len(ps), len(snap['triggers'] or []), len(snap['cron'] or [])))
