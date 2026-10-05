// 앱(docs/index.html)의 털실체 글자 엔진을 그대로 복사한 것. 원본이 바뀌면 다시 복사한다.
const TS=(()=>{
  const CHO='ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ', JUNG='ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ', JONG=' ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ';
  const CL={'ㄲ':'ㄱㄱ','ㄸ':'ㄷㄷ','ㅃ':'ㅂㅂ','ㅆ':'ㅅㅅ','ㅉ':'ㅈㅈ','ㄳ':'ㄱㅅ','ㄵ':'ㄴㅈ','ㄶ':'ㄴㅎ','ㄺ':'ㄹㄱ','ㄻ':'ㄹㅁ','ㄼ':'ㄹㅂ','ㄽ':'ㄹㅅ','ㄾ':'ㄹㅌ','ㄿ':'ㄹㅍ','ㅀ':'ㄹㅎ','ㅄ':'ㅂㅅ'};
  const VERT={'ㅡ':1,'ㅗ':1,'ㅜ':1,'ㅛ':1,'ㅠ':1}, CX={'ㅘ':['ㅗ','ㅏ'],'ㅙ':['ㅗ','ㅐ'],'ㅚ':['ㅗ','ㅣ'],'ㅝ':['ㅜ','ㅓ'],'ㅞ':['ㅜ','ㅔ'],'ㅟ':['ㅜ','ㅣ'],'ㅢ':['ㅡ','ㅣ']};
  function J(n,x0,y0,x1,y1){
    if(CL[n]){ const [a,b]=CL[n]; const w=(x1-x0-60)/2; return J(a,x0,y0,x0+w,y1)+' '+J(b,x1-w,y0,x1,y1); }
    const xm=(x0+x1)/2, ym=(y0+y1)/2, w=x1-x0, h=y1-y0;
    switch(n){
      case 'ㄱ': return `M${x0} ${y0} H${x1} V${y1}`;
      case 'ㄴ': return `M${x0} ${y0} V${y1} H${x1}`;
      case 'ㄷ': return `M${x1} ${y0} H${x0} V${y1} H${x1}`;
      case 'ㄹ': return `M${x0} ${y0} H${x1} V${ym} H${x0} V${y1} H${x1}`;
      case 'ㅁ': return `M${x0} ${y0} H${x1} V${y1} H${x0} Z`;
      case 'ㅂ': return `M${x0} ${y0} V${y1} H${x1} V${y0} M${x0} ${ym} H${x1}`;
      case 'ㅅ': return `M${xm} ${y0} Q${xm-w*0.18} ${ym+h*0.1} ${x0} ${y1} M${xm} ${y0} Q${xm+w*0.18} ${ym+h*0.1} ${x1} ${y1}`;
      case 'ㅈ': return `M${x0} ${y0} H${x1} `+J('ㅅ',x0,y0+h*0.22,x1,y1);
      case 'ㅊ': return `M${xm-w*0.15} ${y0} H${xm+w*0.15} `+J('ㅈ',x0,y0+h*0.2,x1,y1);
      case 'ㅎ': { const r=(h-h*0.42)/2, cy=y1-r; return `M${xm-w*0.18} ${y0} H${xm+w*0.18} M${x0} ${y0+h*0.24} H${x1} M${xm-r} ${cy} a${r} ${r} 0 1 0 ${2*r} 0 a${r} ${r} 0 1 0 ${-2*r} 0`; }
      case 'ㅇ': { const r=Math.min(w,h)/2; return `M${xm-r} ${ym} a${r} ${r} 0 1 0 ${2*r} 0 a${r} ${r} 0 1 0 ${-2*r} 0`; }
      case 'ㅋ': return `M${x0} ${y0} H${x1} V${y1} M${x0} ${ym} H${x1}`;
      case 'ㅌ': return `M${x1} ${y0} H${x0} V${y1} H${x1} M${x0} ${ym} H${x1}`;
      case 'ㅍ': return `M${x0} ${y0} H${x1} M${x0+w*0.3} ${y0} V${y1} M${x1-w*0.3} ${y0} V${y1} M${x0} ${y1} H${x1}`;
      case 'ㅡ': return `M${x0} ${ym} H${x1}`;
      case 'ㅗ': return `M${x0} ${y1} H${x1} M${xm} ${y0} V${y1}`;
      case 'ㅛ': return `M${x0} ${y1} H${x1} M${x0+w*0.33} ${y0} V${y1} M${x1-w*0.33} ${y0} V${y1}`;
      case 'ㅜ': return `M${x0} ${y0} H${x1} M${xm} ${y0} V${y1}`;
      case 'ㅠ': return `M${x0} ${y0} H${x1} M${x0+w*0.33} ${y0} V${y1} M${x1-w*0.33} ${y0} V${y1}`;
      case 'ㅏ': return `M${x0} ${y0} V${y1} M${x0} ${ym} H${x0+w*0.55}`;
      case 'ㅑ': return `M${x0} ${y0} V${y1} M${x0} ${y0+h*0.38} H${x0+w*0.55} M${x0} ${y0+h*0.62} H${x0+w*0.55}`;
      case 'ㅐ': return `M${x0} ${y0} V${y1} M${x0} ${ym} H${x1} M${x1} ${y0} V${y1}`;
      case 'ㅒ': return `M${x0} ${y0} V${y1} M${x0} ${y0+h*0.38} H${x1} M${x0} ${y0+h*0.62} H${x1} M${x1} ${y0} V${y1}`;
      case 'ㅓ': { const xa=x0+w*0.55; return `M${xa} ${y0} V${y1} M${x0} ${ym} H${xa}`; }
      case 'ㅕ': { const xa=x0+w*0.55; return `M${xa} ${y0} V${y1} M${x0} ${y0+h*0.38} H${xa} M${x0} ${y0+h*0.62} H${xa}`; }
      case 'ㅔ': { const xa=x0+w*0.45; return `M${xa} ${y0} V${y1} M${x0} ${ym} H${xa} M${x1} ${y0} V${y1}`; }
      case 'ㅖ': { const xa=x0+w*0.45; return `M${xa} ${y0} V${y1} M${x0} ${y0+h*0.38} H${xa} M${x0} ${y0+h*0.62} H${xa} M${x1} ${y0} V${y1}`; }
      case 'ㅣ': return `M${xm} ${y0} V${y1}`;
    }
    return '';
  }
  function syl(c,v,f){
    if(CX[v]){ const [b,r]=CX[v];
      if(!f) return [J(c,80,100,440,440), b==='ㅡ'?'M60 560 H500':J(b,60,470,500,620), J(r,600,80,930,900)].join(' ');
      return [J(c,100,80,420,340), b==='ㅡ'?'M60 450 H480':J(b,60,370,480,500), J(r,600,60,930,560), J(f,90,640,900,920)].join(' ');
    }
    if(!VERT[v]){ const nx=v==='ㅣ'; const vx0=nx?600:590, vx1=nx?760:930;
      if(!f) return J(c,70,120,470,880)+' '+J(v,vx0,90,vx1,910);
      return [J(c,70,90,470,470), J(v,vx0,60,vx1,560), J(f,90,640,900,920)].join(' ');
    }
    const tall = v!=='ㅡ';
    if(!f) return J(c,140,90,860,470)+' '+(tall?J(v,90,560,910,900):J(v,90,640,910,760));
    return [J(c,190,80,810,380), tall?J(v,90,420,910,600):J(v,90,470,910,560), J(f,140,660,860,920)].join(' ');
  }
  const DIG={'0':'M500 90 a230 410 0 1 0 1 0','1':'M400 230 L560 90 V910','2':'M330 260 a220 220 0 1 1 380 160 L330 910 H720','3':'M340 210 a210 190 0 1 1 260 300 M600 510 a220 200 0 1 1 -280 300','4':'M640 90 L280 640 H760 M640 400 V910','5':'M700 90 H360 L330 480 c 100 -70 340 -40 340 190 c 0 250 -260 290 -380 180','6':'M640 100 c -280 120 -340 400 -320 560 a220 220 0 1 0 60 -220','7':'M300 90 H720 L450 910','8':'M500 480 a200 190 0 1 0 -1 0 M500 480 a215 215 0 1 1 -1 0','9':'M360 900 c 280 -120 340 -400 320 -560 a220 220 0 1 1 -60 220'};
  function svg(text, size, sw, color){
    sw=sw||95; color=color||'currentColor'; let x=0; const out=[];
    for(const ch of text){
      if(ch===' '){ x+=360; continue; }
      if(ch==='·'){ out.push(`<circle cx="${x+230}" cy="520" r="${sw*0.6}" fill="${color}"/>`); x+=460; continue; }
      let d, adv=1000;
      if(DIG[ch]) d=DIG[ch];
      else { const o=ch.charCodeAt(0)-0xAC00; if(o<0||o>11171) return null; const c=CHO[Math.floor(o/588)], v=JUNG[Math.floor((o%588)/28)], f=JONG[o%28].trim(); d=syl(c,v,f||null); if(v==='ㅣ'&&!f) adv=860; }
      out.push(`<path d="${d}" transform="translate(${Math.round(x)},0)" fill="none" stroke="${color}" stroke-width="${sw}" stroke-linecap="round" stroke-linejoin="round"/>`);
      x+=adv*0.99;
    }
    if(!out.length) return null;
    return `<svg width="${(x*size/1000).toFixed(1)}" height="${size}" viewBox="0 0 ${Math.round(x)} 1000" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="${text.replace(/"/g,'&quot;')}">${out.join('')}</svg>`;
  }
  return { svg };
})();
export const TS_SVG = TS.svg;
