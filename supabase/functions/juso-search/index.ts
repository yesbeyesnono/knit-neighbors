// 도로명주소 검색(행정안전부 주소기반산업지원서비스 '도로명주소 검색 API') 중계 — 동네 찾기 전용.
// 왜 서버를 거치나: 승인키를 공개 저장소·앱에 넣지 않기 위해(시크릿 JUSO_KEY). 키가 없으면 { off:true } 로 답하고 앱은 동 이름 목록·지도 고르기만 쓴다.
// 개인정보: 회원이 적은 검색어(주소)는 행안부로 전달만 하고 **저장·로그하지 않는다**. 앱에 돌려주는 것은 주소 글자와 그 주소의 시도·시군구·읍면동·행정동 이름뿐.
// 로그인한 회원만, 1인 60회/시간(rate_hit).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const auth = req.headers.get("Authorization") ?? ""; if (!auth) return json({ error: "forbidden" }, 401);
    const uc = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: auth } } });
    const { data: u } = await uc.auth.getUser(); if (!u?.user?.id) return json({ error: "forbidden" }, 401);
    const key = Deno.env.get("JUSO_KEY"); if (!key) return json({ off: true, rows: [] });
    const body = await req.json().catch(() => ({}));
    // 검색 API 가 거절하는 특수문자·SQL 예약어 모양은 미리 지운다(가이드의 checkSearchedWord 와 같은 취지)
    const q = String(body.q ?? "").replace(/[%=><\[\]{}'"\\;]/g, " ").replace(/\s+/g, " ").trim().slice(0, 60);
    if (q.length < 2) return json({ rows: [] });
    const { data: ok } = await uc.rpc("rate_hit", { p_key: "juso", p_limit: 60, p_window_sec: 3600 });
    if (ok === false) return json({ error: "잠시 뒤에 다시 찾아 주세요" }, 429);
    const url = "https://business.juso.go.kr/addrlink/addrLinkApi.do?currentPage=1&countPerPage=10&resultType=json&addInfoYn=Y&keyword=" +
      encodeURIComponent(q) + "&confmKey=" + encodeURIComponent(key);
    const r = await fetch(url, { signal: AbortSignal.timeout(6000) });
    const j = await r.json();
    const c = j?.results?.common ?? {};
    if (String(c.errorCode) !== "0") return json({ rows: [], note: String(c.errorMessage ?? "").slice(0, 80) });
    const rows = (j.results.juso ?? []).slice(0, 10).map((x: Record<string, string>) => ({
      road: x.roadAddrPart1 || x.roadAddr || "", si: x.siNm || "", sgg: x.sggNm || "", emd: x.emdNm || "", hemd: x.hemdNm || "",
    }));
    return json({ rows });
  } catch (_e) {
    return json({ rows: [], note: "search_failed" });
  }
});
