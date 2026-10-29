import { env, SELF, fetchMock } from "cloudflare:test";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { resetPayPalTokenCache } from "../../src/lib/paypal";
import {
  PAYPAL_ORIGIN,
  assertNoPendingInterceptors,
  clearPaypalCalls,
  deviceHashOf,
  interceptPayPalGet,
  interceptPayPalGetFailure,
  interceptPayPalToken,
  interceptPayPalVerify,
  mintInstallId,
  paypalCalls,
  seedSubscription,
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

const SUB = "I-WEBHOOK0001";
const PAYER_EMAIL = "payer.secret@example.test";
const FUTURE = "2099-01-01T00:00:00Z";

const SIG_HEADERS: Record<string, string> = {
  "PAYPAL-AUTH-ALGO": "SHA256withRSA",
  "PAYPAL-CERT-URL": "https://api.sandbox.paypal.com/v1/notifications/certs/CERT-1",
  "PAYPAL-TRANSMISSION-ID": "tx-0001",
  "PAYPAL-TRANSMISSION-SIG": "c2lnbmF0dXJl",
  "PAYPAL-TRANSMISSION-TIME": "2026-10-20T10:00:00Z",
};

function subscriptionEvent(type: string, id = SUB): string {
  return JSON.stringify({
    id: "WH-EVENT-1",
    event_type: type,
    resource: { id, status: "ACTIVE", subscriber: { email_address: PAYER_EMAIL, name: { given_name: "Test" } } },
  });
}

function saleEvent(agreementId = SUB): string {
  return JSON.stringify({
    id: "WH-EVENT-2",
    event_type: "PAYMENT.SALE.COMPLETED",
    resource: { id: "SALE-1", billing_agreement_id: agreementId, payer_email: PAYER_EMAIL },
  });
}

function post(body: string, headers: Record<string, string> = SIG_HEADERS) {
  return SELF.fetch("https://worker.test/v1/paypal/webhook", {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body,
  });
}

async function storedStatus(id: string): Promise<string | undefined> {
  const row = await env.DB.prepare("SELECT status FROM pro_subscriptions WHERE subscription_id = ?1")
    .bind(id)
    .first<{ status: string }>();
  return row?.status;
}

async function bound(status = "active"): Promise<string> {
  const installId = await mintInstallId();
  return seedSubscription(deviceHashOf(installId), { id: SUB, status });
}

describe("POST /v1/paypal/webhook — verification (SC-004)", () => {
  it("a bad signature is 400 and changes nothing", async () => {
    await bound("active");
    interceptPayPalVerify("FAILURE");
    const res = await post(subscriptionEvent("BILLING.SUBSCRIPTION.SUSPENDED"));
    expect(res.status).toBe(400);
    expect(((await res.json()) as any).error.code).toBe("BAD_REQUEST");
    expect(await storedStatus(SUB)).toBe("active");
    expect(paypalCalls().some((c) => c.startsWith("GET"))).toBe(false);
  });

  it.each(Object.keys(SIG_HEADERS))("a missing %s is 400, with no call to PayPal", async (missing) => {
    await bound("active");
    const headers = { ...SIG_HEADERS };
    delete headers[missing];
    const res = await post(subscriptionEvent("BILLING.SUBSCRIPTION.SUSPENDED"), headers);
    expect(res.status).toBe(400);
    expect(paypalCalls()).toEqual([]);
    expect(await storedStatus(SUB)).toBe("active");
  });

  it("a body that is not JSON is 400", async () => {
    expect((await post("{not json")).status).toBe(400);
    expect(paypalCalls()).toEqual([]);
  });

  it("a body over 64 KiB is 400, with no call to PayPal", async () => {
    const res = await post(JSON.stringify({ event_type: "X", pad: "a".repeat(70_000) }));
    expect(res.status).toBe(400);
    expect(paypalCalls()).toEqual([]);
  });

  it("PayPal unreachable during verification is 400 and changes nothing", async () => {
    await bound("active");
    fetchMock
      .get(PAYPAL_ORIGIN)
      .intercept({ path: "/v1/notifications/verify-webhook-signature", method: "POST" })
      .reply(500, {});
    const res = await post(subscriptionEvent("BILLING.SUBSCRIPTION.SUSPENDED"));
    expect(res.status).toBe(400);
    expect(await storedStatus(SUB)).toBe("active");
  });

  it("splices the raw event into the verification request unchanged, with our webhook id", async () => {
    await bound("active");
    // Deliberately odd spacing and key order: re-serialising would change it.
    const raw = `{ "resource" : {"id":"${SUB}"},   "event_type":"BILLING.SUBSCRIPTION.SUSPENDED" }`;
    let sent = "";
    fetchMock
      .get(PAYPAL_ORIGIN)
      .intercept({ path: "/v1/notifications/verify-webhook-signature", method: "POST" })
      .reply(200, (opts) => {
        sent = opts.body as string;
        return { verification_status: "FAILURE" };
      });
    await post(raw);
    expect(sent).toContain(`"webhook_event":${raw}`);
    expect(sent).toContain('"webhook_id":"WH-TEST"');
    expect(sent).toContain('"transmission_id":"tx-0001"');
    expect(sent).toContain('"auth_algo":"SHA256withRSA"');
    expect(() => JSON.parse(sent)).not.toThrow();
  });
});

describe("POST /v1/paypal/webhook — a signal to re-read, never a state change", () => {
  it("SUSPENDED → re-read → suspended", async () => {
    await bound("active");
    interceptPayPalVerify("SUCCESS");
    interceptPayPalGet(SUB, { status: "SUSPENDED" });
    const res = await post(subscriptionEvent("BILLING.SUBSCRIPTION.SUSPENDED"));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
    expect(await storedStatus(SUB)).toBe("suspended");
  });

  it("the same event twice gives the same result", async () => {
    await bound("active");
    for (let i = 0; i < 2; i++) {
      interceptPayPalVerify("SUCCESS");
      interceptPayPalGet(SUB, { status: "SUSPENDED" });
      expect((await post(subscriptionEvent("BILLING.SUBSCRIPTION.SUSPENDED"))).status).toBe(200);
    }
    expect(await storedStatus(SUB)).toBe("suspended");
  });

  it("FR-008: a late ACTIVATED after a cancel still converges on PayPal's current CANCELLED", async () => {
    await bound("active");
    interceptPayPalVerify("SUCCESS");
    interceptPayPalGet(SUB, { status: "CANCELLED", nextBillingTime: FUTURE });
    expect((await post(subscriptionEvent("BILLING.SUBSCRIPTION.ACTIVATED"))).status).toBe(200);
    expect(await storedStatus(SUB)).toBe("cancelled");
  });

  it("a cancel keeps the stored period_end when PayPal stops sending one", async () => {
    const installId = await mintInstallId();
    await seedSubscription(deviceHashOf(installId), { id: SUB, status: "active", periodEnd: FUTURE });
    interceptPayPalVerify("SUCCESS");
    interceptPayPalGet(SUB, { status: "CANCELLED" });
    await post(subscriptionEvent("BILLING.SUBSCRIPTION.CANCELLED"));
    const row = await env.DB.prepare("SELECT status, period_end FROM pro_subscriptions WHERE subscription_id = ?1")
      .bind(SUB)
      .first<{ status: string; period_end: string }>();
    expect(row).toEqual({ status: "cancelled", period_end: FUTURE });
  });

  it("PAYMENT.SALE.COMPLETED finds the subscription in billing_agreement_id", async () => {
    await bound("payment_failed");
    interceptPayPalVerify("SUCCESS");
    interceptPayPalGet(SUB, { status: "ACTIVE", nextBillingTime: FUTURE });
    expect((await post(saleEvent())).status).toBe(200);
    expect(await storedStatus(SUB)).toBe("active");
  });

  it("a failed payment event leaves the subscription not entitled", async () => {
    await bound("active");
    interceptPayPalVerify("SUCCESS");
    interceptPayPalGet(SUB, { status: "ACTIVE", failedPaymentsCount: 1 });
    await post(subscriptionEvent("BILLING.SUBSCRIPTION.PAYMENT.FAILED"));
    expect(await storedStatus(SUB)).toBe("payment_failed");
  });

  it("an id that is not ours is 200 with no write and no re-read", async () => {
    interceptPayPalVerify("SUCCESS");
    const res = await post(subscriptionEvent("BILLING.SUBSCRIPTION.ACTIVATED", "I-NOTOURS0001"));
    expect(res.status).toBe(200);
    expect(await storedStatus("I-NOTOURS0001")).toBeUndefined();
    expect(paypalCalls().some((c) => c.startsWith("GET"))).toBe(false);
  });

  it("an event type we do not use is 200 with no re-read", async () => {
    await bound("active");
    interceptPayPalVerify("SUCCESS");
    const res = await post(JSON.stringify({ event_type: "CHECKOUT.ORDER.APPROVED", resource: { id: SUB } }));
    expect(res.status).toBe(200);
    expect(paypalCalls().some((c) => c.startsWith("GET"))).toBe(false);
    expect(await storedStatus(SUB)).toBe("active");
  });

  it("a malformed subscription id in the event is ignored", async () => {
    interceptPayPalVerify("SUCCESS");
    const res = await post(subscriptionEvent("BILLING.SUBSCRIPTION.ACTIVATED", "../../x"));
    expect(res.status).toBe(200);
    expect(paypalCalls().some((c) => c.startsWith("GET"))).toBe(false);
  });

  it("PayPal unreadable after a good signature is a 500 envelope, so PayPal redelivers", async () => {
    await bound("active");
    interceptPayPalVerify("SUCCESS");
    interceptPayPalGetFailure(SUB);
    const res = await post(subscriptionEvent("BILLING.SUBSCRIPTION.SUSPENDED"));
    expect(res.status).toBe(500);
    expect(((await res.json()) as any).error.code).toBe("UNCLEAR_RETRY");
    expect(await storedStatus(SUB)).toBe("active");
  });
});

describe("POST /v1/paypal/webhook — payer data is never kept (SC-007, FR-023)", () => {
  it("the event's email is nowhere in D1 afterwards", async () => {
    await bound("active");
    interceptPayPalVerify("SUCCESS");
    // The re-read carries payer data too, as PayPal's does.
    interceptPayPalGet(SUB, { status: "ACTIVE", nextBillingTime: FUTURE, subscriberEmail: PAYER_EMAIL });
    expect((await post(subscriptionEvent("BILLING.SUBSCRIPTION.ACTIVATED"))).status).toBe(200);

    const { results: tables } = await env.DB.prepare(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '_cf_%' AND name != 'd1_migrations'",
    ).all<{ name: string }>();
    expect(tables.length).toBeGreaterThan(3);
    for (const { name } of tables) {
      const { results } = await env.DB.prepare(`SELECT * FROM "${name}"`).all();
      expect(JSON.stringify(results), `table ${name}`).not.toContain(PAYER_EMAIL);
    }
  });

  it("only the five columns are ever stored for a subscription", async () => {
    await bound("active");
    interceptPayPalVerify("SUCCESS");
    interceptPayPalGet(SUB, { status: "ACTIVE", nextBillingTime: FUTURE, subscriberEmail: PAYER_EMAIL });
    await post(subscriptionEvent("BILLING.SUBSCRIPTION.ACTIVATED"));
    const row = await env.DB.prepare("SELECT * FROM pro_subscriptions WHERE subscription_id = ?1").bind(SUB).first();
    expect(Object.keys(row!).sort()).toEqual(["confirmed_at", "device_hash", "period_end", "status", "subscription_id"]);
  });

  it("FR-023: nothing logged contains the raw body, for a valid or an invalid webhook", async () => {
    await bound("active");
    const spies = (["log", "info", "warn", "error"] as const).map((m) => vi.spyOn(console, m).mockImplementation(() => {}));
    try {
      interceptPayPalVerify("SUCCESS");
      interceptPayPalGet(SUB, { status: "SUSPENDED", subscriberEmail: PAYER_EMAIL });
      await post(subscriptionEvent("BILLING.SUBSCRIPTION.SUSPENDED"));

      interceptPayPalVerify("FAILURE");
      await post(subscriptionEvent("BILLING.SUBSCRIPTION.ACTIVATED"));

      for (const spy of spies) {
        for (const call of spy.mock.calls) {
          const text = call.map((a) => (typeof a === "string" ? a : JSON.stringify(a))).join(" ");
          expect(text).not.toContain(PAYER_EMAIL);
          expect(text).not.toContain("WH-EVENT-1");
        }
      }
    } finally {
      spies.forEach((s) => s.mockRestore());
    }
  });
});
