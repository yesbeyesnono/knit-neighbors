// 앱 푸시 발송(iOS = APNs HTTP/2 · Android = FCM HTTP v1). notifications insert 트리거(push_on_notification) → 이 함수 → 회원의 기기 토큰마다 발송
//   시크릿(iOS): APNS_KEY(.p8 파일 내용 전체, -----BEGIN PRIVATE KEY----- 포함) · APNS_KEY_ID(10자) · APNS_TEAM_ID(M59979ZT3A) · APNS_SANDBOX=1 이면 개발용 서버
//   시크릿(Android): FCM_SERVICE_ACCOUNT = Firebase › 프로젝트 설정 › 서비스 계정 › 새 비공개 키 로 받은 JSON 파일 내용 전체
//   토픽 = 기기 토큰이 등록될 때 앱이 보낸 bundle(KOAP: kr.co.firmtech.knitneighbors / Lab: ...lab). 410·BadDeviceToken·UNREGISTERED 는 토큰 비활성화
//   한쪽 키가 없어도 다른 쪽은 발송된다(기기별로 따로 처리)
//   호출 인증: x-jigi-secret(jigi_config.hook_secret) 또는 관리자 JWT(테스트 발송 route 'test')
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const URL_ = Deno.env.get("SUPABASE_URL")!;
const db = createClient(URL_, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const env = (k: string) => Deno.env.get(k) ?? "";
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };   // 앱(웹뷰)에서 테스트 발송을 부를 수 있게
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
const b64url = (b: ArrayBuffer | Uint8Array) => btoa(String.fromCharCode(...new Uint8Array(b))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const pemDer = (pem: string) => Uint8Array.from(atob(pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "")), (c) => c.charCodeAt(0));
type Msg = { title: string; body: string; badge?: number; kind: string; nid?: string };

// ---- APNs 제공자 토큰(JWT ES256), 50분마다 갱신
let jwtCache: { t: string; at: number } | null = null;
async function apnsJwt(): Promise<string> {
  if (jwtCache && Date.now() - jwtCache.at < 50 * 60 * 1000) return jwtCache.t;
  const pem = env("APNS_KEY").replace(/\\n/g, "\n"); const kid = env("APNS_KEY_ID"), iss = env("APNS_TEAM_ID");
  if (!pem || !kid || !iss) throw new Error("no_apns_key");
  const key = await crypto.subtle.importKey("pkcs8", pemDer(pem), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const enc = new TextEncoder();
  const head = b64url(enc.encode(JSON.stringify({ alg: "ES256", kid }))), payload = b64url(enc.encode(JSON.stringify({ iss, iat: Math.floor(Date.now() / 1000) })));
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, enc.encode(head + "." + payload));   // WebCrypto 는 r||s(64B) 그대로 — APNs 가 요구하는 JOSE 형식
  jwtCache = { t: `${head}.${payload}.${b64url(sig)}`, at: Date.now() }; return jwtCache.t;
}
async function sendApns(token: string, bundle: string, m: Msg) {
  const payload = { aps: { alert: { title: m.title, body: m.body }, ...(m.badge != null ? { badge: m.badge } : {}), sound: "default", "thread-id": m.kind }, kind: m.kind, nid: m.nid };
  const host = env("APNS_SANDBOX") === "1" ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";
  const r = await fetch(`${host}/3/device/${token}`, { method: "POST", headers: { authorization: `bearer ${await apnsJwt()}`, "apns-topic": bundle, "apns-push-type": "alert", "apns-priority": "10", "apns-expiration": String(Math.floor(Date.now() / 1000) + 86400) }, body: JSON.stringify(payload) });
  const txt = r.ok ? "" : await r.text();
  const dead = r.status === 410 || /BadDeviceToken|Unregistered|DeviceTokenNotForTopic/.test(txt);
  await db.rpc("push_mark", { p_token: token, p_ok: r.ok, p_dead: dead });
  return { platform: "ios", status: r.status, dead, err: txt.slice(0, 120) };
}

// ---- FCM: 서비스 계정 JWT(RS256) → OAuth 액세스 토큰(50분 캐시) → messages:send
let fcmCache: { t: string; pid: string; at: number } | null = null;
async function fcmAccess(): Promise<{ t: string; pid: string }> {
  if (fcmCache && Date.now() - fcmCache.at < 50 * 60 * 1000) return fcmCache;
  const raw = env("FCM_SERVICE_ACCOUNT"); if (!raw) throw new Error("no_fcm_key");
  let sa: { client_email?: string; private_key?: string; project_id?: string };
  try { sa = JSON.parse(raw); } catch { throw new Error("bad_fcm_key"); }
  if (!sa.client_email || !sa.private_key || !sa.project_id) throw new Error("bad_fcm_key");
  const key = await crypto.subtle.importKey("pkcs8", pemDer(sa.private_key.replace(/\\n/g, "\n")), { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const enc = new TextEncoder(), now = Math.floor(Date.now() / 1000);
  const head = b64url(enc.encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claim = b64url(enc.encode(JSON.stringify({ iss: sa.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging", aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600 })));
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, enc.encode(head + "." + claim));
  const r = await fetch("https://oauth2.googleapis.com/token", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${head}.${claim}.${b64url(sig)}` }) });
  const j = await r.json().catch(() => ({}));
  if (!r.ok || !j.access_token) throw new Error("fcm_auth_" + r.status);
  fcmCache = { t: j.access_token, pid: sa.project_id, at: Date.now() }; return fcmCache;
}
async function sendFcm(token: string, m: Msg) {
  const a = await fcmAccess();
  const message = { token, notification: { title: m.title, body: m.body }, data: { kind: String(m.kind ?? ""), nid: String(m.nid ?? "") }, android: { priority: "HIGH", ttl: "86400s", notification: { sound: "default", tag: m.nid ? String(m.nid) : undefined } } };
  const r = await fetch(`https://fcm.googleapis.com/v1/projects/${a.pid}/messages:send`, { method: "POST", headers: { authorization: `Bearer ${a.t}`, "content-type": "application/json" }, body: JSON.stringify({ message }) });
  const txt = r.ok ? "" : await r.text();
  const dead = r.status === 404 || /UNREGISTERED/.test(txt);
  await db.rpc("push_mark", { p_token: token, p_ok: r.ok, p_dead: dead });
  return { platform: "android", status: r.status, dead, err: txt.replace(/\s+/g, " ").slice(0, 120) };
}
async function sendTo(t: { token: string; bundle: string; platform: string }, m: Msg) {
  try { return t.platform === "android" ? await sendFcm(t.token, m) : await sendApns(t.token, t.bundle, m); }
  catch (e) { return { platform: t.platform, status: 0, dead: false, err: String((e as Error).message).slice(0, 60) }; }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const body = await req.json().catch(() => ({}));
    const { data: cfg } = await db.from("jigi_config").select("value").eq("key", "hook_secret").single();
    const viaHook = !!cfg?.value && req.headers.get("x-jigi-secret") === cfg.value;
    let isAdmin = false, uid = "";
    if (!viaHook) {
      const auth = req.headers.get("Authorization") ?? "";
      const c = createClient(URL_, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: auth } } });
      const { data: u } = await c.auth.getUser(); uid = u?.user?.id ?? "";
      const { data: adm } = await c.rpc("is_admin"); isAdmin = adm === true;
      if (!uid) return json({ error: "forbidden" }, 403);
    }
    if (body.route === "status") return json({ apns: !!env("APNS_KEY") && !!env("APNS_KEY_ID") && !!env("APNS_TEAM_ID"), fcm: !!env("FCM_SERVICE_ACCOUNT"), sandbox: env("APNS_SANDBOX") === "1" });
    if (body.route === "test") {   // 본인 기기로 테스트 발송(로그인 사용자 누구나 자기 기기에만)
      const { data: toks } = await db.from("device_tokens").select("token,bundle,platform").eq("profile_id", uid).is("disabled_at", null);
      const out = []; for (const t of toks ?? []) out.push(await sendTo(t, { title: "뜨개동네", body: "푸시 알림이 잘 도착했어요 🧶", kind: "test" }));
      const err = out.find((o) => o.status !== 200)?.err ?? "";
      return json({ sent: out.filter((o) => o.status === 200).length, tried: out.length, error: /^no_|^bad_/.test(err) ? err : undefined, results: out });
    }
    if (!viaHook && !isAdmin) return json({ error: "forbidden" }, 403);
    const id = String(body.notification_id ?? ""); if (!id) return json({ error: "no_id" }, 400);
    const { data: p } = await db.rpc("push_payload", { p_id: id });
    if (!p || !(p.tokens ?? []).length) return json({ sent: 0 });
    const m: Msg = { title: p.title, body: p.body, badge: p.badge ?? 0, kind: p.kind, nid: p.notification_id };
    const out = []; for (const t of p.tokens) out.push(await sendTo(t, m));
    return json({ sent: out.filter((o) => o.status === 200).length, results: out });
  } catch (e) { return json({ error: String((e as Error).message).slice(0, 120) }, 200); }
});
