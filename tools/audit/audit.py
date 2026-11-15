import io,re,sys,json
R='C:/Users/yesbe/OneDrive/Documents/Claude/Projects/knit-neighbors/'
out={}
def analyze(fn):
    s=io.open(R+fn,encoding='utf-8').read()
    res={}
    # 함수 정의
    defs=set(re.findall(r'(?:async\s+)?function\s+([A-Za-z_$][\w$]*)\s*\(',s))
    defs|=set(re.findall(r'(?:^|[;{}\n])\s*(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s*)?(?:\([^)]*\)|[A-Za-z_$][\w$]*)\s*=>',s))
    dead=[]
    for d in sorted(defs):
        n=len(re.findall(r'(?<![\w$.])'+re.escape(d)+r'(?![\w$])',s))
        if n<=1: dead.append(d)
    res['defs']=len(defs); res['dead']=dead
    # 인라인 핸들러가 부르는 함수
    calls=set()
    for m in re.finditer(r'on(?:click|input|change|keydown|keyup|submit|focus|blur|load|error|touchstart|scroll)="([^"]*)"',s):
        for c in re.findall(r'(?<![\w$.\'])([A-Za-z_$][\w$]*)\s*\(',m.group(1)): calls.add(c)
    builtin={'if','event','alert','confirm','prompt','setTimeout','String','Number','parseInt','parseFloat','encodeURIComponent','JSON','Math','Date','Boolean','Array','Object','isNaN','return','function','typeof','void','for','while','switch','catch','requestAnimationFrame','open','close','focus','blur','print','decodeURIComponent','clearTimeout'}
    res['missing_handlers']=sorted(c for c in calls if c not in defs and c not in builtin and not re.search(r'(?:window\.|^|[\s;,{(])'+re.escape(c)+r'\s*=',s))
    # id 참조
    ids=set(re.findall(r'\bid="([A-Za-z][\w-]*)"',s))|set(re.findall(r"\bid='([A-Za-z][\w-]*)'",s))|set(re.findall(r'\.id\s*=\s*[\'"]([A-Za-z][\w-]*)[\'"]',s))
    refs=set(re.findall(r"\$\('#([A-Za-z][\w-]*)'\)",s))|set(re.findall(r'getElementById\([\'"]([A-Za-z][\w-]*)[\'"]\)',s))
    res['missing_ids']=sorted(r for r in refs if r not in ids and not re.search(r'id="'+re.escape(r)+r'[\$"-]|id=\\?"\$\{[^}]*\}|id="'+re.escape(r[:3]),s))
    res['missing_ids_strict']=sorted(r for r in refs if r not in ids)
    dup=[i for i in ids if len(re.findall(r'<[a-z][^>]*\bid="'+re.escape(i)+r'"',s))>1]
    res['dup_ids']=sorted(dup)[:60]
    res['rpc']=sorted(set(re.findall(r"\.rpc\(\s*['\"]([\w]+)['\"]",s)))
    res['tables']=sorted(set(re.findall(r"\.from\(\s*['\"]([\w]+)['\"]",s)))
    res['buckets']=sorted(set(re.findall(r"storage\.from\(\s*['\"]([\w-]+)['\"]",s)))
    res['fn_invoke']=sorted(set(re.findall(r"functions\.invoke\(\s*['\"]([\w-]+)['\"]",s))|set(re.findall(r"functions/v1/([\w-]+)",s)))
    # 낱말
    words={'답글':0,'작품 인증':0,'해결됐어요':0,'서포터':0,'KOAP':0,'TODO':0,'FIXME':0,'console.log':0,'debugger':0,'카카오':0,'Lv.':0,'신청 대기 중':0}
    for w in words: words[w]=len(re.findall(re.escape(w),s))
    res['words']=words
    # '완성작품 인증'을 뺀 '작품 인증'
    res['작품 인증(완성 제외)']=len(re.findall(r'(?<!완성)작품 인증',s))
    res['size']=len(s); res['lines']=s.count('\n')
    # CSS 클래스: 정의됐지만 안 쓰이는 것(대략)
    style=''.join(re.findall(r'<style[^>]*>(.*?)</style>',s,flags=re.S)); body=re.sub(r'<style[^>]*>.*?</style>','',s,flags=re.S)
    classes=set(re.findall(r'\.([A-Za-z][\w-]*)',re.sub(r'\{[^}]*\}','{}',style)))
    unused=[c for c in sorted(classes) if not re.search(r'(?<![\w-])'+re.escape(c)+r'(?![\w-])',body)]
    res['css_classes']=len(classes); res['css_unused']=unused
    res['style_bytes']=len(style)
    return res
for fn in ['docs/index.html','docs/admin.html']:
    out[fn]=analyze(fn)
json.dump(out,io.open('C:/Users/yesbe/AppData/Local/Temp/claude/0422a6549ab0c97e/27c68b59-113b-41d4-b2cf-d0547eb8f68d/scratchpad/audit1.json','w',encoding='utf-8'),ensure_ascii=False,indent=0)
for fn,r in out.items():
    print('=====',fn,r['size'],'bytes',r['lines'],'lines; funcs',r['defs'],'; css classes',r['css_classes'],'style bytes',r['style_bytes'])
    print('dead funcs',len(r['dead']),':',' '.join(r['dead']))
    print('missing handlers:',r['missing_handlers'])
    print('missing ids(strict)',len(r['missing_ids_strict']),':',' '.join(r['missing_ids_strict'][:80]))
    print('dup ids:',r['dup_ids'])
    print('words:',r['words'],'작품 인증(완성 제외)',r['작품 인증(완성 제외)'])
    print('css unused',len(r['css_unused']),':',' '.join(r['css_unused'][:150]))
    print('rpc',len(r['rpc']),'tables',len(r['tables']),'buckets',r['buckets'],'fn',r['fn_invoke'])
