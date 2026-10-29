import { fetchMock } from "cloudflare:test";
import { afterEach, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { deriveStatus, getSubscription, resetPayPalTokenCache } from "../../src/lib/paypal";
import { assertNoPendingInterceptors, interceptPayPalGet, interceptPayPalToken } from "../contract/helpers";

const view = (
  status: Parameters<typeof deriveStatus>[0]["status"],
  extra: Partial<Parameters<typeof deriveStatus>[0]> = {},
) => ({ id: "I-TESTSUB0001", status, nextBillingTime: null, failedPaymentsCount: 0, ...extra });

// research.md R-6, row for row.
describe("deriveStatus", () => {
  it("APPROVAL_PENDING → pending", () => {
    expect(deriveStatus(view("APPROVAL_PENDING")).status).toBe("pending");
  });
  it("APPROVED → approved", () => {
    expect(deriveStatus(view("APPROVED")).status).toBe("approved");
  });
  it("ACTIVE → active", () => {
    expect(deriveStatus(view("ACTIVE")).status).toBe("active");
  });
  it("ACTIVE with a failed payment → payment_failed", () => {
    expect(deriveStatus(view("ACTIVE", { failedPaymentsCount: 1 })).status).toBe("payment_failed");
  });
  it("CANCELLED → cancelled", () => {
    expect(deriveStatus(view("CANCELLED")).status).toBe("cancelled");
  });
  it("SUSPENDED → suspended", () => {
    expect(deriveStatus(view("SUSPENDED")).status).toBe("suspended");
  });
  it("EXPIRED → expired", () => {
    expect(deriveStatus(view("EXPIRED")).status).toBe("expired");
  });
  it("periodEnd is next_billing_time, or null", () => {
    expect(deriveStatus(view("ACTIVE", { nextBillingTime: "2026-11-20T10:00:00Z" })).periodEnd).toBe(
      "2026-11-20T10:00:00Z",
    );
    expect(deriveStatus(view("CANCELLED")).periodEnd).toBeNull();
  });
});

describe("getSubscription", () => {
  const env = { PAYPAL_CLIENT_ID: "c", PAYPAL_CLIENT_SECRET: "s", PAYPAL_WEBHOOK_ID: "WH" };

  beforeAll(() => {
    fetchMock.activate();
    fetchMock.disableNetConnect();
  });
  beforeEach(() => {
    resetPayPalTokenCache();
    interceptPayPalToken();
  });
  afterEach(() => {
    assertNoPendingInterceptors();
  });

  it("keeps only the narrow view and drops payer data at parse time", async () => {
    interceptPayPalGet("I-TESTSUB0001", {
      status: "ACTIVE",
      nextBillingTime: "2026-11-20T10:00:00Z",
      subscriberEmail: "buyer@example.test",
    });
    const got = await getSubscription(env, "I-TESTSUB0001");
    expect(got).toEqual({
      id: "I-TESTSUB0001",
      status: "ACTIVE",
      nextBillingTime: "2026-11-20T10:00:00Z",
      failedPaymentsCount: 0,
    });
    expect(JSON.stringify(got)).not.toContain("buyer@example.test");
  });

  it("refuses an id that is not shaped like a subscription id, before any request", async () => {
    await expect(getSubscription(env, "../etc/passwd")).rejects.toMatchObject({ code: "UNCLEAR_RETRY" });
  });

  it("a 404 is UNCLEAR_RETRY", async () => {
    fetchMock
      .get("https://api-m.sandbox.paypal.com")
      .intercept({ path: "/v1/billing/subscriptions/I-TESTSUB0001", method: "GET" })
      .reply(404, { name: "RESOURCE_NOT_FOUND" });
    await expect(getSubscription(env, "I-TESTSUB0001")).rejects.toMatchObject({ code: "UNCLEAR_RETRY" });
  });
});
