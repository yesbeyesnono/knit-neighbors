// 모임 장소 검색 — 카카오 로컬 키워드 검색을 감싼다. 키(KAKAO_REST_KEY)가 없거나 실패하면 {fallback:true} → 앱이 기존 geocodePlace()로 대체.
// 로그인 사용자만(verify_jwt), 1인 분당 40회(rate_hit).
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
    const auth = req.headers.get("Authorization") ?? "";
    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: auth } } });
    const { data: ok, error: rerr } = await sb.rpc("rate_hit", { p_key: "place", p_limit: 40 });
    if (rerr) return json({ error: "auth" }, 401);
    if (!ok) return json({ error: "rate", results: [] }, 429);

    const key = Deno.env.get("KAKAO_REST_KEY");
    if (!key) return json({ fallback: true, results: [] });

    const b = await req.json().catch(() => ({}));
    const q = String(b.q ?? "").trim().slice(0, 60);
    const lat = Number(b.lat), lng = Number(b.lng);
    const near = Number.isFinite(lat) && Number.isFinite(lng) && lat > 32 && lat < 40 && lng > 123 && lng < 133;
    if (!q) return json({ results: [] });

    const p = new URLSearchParams({ query: q, size: "10" });
    if (near) { p.set("x", String(lng)); p.set("y", String(lat)); if (b.sort === "distance") { p.set("sort", "distance"); p.set("radius", "20000"); } }
    const h = { Authorization: `KakaoAK ${key}` };
    const r = await fetch("https://dapi.kakao.com/v2/local/search/keyword.json?" + p, { headers: h });
    if (!r.ok) return json({ fallback: true, results: [] });
    const j = await r.json();
    let results = (j.documents ?? []).map((d: Record<string, string>) => ({
      name: d.place_name, category: (d.category_group_name || (d.category_name ?? "").split(" > ").pop() || ""),
      addr: d.road_address_name || d.address_name, lat: +d.y, lng: +d.x,
    }));
    if (!results.length) {   // 장소 이름이 아니라 주소를 친 경우
      const r2 = await fetch("https://dapi.kakao.com/v2/local/search/address.json?" + new URLSearchParams({ query: q, size: "5" }), { headers: h });
      if (r2.ok) results = ((await r2.json()).documents ?? []).map((d: Record<string, any>) => ({
        name: d.road_address?.building_name || d.address_name, category: "주소", addr: d.road_address?.address_name || d.address_name, lat: +d.y, lng: +d.x,
      }));
    }
    return json({ results });
  } catch (_e) {
    return json({ fallback: true, results: [] });
  }
});
