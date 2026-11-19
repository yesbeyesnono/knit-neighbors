// 영상 올리기 — 회원의 영상을 Cloudflare Stream 에 올려 서버가 자동으로 줄이게 한다(2026-11-19 대표: 큰 영상도 자동으로 압축 · 쓰레드처럼).
// 앱은 ① create 로 '바로 올리는 주소'를 받아 영상을 그 주소로 직접 올리고 ② finish 로 내려받기용 MP4 를 켠다.
// 길이는 Cloudflare 가 막는다(maxDurationSeconds). 누가 올린 영상인지 video_uploads 에 적어 두고, 글에 붙일 때 DB(posts_video_guard)가 확인한다.
// 환경변수: CF_STREAM_TOKEN (Cloudflare API 토큰 — Stream 편집 권한). 값은 어디에도 내보내지 않는다.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const CF_ACCOUNT = "3a6c5f3a6735255b1e3b87fe35250e19";
const API = `https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT}/stream`;
const MAX_SECONDS = 36;      // 앱 안내는 30초 — 조금 넘는 것은 받아 준다
const PER_DAY = 10;

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
    const token = Deno.env.get("CF_STREAM_TOKEN") ?? "";
    const url = Deno.env.get("SUPABASE_URL")!;
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const sb = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } });
    const body = await req.json().catch(() => ({}));
    if (body.ping) return json({ ready: !!token });   // 열쇠가 들어 있는지만 알려 준다
    if (!token) return json({ error: "not_ready" }, 503);

    const { data: u } = await sb.auth.getUser();
    const uid = u?.user?.id;
    if (!uid) return json({ error: "auth" }, 401);
    const cf = (path: string, init: RequestInit = {}) =>
      fetch(API + path, { ...init, headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json", ...(init.headers ?? {}) } });

    if (body.action === "create") {
      const { data: prof } = await admin.from("profiles").select("suspended_at, deleted_at, post_restricted_until").eq("id", uid).maybeSingle();
      if (!prof || prof.suspended_at || prof.deleted_at || (prof.post_restricted_until && new Date(prof.post_restricted_until) > new Date())) return json({ error: "forbidden" }, 403);
      const since = new Date(Date.now() - 864e5).toISOString();
      const { count } = await admin.from("video_uploads").select("uid", { count: "exact", head: true }).eq("owner", uid).gte("created_at", since);
      if ((count ?? 0) >= PER_DAY) return json({ error: "daily_limit" }, 429);
      const r = await cf("/direct_upload", { method: "POST", body: JSON.stringify({ maxDurationSeconds: MAX_SECONDS, creator: uid, requireSignedURLs: false, meta: { name: `knitup ${uid.slice(0, 8)}` } }) });
      const j = await r.json().catch(() => null);
      if (!r.ok || !j?.success || !j.result?.uid || !j.result?.uploadURL) return json({ error: "cf_create" }, 502);
      const { error } = await admin.from("video_uploads").insert({ uid: j.result.uid, owner: uid });
      if (error) return json({ error: "save" }, 500);
      return json({ uid: j.result.uid, uploadURL: j.result.uploadURL });
    }

    if (body.action === "finish") {
      const id = String(body.uid ?? "");
      if (!/^[0-9a-f]{32}$/.test(id)) return json({ error: "bad_uid" }, 400);
      const { data: row } = await admin.from("video_uploads").select("uid, owner").eq("uid", id).maybeSingle();
      if (!row || row.owner !== uid) return json({ error: "forbidden" }, 403);
      const r = await cf(`/${id}`);
      const j = await r.json().catch(() => null);
      if (!r.ok || !j?.success) return json({ error: "cf_status" }, 502);
      const v = j.result ?? {};
      const state = String(v.status?.state ?? "");
      if (state === "error") return json({ state, error: "cf_error", reason: String(v.status?.errorReasonCode ?? "") });
      // 어느 기기에서나 재생되도록 MP4 내려받기를 켜 둔다(이미 켜져 있으면 그대로)
      let mp4 = "";
      if (v.readyToStream) {
        const d = await cf(`/${id}/downloads`, { method: "POST" });
        const dj = await d.json().catch(() => null);
        mp4 = String(dj?.result?.default?.status ?? "");
      }
      await admin.from("video_uploads").update({ ready_at: v.readyToStream ? new Date().toISOString() : null, duration: typeof v.duration === "number" && v.duration > 0 ? v.duration : null }).eq("uid", id);
      return json({ state, ready: !!v.readyToStream, mp4, duration: v.duration ?? null, w: v.input?.width ?? null, h: v.input?.height ?? null });
    }
    return json({ error: "bad_action" }, 400);
  } catch (_e) {
    return json({ error: "server" }, 500);
  }
});
