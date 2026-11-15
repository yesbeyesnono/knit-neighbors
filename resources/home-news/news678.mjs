// 홈페이지 업데이트 소식(v1.0.6~1.0.8) 시안: 소식 이미지 + 홈페이지 '새로 바뀐 것들' 칸 미리보기 — 올리지 않음
import puppeteer from 'puppeteer-core';
import fs from 'fs';
const S = 'C:/Users/yesbe/AppData/Local/Temp/claude/0422a6549ab0c97e/27c68b59-113b-41d4-b2cf-d0547eb8f68d/scratchpad';
const HOME = S + '/kh', RAW = S + '/shots/raw', OUT = S + '/news';
fs.mkdirSync(OUT, { recursive: true });
const b64 = f => 'data:image/' + (f.endsWith('.png') ? 'png' : 'jpeg') + ';base64,' + fs.readFileSync(f).toString('base64');
const b = await puppeteer.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: 'new', args: ['--no-sandbox', '--hide-scrollbars', '--allow-file-access-from-files'] });
const p = await b.newPage();
const IM = {
  '1.0.7': [[S + '/ag_1.jpeg', '작가 화면 · 팔로우와 문의', 'top'], [RAW + '/chatswipe-2.png', '채팅 · 밀어서 보관·나가기', 'top']],
  '1.0.8': [[RAW + '/fq-2.png', '뜨친 신청이 오면 바로', 'top'], [RAW + '/hub-1.png', '마이 · 손 들기와 소식', 'top']],
};
for (const v of Object.keys(IM)) {
  await p.setViewport({ width: 1200, height: 760, deviceScaleFactor: 1 });
  await p.setContent(`<body style="margin:0;background:#DDE8D6;display:flex;justify-content:center;align-items:flex-end;gap:56px;height:760px;overflow:hidden;font-family:'Malgun Gothic',sans-serif">
  ${IM[v].map(([f, t, pos]) => `<div style="text-align:center"><div style="font-weight:700;font-size:24px;color:#22362A;margin-bottom:22px">${t}</div><div style="width:330px;height:640px;border-radius:34px 34px 0 0;border:8px solid #22362A;border-bottom:0;overflow:hidden;background:#F3F1EA;box-shadow:0 12px 40px rgba(34,54,42,.25)"><img src="${b64(f)}" style="width:100%;height:100%;object-fit:cover;object-position:${pos};display:block"></div></div>`).join('')}
</body>`);
  await p.screenshot({ path: `${OUT}/update-${v}.jpg`, type: 'jpeg', quality: 86 });
}
const A = (v, date, title, body, alt) => `<article style="background: #FFFFFF; border-radius: 20px; padding: 24px 28px; display: flex; flex-wrap: wrap; gap: 20px; align-items: flex-start">
<div class="upmeta" style="flex: 0 0 140px; display: flex; flex-direction: column; gap: 6px">
<span style="align-self: flex-start; background: #3E6B48; color: #FFFFFF; font-size: 13px; font-weight: 700; padding: 3px 10px; border-radius: 999px">업데이트 · v${v}</span>
<span style="font-size: 14px; color: #55604F">${date}</span>
</div>
<div style="flex: 1 1 400px; min-width: 0">
<h3 style="margin: 0 0 6px; font-size: 19px">${title}</h3>
<p style="margin: 0; color: #55604F; font-size: 15px">${body}</p>
<img src="images/update-${v}.jpg" alt="${alt}" loading="lazy" style="display: block; margin-top: 16px; width: 100%; max-width: 560px; border-radius: 14px">
</div>
</article>
`;
const arts = {
  '1.0.8': A('1.0.8', '출시일', '올린 글을 고칠 수 있어요', '올린 글과 완성작품 인증을 고치고, 프로필에 고정하거나 나만 보게 보관할 수 있어요. 뜨친 신청이 오면 앱을 열 때 바로 알려 드려요. 마이 화면에서 손 들기와 소식·사용법을 바로 볼 수 있고, 내 실함에 실을 담을 때는 실과 띠지를 찍으면 정보를 읽어 드려요.', '뜨친 신청 알림 카드와 마이 화면'),
  '1.0.7': A('1.0.7', '출시일', '작가와 공방을 팔로우하고 문의할 수 있어요', '작가와 공방 화면이 새로워졌어요. 팔로우하면 새 모임·클래스 소식이 알림으로 오고, [문의]를 누르면 바로 대화할 수 있어요. 글을 누르면 그 자리에서 댓글이 펼쳐지고, 사진은 크게 넘겨 보며 확대할 수 있어요. 채팅 목록은 왼쪽으로 밀어 보관하거나 나갈 수 있어요.', '새 작가 화면과 채팅 목록의 보관·나가기 버튼'),
  '1.0.6': A('1.0.6', '2026.11.13', '댓글에 댓글을 달 수 있어요', '글과 댓글이 한눈에 구분되고, 댓글에 댓글을 달면 그 댓글 아래에 모여요. 댓글에서 엔터로 줄을 바꿀 수 있고, 새 글에서 @를 치면 뜨친을 고를 수 있어요. 지도에서는 작가님이 황금색 핀으로 보여요.', '댓글 아래에 댓글이 모인 글 화면과 지도의 황금색 작가 핀'),
};
for (const v of Object.keys(arts)) fs.writeFileSync(`${OUT}/article-${v}.html`, arts[v]);
let html = fs.readFileSync(HOME + '/index.html', 'utf8');
const head = '<div style="display: flex; flex-direction: column; gap: 12px">';
const at = html.indexOf(head, html.indexOf('id="updates"'));
if (at < 0) throw new Error('marker not found');
html = html.slice(0, at + head.length) + String.fromCharCode(10) + arts['1.0.8'] + arts['1.0.7'] + arts['1.0.6'] + html.slice(at + head.length);
fs.writeFileSync(HOME + '/_preview.html', html);
for (const v of ['1.0.6', '1.0.7', '1.0.8']) fs.copyFileSync(`${OUT}/update-${v}.jpg`, `${HOME}/images/_pv-${v}.jpg`);
fs.writeFileSync(HOME + '/_preview.html', html.replace(/images\/update-(1\.0\.[678])\.jpg/g, 'images/_pv-$1.jpg'));
await p.setViewport({ width: 1100, height: 900, deviceScaleFactor: 1 });
await p.goto('file:///' + HOME + '/_preview.html', { waitUntil: 'networkidle0' });
await p.evaluate(() => { const u = document.querySelector('#updates'); const as = u.querySelectorAll('article'); as.forEach((a, i) => { if (i > 2) a.remove(); }); });
const el = await p.$('#updates'); await el.screenshot({ path: `${OUT}/preview-678.png` });
fs.unlinkSync(HOME + '/_preview.html'); for (const v of ['1.0.6', '1.0.7', '1.0.8']) fs.unlinkSync(`${HOME}/images/_pv-${v}.jpg`);
await b.close(); console.log('ok');
