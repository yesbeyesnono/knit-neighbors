// knitup v9 앱의 📐 사이즈 변환 뷰어(VIEWER_SIZE_HTML)를 뽑아 뜨개동네용 docs/viewer.html 로 만든다.
// 사용: node tools/build-viewer.js [knitup/docs/app_v9.html 경로]
// knitup 쪽 뷰어가 바뀌면 다시 실행하면 된다. (knitup 폴더에서는 읽기만 한다)
const fs = require('fs');
const path = require('path');
const srcPath = process.argv[2] || path.join(__dirname, '..', '..', 'knitup', 'docs', 'app_v9.html');
const src = fs.readFileSync(srcPath, 'utf8');
const head = 'const VIEWER_SIZE_HTML = `';
const i = src.indexOf(head);
if (i < 0) throw new Error('VIEWER_SIZE_HTML not found');
let k = i + head.length;
for (;; k++) { if (src[k] === '\\') { k++; continue; } if (src[k] === '`') break; }
let html = eval(src.slice(i + head.length - 1, k + 1));

const css = `<style id="kn-embed">
  body{visibility:hidden;-webkit-text-size-adjust:100%}
  body.kn-ready{visibility:visible}
  header{padding:calc(env(safe-area-inset-top,0px) + 52px) 14px 0 !important}
  .wrap{padding:10px 14px calc(env(safe-area-inset-bottom,0px) + 40px) !important}
  #btnPkg,#filePkg{display:none !important}
  #chartVp{height:min(62vh,560px) !important;touch-action:none}
  .vzhint{display:none}
  .wrap > .card:first-child{display:none} /* 실 소요량 카드: 실 DB가 예시 데이터라 뜨개동네에서는 숨김 */
  .main{margin-top:0 !important}
  .main > div:last-child{display:none} /* AI 사이즈 변환 대화: 모자 전용 데모라 뜨개동네에서는 숨김(추후 연동) */
  .main{grid-template-columns:1fr !important}
  h1{font-size:20px !important;line-height:1.3}
  #knBar{position:fixed;left:0;right:0;top:0;z-index:50;display:flex;align-items:center;gap:8px;padding:calc(env(safe-area-inset-top,0px) + 8px) 10px 8px;background:rgba(255,255,255,.94);backdrop-filter:blur(8px);border-bottom:1px solid #e5e5e5;font-family:inherit}
  #knBar button{border:0;background:none;font-size:15px;font-weight:700;padding:8px 10px;cursor:pointer;font-family:inherit;color:#000}
  #knBar span{font-size:12px;color:#777;margin-left:auto;padding-right:6px}
  @media(max-width:700px){ .ystats{grid-template-columns:1fr 1fr !important} table.instr{font-size:13px} }
</style>`;

const js = `<script>
/* ── 뜨개동네 임베드: 닫기 바 · 진도 저장 브리지 · 터치 이동/확대 · 로컬 파서 고정 ── */
(function(){
  var bar=document.createElement('div'); bar.id='knBar';
  bar.innerHTML='<button id="knClose">‹ 닫기</button><span id="knSaved"></span>';
  document.body.appendChild(bar);
  document.getElementById('knClose').onclick=function(){ parent.postMessage({type:'kn-close'},'*'); };
  var brand=document.querySelector('.brand'); if(brand) brand.textContent='뜨개동네 · 도안 뷰어 (knitup)';
  // AI 연결(API 키) 카드는 숨기고 키 없이 도는 로컬 파서만 사용
  try{ var pv=document.getElementById('aiProv'); if(pv){ pv.value='local'; var c=pv.closest('.card'); if(c) c.style.display='none'; } }catch(e){}
  // 진도: 바뀔 때마다 부모에 알림
  var _setProg=window.setProg||setProg, lastSent=-1;
  function report(){ try{ if(prog!==lastSent){ lastSent=prog; parent.postMessage({type:'kn-prog', prog:prog},'*'); var s=document.getElementById('knSaved'); if(s) s.textContent=prog?('진도 '+prog+'단 저장됨'):''; } }catch(e){} }
  setProg=function(r){ _setProg(r); report(); }; window.setProg=setProg;
  // 부모 → 패키지(+저장된 진도)
  window.addEventListener('message', function(e){
    var d=e.data; if(!d||d.type!=='knitup-pkg') return;
    if(d.who){ window.KN_WHO=String(d.who).slice(0,30); try{ render(converted? baseState:null); }catch(err){} }
    setTimeout(function(){
      try{ if(d.prog>0){ prog=d.prog; lastSent=d.prog; render(converted? baseState:null); var s=document.getElementById('knSaved'); if(s) s.textContent='진도 '+prog+'단부터 이어서'; } }catch(err){}
      document.body.classList.add('kn-ready');
    }, 30);
  });
  setTimeout(function(){ document.body.classList.add('kn-ready'); }, 2500);
  // 터치: 한 손가락 이동, 두 손가락 확대·축소
  var vp=document.getElementById('chartVp'), t0=null;
  function dist(a,b){ return Math.hypot(a.clientX-b.clientX, a.clientY-b.clientY); }
  vp.addEventListener('touchstart', function(e){
    if(e.touches.length===1) t0={m:'pan', x:e.touches[0].clientX, y:e.touches[0].clientY, ox:vz.x, oy:vz.y};
    else if(e.touches.length===2){ var r=vp.getBoundingClientRect(); t0={m:'zoom', d:dist(e.touches[0],e.touches[1]), s:vz.s, ox:vz.x, oy:vz.y,
      cx:(e.touches[0].clientX+e.touches[1].clientX)/2-r.left, cy:(e.touches[0].clientY+e.touches[1].clientY)/2-r.top}; }
  }, {passive:true});
  vp.addEventListener('touchmove', function(e){
    if(!t0) return; e.preventDefault();
    if(t0.m==='pan' && e.touches.length===1){ vz.x=t0.ox+(e.touches[0].clientX-t0.x); vz.y=t0.oy+(e.touches[0].clientY-t0.y); applyVz(); }
    else if(t0.m==='zoom' && e.touches.length===2){ var ns=Math.min(3.5, Math.max(0.45, t0.s*dist(e.touches[0],e.touches[1])/t0.d));
      vz.x=t0.cx-(t0.cx-t0.ox)*(ns/t0.s); vz.y=t0.cy-(t0.cy-t0.oy)*(ns/t0.s); vz.s=ns; applyVz(); }
  }, {passive:false});
  vp.addEventListener('touchend', function(){ t0=null; });
})();
<\/script>`;

// 워터마크: 부모가 넘겨준 열람자 이름 사용
html = html.replace("const who='knitter_'+('demo01')", "const who=(window.KN_WHO||'뜨개동네')");
html = html.replace("knitup · '+who+'", "뜨개동네 · '+who+'");
// 모바일: 차트를 화면 폭에 맞춰 가운데로
html = html.replace("function vzReset(){ vz={s:1, x:Math.max(0,(vp.clientWidth-560)/2), y:0}; applyVz(); }",
  "function vzReset(){ var s0=Math.min(1, vp.clientWidth/560); vz={s:s0, x:(vp.clientWidth-560*s0)/2, y:0}; applyVz(); }");
html = html.replace('<meta name="viewport"', '<meta name="kn-x" content=""><meta name="viewport"');
if (!/name="viewport"/.test(html)) html = html.replace('<head>', '<head><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">');
html = html.replace('</head>', css + '\n</head>');
const end = html.lastIndexOf('</body>');
html = html.slice(0, end) + js + '\n' + html.slice(end);
html = html.replace(/<title>[^<]*<\/title>/, '<title>뜨개동네 · 도안 뷰어</title>');
const out = path.join(__dirname, '..', 'docs', 'viewer.html');
fs.writeFileSync(out, html);
console.log('wrote', out, html.length);
