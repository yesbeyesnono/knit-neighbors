// 털실체 글리프 뼈대 내보내기 — docs/index.html 의 TS 엔진(원본)을 그대로 실행해 글자별 SVG 경로(획 중심선)와 자폭을 JSON 으로
// 사용: node tools/font/export-glyphs.js <획두께> <out.json>   (예: 95 → Regular, 120 → Bold)
// 글자: 한글 음절 11,172 + 숫자 0~9 + 가운뎃점(원) + 공백(자폭만). 좌표계는 엔진 그대로(1000 유닛, y 아래로)
const fs = require('fs'), path = require('path');
const sw = +process.argv[2] || 95, out = process.argv[3] || `teolsil_${sw}.json`;
const html = fs.readFileSync(path.join(__dirname, '..', '..', 'docs', 'index.html'), 'utf8');
const i = html.indexOf('const TS=(()=>{'), j = html.indexOf('})();', i) + 5;
const TS = new Function(html.slice(i, j) + '; return TS;')();
const glyphs = {};
function one(ch) {
  const svg = TS.svg(ch, 1000, sw, '#000'); if (!svg) return null;
  const vb = /viewBox="0 0 (\d+) 1000"/.exec(svg); const adv = Math.round(+vb[1] / 0.99);   // 엔진은 자간 -1% 를 x 진행에 섞음 → 폰트 자폭은 원래 값
  const d = /<path d="([^"]+)"/.exec(svg); const c = /<circle cx="([\d.]+)" cy="([\d.]+)" r="([\d.]+)"/.exec(svg);
  return { adv, d: d ? d[1] : null, circle: c ? [+c[1], +c[2], +c[3]] : null };
}
for (let cp = 0xAC00; cp <= 0xD7A3; cp++) glyphs[String.fromCharCode(cp)] = one(String.fromCharCode(cp));
for (const ch of '0123456789·') glyphs[ch] = one(ch);
glyphs[' '] = { adv: 360, d: null, circle: null };
fs.writeFileSync(out, JSON.stringify({ sw, glyphs }));
console.log('glyphs', Object.keys(glyphs).length, '->', out);
