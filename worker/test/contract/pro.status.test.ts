import { env, SELF, fetchMock } from "cloudflare:test";
import { afterEach, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { resetPayPalTokenCache } from "../../src/lib/paypal";
import {
  assertNoPendingInterceptors,
  clearPaypalCalls,
  deviceHashOf,
  interceptPayPalGet,
  interceptPayPalGetFailure,
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

async function status(installId: string | null): Promise<{ res: Response; body: any }> {
  const res = await SELF.fetch("https://worker.test/v1/pro/status", {
    headers: installId ? { "X-Install-Id": installId } : {},
  });
  return { res, body: res.status === 200 ? await res.json() : null };
}

async function storedStatus(id: string): Promise<string | undefined> {
  const row = await env.DB.prepare("SELECT status FROM pro_subscriptions WHERE subscription_id = ?1")
    .bind(id)
    .first<{ status: string }>();
  return row?.status;
}

const hoursAgo = (h: number) => new Date(Date.now() - h * 3600_000).toISOString();
const FUTURE = "2099-01-01T00:00:00Z";

describe("GET /v1/pro/status", () => {
  it("needs an install id", async () => {
    expect((await status(null)).res.status).toBe(400);
  });

  it("a free device: lifetime usage, no subscription, no pro_limit", async () => {
    const installId = await mintInstallId();
    const { res, body } = await status(installId);
    expect(res.status).toBe(200);
    expect(res.headers.get("cache-control")).toBe("private, no-store");
    expect(body).toMatchObject({
      offer_enabled: false,
      plan: "free",
      subscription: null,
      pro_limit: null,
      usage: { sessions_used: 0, sessions_period: "lifetime", voice_seconds_used: 0 },
    });
    expect(typeof body.usage.sessions_limit).toBe("number");
    expect(Number.isNaN(Date.parse(body.as_of))).toBe(false);
  });

  it("offer_enabled follows the pro block", async () => {
    await setProConfig();
    const installId = await mintInstallId();
    expect((await status(installId)).body.offer_enabled).toBe(true);
    await setProConfig({ enabled: false });
    expect((await status(installId)).body.offer_enabled).toBe(false);
  });

  it("an entitled device is plan pro with Pro usage", async () => {
    await setProConfig({ sessions_per_day: 4, voice_seconds_per_day: 600 });
    const installId = await mintInstallId();
    await seedSubscription(deviceHashOf(installId), { status: "active", periodEnd: FUTURE });
    const { body } = await status(installId);
    expect(body.plan).toBe("pro");
    expect(body.pro_limit).toBe("ok");
    expect(body.subscription).toMatchObject({ status: "active", period_end: FUTURE });
    expect(body.usage).toMatchObject({
      sessions_used: 0,
      sessions_limit: 4,
      sessions_period: "day",
      voice_seconds_limit: 600,
    });
  });

  it("a pending row is rechecked with PayPal and becomes active", async () => {
    await setProConfig();
    const installId = await mintInstallId();
    const id = await seedSubscription(deviceHashOf(installId), { id: "I-PENDING0001", status: "pending" });
    interceptPayPalGet(id, { status: "ACTIVE", nextBillingTime: FUTURE });
    const { body } = await status(installId);
    expect(body.plan).toBe("pro");
    expect(body.subscription.status).toBe("active");
    expect(await storedStatus(id)).toBe("active");
  });

  it("an approved row is rechecked too", async () => {
    await setProConfig();
    const installId = await mintInstallId();
    const id = await seedSubscription(deviceHashOf(installId), { id: "I-APPROVED001", status: "approved" });
    interceptPayPalGet(id, { status: "ACTIVE", nextBillingTime: FUTURE });
    expect((await status(installId)).body.plan).toBe("pro");
  });

  it("a fresh active row is NOT rechecked", async () => {
    await setProConfig();
    const installId = await mintInstallId();
    const id = await seedSubscription(deviceHashOf(installId), { id: "I-FRESHACT001", status: "active" });
    // If the Worker asked, PayPal would say SUSPENDED and the plan would change.
    interceptPayPalGet(id, { status: "SUSPENDED" }, { persist: true });
    const { body } = await status(installId);
    expect(body.plan).toBe("pro");
    expect(paypalCalls().filter((c) => c.startsWith("GET"))).toEqual([]);
    expect(await storedStatus(id)).toBe("active");
  });

  it("a stale active row is rechecked after recheck_after_seconds", async () => {
    await setProConfig({ recheck_after_seconds: 3600 });
    const installId = await mintInstallId();
    const id = await seedSubscription(deviceHashOf(installId), {
      id: "I-STALEACT001",
      status: "active",
      confirmedAt: hoursAgo(2),
    });
    interceptPayPalGet(id, { status: "SUSPENDED" });
    const { body } = await status(installId);
    expect(body.plan).toBe("free");
    expect(body.subscription.status).toBe("suspended");
    expect(await storedStatus(id)).toBe("suspended");
  });

  it("a PayPal failure serves the stored row as it is", async () => {
    await setProConfig({ recheck_after_seconds: 3600 });
    const installId = await mintInstallId();
    const stale = hoursAgo(2);
    const id = await seedSubscription(deviceHashOf(installId), {
      id: "I-STALEACT002",
      status: "active",
      confirmedAt: stale,
    });
    interceptPayPalGetFailure(id);
    const { res, body } = await status(installId);
    expect(res.status).toBe(200);
    expect(body.plan).toBe("pro");
    expect(body.subscription.confirmed_at).toBe(stale);
  });

  it("pro_limit is sessions_used once today's Pro sessions are spent", async () => {
    await setProConfig({ sessions_per_day: 2 });
    const installId = await mintInstallId();
    const hash = deviceHashOf(installId);
    await seedSubscription(hash, { status: "active" });
    await env.DB.prepare("UPDATE devices SET pro_day_date = ?2, pro_day_sessions = 2 WHERE device_hash = ?1")
      .bind(hash, new Date().toISOString().slice(0, 10))
      .run();
    const { body } = await status(installId);
    expect(body.plan).toBe("pro");
    expect(body.pro_limit).toBe("sessions_used");
    expect(body.usage.sessions_used).toBe(2);
  });

  it("yesterday's Pro sessions do not count today", async () => {
    await setProConfig({ sessions_per_day: 2 });
    const installId = await mintInstallId();
    const hash = deviceHashOf(installId);
    await seedSubscription(hash, { status: "active" });
    await env.DB.prepare("UPDATE devices SET pro_day_date = '2020-01-01', pro_day_sessions = 2 WHERE device_hash = ?1")
      .bind(hash)
      .run();
    const { body } = await status(installId);
    expect(body.pro_limit).toBe("ok");
    expect(body.usage.sessions_used).toBe(0);
  });

  it("pro_limit is capacity at a spend ceiling, and plan stays pro", async () => {
    await setProConfig({ daily_token_ceiling: 1000 });
    const installId = await mintInstallId();
    await seedSubscription(deviceHashOf(installId), { status: "active" });
    await env.DB.prepare("INSERT INTO pro_spend (date, tokens_spent) VALUES (?1, 1000)")
      .bind(new Date().toISOString().slice(0, 10))
      .run();
    const { body } = await status(installId);
    expect(body.plan).toBe("pro");
    expect(body.pro_limit).toBe("capacity");
  });

  it("a cancelled subscription with a future period_end is still Pro; a past one is not", async () => {
    await setProConfig();
    const a = await mintInstallId();
    await seedSubscription(deviceHashOf(a), { id: "I-CANCELLED01", status: "cancelled", periodEnd: FUTURE });
    expect((await status(a)).body.plan).toBe("pro");
    const b = await mintInstallId();
    await seedSubscription(deviceHashOf(b), { id: "I-CANCELLED02", status: "cancelled", periodEnd: "2020-01-01T00:00:00Z" });
    // cancelled is terminal but old: recheck only when stale, which it is not
    expect((await status(b)).body.plan).toBe("free");
  });

  it("FR-005: another device's active subscription does not make this device Pro", async () => {
    await setProConfig();
    const a = await mintInstallId();
    const b = await mintInstallId();
    await seedSubscription(deviceHashOf(a), { status: "active" });
    expect((await status(a)).body.plan).toBe("pro");
    const other = await status(b);
    expect(other.body.plan).toBe("free");
    expect(other.body.subscription).toBeNull();
  });

  it("with Pro switched off an entitled device reports free", async () => {
    await setProConfig({ enabled: false });
    const installId = await mintInstallId();
    await seedSubscription(deviceHashOf(installId), { status: "active" });
    const { body } = await status(installId);
    expect(body.plan).toBe("free");
    expect(body.offer_enabled).toBe(false);
    expect(body.subscription.status).toBe("active");
  });
});
