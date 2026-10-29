import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { currentSubscription, isEntitled } from "../../src/lib/pro";

const NOW = new Date("2026-10-20T12:00:00Z");
const FUTURE = "2026-11-20T10:00:00Z";
const PAST = "2026-10-01T10:00:00Z";

describe("isEntitled", () => {
  it("active is entitled", () => {
    expect(isEntitled({ status: "active", period_end: null }, NOW)).toBe(true);
  });
  it("cancelled is entitled only while period_end is in the future", () => {
    expect(isEntitled({ status: "cancelled", period_end: FUTURE }, NOW)).toBe(true);
    expect(isEntitled({ status: "cancelled", period_end: PAST }, NOW)).toBe(false);
    expect(isEntitled({ status: "cancelled", period_end: null }, NOW)).toBe(false);
  });
  it.each(["suspended", "expired", "payment_failed", "pending", "approved"])("%s is not entitled", (status) => {
    expect(isEntitled({ status, period_end: FUTURE }, NOW)).toBe(false);
  });
});

describe("currentSubscription", () => {
  const device = "a".repeat(64);
  async function put(id: string, status: string, confirmedAt: string, periodEnd: string | null = null) {
    await env.DB.prepare(
      "INSERT INTO pro_subscriptions (subscription_id, device_hash, status, period_end, confirmed_at) VALUES (?1, ?2, ?3, ?4, ?5)",
    )
      .bind(id, device, status, periodEnd, confirmedAt)
      .run();
  }

  it("is null for a device with no rows", async () => {
    expect(await currentSubscription(env.DB, device, NOW)).toBeNull();
  });

  it("prefers an entitled row over a newer non-entitled one", async () => {
    await put("I-ENTITLED01", "active", "2026-10-01T00:00:00Z");
    await put("I-NEWERPEND1", "pending", "2026-10-20T00:00:00Z");
    expect((await currentSubscription(env.DB, device, NOW))?.subscription_id).toBe("I-ENTITLED01");
  });

  it("falls back to the row with the latest confirmed_at", async () => {
    await put("I-OLDSUSPEN1", "suspended", "2026-10-01T00:00:00Z");
    await put("I-NEWEREXPI1", "expired", "2026-10-10T00:00:00Z");
    expect((await currentSubscription(env.DB, device, NOW))?.subscription_id).toBe("I-NEWEREXPI1");
  });
});
