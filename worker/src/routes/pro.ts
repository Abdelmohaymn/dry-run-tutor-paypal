// Pro Plus (feature 009): GET /v1/pro/status and POST /v1/pro/checkout.
// worker-api.md §1, §2. Install-auth, mounted in index.ts.
//
// The relay decides Pro on every call; the app only asks and displays. A
// checkout binds its subscription to this device at creation, and nothing here
// accepts a subscription id from the client (research.md R-8).
import { Hono } from "hono";
import type { Env, Variables } from "../types";
import { AppError } from "../lib/errors";
import { createSubscription } from "../lib/paypal";
import { currentSubscription, isEntitled, recheckDevice, resolveProTier } from "../lib/pro";
import { proSessionsToday } from "../lib/pro-session";
import { getRuntimeConfig, proConfig, voiceConfig } from "../lib/runtime-config";
import { getTrialConsumed, trialSessionsClaimed } from "../lib/trial-pool";
import { getVoiceSecondsUsed } from "../lib/voice-quota";
import { utcDate } from "../lib/time";

export const proRoute = new Hono<{ Bindings: Env; Variables: Variables }>();

const NO_STORE = { "cache-control": "private, no-store" };
const PENDING_TTL_MS = 3 * 60 * 60 * 1000;

proRoute.post("/checkout", async (c) => {
  const db = c.env.DB;
  const deviceHash = c.get("installId");
  const cfg = await getRuntimeConfig(db);

  // 1. Pro must be on.
  const pro = proConfig(cfg);
  if (!pro) throw new AppError("BAD_REQUEST");

  // 2. Per-device rate limit.
  const { success } = await c.env.PRO_RL.limit({ key: deviceHash });
  if (!success) throw new AppError("RATE_LIMITED");

  // 3. Already entitled: no second subscription, no PayPal call.
  const now = new Date();
  const current = await currentSubscription(db, deviceHash, now);
  if (current && isEntitled(current, now)) {
    return c.json({ already_active: true }, 200, NO_STORE);
  }

  // 4. Housekeeping: checkouts this device abandoned.
  await db
    .prepare("DELETE FROM pro_subscriptions WHERE device_hash = ?1 AND status = 'pending' AND confirmed_at < ?2")
    .bind(deviceHash, new Date(now.getTime() - PENDING_TTL_MS).toISOString())
    .run();

  // 5-6. Create the subscription. Any failure is UNCLEAR_RETRY and writes no row.
  const origin = new URL(c.req.url).origin;
  const created = await createSubscription(c.env, pro.plan_id, `${origin}/paypal/return`, `${origin}/paypal/cancel`);

  // 7. Bind it to this device, now and for good.
  await db
    .prepare(
      "INSERT INTO pro_subscriptions (subscription_id, device_hash, status, period_end, confirmed_at) VALUES (?1, ?2, 'pending', NULL, ?3)",
    )
    .bind(created.id, deviceHash, now.toISOString())
    .run();

  return c.json({ approve_url: created.approveUrl }, 200, NO_STORE);
});

proRoute.get("/status", async (c) => {
  const db = c.env.DB;
  const deviceHash = c.get("installId");
  const cfg = await getRuntimeConfig(db);
  const now = new Date();
  const today = utcDate(now);
  const pro = proConfig(cfg);

  // R-12: heal a missed webhook. Best effort; a PayPal failure serves the stored row.
  if (pro) await recheckDevice(c.env, db, deviceHash, pro, now);

  const tier = await resolveProTier(cfg, db, deviceHash, now);
  const sub = await currentSubscription(db, deviceHash, now);
  const voiceUsed = await getVoiceSecondsUsed(db, deviceHash, today);

  let proLimit: "ok" | "sessions_used" | "capacity" | null = null;
  let usage: {
    sessions_used: number;
    sessions_limit: number;
    sessions_period: "day" | "lifetime";
    voice_seconds_used: number;
    voice_seconds_limit: number;
  };
  if (tier) {
    const sessionsUsed = await proSessionsToday(db, deviceHash, today);
    proLimit = !tier.capacityOk ? "capacity" : sessionsUsed >= tier.pro.sessions_per_day ? "sessions_used" : "ok";
    usage = {
      sessions_used: sessionsUsed,
      sessions_limit: tier.pro.sessions_per_day,
      sessions_period: "day",
      voice_seconds_used: voiceUsed,
      voice_seconds_limit: tier.pro.voice_seconds_per_day,
    };
  } else {
    const voice = voiceConfig(cfg);
    usage = {
      sessions_used: trialSessionsClaimed(await getTrialConsumed(db, deviceHash)),
      sessions_limit: cfg.trial.sessions_per_device,
      sessions_period: "lifetime",
      voice_seconds_used: voice ? voiceUsed : 0,
      voice_seconds_limit: voice ? voice.seconds_per_device : 0,
    };
  }

  return c.json(
    {
      offer_enabled: pro !== null,
      plan: tier ? "pro" : "free",
      subscription: sub
        ? { status: sub.status, period_end: sub.period_end, confirmed_at: sub.confirmed_at }
        : null,
      pro_limit: proLimit,
      usage,
      as_of: now.toISOString(),
    },
    200,
    NO_STORE,
  );
});
