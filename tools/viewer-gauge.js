/* ── 뜨개동네 임베드: 게이지 · 완성 크기 카드 (build-viewer.js 가 viewer.html 끝에 그대로 넣는다) ──
   부모(앱)가 knitup-pkg 메시지에 gauge(= DB pattern_gauge_ctx)를 같이 보낸다:
     { craft, base:{sts,rows,needle,stitch,src:'author'|'yarn'|'needle'}, needle_mm, needle, yarn, mine:[{name,sts,rows,needle,stitch}] }
   기준 게이지 = 작가가 적은 값 → 기준 실의 실 사전 값 → 바늘 호수 추정(코바늘은 뷰어 표, 대바늘은 실 사전 중앙값) → 4.0mm 표준
   내 게이지 = 스와치 직접 입력 / 내 실함의 실 / 실 이름 검색(부모에 kn-yarn-q → kn-yarn-r). 도안 코 수는 그대로 두고 완성 크기와 '같은 크기로 뜨려면'만 계산 */
(function(){
  var CTX=null, BASE=null, MY=null, qT=null, found=[];
  var st=document.createElement('style');
  st.textContent='#knGauge{margin-bottom:12px}#knGauge h2 small{font-weight:400}'
    +'#knGauge .kg-base{font-size:14px;line-height:1.6}#knGauge .kg-base small,#knGauge .kg-note{color:var(--sub);font-size:12px}'
    +'#knGauge .kg-dim{font-size:13px;margin:4px 0 12px}'
    +'#knGauge .kg-my{display:flex;flex-wrap:wrap;align-items:center;gap:6px;font-size:14px;font-weight:700}'
    +'#knGauge input{font:inherit;font-size:16px;border:1.5px solid #ddd;border-radius:10px;padding:8px 10px;background:#fff;color:inherit}'
    +'#knGauge .kg-my input{width:64px;text-align:center}#knGauge #kgQ{width:100%;box-sizing:border-box;margin-top:10px}'
    +'#knGauge button{font:inherit;font-size:13px;font-weight:700;border:1.5px solid #ddd;background:#fff;border-radius:10px;padding:8px 12px;cursor:pointer;color:inherit}'
    +'#knGauge #kgGo{border-color:var(--accent);color:var(--accent)}'
    +'#knGauge .kg-chips{display:flex;flex-wrap:wrap;gap:6px;margin-top:8px}#knGauge .kg-chips button{font-weight:500;border-radius:999px;padding:6px 11px;text-align:left}'
    +'#knGauge .kg-chips button small{color:var(--sub)}'
    +'#knGauge #kgOut{margin-top:12px;padding:12px;border-radius:12px;background:var(--accent-soft);font-size:13px;line-height:1.65}#knGauge #kgOut:empty{display:none}'
    +'#knGauge .kg-ai{margin-top:14px;border-top:1px dashed #ddd;padding-top:12px}#knGauge .kg-ai h3{font-size:14px;margin:0 0 8px}#knGauge .kg-ai .kg-chips button{border-color:#c9d6c2}'
    +'#knGauge #kgAiQ{width:100%;box-sizing:border-box;margin-top:8px}#knGauge #kgAiOut{margin-top:10px;padding:12px;border-radius:12px;background:#f3f1ea;font-size:13px;line-height:1.65;white-space:pre-wrap}#knGauge #kgAiOut:empty{display:none}'
    +'#knGauge .kg-ai .kg-note{display:block;margin-top:6px}';
  document.head.appendChild(st);
  var card=document.createElement('div'); card.className='card'; card.id='knGauge'; card.style.display='none';
  var wrap=document.querySelector('.wrap'), main=document.querySelector('.main'); if(!wrap||!main) return; wrap.insertBefore(card, main);

  function esc(s){ return String(s==null?'':s).replace(/[&<>"']/g, function(c){ return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]; }); }
  function f1(n){ return String(Math.round(n*10)/10); }
  function sign(n){ return (n>=0?'+':'−')+f1(Math.abs(n)); }
  function num(v){ v=parseFloat(String(v).replace(',','.')); return isFinite(v)?v:0; }
  function shape(){ var rs=pkgState.rounds, c=rs.map(function(r){ return +r.cnt||0; }); return { maxC:Math.max.apply(null, c.concat([1])), n:rs.length, round:pkgState.chart.kind==='round' }; }
  function dims(g){ var s=shape(); return { w:s.maxC*10/g.gx, h:s.n*10/g.gy }; }
  function dimTxt(d){ return shape().round ? '지름 약 <b>'+f1(d.h*2)+'cm</b> <span class="kg-note">(평평한 원형일 때)</span> · 가장 넓은 단 둘레 약 <b>'+f1(d.w)+'cm</b>'
                                           : '가로 약 <b>'+f1(d.w)+'cm</b> × 세로 약 <b>'+f1(d.h)+'cm</b>'; }
  function pickBase(){
    var b=CTX&&CTX.base;
    if(b&&b.sts>0&&b.rows>0){
      var lab = b.src==='author' ? '작가 게이지' : b.src==='yarn' ? '기준 실 '+(CTX.yarn||'')+' · 실 사전' : '바늘 '+(b.needle||'')+' 평균 · 실 사전 '+(b.n||'')+'종';
      return { gx:+b.sts, gy:+b.rows, stitch:b.stitch||'', needle:b.needle||'', label:lab, est:b.src==='needle' };
    }
    var mm=CTX&&CTX.needle_mm, crochet=!CTX||CTX.craft!=='knitting';
    if(mm>0&&crochet){ var g=hookToGauge(+mm); return { gx:g.gx, gy:g.gy, stitch:'짧은뜨기', needle:mm+'mm', label:'바늘 '+mm+'mm 표준(짧은뜨기) 추정', est:true }; }
    var g0=hookToGauge(4.0); return { gx:g0.gx, gy:g0.gy, stitch:'짧은뜨기', needle:'4mm', label:'4.0mm 표준 추정 — 작가가 게이지를 적지 않았어요', est:true };
  }
  function setBase(){
    BASE=pickBase();
    baseState={ p:pkgPattern(pkgState.rounds, BASE.gx, BASE.gy), gx:BASE.gx, gy:BASE.gy, T:1, hasSw:false, ux:10/BASE.gx, free:baseState.free };
    cur=baseState; converted=false; MY=null; render(null);
    var sub=document.getElementById('subT');
    if(sub) sub.innerHTML='📦 작가 패키지 · '+esc(pkgState.chart.part||'차트')+' · 기준 게이지 '+f1(BASE.gx)+'코×'+f1(BASE.gy)+'단/10cm';
  }
  function build(){
    card.innerHTML='<h2>📐 게이지 · 완성 크기 <small>— 10cm × 10cm 기준</small></h2>'
      +'<div class="kg-base" id="kgBase"></div><div class="kg-dim" id="kgDim"></div>'
      +'<div class="kg-my">내 게이지 <input id="kgS" inputmode="decimal" placeholder="코" aria-label="내 게이지 코"> 코 × <input id="kgR" inputmode="decimal" placeholder="단" aria-label="내 게이지 단"> 단'
      +'<button id="kgGo">적용</button><button id="kgReset">원래대로</button></div>'
      +'<div class="kg-note" style="margin-top:6px">스와치를 떠서 10cm 안의 코·단을 세어 적으면 가장 정확해요. 단을 비우면 도안 비율로 추정해요.</div>'
      +'<div class="kg-chips" id="kgMine"></div>'
      +'<input id="kgQ" placeholder="뜨려는 실 이름으로 찾기 (게이지가 등록된 실)" autocomplete="off" maxlength="40"><div class="kg-chips" id="kgRes"></div>'
      +'<div id="kgOut"></div>'
      +'<div class="kg-ai"><h3>AI에게 묻기 <small class="kg-note" style="display:inline">— 내 실함·실 사전을 보고 답해요</small></h3>'
      +'<div class="kg-chips" id="kgAiQuick"><button type="button" data-q="내 실함의 실로 이 도안을 뜨면 크기가 어떻게 되고, 어떤 실이 가장 맞아요?">내 실로 뜨면?</button><button type="button" data-q="이 도안에 맞는 실을 추천해 주세요. 대신 쓸 수 있는 실도 알려 주세요.">맞는 실 추천</button><button type="button" data-q="이 도안을 뜨려면 실이 대략 얼마나 필요해요?">실 소요량</button></div>'
      +'<input id="kgAiQ" placeholder="직접 물어보기 (예: 10% 크게 뜨려면?)" maxlength="200" autocomplete="off"><button id="kgAiGo" style="margin-top:8px">물어보기</button>'
      +'<div id="kgAiOut"></div><div class="kg-chips" id="kgAiYarns"></div><span class="kg-note">AI 답은 참고용이에요 — 스와치로 확인하세요. 한 시간에 30번까지.</span></div>';
    document.getElementById('kgGo').onclick=function(){ var s=num(document.getElementById('kgS').value), r=num(document.getElementById('kgR').value);
      if(!(s>=3&&s<=80)) return toast('10cm 안의 코 수를 적어 주세요');
      if(r&&!(r>=2&&r<=150)) return toast('단 수를 다시 확인해 주세요');
      applyMy(s, r||BASE.gy*s/BASE.gx, r?'직접 입력':'직접 입력 · 단수는 추정'); };
    document.getElementById('kgReset').onclick=function(){ document.getElementById('inSw').value=''; document.getElementById('inSwR').value='';
      document.getElementById('kgS').value=''; document.getElementById('kgR').value=''; cur=baseState; converted=false; MY=null; render(null); paint(); };
    document.getElementById('kgQ').oninput=function(){ var q=this.value.trim(); clearTimeout(qT);
      if(q.length<2){ found=[]; chips('kgRes', found, ''); return; }
      qT=setTimeout(function(){ parent.postMessage({type:'kn-yarn-q', q:q, craft:(CTX&&CTX.craft)||'crochet'}, '*'); }, 400); };
    chips('kgMine', (CTX&&CTX.mine)||[], '내 실함');
    function aiAsk(q){ q=(q||'').trim(); if(!q) return; var o=document.getElementById('kgAiOut'); o.textContent='생각하는 중…'; document.getElementById('kgAiYarns').innerHTML='';
      var s=shape(); parent.postMessage({type:'kn-ai-q', q:q, ctx:{ title:(pkgState.pkg&&pkgState.pkg.title)||'', chart:pkgState.chart.part||'', maxC:s.maxC, rows:s.n, round:s.round, base:BASE?{gx:BASE.gx,gy:BASE.gy,stitch:BASE.stitch,needle:BASE.needle}:null, my:MY||null }}, '*'); }
    Array.prototype.forEach.call(document.querySelectorAll('#kgAiQuick button'), function(b){ b.onclick=function(){ aiAsk(b.getAttribute('data-q')); }; });
    document.getElementById('kgAiGo').onclick=function(){ aiAsk(document.getElementById('kgAiQ').value); };
    document.getElementById('kgAiQ').onkeydown=function(e){ if(e.key==='Enter') aiAsk(this.value); };
    paint();
  }
  function chips(id, rows, head){
    var el=document.getElementById(id); if(!el) return;
    el.innerHTML=(rows.length&&head?'<span class="kg-note" style="width:100%">'+head+'</span>':'')
      +rows.map(function(y,i){ return '<button type="button" data-i="'+i+'">'+esc(y.name)+' <small>'+f1(y.sts)+'코×'+f1(y.rows)+'단'+(y.needle?' · '+esc(y.needle):'')+'</small></button>'; }).join('');
    Array.prototype.forEach.call(el.querySelectorAll('button'), function(b){ b.onclick=function(){ useYarn(rows[+b.getAttribute('data-i')]); }; });
  }
  function useYarn(y){
    if(!y||!(y.sts>0)) return;
    var same = y.stitch && BASE.stitch && y.stitch===BASE.stitch && y.rows>0;
    var gx=+y.sts, gy = same ? +y.rows : BASE.gy*gx/BASE.gx;
    document.getElementById('kgS').value=f1(gx); document.getElementById('kgR').value=same?f1(gy):'';
    applyMy(gx, gy, y.name+(same?' · 실 사전':' · 실 사전('+(y.stitch||'다른 편물')+' 기준)이라 단수는 추정'));
  }
  function applyMy(gx, gy, label){
    MY={gx:gx, gy:gy, label:label};
    document.getElementById('inSw').value=gx; document.getElementById('inSwR').value=gy;
    convert(true); paint();
  }
  function paint(){
    if(!BASE) return;
    document.getElementById('kgBase').innerHTML='도안 기준 <b>'+f1(BASE.gx)+'코 × '+f1(BASE.gy)+'단</b>'+(BASE.stitch?' · '+esc(BASE.stitch):'')+(BASE.needle?' · '+esc(BASE.needle):'')
      +'<br><small>'+esc(BASE.label)+'</small>';
    var d0=dims(BASE); document.getElementById('kgDim').innerHTML='완성 크기 '+dimTxt(d0)+(BASE.est?' <span class="kg-note">(추정)</span>':'');
    var out=document.getElementById('kgOut'); if(!MY){ out.innerHTML=''; return; }
    var d1=dims(MY), rx=MY.gx/BASE.gx, ry=MY.gy/BASE.gy, s=shape();
    var h='<b>내 게이지 '+f1(MY.gx)+'코 × '+f1(MY.gy)+'단</b> <span class="kg-note">('+esc(MY.label)+')</span><br>';
    if(Math.abs(rx-1)<0.03&&Math.abs(ry-1)<0.03) h+='도안 게이지와 거의 같아요 — 도안 그대로 뜨면 돼요.';
    else h+='도안 그대로 뜨면 '+dimTxt(d1)+' <span class="kg-note">(도안보다 '+(s.round?'지름 '+sign((d1.h-d0.h)*2):'가로 '+sign(d1.w-d0.w)+'cm · 세로 '+sign(d1.h-d0.h))+'cm)</span><br>'
      +'도안과 같은 크기로 뜨려면 코 수 <b>×'+rx.toFixed(2)+'</b> (가장 넓은 단 '+s.maxC+'코 → 약 '+Math.max(1,Math.round(s.maxC*rx))+'코), '
      +'단 수 <b>×'+ry.toFixed(2)+'</b> ('+s.n+'단 → 약 '+Math.max(1,Math.round(s.n*ry))+'단)';
    out.innerHTML=h;
  }
  window.addEventListener('message', function(e){
    var d=e.data; if(!d) return;
    if(d.type==='knitup-pkg'){ if(!pkgState) return; CTX=d.gauge||{};
      try{ setBase(); build(); card.style.display=''; }catch(err){ card.style.display='none'; }
      return; }
    if(d.type==='kn-ai-r'){ var o=document.getElementById('kgAiOut'); if(!o) return; o.textContent=d.error?('답하지 못했어요: '+d.error):(d.answer||'');
      var ys=(d.yarns||[]).filter(function(y){ return y&&y.name; }); var el=document.getElementById('kgAiYarns');
      if(el){ el.innerHTML=ys.length?'<span class="kg-note" style="width:100%">추천 실 — 게이지가 있으면 눌러서 적용</span>':'';
        ys.forEach(function(y){ var b=document.createElement('button'); b.type='button'; b.innerHTML=esc(y.name)+(y.sts?' <small>'+f1(y.sts)+'코'+(y.rows?'×'+f1(y.rows)+'단':'')+'</small>':'')+(y.reason?'<br><small>'+esc(y.reason)+'</small>':''); if(y.sts) b.onclick=function(){ useYarn({name:y.name, sts:y.sts, rows:y.rows, stitch:y.stitch, needle:y.needle}); }; else b.disabled=true; el.appendChild(b); }); }
      return; }
    if(d.type==='kn-yarn-r'){ var q=document.getElementById('kgQ'); if(!q||q.value.trim()!==d.q) return;
      found=(d.rows||[]).slice(0,8); chips('kgRes', found, found.length?'':'');
      if(!found.length){ var el=document.getElementById('kgRes'); if(el) el.innerHTML='<span class="kg-note">게이지가 등록된 실을 찾지 못했어요 — 스와치를 재서 직접 적어 주세요</span>'; } }
  });
})();
