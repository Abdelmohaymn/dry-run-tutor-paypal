import { env, SELF, fetchMock } from "cloudflare:test";
import { afterEach, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { resetPayPalTokenCache } from "../../src/lib/paypal";
import {
  assertNoPendingInterceptors,
  clearPaypalCalls,
  deviceHashOf,
  interceptPayPalGet,
  interceptPayPalToken,
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

async function storedStatus(id: string): Promise<string | undefined> {
  const row = await env.DB.prepare("SELECT status FROM pro_subscriptions WHERE subscription_id = ?1")
    .bind(id)
    .first<{ status: string }>();
  return row?.status;
}

const get = (path: string) => SELF.fetch(`https://worker.test${path}`);

describe("GET /paypal/return", () => {
  it("re-reads a known subscription and serves the page with the app link", async () => {
    const installId = await mintInstallId();
    const id = await seedSubscription(deviceHashOf(installId), { id: "I-RETURN00001", status: "pending" });
    interceptPayPalGet(id, { status: "ACTIVE", nextBillingTime: "2099-01-01T00:00:00Z" });

    const res = await get(`/paypal/return?subscription_id=${id}&ba_token=BA-1&token=EC-1`);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("text/html");
    expect(res.headers.get("cache-control")).toBe("no-store");
    const html = await res.text();
    expect(html).toContain("Back to Dry Run");
    expect(html).toContain("You can close this page and return to the app.");
    expect(html).toContain('href="dryruntutor://pro/return"');
    expect(await storedStatus(id)).toBe("active");
  });

  it("still serves the page when PayPal cannot be read", async () => {
    const installId = await mintInstallId();
    const id = await seedSubscription(deviceHashOf(installId), { id: "I-RETURN00002", status: "pending" });
    const res = await get(`/paypal/return?subscription_id=${id}`);
    expect(res.status).toBe(200);
    expect(await storedStatus(id)).toBe("pending");
  });

  it("ignores an id that is not ours, with no PayPal call", async () => {
    const res = await get("/paypal/return?subscription_id=I-NOTOURS0001");
    expect(res.status).toBe(200);
    expect(paypalCalls()).toEqual([]);
  });

  it("ignores a malformed subscription_id", async () => {
    for (const bad of ["../../etc/passwd", "i-lowercase1", "I-", "I-%0d%0aHost:evil"]) {
      const res = await get(`/paypal/return?subscription_id=${bad}`);
      expect(res.status).toBe(200);
    }
    expect(paypalCalls()).toEqual([]);
  });

  it("serves the page with no query at all", async () => {
    expect((await get("/paypal/return")).status).toBe(200);
  });
});

describe("GET /paypal/cancel", () => {
  it("deletes a pending row PayPal still reports as APPROVAL_PENDING", async () => {
    const installId = await mintInstallId();
    const id = await seedSubscription(deviceHashOf(installId), { id: "I-CANCEL00001", status: "pending" });
    interceptPayPalGet(id, { status: "APPROVAL_PENDING" });

    const res = await get(`/paypal/cancel?subscription_id=${id}`);
    expect(res.status).toBe(200);
    const html = await res.text();
    expect(html).toContain("Subscription not completed");
    expect(html).toContain("dryruntutor://pro/return?result=cancel");
    expect(await storedStatus(id)).toBeUndefined();
  });

  it("keeps a row PayPal reports as approved", async () => {
    const installId = await mintInstallId();
    const id = await seedSubscription(deviceHashOf(installId), { id: "I-CANCEL00002", status: "pending" });
    interceptPayPalGet(id, { status: "APPROVED" });
    await get(`/paypal/cancel?subscription_id=${id}`);
    expect(await storedStatus(id)).toBe("approved");
  });

  it("leaves a row that is no longer pending alone, with no PayPal call", async () => {
    const installId = await mintInstallId();
    const id = await seedSubscription(deviceHashOf(installId), { id: "I-CANCEL00003", status: "active" });
    await get(`/paypal/cancel?subscription_id=${id}`);
    expect(await storedStatus(id)).toBe("active");
    expect(paypalCalls()).toEqual([]);
  });

  it("ignores a malformed subscription_id", async () => {
    const res = await get("/paypal/cancel?subscription_id=not-an-id");
    expect(res.status).toBe(200);
    expect(paypalCalls()).toEqual([]);
  });
});
