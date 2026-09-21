# 코바늘 기호 94종 검수 시트 — 외부 담당자 전달용(파일 하나로 열림: 원본 기호 이미지를 안에 넣고, 검수 표시·메모·결과 복사 기능 포함)
#   python tools/gen-crochet-symbols.py 를 먼저 실행한 뒤:  python tools/build-symbol-review-share.py
#   결과: resources/symbols/ref/코바늘기호94_검수요청.html  (원본 이미지는 책에서 온 것이라 저장소에는 올리지 않는다 — 검수 목적의 전달용)
import io, json, os, base64, datetime
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SYM = os.path.join(ROOT, 'resources', 'symbols')
lib = json.load(io.open(os.path.join(SYM, 'crochet_symbols_v1.2.json'), encoding='utf-8'))['symbols']
master = {m['no']: m for m in json.load(io.open(os.path.join(ROOT, 'tools', 'crochet-symbols-master.json'), encoding='utf-8'))}
esc = lambda s: (s or '').replace('&', '&amp;').replace('<', '&lt;').replace('"', '&quot;')
b64 = lambda no: base64.b64encode(open(os.path.join(SYM, 'ref', '%02d.png' % no), 'rb').read()).decode()
today = datetime.date.today().strftime('%Y-%m-%d')

cards, sec = [], None
for key, v in sorted(lib.items(), key=lambda kv: kv[1]['no']):
    m = master[v['no']]
    if m['sec'] != sec:
        cards.append(('</div>' if sec else '') + '<h2>%s</h2><div class="g">' % esc(m['sec'])); sec = m['sec']
    same = ' <span class="tag same">기호는 %d번과 같음(이름으로 구분)</span>' % lib[v['same_as']]['no'] if v.get('same_as') else ''
    cards.append('''<div class="c" data-no="%d" data-ko="%s"><div class="pic"><div><svg width="%d" height="64" viewBox="0 0 %d 48" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">%s</svg><small>새로 그린 기호</small></div><div><img src="data:image/png;base64,%s" alt=""><small>원본</small></div></div>
<div class="tx"><span class="no">%d</span> <span class="ko">%s</span><div class="jp">%s</div><div class="en">%s</div>%s</div>
<div class="fb"><label><input type="radio" name="r%d" value="ok"> 맞아요</label><label><input type="radio" name="r%d" value="fix"> 고쳐야 해요</label><input type="text" placeholder="어디가 다른지 · 이름이 어색하면 바른 이름" maxlength="200"></div></div>''' % (
        v['no'], esc(m['ko']), round(64 * v['w'] / 48), v['w'], v['svg'], b64(v['no']), v['no'], esc(m['ko']), esc(m['jp']), esc(m['en']), same, v['no'], v['no']))
cards.append('</div>')

html = '''<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>코바늘 기호 94종 검수 요청</title>
<style>
body{font-family:-apple-system,BlinkMacSystemFont,"Apple SD Gothic Neo","Malgun Gothic","Noto Sans KR",sans-serif;margin:0;color:#3C4043;background:#fff;line-height:1.45;word-break:keep-all}
.wrap{max-width:1180px;margin:0 auto;padding:20px 16px 120px}
h1{font-size:22px;margin:0 0 6px}h2{font-size:15px;margin:26px 0 10px;padding-top:12px;border-top:1px solid #e3e3e3}
.lead{color:#6A6E73;font-size:14px;margin:0 0 12px}.box{background:#f5f5f5;border-radius:12px;padding:12px 14px;font-size:13.5px;margin:10px 0}.box b{color:#3C4043}.box ul{margin:6px 0 0;padding-left:18px}
.g{display:grid;grid-template-columns:repeat(auto-fill,minmax(340px,1fr));gap:10px}
.c{border:1px solid #e3e3e3;border-radius:12px;padding:10px 12px;display:grid;grid-template-columns:170px 1fr;gap:6px 12px;align-items:center}
.c.fix{border-color:#B5605A;background:#fdf6f5}.c.ok{border-color:#5C7A4C}
.pic{display:flex;gap:8px;align-items:flex-end}.pic>div{text-align:center}.pic small{display:block;font-size:10.5px;color:#9AA0A6;margin-top:2px}
.pic svg{background:#fafafa;border-radius:8px}.pic img{height:50px;border-radius:6px;border:1px solid #eee;display:block}
.no{font-weight:700;color:#5C7A4C}.ko{font-weight:600;font-size:14.5px}.jp,.en{font-size:12px;color:#6A6E73}
.tag{display:inline-block;font-size:11px;padding:1px 7px;border-radius:99px;margin-top:3px}.tag.same{background:#eee;color:#666}
.fb{grid-column:1 / -1;display:flex;gap:10px;align-items:center;flex-wrap:wrap;font-size:13px;border-top:1px dashed #e3e3e3;padding-top:8px}
.fb input[type=text]{flex:1;min-width:180px;font:inherit;padding:7px 10px;border:1px solid #ddd;border-radius:8px}
.bar{position:fixed;left:0;right:0;bottom:0;background:#fff;border-top:1px solid #ddd;padding:10px 16px;display:flex;gap:10px;align-items:center;justify-content:center;flex-wrap:wrap;font-size:13.5px}
.bar button{font:inherit;font-weight:600;padding:10px 16px;border-radius:10px;border:1px solid #3C4043;background:#3C4043;color:#fff;cursor:pointer}.bar button.o{background:#fff;color:#3C4043}
textarea#out{width:100%;min-height:160px;font:13px/1.5 inherit;padding:10px;border:1px solid #ddd;border-radius:10px;margin-top:10px;display:none}
@media (max-width:520px){.c{grid-template-columns:1fr}.g{grid-template-columns:1fr}}
@media print{.bar{display:none}.c{break-inside:avoid}}
</style></head><body><div class="wrap">
<h1>코바늘 기호 94종 검수 요청</h1>
<p class="lead">뜨개동네 · knitup — 작성일 __DATE__ · 이 파일 하나만 열면 됩니다(인터넷 연결 불필요).</p>
<div class="box"><b>무엇을 봐 주시면 되나요</b>
<ul><li>각 칸의 <b>왼쪽 = 저희가 새로 그린 기호</b>, <b>오른쪽 = 원본 표의 기호</b>입니다. 모양이 같은 뜻으로 읽히는지 봐 주세요(선 굵기·비율이 조금 다른 것은 괜찮습니다).</li>
<li><b>한국어 이름</b>이 현장에서 쓰는 말과 다르면 바른 이름을 적어 주세요. 이름은 한국 관행(긴뜨기 · 한길 긴뜨기 · 두길 긴뜨기 · 세길 · 네길)으로 통일했습니다.</li>
<li>칸마다 「맞아요 / 고쳐야 해요」를 고르고, 고칠 곳은 한 줄로 적어 주세요. 다 보신 뒤 맨 아래 <b>「검수 결과 복사」</b>를 눌러 그 내용을 메일·메신저로 보내 주시면 됩니다.</li></ul></div>
<div class="box"><b>그린 규칙</b> — 책의 그림을 옮긴 것이 아니라 JIS 편목기호 규칙으로 새로 그렸습니다: 기둥의 <b>사선 수 = 실을 감는 횟수</b>(긴 0 · 한길 긴 1 · 두길 2 · 세길 3 · 네길 4) / <b>밑이 한 점에 모이면 「코에 넣어」</b>, <b>밑이 떨어져 있으면 「코 아래(사슬 공간)에서」</b> / 위가 한 점에 모이면 모아뜨기·구슬뜨기. 짧은뜨기는 ×로 그렸습니다(원본은 +, 같은 기호의 두 가지 표기).
<br>원본 기호 이미지는 검수 대조용으로만 넣었습니다. 이 파일은 외부에 공개·재배포하지 말아 주세요.</div>
__CARDS__
<textarea id="out" readonly></textarea>
</div>
<div class="bar"><span id="stat">0 / 94 확인</span><button class="o" onclick="onlyFix()">고칠 것만 보기</button><button onclick="copyResult()">검수 결과 복사</button></div>
<script>
var KEY='crochet94-review-v1';
function cards(){return [].slice.call(document.querySelectorAll('.c'));}
function state(){var o={};cards().forEach(function(c){var r=c.querySelector('input[type=radio]:checked');var t=c.querySelector('input[type=text]').value.trim();if(r||t)o[c.dataset.no]={v:r?r.value:'',t:t};});return o;}
function paint(){var n=0;cards().forEach(function(c){var r=c.querySelector('input[type=radio]:checked');c.classList.toggle('fix',!!r&&r.value==='fix');c.classList.toggle('ok',!!r&&r.value==='ok');if(r)n++;});document.getElementById('stat').textContent=n+' / 94 확인';}
function save(){try{localStorage.setItem(KEY,JSON.stringify(state()));}catch(e){} paint();}
function load(){var o={};try{o=JSON.parse(localStorage.getItem(KEY)||'{}');}catch(e){} cards().forEach(function(c){var s=o[c.dataset.no];if(!s)return;if(s.v){var r=c.querySelector('input[value="'+s.v+'"]');if(r)r.checked=true;}c.querySelector('input[type=text]').value=s.t||'';});paint();}
document.addEventListener('change',save);document.addEventListener('input',function(e){if(e.target.type==='text'){var c=e.target.closest('.c');if(e.target.value.trim()&&!c.querySelector('input[type=radio]:checked')){c.querySelector('input[value=fix]').checked=true;}save();}});
var showFix=false;function onlyFix(){showFix=!showFix;cards().forEach(function(c){c.style.display=(!showFix||c.classList.contains('fix'))?'':'none';});event.target.textContent=showFix?'전체 보기':'고칠 것만 보기';}
function copyResult(){var s=state(),fix=[],ok=0;cards().forEach(function(c){var x=s[c.dataset.no];if(!x)return;if(x.v==='fix'||x.t)fix.push(c.dataset.no+'번 '+c.dataset.ko+' — '+(x.t||'(내용 없음)'));else if(x.v==='ok')ok++;});
 var txt='[코바늘 기호 94종 검수 결과]\\n맞아요 '+ok+'개 · 고쳐야 해요 '+fix.length+'개 · 미확인 '+(94-ok-fix.length)+'개\\n\\n'+(fix.length?fix.join('\\n'):'고칠 곳 없음');
 var ta=document.getElementById('out');ta.style.display='block';ta.value=txt;ta.select();
 if(navigator.clipboard&&navigator.clipboard.writeText){navigator.clipboard.writeText(txt).then(function(){alert('복사했어요. 메일이나 메신저에 붙여 넣어 보내 주세요.');},function(){alert('아래 상자의 내용을 복사해 보내 주세요.');});}else{try{document.execCommand('copy');alert('복사했어요.');}catch(e){alert('아래 상자의 내용을 복사해 보내 주세요.');}}
 ta.scrollIntoView({behavior:'smooth'});}
load();
</script></body></html>'''.replace('__DATE__', today).replace('__CARDS__', '\n'.join(cards))
out = os.path.join(SYM, 'ref', '코바늘기호94_검수요청.html')
io.open(out, 'w', encoding='utf-8').write(html)
print(out, os.path.getsize(out) // 1024, 'KB')
