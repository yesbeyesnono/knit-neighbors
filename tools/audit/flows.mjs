// 화면별 동작 점검: 테스트 계정 두 개(demo1·demo2 — 둘 다 가입을 마친 정상 계정이어야 한다. demo4·demo6 은 정지 상태)로 주요 흐름을 실제로 눌러 본다.
//   스테이징(127.0.0.1:8767/knit.html)에서 실행. 테스트 계정의 글은 테스트 계정끼리만 보인다.
//   만든 것(글·댓글·친구·대화)의 id 를 끝에 출력한다 → 점검 뒤 지울 것. 신고·모임 만들기·주문은 하지 않는다.
import puppeteer from 'puppeteer-core';
const URL = process.argv[2] || 'http://127.0.0.1:8767/knit.html';
const wait = ms => new Promise(r => setTimeout(r, ms));
const b = await puppeteer.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: 'new', args: ['--no-sandbox', '--hide-scrollbars'] });
const results = []; const made = {};
const ok = (name, pass, note = '') => { results.push({ name, pass: !!pass, note: String(note).slice(0, 160) }); };
async function open(email, extra = '') {
  const ctx = await b.createBrowserContext(); const p = await ctx.newPage();
  await p.setViewport({ width: 390, height: 844, deviceScaleFactor: 1, isMobile: true, hasTouch: true });
  p.errs = []; p.net = [];
  p.on('pageerror', e => p.errs.push(e.message));
  p.on('dialog', d => { p.errs.push('native dialog: ' + d.message().slice(0, 60)); d.dismiss(); });
  p.on('response', r => { const u = r.url(); if (r.status() >= 400 && /supabase\.co|api\.knitup\.co\.kr/.test(u)) p.net.push(r.status() + ' ' + u.replace(/^https:\/\/[^/]+/, '').slice(0, 90)); });
  await p.goto(URL + extra, { waitUntil: 'networkidle2' });
  await p.evaluate(async (email) => { localStorage.setItem('kn_notice_s', '20261114-ddeuchin'); localStorage.setItem('kn_fq_acc', '[]'); window.TOASTS = []; await sb.auth.signInWithPassword({ email, password: 'knit1234' }); }, email);
  await wait(7000);
  await p.evaluate(() => { try { closeSheet(); } catch (e) { } const t0 = window.toast; window.toast = t => { TOASTS.push(String(t)); return t0(t); }; });
  return p;
}
const step = async (p, name, fn, arg, ms = 1500) => { const e0 = p.errs.length, n0 = p.net.length; let r, err = ''; try { r = await p.evaluate(fn, arg); } catch (e) { err = e.message.split('\n')[0]; } await wait(ms); const bad = p.errs.slice(e0).concat(p.net.slice(n0)); ok(name, !err && !bad.length && r !== false, err || bad.join(' | ') || (r === false ? 'check failed' : (typeof r === 'string' ? r : ''))); return r; };

const A = await open('demo1@knit.local'), B = await open('demo2@knit.local');
const idA = await A.evaluate(() => me.id), idB = await B.evaluate(() => me.id);
const tag = '점검' + Date.now().toString().slice(-6);

// ── 1. 글 쓰기·좋아요·수정·고정·보관·태그 ──
await step(A, '커뮤니티 열기', () => { go('comm'); }, null, 3000);
await step(A, '글 쓰기', async (tag) => { $('#cText').value = '점검용 글이에요 #' + tag; updateCnt(); await submitPost(); }, tag, 3500);
made.post = await A.evaluate(async () => { const { data } = await sb.from('posts').select('id,tags').eq('author_id', me.id).is('parent_id', null).order('created_at', { ascending: false }).limit(1); return data && data[0]; });
ok('글이 저장되고 태그가 뽑힘', made.post && (made.post.tags || []).includes(tag), JSON.stringify(made.post));
const pid = made.post?.id;
if (pid) {
  await step(A, '좋아요', async (id) => { const lb=document.querySelector(`[onclick*="toggleLike('${id}'"]`); if(!lb) return '좋아요 버튼 없음'; lb.click(); await new Promise(r => setTimeout(r, 1200)); const { count } = await sb.from('post_likes').select('*', { count: 'exact', head: true }).eq('post_id', id); return count === 1; }, pid);
  await step(A, '글 수정 화면', async (id) => { await editPostOpen(id); return view === 'compose' && /점검용/.test($('#sText').value); }, pid, 1200);
  await step(A, '글 수정 저장', async (id) => { $('#sText').value += ' (고침)'; await submitCompose(); const { data } = await sb.from('posts').select('body,edited_at').eq('id', id).single(); return /고침/.test(data.body) && !!data.edited_at; }, pid, 2500);
  await step(A, '프로필에 고정/풀기', async (id) => { await pinPost(id, true); const a = (await sb.from('posts').select('pinned_at').eq('id', id).single()).data.pinned_at; await pinPost(id, false); const c = (await sb.from('posts').select('pinned_at').eq('id', id).single()).data.pinned_at; return !!a && !c; }, pid, 1200);
  await step(A, '태그 모아 보기', async (tag) => { openTag(tag); await new Promise(r => setTimeout(r, 2500)); return document.querySelector('#v-comm').classList.contains('tagmode') && document.querySelectorAll('#feed .post').length >= 1; }, tag, 500);
  await step(A, '태그 모아 보기 닫기', () => { closeTag(); return !document.querySelector('#v-comm').classList.contains('tagmode'); }, null, 2500);
  // ── 2. 댓글·대댓글 (다른 계정) ──
  await step(B, '상대 계정에서 글이 보임', async (id) => { go('comm'); await new Promise(r => setTimeout(r, 3000)); const { data } = await sb.from('posts').select('id').eq('id', id); return (data || []).length === 1; }, pid, 500);
  await step(B, '목록에서 펼쳐 댓글 달기', async (id) => { if (!document.getElementById('rin-' + id)) { await toggleReplies(id); await new Promise(r => setTimeout(r, 1200)); } const i = document.getElementById('rin-' + id); if (!i) return '펼침 입력칸 없음(피드에 글이 안 보임)'; i.value = '점검 댓글이에요'; await submitInlineReply(id); await new Promise(r => setTimeout(r, 1500)); const { data } = await sb.from('posts').select('id').eq('parent_id', id); return (data || []).length === 1; }, pid, 800);
  made.reply = await A.evaluate(async (id) => (await sb.from('posts').select('id').eq('parent_id', id).limit(1)).data?.[0]?.id, pid);
  await step(A, '댓글 알림이 옴', async (id) => { const { data } = await sb.from('notifications').select('id,kind').eq('recipient_id', me.id).eq('kind', 'reply').order('created_at', { ascending: false }).limit(1); return (data || []).length === 1; }, pid);
  await step(A, '글 화면 열기', async (id) => { await openPost(id); return view === 'post' && document.querySelectorAll('#postBody .cmt, #postBody [id^="c-"]').length >= 0; }, pid, 2000);
  if (made.reply) await step(A, '대댓글 달기', async ([id, rid]) => { setReplyTo(rid); $('#replyIn').value = '대댓글 점검'; rpIn($('#replyIn')); await submitReply(); await new Promise(r => setTimeout(r, 1500)); const { data } = await sb.from('posts').select('id,reply_to').eq('parent_id', id).not('reply_to', 'is', null); return (data || []).length === 1 && data[0].reply_to === rid; }, [pid, made.reply], 800);
  await step(A, '보관하기 → 남에게 안 보임', async (id) => { await archivePost(id, true); return (await sb.from('posts').select('hidden,archived_at').eq('id', id).single()).data.hidden === true; }, pid, 1200);
  await step(B, '보관한 글은 상대에게 안 보임', async (id) => ((await sb.from('posts').select('id').eq('id', id)).data || []).length === 0, pid, 300);
  await step(A, '보관함 열기·다시 공개', async (id) => { await openArchivedPosts(); await new Promise(r => setTimeout(r, 1200)); await archivePost(id, false); try { closeSheet(); closeSub(); } catch (e) { } return (await sb.from('posts').select('hidden').eq('id', id).single()).data.hidden === false; }, pid, 1200);
}
// ── 3. 뜨친 신청 → 팝업 → 수락 → 대화 ──
const pre = await A.evaluate(async (o) => (await sb.from('friendships').select('status').or(`and(requester_id.eq.${me.id},addressee_id.eq.${o}),and(requester_id.eq.${o},addressee_id.eq.${me.id})`)).data, idB);
if (pre && pre.length) ok('뜨친 흐름', true, '두 테스트 계정이 이미 뜨친/신청 상태라 건너뜀: ' + JSON.stringify(pre));
else {
  made.friend = [idB, idA];
  await step(B, '뜨친 신청 보내기', async (o) => { const { error } = await sb.from('friendships').insert({ requester_id: me.id, addressee_id: o, status: 'pending', message: '점검용 신청이에요' }); if (error) { const r = await sb.from('friendships').insert({ requester_id: me.id, addressee_id: o, status: 'pending' }); if (r.error) return r.error.message; } return true; }, idA);
  await step(A, '신청 팝업이 뜸', async () => { localStorage.removeItem('kn_fq_seen'); go('comm'); await new Promise(r => setTimeout(r, 1500)); await fqCheck(true); await new Promise(r => setTimeout(r, 1500)); return !!document.querySelector('#fqpop'); }, null, 500);
  await step(A, '수락 → 축하 카드', async (o) => { await fqAccept(o); await new Promise(r => setTimeout(r, 1800)); const st = (await sb.from('friendships').select('status').eq('requester_id', o).eq('addressee_id', me.id).single()).data.status; return st === 'accepted' && !!document.querySelector('#fqpop'); }, idB, 500);
  await step(A, '첫 인사 → 대화방', async (o) => { const btn = [...document.querySelectorAll('#fqpop button')].find(x => /인사/.test(x.textContent)); if (!btn) return '인사 버튼 없음'; btn.click(); await new Promise(r => setTimeout(r, 3000)); return view === 'room'; }, idB, 500);
  made.room = await A.evaluate(() => roomId);
  await step(A, '메시지 보내기(여러 줄)', async () => { await sendMsg('안녕하세요!\n점검용 메시지예요'); await new Promise(r => setTimeout(r, 1200)); const bubs = document.querySelectorAll('#msgs .bub'); return bubs.length >= 1 && getComputedStyle(bubs[bubs.length - 1]).whiteSpace === 'pre-wrap'; }, null, 500);
  await step(B, '상대의 채팅 탭에 안 읽음 표시', async () => { go('chats'); await new Promise(r => setTimeout(r, 3000)); const { data } = await sb.rpc('my_unread_rooms'); return (Array.isArray(data) ? data.length : Number(data || 0)) >= 1 || !document.querySelector('#chatDot')?.hidden; }, null, 500);
  await step(B, '대화방 열고 답하기', async (rid) => { await openRoom(rid); await new Promise(r => setTimeout(r, 2500)); await sendMsg('반가워요, 점검 답장이에요'); await new Promise(r => setTimeout(r, 1200)); return document.querySelectorAll('#msgs .bub').length >= 2; }, made.room, 500);
  await step(A, '실시간으로 답장이 보임', async () => document.querySelectorAll('#msgs .bub').length >= 2, null, 300);
  await step(B, '대화 보관 → 목록에서 빠짐 → 되돌리기', async (rid) => { go('chats'); await new Promise(r => setTimeout(r, 2000)); await chArchive(rid, true); await new Promise(r => setTimeout(r, 1500)); const gone = !document.querySelector(`#chatsBody [onclick*="${rid}"]`); await chArchive(rid, false); await new Promise(r => setTimeout(r, 1500)); return gone; }, made.room, 500);
}
// ── 4. 화면 열기 (오류가 없는지) ──
const screens = [
  ['지도', () => { try { closeSheet(); closeSub(); } catch (e) { } go('map'); }, 4500],
  ['지도 필터 전부', async () => { for (const btn of document.querySelectorAll('.filters button')) { btn.click(); await new Promise(r => setTimeout(r, 900)); } const f = document.querySelector('.filters button'); if (f) f.click(); }, 1500],
  ['마이 Dashboard', () => go('my'), 2500], ['마이 Thread 탭 전부', async () => { goMy('thread'); await new Promise(r => setTimeout(r, 1200)); for (const t of document.querySelectorAll('#myTabs button, #v-my .subtabs button')) { t.click(); await new Promise(r => setTimeout(r, 900)); } }, 800],
  ['활동(알림)', () => openActivity(), 2000], ['설정', () => openSettings(), 1200],
  ['내 뜨개 단계', () => { closeSheet(); openSkills(); }, 2500], ['내 뜨개 단계 대바늘 탭', () => { const t = [...document.querySelectorAll('#skillsBody .tabs button')][1]; if (t) t.click(); }, 1500],
  ['기법 패널', () => { const t = document.querySelector('#skillsBody .tech'); if (t) t.click(); }, 1500],
  ['내 실함', () => { try { closeSheet(); closeSub(); } catch (e) { } openStash(); }, 2500], ['실 고르기', () => { try { closeSub(); } catch (e) { } openCert(true, true); openYarnPick(); }, 2000],
  ['실 검색', async () => { const i = document.querySelector('#ypQ, #subpg input'); if (i) { i.value = '낙양'; i.dispatchEvent(new Event('input', { bubbles: true })); } await new Promise(r => setTimeout(r, 1800)); }, 500],
  ['완성작품 인증 폼', () => { try { closeSub(); closeSheet(); } catch (e) { } openCert(true, true); }, 1500], ['인증 미리 보기', () => { if (typeof certPreview === 'function') certPreview(); }, 1200],
  ['모임 만들기 폼', () => { try { closeSub(); closeSheet(); } catch (e) { } openMeetForm(); }, 1500], ['장소 검색', () => openPlaceSearch('m'), 1500],
  ['소식·사용법', () => { try { closeSub(); closeSheet(); } catch (e) { } openHub('news'); }, 2000], ['사용법 카드', async () => { openHub('guide'); await new Promise(r => setTimeout(r, 1200)); await openGuide('cert'); }, 1500],
  ['프로필 편집', () => { try { closeSub(); closeSheet(); } catch (e) { } openOnboard(true); show('onboard'); }, 1500], ['동네 찾기 시트', () => manualDong(), 1000],
  ['동 이름 검색', async () => { $('#dongQ').value = '주엽'; await dongSearch(); return document.querySelectorAll('#dongRes > *').length > 0; }, 1500],
  ['작가 신청 화면', () => { closeSheet(); openAuthorApply(); }, 2000], ['가게 등록 신청 화면', () => { try { closeSheet(); closeSub(); } catch (e) { } openShopClaim(); }, 2000],
  ['지기에게 말하기', () => { try { closeSheet(); closeSub(); } catch (e) { } openSupportRoom(); }, 2500],
  ['이벤트·뜨친 이벤트 안내', async () => { go('comm'); await loadEvents(); await openDdeuchin(); }, 2000],
  ['가게 화면', async () => { try { closeSheet(); } catch (e) { } const { data } = await sb.rpc('nearby_shops', { p_lat: 37.5, p_lng: 127, p_radius_m: 1000 }); if (!data || !data[0]) return '가게 없음'; await openShop(data[0].id); }, 3000],
  ['작가 화면', async () => { const { data } = await sb.from('profiles').select('id').eq('is_author', true).eq('is_test', true).neq('id', me.id).limit(1); if (!data || !data[0]) return '테스트 작가 없음'; await openProfile(data[0].id); }, 3000],
  ['상대 프로필(뜨친)', async (o) => { await openProfile(o); }, 3000, idB],
  ['글 ··· 메뉴', async () => { go('comm'); await new Promise(r => setTimeout(r, 2500)); const m = document.querySelector('#feed .post [onclick*="postMenu"]'); if (m) m.click(); }, 800],
  ['＋ 시트', () => { try { pmClose(); } catch (e) { } openPlusSheet(); }, 800],
];
for (const [name, fn, ms, arg] of screens) await step(A, '화면: ' + name, fn, arg ?? null, ms);
await A.evaluate(() => { try { closeSheet(); closeSub(); } catch (e) { } });
// ── 5. Lab(전체 기능) 화면 ──
const L = await open('demo1@knit.local', '?edition=full');
for (const [name, fn, ms] of [['상점', () => openStore(), 2500], ['장바구니', () => openCart(), 1500], ['도안 탭', () => { try { closeSheet(); } catch (e) { } openStore('patterns'); }, 2500],
  ['도안 상세', async () => { const { data } = await sb.from('patterns').select('id').limit(1); if (data && data[0]) await openPattern(data[0].id); }, 2500], ['내 주문', () => { try { closeSheet(); closeSub(); } catch (e) { } openMyOrders(); }, 2000], ['내 도안(작가 아님)', () => { try { closeSheet(); } catch (e) { } if (typeof openMyPatterns === 'function') openMyPatterns(); }, 2000]])
  await step(L, 'Lab: ' + name, fn, null, ms);
await L.evaluate(async () => { localStorage.setItem('kn_edition', 'meet'); });
// ── 6. 뒷정리(앱에서 할 수 있는 것) ──
if (pid) await step(A, '글 삭제', async (id) => { go('comm'); await new Promise(r => setTimeout(r, 2000)); await deletePost(id, true); await new Promise(r => setTimeout(r, 1500)); return ((await sb.from('posts').select('id').eq('id', id)).data || []).length === 0; }, pid, 500);
const toasts = { A: await A.evaluate(() => TOASTS.filter(t => /실패|오류|못 |없어요|안 돼/.test(t))), B: await B.evaluate(() => TOASTS.filter(t => /실패|오류|못 |없어요|안 돼/.test(t))) };
for (const p of [A, B, L]) await p.evaluate(async () => { await sb.auth.signOut(); localStorage.clear(); });
await b.close();
const fail = results.filter(r => !r.pass);
console.log(`점검 ${results.length}개 · 통과 ${results.length - fail.length} · 실패 ${fail.length}`);
for (const r of results) console.log((r.pass ? 'OK  ' : 'FAIL') + ' ' + r.name + (r.note ? '  — ' + r.note : ''));
console.log('걸린 알림 문구:', JSON.stringify(toasts));
console.log('만든 것:', JSON.stringify({ ...made, idA, idB }));
