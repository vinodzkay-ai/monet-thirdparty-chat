import { createClient } from "@supabase/supabase-js";

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

const supabase = (SUPABASE_URL && SUPABASE_SERVICE_ROLE_KEY)
  ? createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false }
    })
  : null;

// Best-effort per warm function instance. For large-scale use, use atomic DB/Redis rate limiting.
const recentRequests = new Map();
const MAX_BODY = 4096;
const ROOM_RE = /^[A-Za-z0-9_-]{2,24}$/;
const NICK_RE = /^[\p{L}\p{N}_ .-]{1,24}$/u;

function response(statusCode, body) {
  return {
    statusCode,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "access-control-allow-origin": "*",
      "access-control-allow-methods": "GET, POST, OPTIONS",
      "access-control-allow-headers": "Content-Type"
    },
    body: JSON.stringify(body)
  };
}
function cleanText(s, max) {
  return String(s ?? "").replace(/[\u0000-\u001F\u007F]/g, " ").trim().slice(0, max);
}
function clientIp(event) {
  return event.headers?.["x-nf-client-connection-ip"]
    || event.headers?.["x-forwarded-for"]?.split(",")[0]?.trim()
    || "unknown";
}
function allowedRate(key, cooldownMs) {
  const now = Date.now();
  const last = recentRequests.get(key) || 0;
  if (now - last < cooldownMs) return false;
  recentRequests.set(key, now);
  if (recentRequests.size > 3000) {
    for (const [k, t] of recentRequests) if (now - t > 120000) recentRequests.delete(k);
  }
  return true;
}

export async function handler(event) {
  if (event.httpMethod === "OPTIONS") return response(204, {});
  if (!["GET", "POST"].includes(event.httpMethod)) {
    return response(405, { ok: false, error: "method_not_allowed" });
  }
  if (!supabase) return response(500, { ok: false, error: "backend_not_configured" });

  if (event.httpMethod === "GET") {
    const room = cleanText(event.queryStringParameters?.room, 24).toUpperCase();
    const afterRaw = Number.parseInt(event.queryStringParameters?.after || "0", 10);
    const after = Number.isFinite(afterRaw) && afterRaw > 0 ? afterRaw : 0;
    if (!ROOM_RE.test(room)) return response(400, { ok: false, error: "invalid_room" });

    const { data, error } = await supabase
      .from("room_messages")
      .select("id, room_id, nickname, message, created_at")
      .eq("room_id", room)
      .gt("id", after)
      .order("id", { ascending: true })
      .limit(40);

    if (error) return response(500, { ok: false, error: "database_error" });
    return response(200, { ok: true, messages: data || [] });
  }

  const raw = event.body || "";
  if (raw.length > MAX_BODY) return response(413, { ok: false, error: "body_too_large" });

  let body;
  try { body = JSON.parse(raw); }
  catch { return response(400, { ok: false, error: "invalid_json" }); }

  const action = body.action;
  const room = cleanText(body.room, 24).toUpperCase();
  if (!ROOM_RE.test(room)) return response(400, { ok: false, error: "invalid_room" });

  if (action !== "send") return response(400, { ok: false, error: "invalid_action" });

  const nickname = cleanText(body.nickname, 24);
  const message = cleanText(body.message, 240);
  if (!NICK_RE.test(nickname)) return response(400, { ok: false, error: "invalid_nickname" });
  if (!message || message.length < 1) return response(400, { ok: false, error: "empty_message" });

  const ip = clientIp(event);
  if (!allowedRate(`${ip}:${room}`, 1800)) {
    return response(429, { ok: false, error: "rate_limited", retry_after_ms: 1800 });
  }

  const { data, error } = await supabase
    .from("room_messages")
    .insert({ room_id: room, nickname, message })
    .select("id, room_id, nickname, message, created_at")
    .single();

  if (error) return response(500, { ok: false, error: "database_error" });
  return response(201, { ok: true, message: data });
}
