import { env, SELF, fetchMock } from "cloudflare:test";
import { afterEach, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { resetPayPalTokenCache } from "../../src/lib/paypal";
import {
  PAYPAL_ORIGIN,
  PRO_PLAN_ID,
  assertNoPendingInterceptors,
  clearPaypalCalls,
  deviceHashOf,
  interceptPayPalCreate,
  interceptPayPalToken,
  mintInstallId,
  paypalCalls,
  seedSubscription,
  setProConfig,
} from "./helpers";

beforeAll(() => {
  fetchMock.activate();
  fetchMock.disableNetConnect();
  interceptPayPalToken();
});

beforeEach(() => {
  resetPayPalTokenCache();
  clearPaypalCalls();
});

afterEach(() => {
  assertNoPendingInterceptors();
});

function checkout(installId: string | null) {
  return SELF.fetch("https://worker.test/v1/pro/checkout", {
    method: "POST",
    headers: { ...(installId ? { "X-Install-Id": installId } : {}), "content-type": "application/json" },
    body: "{}",
  });
}

async function rowsFor(installId: string) {
  const { results } = await env.DB.prepare("SELECT * FROM pro_subscriptions WHERE device_hash = ?1")
    .bind(deviceHashOf(installId))
    .all<Record<string, unknown>>();
  return results;
}

async function errorCode(res: Response): Promise<string> {
  return ((await res.json()) as any).error.code;
}

describe("POST /v1/pro/checkout", () => {
  it("is BAD_REQUEST while Pro is off (absent block)", async () => {
    const installId = await mintInstallId();
    const res = await checkout(installId);
    expect(res.status).toBe(400);
    expect(await errorCode(res)).toBe("BAD_REQUEST");
    expect(paypalCalls()).toEqual([]);
  });

  it("is BAD_REQUEST while Pro is switched off", async () => {
    await setProConfig({ enabled: false });
    const installId = await mintInstallId();
    expect(await errorCode(await checkout(installId))).toBe("BAD_REQUEST");
  });

  it("needs an install id", async () => {
    await setProConfig();
    expect((await checkout(null)).status).toBe(400);
  });

  it("returns the approve link and a pending row bound to this device", async () => {
    await setProConfig();
    const installId = await mintInstallId();
    let created: any;
    fetchMock
      .get(PAYPAL_ORIGIN)
      .intercept({ path: "/v1/billing/subscriptions", method: "POST" })
      .reply(201, (opts) => {
        created = JSON.parse(opts.body as string);
        return {
          id: "I-NEWSUB00001",
          status: "APPROVAL_PENDING",
          links: [{ rel: "approve", href: "https://www.sandbox.paypal.com/webapps/billing/subscriptions?ba_token=BA-1" }],
        };
      });

    const res = await checkout(installId);
    expect(res.status).toBe(200);
    expect(res.headers.get("cache-control")).toBe("private, no-store");
    expect(await res.json()).toEqual({
      approve_url: "https://www.sandbox.paypal.com/webapps/billing/subscriptions?ba_token=BA-1",
    });

    const rows = await rowsFor(installId);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ subscription_id: "I-NEWSUB00001", status: "pending", period_end: null });

    // What PayPal is sent: the plan and our own pages, and nothing about the learner or the device.
    expect(created.plan_id).toBe(PRO_PLAN_ID);
    expect(created.application_context.return_url).toBe("https://worker.test/paypal/return");
    expect(created.application_context.cancel_url).toBe("https://worker.test/paypal/cancel");
    expect(created).not.toHaveProperty("subscriber");
    expect(created).not.toHaveProperty("custom_id");
    expect(JSON.stringify(created)).not.toContain(deviceHashOf(installId));
  });

  it("an entitled device gets already_active and no PayPal call", async () => {
    await setProConfig();
    const installId = await mintInstallId();
    await seedSubscription(deviceHashOf(installId), { status: "active" });
    const res = await checkout(installId);
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ already_active: true });
    expect(paypalCalls()).toEqual([]);
    expect(await rowsFor(installId)).toHaveLength(1);
  });

  it("a PayPal failure is UNCLEAR_RETRY and writes no row", async () => {
    await setProConfig();
    const installId = await mintInstallId();
    fetchMock
      .get(PAYPAL_ORIGIN)
      .intercept({ path: "/v1/billing/subscriptions", method: "POST" })
      .reply(500, { name: "INTERNAL_SERVER_ERROR", details: "secret upstream detail" });
    const res = await checkout(installId);
    expect(res.status).toBe(502);
    const text = await res.text();
    expect(JSON.parse(text).error.code).toBe("UNCLEAR_RETRY");
    expect(text).not.toContain("secret upstream detail");
    expect(await rowsFor(installId)).toHaveLength(0);
  });

  it("an approve link that is not on the sandbox host is UNCLEAR_RETRY and writes no row", async () => {
    await setProConfig();
    const installId = await mintInstallId();
    interceptPayPalCreate("I-NEWSUB00002", "https://evil.example/approve");
    expect(await errorCode(await checkout(installId))).toBe("UNCLEAR_RETRY");
    expect(await rowsFor(installId)).toHaveLength(0);
  });

  it("a response with no approve link is UNCLEAR_RETRY", async () => {
    await setProConfig();
    const installId = await mintInstallId();
    fetchMock
      .get(PAYPAL_ORIGIN)
      .intercept({ path: "/v1/billing/subscriptions", method: "POST" })
      .reply(201, { id: "I-NEWSUB00003", status: "APPROVAL_PENDING", links: [] });
    expect(await errorCode(await checkout(installId))).toBe("UNCLEAR_RETRY");
    expect(await rowsFor(installId)).toHaveLength(0);
  });

  it("sweeps this device's pending rows older than three hours, and keeps newer ones", async () => {
    await setProConfig();
    const installId = await mintInstallId();
    const hash = deviceHashOf(installId);
    const old = new Date(Date.now() - 4 * 3600_000).toISOString();
    await seedSubscription(hash, { id: "I-OLDPENDING1", status: "pending", confirmedAt: old });
    await seedSubscription(hash, { id: "I-NEWPENDING1", status: "pending" });
    interceptPayPalCreate("I-NEWSUB00004");
    expect((await checkout(installId)).status).toBe(200);
    const ids = (await rowsFor(installId)).map((r) => r.subscription_id).sort();
    expect(ids).toEqual(["I-NEWPENDING1", "I-NEWSUB00004"]);
  });

  it("is RATE_LIMITED when the per-device limiter says so", async () => {
    await setProConfig();
    const installId = await mintInstallId();
    const original = env.PRO_RL.limit;
    env.PRO_RL.limit = async () => ({ success: false });
    try {
      const res = await checkout(installId);
      expect(res.status).toBe(429);
      expect(await errorCode(res)).toBe("RATE_LIMITED");
    } finally {
      env.PRO_RL.limit = original;
    }
  });
});
