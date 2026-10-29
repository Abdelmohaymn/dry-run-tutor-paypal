import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import {
  claimProSession,
  proSessionState,
  proSessionsToday,
  releaseProSession,
  resetProSession,
} from "../../src/lib/pro-session";

const DEVICE = "b".repeat(64);
const DAY = "2026-10-20";
const NOW = "2026-10-20T12:00:00Z";
const CAP = 2;

const claim = (problem: string, date = DAY, cap = CAP) =>
  claimProSession(env.DB, DEVICE, problem, date, cap, NOW);

describe("claimProSession", () => {
  it("claims the first session on a device with no row", async () => {
    expect(await claim("vp-0001")).toBe("claimed");
    expect(await proSessionsToday(env.DB, DEVICE, DAY)).toBe(1);
  });

  it("the same problem on the same day is in_flight and the count is unchanged", async () => {
    await claim("vp-0001");
    expect(await claim("vp-0001")).toBe("in_flight");
    expect(await proSessionsToday(env.DB, DEVICE, DAY)).toBe(1);
  });

  it("a new problem is claimed until the cap, then refused", async () => {
    expect(await claim("vp-0001")).toBe("claimed");
    expect(await claim("vp-0002")).toBe("claimed");
    expect(await claim("vp-0003")).toBe("refused");
    expect(await proSessionsToday(env.DB, DEVICE, DAY)).toBe(2);
  });

  it("a new day resets the count", async () => {
    await claim("vp-0001");
    await claim("vp-0002");
    expect(await claim("vp-0003", "2026-10-21")).toBe("claimed");
    expect(await proSessionsToday(env.DB, DEVICE, "2026-10-21")).toBe(1);
    expect(await proSessionsToday(env.DB, DEVICE, DAY)).toBe(0);
  });

  it("works on an existing device row that has never had a Pro session", async () => {
    await env.DB.prepare("INSERT INTO devices (device_hash, created_at) VALUES (?1, ?2)").bind(DEVICE, NOW).run();
    expect(await claim("vp-0001")).toBe("claimed");
  });
});

describe("proSessionState", () => {
  it("available → in_flight → sessions_used", async () => {
    expect(await proSessionState(env.DB, DEVICE, "vp-0001", DAY, 1)).toBe("available");
    await claim("vp-0001", DAY, 1);
    expect(await proSessionState(env.DB, DEVICE, "vp-0001", DAY, 1)).toBe("in_flight");
    expect(await proSessionState(env.DB, DEVICE, "vp-0002", DAY, 1)).toBe("sessions_used");
    expect(await proSessionState(env.DB, DEVICE, "vp-0002", "2026-10-21", 1)).toBe("available");
  });
});

describe("releaseProSession / resetProSession", () => {
  it("release refunds the count and frees the slot", async () => {
    await claim("vp-0001");
    await releaseProSession(env.DB, DEVICE, "vp-0001", DAY);
    expect(await proSessionsToday(env.DB, DEVICE, DAY)).toBe(0);
    expect(await proSessionState(env.DB, DEVICE, "vp-0001", DAY, CAP)).toBe("available");
  });

  it("release never takes the count below zero or touches another session", async () => {
    await claim("vp-0001");
    await releaseProSession(env.DB, DEVICE, "vp-0009", DAY);
    expect(await proSessionsToday(env.DB, DEVICE, DAY)).toBe(1);
    await releaseProSession(env.DB, DEVICE, "vp-0001", DAY);
    await releaseProSession(env.DB, DEVICE, "vp-0001", DAY);
    expect(await proSessionsToday(env.DB, DEVICE, DAY)).toBe(0);
  });

  it("reset frees the slot but keeps the count, so a replay is a new Pro session", async () => {
    await claim("vp-0001");
    await resetProSession(env.DB, DEVICE, "vp-0001", DAY);
    expect(await proSessionsToday(env.DB, DEVICE, DAY)).toBe(1);
    expect(await claim("vp-0001")).toBe("claimed");
    expect(await proSessionsToday(env.DB, DEVICE, DAY)).toBe(2);
  });
});
