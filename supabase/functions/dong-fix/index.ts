// 동네 자동 보정 (2026-11-14 대표 지시: "주소가 문제가 될 땐 오늘 처리한 방식으로 자동으로")
// 대상: 프로필은 끝냈는데 지도 위치가 없는 회원(옛 앱에서 동네를 글자로만 적은 경우). 매시 크론 dong-fix 가 부른다.
// 방법(AI 모델은 쓰지 않는다 — 회원이 적은 글자를 AI 에 보내지 않음):
//   ① 적은 글자가 동 이름이면(구로동 → 구로1~5동) 전국 행정동 목록(kr-dongs.json)에서 찾아 그 중심으로
//   ② 길 이름이면(봉우재로·부천로40번길) 행정안전부 도로명주소 검색으로 그 길이 가장 많이 걸친 동을 찾아 그 동의 중심으로, 동네 이름도 길 이름 → 동 이름
//   ③ 하나로 정해지지 않으면 손대지 않고 대표에게 텔레그램으로 알린다(같은 글자는 30일 동안 다시 시도하지 않음)
// 실제 수정·기록은 DB 함수 dong_autofix_apply(service_role 전용)가 한다. 호출은 x-jigi-secret 으로만.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

type Row = [string, string, number, number];   // [시군구("서울특별시 구로구"), 동, lat, lng]
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json" } });
const base = (d: string) => d.replace(/제?\d+(?:[·.,]\d+)*동$/, "동");                       // 구로1동·상계6·7동 → 구로동·상계동
const hnorm = (d: string) => d.replace(/제(\d)/g, "$1");                                      // 성수2가제3동 → 성수2가3동
const avg = (rs: Row[]) => ({ lat: rs.reduce((t, r) => t + r[2], 0) / rs.length, lng: rs.reduce((t, r) => t + r[3], 0) / rs.length });
let DONGS: Row[] | null = null;
async function dongs(): Promise<Row[]> {
  if (DONGS) return DONGS;
  const r = await fetch("https://yesbeyesnono.github.io/knit-neighbors/kr-dongs.json", { signal: AbortSignal.timeout(8000) });
  DONGS = ((await r.json()).rows ?? []) as Row[]; return DONGS;
}
type Hit = { name: string; code: string; lat: number; lng: number; why: string };

function byDongName(all: Row[], raw: string, sido: string | null): Hit | string {
  const tok = raw.trim().split(/\s+/).pop() ?? ""; const cands = [tok, tok.endsWith("동") || tok.endsWith("읍") || tok.endsWith("면") ? "" : tok + "동"].filter(Boolean);
  for (const n of cands) {
    let m = all.filter((r) => r[1] === n || base(r[1]) === n);
    // 성수동 → 성수1가1동·성수2가3동처럼 숫자 규칙으로 안 줄어드는 이름: 앞 글자가 같은 동을 찾는다(두 글자 이상, 아래에서 시군구가 하나일 때만 인정)
    if (!m.length && n.endsWith("동") && n.length >= 3) { const stem = n.slice(0, -1); m = all.filter((r) => r[1].startsWith(stem) && /\d/.test(r[1].slice(stem.length)) && r[1].endsWith("동")); }
    if (!m.length) continue;
    let groups = [...new Set(m.map((r) => r[0]))];
    if (groups.length > 1 && sido) { const f = m.filter((r) => r[0].startsWith(sido)); const g2 = [...new Set(f.map((r) => r[0]))]; if (g2.length === 1) { m = f; groups = g2; } }
    if (groups.length > 1) return `같은 이름의 동이 여러 곳에 있어요(${groups.slice(0, 4).join(", ")})`;
    const [si, ...rest] = groups[0].split(" "); const c = avg(m);
    return { name: raw.trim(), code: `${si}|${rest.join(" ")}|${n}`, lat: c.lat, lng: c.lng, why: `적은 동 이름(${n}) → ${groups[0]} ${m.map((r) => r[1]).join("·")} 중심` };
  }
  return "";
}

async function byRoad(all: Row[], raw: string): Promise<Hit | string> {
  const key = Deno.env.get("JUSO_KEY"); if (!key) return "도로명 검색 키가 없어요";
  const q = raw.replace(/[%=><\[\]{}'"\\;]/g, " ").replace(/\s+/g, " ").trim().slice(0, 60); if (q.length < 2) return "";
  const url = "https://business.juso.go.kr/addrlink/addrLinkApi.do?currentPage=1&countPerPage=100&resultType=json&addInfoYn=Y&keyword=" + encodeURIComponent(q) + "&confmKey=" + encodeURIComponent(key);
  const j = await (await fetch(url, { signal: AbortSignal.timeout(8000) })).json();
  if (String(j?.results?.common?.errorCode) !== "0") return "도로명 검색에서 찾지 못했어요";
  const rows = (j.results.juso ?? []) as Record<string, string>[]; if (!rows.length) return "도로명 검색 결과가 없어요";
  // 긴 길은 첫 100건이 길의 한쪽 끝(번호가 작은 쪽)만 보여 준다 → 전체 건수에 맞춰 쪽을 고르게 건너뛰며 더 읽는다(최대 6쪽 더)
  const total = +(j.results.common.totalCount ?? rows.length) || rows.length; const pages = Math.ceil(total / 100);
  if (pages > 1) { const pick = new Set<number>(); const want = Math.min(6, pages - 1); for (let i = 1; i <= want; i++) pick.add(1 + Math.round((i * (pages - 1)) / want));
    for (const pg of pick) { try { const jj = await (await fetch(url.replace("currentPage=1", "currentPage=" + pg), { signal: AbortSignal.timeout(8000) })).json(); if (String(jj?.results?.common?.errorCode) === "0") rows.push(...((jj.results.juso ?? []) as Record<string, string>[])); } catch (_e) { /* 한 쪽 실패는 넘어감 */ } } }
  const cnt: Record<string, { n: number; si: string; sgg: string; emd: string; hemd: Set<string> }> = {};
  for (const x of rows) { const k = `${x.siNm}|${x.sggNm}|${x.emdNm}`; (cnt[k] ??= { n: 0, si: x.siNm, sgg: x.sggNm, emd: x.emdNm, hemd: new Set() }).n++; if (x.hemdNm) cnt[k].hemd.add(hnorm(x.hemdNm)); }
  const list = Object.values(cnt).sort((a, b) => b.n - a.n); const top = list[0];
  const cities = new Set(list.map((x) => `${x.si} ${x.sgg}`));
  if (cities.size > 1 && top.n / rows.length < 0.8) return `같은 길 이름이 여러 지역에 있어요(${[...cities].slice(0, 4).join(", ")})`;
  if (top.n / rows.length < 0.4) return `길이 여러 동에 걸쳐 있어 하나로 정하지 못했어요(${list.slice(0, 4).map((x) => x.emd).join(", ")})`;
  const sgKey = `${top.si} ${top.sgg.replace(/\s+/g, "")}`;
  let m = all.filter((r) => r[0] === sgKey && (r[1] === top.emd || base(r[1]) === top.emd));
  if (!m.length) m = all.filter((r) => r[0] === sgKey && top.hemd.has(r[1]));
  if (!m.length) return `${top.si} ${top.sgg} ${top.emd} 의 위치를 목록에서 찾지 못했어요`;
  const c = avg(m);
  return { name: top.emd, code: `${top.si}|${top.sgg}|${top.emd}`, lat: c.lat, lng: c.lng, why: `길 이름(${q}) → 도로명주소 검색에서 가장 많이 걸친 동: ${top.si} ${top.sgg} ${top.emd}(${top.n}/${rows.length}건)` };
}

Deno.serve(async (req: Request) => {
  try {
    const { data: cfg } = await db.from("jigi_config").select("value").eq("key", "hook_secret").maybeSingle();
    if (!cfg?.value || req.headers.get("x-jigi-secret") !== cfg.value) return json({ error: "forbidden" }, 403);
    const { data: list, error } = await db.rpc("dong_autofix_candidates");
    if (error) return json({ error: error.message }, 500);
    if (!(list ?? []).length) return json({ checked: 0 });
    const all = await dongs(); const fixed: string[] = [], failed: string[] = [];
    for (const p of list as { id: string; nickname: string; dong_name: string; dong_code: string | null }[]) {
      const raw = String(p.dong_name ?? "").trim(); const sido = p.dong_code && p.dong_code.includes("|") ? p.dong_code.split("|")[0] : null;
      let res: Hit | string = "";
      try {
        res = byDongName(all, raw, sido);
        if (res === "" && /(로|길)\s*\d*(번길|길)?\s*[\d-]*$/.test(raw.replace(/\s+/g, ""))) res = await byRoad(all, raw.replace(/\s*\d+(-\d+)?\s*$/, ""));   // 끝의 번지는 떼고 길 이름만 보낸다
        if (res === "") res = "동 이름도 길 이름도 아니에요";
      } catch (_e) { res = "확인 중 오류"; }
      if (typeof res === "string") { await db.rpc("dong_autofix_apply", { p_profile: p.id, p_tried: raw, p_ok: false, p_note: res }); failed.push(`· ${p.nickname} — 적은 동네 「${raw}」: ${res}`); continue; }
      const { data: ok } = await db.rpc("dong_autofix_apply", { p_profile: p.id, p_tried: raw, p_ok: true, p_note: res.why, p_name: res.name, p_code: res.code, p_lat: res.lat, p_lng: res.lng });
      if (ok) fixed.push(`· ${p.nickname} — 「${raw}」 → ${res.code.split("|").join(" ")}`); else failed.push(`· ${p.nickname} — 「${raw}」: 저장하지 못했어요`);
    }
    if (fixed.length || failed.length) {
      const text = `📍 동네 자동 보정\n\n프로필은 끝냈는데 지도 위치가 없던 회원을 확인했어요(동네를 글자로만 적은 경우예요).\n\n` +
        (fixed.length ? `고친 회원 ${fixed.length}명 — 이제 지도에 핀이 보여요(본인이 지도 공개를 꺼 둔 경우는 제외). 회원에게 알림은 보내지 않았어요.\n${fixed.join("\n")}\n\n` : "") +
        (failed.length ? `자동으로 정하지 못한 회원 ${failed.length}명 — 손대지 않았어요. 콘솔 › 회원 › '동네 확인 필요'에서 [바꾸기]로 직접 고쳐 주세요. 같은 내용으로는 30일 동안 다시 알리지 않아요.\n${failed.join("\n")}\n\n` : "") +
        `방법: 동 이름이면 그 동(여러 개면 평균)의 중심, 길 이름이면 도로명주소 검색에서 그 길이 가장 많이 걸친 동의 중심으로 잡아요. 길 이름을 적었던 회원은 동네 칸도 동 이름으로 바꿨어요.`;
      await db.from("jigi_reminders").insert({ due_at: new Date().toISOString(), text });
    }
    return json({ checked: list.length, fixed: fixed.length, failed: failed.length });
  } catch (e) { return json({ error: String((e as Error)?.message ?? e).slice(0, 200) }, 500); }
});
