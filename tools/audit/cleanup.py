import io,re,sys
R='C:/Users/yesbe/OneDrive/Documents/Claude/Projects/knit-neighbors/'
def scan_end(s,i):
    """i = 본문을 여는 '{' 위치. 짝이 맞는 '}' 의 다음 위치를 돌려준다 (문자열·템플릿·주석·정규식 무시)."""
    depth=0; n=len(s); stack=[]   # stack: 'tpl' 안의 ${ 깊이 기록
    prev=''  # 직전의 의미 있는 글자
    while i<n:
        c=s[i]
        if c=='"' or c=="'":
            j=i+1
            while j<n and s[j]!=c:
                if s[j]=='\\': j+=1
                if s[j]=='\n': break
                j+=1
            i=j+1; prev='s'; continue
        if c=='`':
            j=i+1
            while j<n:
                if s[j]=='\\': j+=2; continue
                if s[j]=='`': break
                if s[j]=='$' and j+1<n and s[j+1]=='{':
                    j=scan_end(s,j+1); continue
                j+=1
            i=j+1; prev='s'; continue
        if c=='/' and i+1<n and s[i+1]=='/':
            j=s.find('\n',i); i=n if j<0 else j; continue
        if c=='/' and i+1<n and s[i+1]=='*':
            j=s.find('*/',i+2); i=n if j<0 else j+2; continue
        if c=='/' and (prev in '(,=:[!&|?{};+-*%<>~^' or prev=='' or prev=='k'):
            j=i+1; incls=False
            while j<n:
                if s[j]=='\\': j+=2; continue
                if s[j]=='\n': break
                if s[j]=='[': incls=True
                elif s[j]==']': incls=False
                elif s[j]=='/' and not incls: break
                j+=1
            i=j+1; prev='s'; continue
        if c=='{': depth+=1
        elif c=='}':
            depth-=1
            if depth==0: return i+1
        if not c.isspace():
            if c.isalnum() or c in '_$':
                # 'return' 'typeof' 같은 낱말 뒤의 / 는 정규식
                m=re.match(r'[A-Za-z_$][\w$]*',s[i:])
                if m:
                    w=m.group(0); i+=len(w); prev='k' if w in ('return','typeof','case','in','of','do','else','void','delete','throw','new') else 'w'; continue
            prev=c
        i+=1
    raise Exception('no end')
def dead_funcs(s):
    defs=set(re.findall(r'(?:async\s+)?function\s+([A-Za-z_$][\w$]*)\s*\(',s))
    return sorted(d for d in defs if len(re.findall(r'(?<![\w$.])'+re.escape(d)+r'(?![\w$])',s))<=1)
def remove_func(s,name):
    m=re.search(r'(?:async\s+)?function\s+'+re.escape(name)+r'\s*\(',s)
    if not m: return s,False
    # 매개변수 괄호 끝
    i=m.end()-1; d=0
    while True:
        if s[i]=='(': d+=1
        elif s[i]==')':
            d-=1
            if d==0: break
        i+=1
    j=s.index('{',i); e=scan_end(s,j)
    a=m.start()
    # 한 줄을 통째로 차지하면 줄째 지운다
    ls=s.rfind('\n',0,a)+1; le=s.find('\n',e); le=len(s) if le<0 else le
    if s[ls:a].strip()=='' and s[e:le].strip() in ('',';'):
        return s[:ls]+s[le+1:],True
    return s[:a]+s[e:].lstrip(' ') if s[a-1:a] in (' ','\t') else s[:a]+s[e:],True
def clean_js(fn, keep=()):
    s=io.open(R+fn,encoding='utf-8',newline='').read(); removed=[]
    for rnd in range(6):
        d=[x for x in dead_funcs(s) if x not in keep]
        if not d: break
        for name in d:
            s2,ok=remove_func(s,name)
            if ok: s=s2; removed.append(name)
    return s,removed
def clean_css(s):
    out=[]; removed=[]
    def fix(m):
        style=m.group(2)
        body=s[:m.start()]+s[m.end():]
        classes=set(re.findall(r'\.([A-Za-z][\w-]*)',re.sub(r'\{[^{}]*\}','{}',style)))
        dead=set(c for c in classes if c not in body and not re.match(r'(leaflet|gm-|n\d)',c))
        if not dead: return m.group(0)
        def rule(r):
            sels=[x for x in r.group(1).split(',')]
            keepS=[x for x in sels if not any(re.search(r'\.'+re.escape(c)+r'(?![\w-])',x) for c in dead)]
            if len(keepS)==len(sels): return r.group(0)
            removed.append(r.group(1).strip()[:60])
            if not keepS: return ''
            return ','.join(keepS)+'{'+r.group(2)+'}'
        new=re.sub(r'([^{}@/]+)\{([^{}]*)\}',rule,style)
        new=re.sub(r'\n[ \t]*\n+','\n',new)
        return m.group(1)+new+m.group(3)
    s2=re.sub(r'(<style[^>]*>)(.*?)(</style>)',fix,s,flags=re.S)
    return s2,removed
for fn in ['docs/index.html','docs/admin.html']:
    s0=io.open(R+fn,encoding='utf-8',newline='').read()
    s,rm=clean_js(fn)
    s,rc=clean_css(s)
    io.open(R+fn,'w',encoding='utf-8',newline='').write(s)
    print(fn,len(s0),'->',len(s),'| funcs removed',len(rm),rm,'| css rules touched',len(rc))
    print('   css:',rc[:60])
