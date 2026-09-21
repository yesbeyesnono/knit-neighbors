// 지기 알림 — ① 예약 알림(jigi_reminders)을 시간이 되면 대표 텔레그램으로 보낸다 ② 텔레그램 웹훅이 우리 주소에서 바뀌었는지 지킨다(토큰 도용 대비).
// 호출: DB 크론(pg_net) 만. 헤더 x-jigi-secret = jigi_config.hook_secret
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const env = (k: string) => Deno.env.get(k) ?? "";
const HOOK = `${Deno.env.get("SUPABASE_URL")}/functions/v1/jigi?fn=tg`;
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json" } });
async function tg(method: string, body: unknown) {
  const r = await fetch(`https://api.telegram.org/bot${env("TG_BOT_TOKEN")}/${method}`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
  return r.ok ? (await r.json()).result : null;
}
const send = (text: string) => tg("sendMessage", { chat_id: env("TG_ADMIN_CHAT_ID"), text: text.slice(0, 3900) });

Deno.serve(async (req: Request) => {
  try {
    const { data: cfg } = await db.from("jigi_config").select("value").eq("key", "hook_secret").single();
    if (!cfg?.value || req.headers.get("x-jigi-secret") !== cfg.value) return json({ error: "forbidden" }, 403);
    if (!env("TG_BOT_TOKEN") || !env("TG_ADMIN_CHAT_ID")) return json({ error: "no_telegram" });
    const body = await req.json().catch(() => ({}));
    const out: Record<string, unknown> = {};

    if (body.route === "guard") {   // 웹훅 주소가 바뀌었으면 되돌리고 알린다
      const info = await tg("getWebhookInfo", {});
      if (info && info.url !== HOOK && env("TG_WEBHOOK_SECRET")) {
        await tg("setWebhook", { url: HOOK, secret_token: env("TG_WEBHOOK_SECRET") });
        await send("⚠️ 보안 알림: 텔레그램 봇의 연결 주소가 바뀌어 있어서 원래대로 되돌렸어요. 봇 토큰이 다른 곳에서 쓰였을 수 있어요 — BotFather 에서 토큰을 새로 발급(Revoke)해 주세요.");
        out.guard = "restored";
      } else out.guard = "ok";
      return json(out);
    }

    const { data: due } = await db.from("jigi_reminders").select("id,text").is("sent_at", null).lte("due_at", new Date().toISOString()).order("due_at").limit(10);
    let n = 0;
    for (const r of due ?? []) { if (await send("🔔 " + r.text)) { await db.from("jigi_reminders").update({ sent_at: new Date().toISOString() }).eq("id", r.id); n++; } }
    return json({ sent: n });
  } catch (e) { return json({ error: String((e as Error).message).slice(0, 100) }, 500); }
});
