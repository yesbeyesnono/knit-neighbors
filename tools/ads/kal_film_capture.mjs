// '함께 뜨기' 소개 영상 찍기: resources/ads/kal_film/film.html 의 render(t) 를 한 프레임씩 불러 JPEG 로 저장한다.
//   node tools/ads/kal_film_capture.mjs <프레임 저장 폴더> [fps=30] [시작초] [끝초] [배속=1]
// 그 뒤 ffmpeg 로 묶는다(끝에 명령 예시를 찍어 줌). Chrome 을 화면 없이 띄워 DevTools 로 조종(추가 설치 없음, Node 22+).
import { spawn } from 'node:child_process';
import { mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { tmpdir } from 'node:os';

const out = resolve(process.argv[2] || 'frames'), fps = +(process.argv[3] || 30);
// 가게 이름·종류는 환경 변수로: KAL_SHOP=이름 KAL_KIND=author|yarn
const qs = new URLSearchParams(); if (process.env.KAL_SHOP) qs.set('shop', process.env.KAL_SHOP); if (process.env.KAL_KIND) qs.set('kind', process.env.KAL_KIND);
const page = pathToFileURL(resolve('resources/ads/kal_film/film.html')).href + (qs.size ? '?' + qs : '');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe', PORT = 9347;
const prof = join(tmpdir(), 'kal_film_prof_' + Date.now());
mkdirSync(out, { recursive: true });
const ch = spawn(CHROME, ['--headless=new', '--no-sandbox', '--hide-scrollbars', '--remote-debugging-port=' + PORT, '--user-data-dir=' + prof, '--window-size=360,640', '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
const sleep = ms => new Promise(r => setTimeout(r, ms));
let ws, seq = 0; const wait = new Map();
const send = (method, params = {}) => new Promise((res, rej) => { const id = ++seq; wait.set(id, { res, rej }); ws.send(JSON.stringify({ id, method, params })); });
try {
  let tab; for (let i = 0; i < 50 && !tab; i++) { await sleep(200); try { const l = await (await fetch(`http://127.0.0.1:${PORT}/json`)).json(); tab = l.find(x => x.type === 'page'); } catch (e) {} }
  if (!tab) throw new Error('Chrome 에 연결하지 못했어요');
  ws = new WebSocket(tab.webSocketDebuggerUrl);
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
  ws.onmessage = ev => { const m = JSON.parse(ev.data); const w = wait.get(m.id); if (w) { wait.delete(m.id); m.error ? w.rej(new Error(m.error.message)) : w.res(m.result); } };
  await send('Page.enable');
  await send('Emulation.setDeviceMetricsOverride', { width: 360, height: 640, deviceScaleFactor: 3, mobile: false });
  await send('Page.navigate', { url: page });
  const ev = async expr => (await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true })).result.value;
  for (let i = 0; i < 100; i++) { await sleep(150); if (await ev("typeof render==='function' && document.readyState==='complete'")) break; }
  await ev("document.fonts.ready.then(()=>true)");
  // 그림 9장을 미리 불러 둔다(첫 프레임에 빈 그림이 찍히지 않게)
  await ev("Promise.all([...document.querySelectorAll('.art')].map(a=>new Promise(r=>{const im=new Image();im.onload=im.onerror=()=>r(1);im.src=a.style.backgroundImage.slice(5,-2);}))).then(()=>true)");
  const dur = await ev('DUR'), from = +(process.argv[4] || 0), to = +(process.argv[5] || dur), speed = +(process.argv[6] || 1);
  const n0 = Math.round(from / speed * fps), n1 = Math.round(to / speed * fps);
  console.log(`길이 ${dur}s · ${speed}배속 · ${fps}fps · 프레임 ${n0}~${n1 - 1}`);
  for (let i = n0; i < n1; i++) {
    await ev(`render(${(i / fps * speed).toFixed(4)}),1`);
    const { data } = await send('Page.captureScreenshot', { format: 'jpeg', quality: 93 });
    writeFileSync(join(out, 'f_' + String(i).padStart(5, '0') + '.jpg'), Buffer.from(data, 'base64'));
    if (i % 150 === 0) console.log('  ', i, '/', n1);
  }
  console.log('끝 →', out);
  console.log(`ffmpeg -y -framerate ${fps} -i "${out}/f_%05d.jpg" -f lavfi -i anullsrc=r=44100:cl=stereo -shortest -c:v libx264 -pix_fmt yuv420p -crf 18 -preset slow -c:a aac -b:a 96k -movflags +faststart out.mp4`);
} finally { try { ws && ws.close(); } catch (e) {} ch.kill(); await sleep(400); try { rmSync(prof, { recursive: true, force: true }); } catch (e) {} }
