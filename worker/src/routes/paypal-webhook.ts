// POST /v1/paypal/webhook — PayPal → relay (feature 009, worker-api.md §3).
// Public: PayPal calls it, not a phone, so it is mounted WITHOUT installAuth.
//
// A webhook is only a trigger to re-read the subscription (research.md R-6): it
// never applies an event as a state change, so duplicates and late arrivals
// converge on PayPal's current truth. The signature is checked through PayPal's
// own verification API with the raw body spliced in (R-7).
//
// Privacy (FR-023): the body is never logged, stored, or put in an error. Of
// the whole event only `event_type` and one subscription id are read.
import { Hono } from "hono";
import { z } from "zod";
import type { Env, Variables } from "../types";
import { AppError, buildEnvelope } from "../lib/errors";
import { isSubscriptionId, verifyWebhook } from "../lib/paypal";
import { refreshSubscription } from "../lib/pro";

export const paypalWebhookRoute = new Hono<{ Bindings: Env; Variables: Variables }>();

const MAX_BODY_BYTES = 65_536;

const PAYPAL_HEADERS = [
  "paypal-auth-algo",
  "paypal-cert-url",
  "paypal-transmission-id",
  "paypal-transmission-sig",
  "paypal-transmission-time",
] as const;

// Not .strict(): everything else in the event (payer name, email…) is dropped here.
const eventSchema = z.object({
  event_type: z.string(),
  resource: z
    .object({
      id: z.string().optional(),
      billing_agreement_id: z.string().optional(),
    })
    .optional(),
});

function subscriptionIdOf(event: z.infer<typeof eventSchema>): string | null {
  if (event.event_type.startsWith("BILLING.SUBSCRIPTION.")) return event.resource?.id ?? null;
  if (event.event_type.startsWith("PAYMENT.SALE.")) return event.resource?.billing_agreement_id ?? null;
  return null;
}

paypalWebhookRoute.post("/webhook", async (c) => {
  // 1. Size and shape.
  const declared = Number(c.req.header("content-length") ?? "0");
  if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) throw new AppError("BAD_REQUEST");
  const raw = await c.req.text();
  if (new TextEncoder().encode(raw).byteLength > MAX_BODY_BYTES) throw new AppError("BAD_REQUEST");
  let json: unknown;
  try {
    json = JSON.parse(raw);
  } catch {
    throw new AppError("BAD_REQUEST");
  }

  // 2. All five signature headers.
  if (PAYPAL_HEADERS.some((h) => !c.req.header(h))) throw new AppError("BAD_REQUEST");

  // 3. Verify with PayPal. Nothing is written unless it says SUCCESS.
  if (!(await verifyWebhook(c.env, c.req.raw.headers, raw))) throw new AppError("BAD_REQUEST");

  // 4. Which subscription, if any.
  const event = eventSchema.safeParse(json);
  const id = event.success ? subscriptionIdOf(event.data) : null;
  if (!id || !isSubscriptionId(id)) return c.json({ ok: true }, 200);

  // 5. Ours? An unknown id is not bound to any device, so there is nothing to update.
  const known = await c.env.DB
    .prepare("SELECT 1 AS one FROM pro_subscriptions WHERE subscription_id = ?1")
    .bind(id)
    .first();
  if (!known) return c.json({ ok: true }, 200);

  // 6. Re-read and store what PayPal says now. If PayPal cannot be read, answer
  // 500 so PayPal redelivers (the envelope is the usual UNCLEAR_RETRY one).
  try {
    await refreshSubscription(c.env, c.env.DB, id, new Date());
  } catch {
    return new Response(JSON.stringify(buildEnvelope(new AppError("UNCLEAR_RETRY"))), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }
  return c.json({ ok: true }, 200);
});
