// PayPal Subscriptions client (feature 009). SANDBOX ONLY: the API base is a
// constant, never config (research.md R-10), and paypal-sandbox-only.test.ts
// fails the build if a live PayPal host appears anywhere in this source.
//
// Plain fetch, no SDK. No response body, PayPal error body or request body is
// ever logged or put in an error (FR-023): every failure is UNCLEAR_RETRY.
import { z } from "zod";
import { AppError } from "./errors";

export const PAYPAL_API_BASE = "https://api-m.sandbox.paypal.com";
export const PAYPAL_APPROVE_HOST = "www.sandbox.paypal.com";

export interface PayPalEnv {
  PAYPAL_CLIENT_ID: string;
  PAYPAL_CLIENT_SECRET: string;
  PAYPAL_WEBHOOK_ID: string;
}

export type StoredStatus =
  | "pending"
  | "approved"
  | "active"
  | "payment_failed"
  | "cancelled"
  | "suspended"
  | "expired";

/** The ONLY fields ever read from a PayPal subscription. Everything else (subscriber name, email, address…) is dropped at parse time. */
export interface PayPalSubscriptionView {
  id: string;
  status: "APPROVAL_PENDING" | "APPROVED" | "ACTIVE" | "SUSPENDED" | "CANCELLED" | "EXPIRED";
  nextBillingTime: string | null;
  failedPaymentsCount: number;
}

const TIMEOUT_MS = 10_000;
const SUBSCRIPTION_ID = /^I-[A-Z0-9]{6,40}$/;

/** True for an id that is safe to put in a PayPal URL or a SQL key. */
export function isSubscriptionId(id: string): boolean {
  return SUBSCRIPTION_ID.test(id);
}

// Not .strict(): unknown keys are dropped, which is how payer data is discarded.
const subscriptionSchema = z.object({
  id: z.string(),
  status: z.enum(["APPROVAL_PENDING", "APPROVED", "ACTIVE", "SUSPENDED", "CANCELLED", "EXPIRED"]),
  billing_info: z
    .object({
      next_billing_time: z.string().optional(),
      failed_payments_count: z.number().int().optional(),
    })
    .optional(),
});

const tokenSchema = z.object({ access_token: z.string().min(1), expires_in: z.number() });

const createSchema = z.object({
  id: z.string(),
  links: z.array(z.object({ rel: z.string(), href: z.string() })),
});

let cachedToken: { token: string; expiresAtMs: number } | null = null;

/** Tests only. */
export function resetPayPalTokenCache(): void {
  cachedToken = null;
}

async function paypalFetch(url: string, init: RequestInit): Promise<Response> {
  try {
    return await fetch(url, { ...init, signal: AbortSignal.timeout(TIMEOUT_MS) });
  } catch {
    throw new AppError("UNCLEAR_RETRY");
  }
}

async function readJson<T>(res: Response, schema: z.ZodType<T>): Promise<T> {
  let raw: unknown;
  try {
    raw = await res.json();
  } catch {
    throw new AppError("UNCLEAR_RETRY");
  }
  const parsed = schema.safeParse(raw);
  if (!parsed.success) throw new AppError("UNCLEAR_RETRY");
  return parsed.data;
}

export async function getAccessToken(env: PayPalEnv): Promise<string> {
  if (cachedToken && cachedToken.expiresAtMs > Date.now()) return cachedToken.token;
  const res = await paypalFetch(`${PAYPAL_API_BASE}/v1/oauth2/token`, {
    method: "POST",
    headers: {
      authorization: `Basic ${btoa(`${env.PAYPAL_CLIENT_ID}:${env.PAYPAL_CLIENT_SECRET}`)}`,
      "content-type": "application/x-www-form-urlencoded",
    },
    body: "grant_type=client_credentials",
  });
  if (!res.ok) throw new AppError("UNCLEAR_RETRY");
  const { access_token, expires_in } = await readJson(res, tokenSchema);
  cachedToken = { token: access_token, expiresAtMs: Date.now() + Math.max(expires_in - 60, 0) * 1000 };
  return access_token;
}

export async function createSubscription(
  env: PayPalEnv,
  planId: string,
  returnUrl: string,
  cancelUrl: string,
): Promise<{ id: string; approveUrl: string }> {
  const token = await getAccessToken(env);
  // No `subscriber` and no `custom_id`: nothing about the learner or the device
  // goes to PayPal (research.md R-8). `application_context` is deprecated in
  // PayPal's schema but has no replacement for wallet subscriptions (R-9).
  const res = await paypalFetch(`${PAYPAL_API_BASE}/v1/billing/subscriptions`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
      "paypal-request-id": crypto.randomUUID(),
      prefer: "return=minimal",
    },
    body: JSON.stringify({
      plan_id: planId,
      application_context: {
        brand_name: "Dry Run",
        shipping_preference: "NO_SHIPPING",
        user_action: "SUBSCRIBE_NOW",
        return_url: returnUrl,
        cancel_url: cancelUrl,
      },
    }),
  });
  if (!res.ok) throw new AppError("UNCLEAR_RETRY");
  const created = await readJson(res, createSchema);
  if (!isSubscriptionId(created.id)) throw new AppError("UNCLEAR_RETRY");
  const href = created.links.find((l) => l.rel === "approve")?.href;
  if (!href) throw new AppError("UNCLEAR_RETRY");
  let host: string;
  try {
    host = new URL(href).host;
  } catch {
    throw new AppError("UNCLEAR_RETRY");
  }
  if (host !== PAYPAL_APPROVE_HOST) throw new AppError("UNCLEAR_RETRY");
  return { id: created.id, approveUrl: href };
}

export async function getSubscription(env: PayPalEnv, id: string): Promise<PayPalSubscriptionView> {
  if (!isSubscriptionId(id)) throw new AppError("UNCLEAR_RETRY");
  const token = await getAccessToken(env);
  const res = await paypalFetch(`${PAYPAL_API_BASE}/v1/billing/subscriptions/${id}`, {
    method: "GET",
    headers: { authorization: `Bearer ${token}` },
  });
  // A 404 (or any non-2xx) throws, so the stored row stays unchanged.
  if (!res.ok) throw new AppError("UNCLEAR_RETRY");
  const sub = await readJson(res, subscriptionSchema);
  return {
    id: sub.id,
    status: sub.status,
    nextBillingTime: sub.billing_info?.next_billing_time ?? null,
    failedPaymentsCount: sub.billing_info?.failed_payments_count ?? 0,
  };
}

const WEBHOOK_HEADERS = [
  ["auth_algo", "paypal-auth-algo"],
  ["cert_url", "paypal-cert-url"],
  ["transmission_id", "paypal-transmission-id"],
  ["transmission_sig", "paypal-transmission-sig"],
  ["transmission_time", "paypal-transmission-time"],
] as const;

/**
 * Asks PayPal to verify a webhook's signature. The raw event text is spliced
 * into the request unchanged (research.md R-7): re-serialising a parsed event
 * changes key order or number formatting, and the signature then fails.
 * Returns true only on HTTP 200 with `verification_status === "SUCCESS"`.
 * Never throws.
 */
export async function verifyWebhook(env: PayPalEnv, headers: Headers, rawBody: string): Promise<boolean> {
  try {
    const parts: string[] = [];
    for (const [field, header] of WEBHOOK_HEADERS) {
      const value = headers.get(header);
      if (!value) return false;
      parts.push(`${JSON.stringify(field)}:${JSON.stringify(value)}`);
    }
    parts.push(`"webhook_id":${JSON.stringify(env.PAYPAL_WEBHOOK_ID)}`);
    parts.push(`"webhook_event":${rawBody}`);
    const token = await getAccessToken(env);
    const res = await paypalFetch(`${PAYPAL_API_BASE}/v1/notifications/verify-webhook-signature`, {
      method: "POST",
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: `{${parts.join(",")}}`,
    });
    if (res.status !== 200) return false;
    const body = (await res.json()) as { verification_status?: unknown };
    return body.verification_status === "SUCCESS";
  } catch {
    return false;
  }
}

/**
 * research.md R-6, exactly. `periodEnd` is `nextBillingTime` or null; the
 * caller COALESCEs it with the stored value, because PayPal drops
 * next_billing_time once a subscription is cancelled.
 */
export function deriveStatus(view: PayPalSubscriptionView): { status: StoredStatus; periodEnd: string | null } {
  const periodEnd = view.nextBillingTime;
  switch (view.status) {
    case "APPROVAL_PENDING":
      return { status: "pending", periodEnd };
    case "APPROVED":
      return { status: "approved", periodEnd };
    case "ACTIVE":
      return { status: view.failedPaymentsCount > 0 ? "payment_failed" : "active", periodEnd };
    case "CANCELLED":
      return { status: "cancelled", periodEnd };
    case "SUSPENDED":
      return { status: "suspended", periodEnd };
    case "EXPIRED":
      return { status: "expired", periodEnd };
  }
}
