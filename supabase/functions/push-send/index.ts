// 앱 푸시 발송(APNs HTTP/2). notifications insert 트리거(push_on_notification) → 이 함수 → 회원의 기기 토큰마다 발송
//   시크릿: APNS_KEY(.p8 파일 내용 전체, -----BEGIN PRIVATE KEY----- 포함) · APNS_KEY_ID(10자) · APNS_TEAM_ID(M59979ZT3A) · APNS_SANDBOX=1 이면 개발용 서버
//   토픽 = 기기 토큰이 등록될 때 앱이 보낸 bundle(KOAP: kr.co.firmtech.knitneighbors / Lab: ...lab). 410·BadDeviceToken 은 토큰 비활성화
//   호출 인증: x-jigi-secret(jigi_config.hook_secret) 또는 관리자 JWT(테스트 발송 route 'test')
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const URL_ = Deno.env.get("SUPABASE_URL")!;
const db = createClient(URL_, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const env = (k: string) => Deno.env.get(k) ?? "";
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json" } });

// ---- APNs 제공자 토큰(JWT ES256), 50분마다 갱신
let jwtCache: { t: string; at: number } | null = null;
const b64url = (b: ArrayBuffer | Uint8Array) => btoa(String.fromCharCode(...new Uint8Array(b))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
async function apnsJwt(): Promise<string> {
  if (jwtCache && Date.now() - jwtCache.at < 50 * 60 * 1000) return jwtCache.t;
  const pem = env("APNS_KEY").replace(/\\n/g, "\n"); const kid = env("APNS_KEY_ID"), iss = env("APNS_TEAM_ID");
  if (!pem || !kid || !iss) throw new Error("no_apns_key");
  const der = Uint8Array.from(atob(pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "")), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const enc = new TextEncoder();
  const head = b64url(enc.encode(JSON.stringify({ alg: "ES256", kid }))), payload = b64url(enc.encode(JSON.stringify({ iss, iat: Math.floor(Date.now() / 1000) })));
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, enc.encode(head + "." + payload));   // WebCrypto 는 r||s(64B) 그대로 — APNs 가 요구하는 JOSE 형식
  jwtCache = { t: `${head}.${payload}.${b64url(sig)}`, at: Date.now() }; return jwtCache.t;
}
async function sendOne(token: string, bundle: string, payload: Record<string, unknown>) {
  const host = env("APNS_SANDBOX") === "1" ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";
  const r = await fetch(`${host}/3/device/${token}`, { method: "POST", headers: { authorization: `bearer ${await apnsJwt()}`, "apns-topic": bundle, "apns-push-type": "alert", "apns-priority": "10", "apns-expiration": String(Math.floor(Date.now() / 1000) + 86400) }, body: JSON.stringify(payload) });
  const txt = r.ok ? "" : await r.text();
  const dead = r.status === 410 || /BadDeviceToken|Unregistered|DeviceTokenNotForTopic/.test(txt);
  await db.rpc("push_mark", { p_token: token, p_ok: r.ok, p_dead: dead });
  return { status: r.status, dead, err: txt.slice(0, 120) };
}

Deno.serve(async (req: Request) => {
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
    if (body.route === "status") return json({ apns: !!env("APNS_KEY") && !!env("APNS_KEY_ID") && !!env("APNS_TEAM_ID"), sandbox: env("APNS_SANDBOX") === "1" });
    if (body.route === "test") {   // 본인 기기로 테스트 발송(로그인 사용자 누구나 자기 기기에만)
      const { data: toks } = await db.from("device_tokens").select("token,bundle").eq("profile_id", uid).is("disabled_at", null);
      const out = []; for (const t of toks ?? []) out.push(await sendOne(t.token, t.bundle, { aps: { alert: { title: "뜨개동네", body: "푸시 알림이 잘 도착했어요 🧶" }, sound: "default" }, kind: "test" }));
      return json({ sent: out.length, results: out });
    }
    if (!viaHook && !isAdmin) return json({ error: "forbidden" }, 403);
    const id = String(body.notification_id ?? ""); if (!id) return json({ error: "no_id" }, 400);
    const { data: p } = await db.rpc("push_payload", { p_id: id });
    if (!p || !(p.tokens ?? []).length) return json({ sent: 0 });
    const payload = { aps: { alert: { title: p.title, body: p.body }, badge: p.badge ?? 0, sound: "default", "thread-id": p.kind }, kind: p.kind, nid: p.notification_id };
    const out = []; for (const t of p.tokens) if (t.platform === "ios") out.push(await sendOne(t.token, t.bundle, payload));
    return json({ sent: out.filter((o) => o.status === 200).length, results: out });
  } catch (e) { return json({ error: String((e as Error).message).slice(0, 120) }, 200); }
});
