// 홈페이지 업데이트 소식(v1.0.3) 시안: ① 소식 이미지(앱 화면 2장) ② 그 소식을 넣은 홈페이지 '새로 바뀐 것들' 칸 미리보기(PC·휴대폰) — 올리지 않음
import puppeteer from 'puppeteer-core';
import fs from 'fs';
const S = 'C:/Users/yesbe/AppData/Local/Temp/claude/0422a6549ab0c97e/27c68b59-113b-41d4-b2cf-d0547eb8f68d/scratchpad';
const HOME = S + '/knitup-home', RAW = S + '/shots/raw', OUT = S + '/news';
fs.mkdirSync(OUT, { recursive: true });
const b64 = f => 'data:image/png;base64,' + fs.readFileSync(f).toString('base64');
const b = await puppeteer.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: 'new', args: ['--no-sandbox', '--hide-scrollbars', '--allow-file-access-from-files'] });
const p = await b.newPage();
// ① 소식 이미지 1200×760
await p.setViewport({ width: 1200, height: 760, deviceScaleFactor: 1 });
const shots = [['sheet2-open.png', '앱을 열면 소식을 먼저'], ['staff2-profile.png', "'운영진' 표시와 바로 문의"]];
await p.setContent(`<body style="margin:0;background:#DDE8D6;display:flex;justify-content:center;align-items:flex-end;gap:56px;height:760px;overflow:hidden;font-family:'Malgun Gothic',sans-serif">
  ${shots.map(([f, t]) => `<div style="text-align:center"><div style="font-weight:700;font-size:24px;color:#22362A;margin-bottom:22px">${t}</div><div style="width:330px;height:640px;border-radius:34px 34px 0 0;border:8px solid #22362A;border-bottom:0;overflow:hidden;background:#F3F1EA;box-shadow:0 12px 40px rgba(34,54,42,.25)"><img src="${b64(RAW + '/' + f)}" style="width:100%;display:block"></div></div>`).join('')}
</body>`);
await p.screenshot({ path: OUT + '/update-1.0.3.jpg', type: 'jpeg', quality: 86 });
// ② 홈페이지 미리보기(사본에 소식 삽입)
let html = fs.readFileSync(HOME + '/index.html', 'utf8');
const article = fs.readFileSync(OUT + '/article-1.0.3.html', 'utf8');
const head = '<div style="display: flex; flex-direction: column; gap: 12px">';
const at = html.indexOf(head, html.indexOf('id="updates"'));
if (at < 0) throw new Error('marker not found');
html = html.slice(0, at + head.length) + String.fromCharCode(10) + article + html.slice(at + head.length);
fs.writeFileSync(HOME + '/_preview.html', html);
fs.copyFileSync(OUT + '/update-1.0.3.jpg', HOME + '/images/update-1.0.3.jpg');
for (const [name, w, h, m] of [['pc', 1280, 900, false], ['mobile', 390, 844, true]]) {
  await p.setViewport({ width: w, height: h, deviceScaleFactor: m ? 2 : 1, isMobile: m });
  await p.goto('file:///' + HOME + '/_preview.html', { waitUntil: 'networkidle0' });
  const el = await p.$('#updates'); await el.screenshot({ path: `${OUT}/preview-${name}.png` });
}
fs.unlinkSync(HOME + '/_preview.html');
await b.close(); console.log('ok');
