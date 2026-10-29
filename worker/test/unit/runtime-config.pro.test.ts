import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { getRuntimeConfig, proConfig, runtimeConfigSchema } from "../../src/lib/runtime-config";

const PRO = {
  enabled: true,
  plan_id: "P-1AB23456CD789012E",
  price_label: "$4.99 / month",
  sessions_per_day: 5,
  voice_seconds_per_day: 900,
  daily_token_ceiling: 1875000,
  total_token_ceiling: 37500000,
};

describe("runtime config — the pro block (feature 009)", () => {
  it("parses when absent, and proConfig() is null (Pro off by default)", async () => {
    const cfg = await getRuntimeConfig(env.DB);
    expect(cfg.pro).toBeUndefined();
    expect(proConfig(cfg)).toBeNull();
  });

  it("parses a full block and fills the defaults", async () => {
    const cfg = await getRuntimeConfig(env.DB);
    const parsed = runtimeConfigSchema.parse({ ...cfg, pro: PRO });
    expect(parsed.pro?.recheck_after_seconds).toBe(21600);
    expect(parsed.pro?.manage_url).toBe("https://www.sandbox.paypal.com/myaccount/autopay/");
    expect(proConfig(parsed)).toEqual(parsed.pro);
  });

  it("proConfig() is null when enabled is false", async () => {
    const cfg = await getRuntimeConfig(env.DB);
    const parsed = runtimeConfigSchema.parse({ ...cfg, pro: { ...PRO, enabled: false } });
    expect(proConfig(parsed)).toBeNull();
  });

  it("rejects a manage_url that is not on the sandbox host", async () => {
    const cfg = await getRuntimeConfig(env.DB);
    expect(() =>
      runtimeConfigSchema.parse({ ...cfg, pro: { ...PRO, manage_url: "https://www.paypal.com/myaccount/autopay/" } }),
    ).toThrow();
    expect(() =>
      runtimeConfigSchema.parse({ ...cfg, pro: { ...PRO, manage_url: "https://evil.example/" } }),
    ).toThrow();
  });

  it("rejects an unknown key and a malformed plan id", async () => {
    const cfg = await getRuntimeConfig(env.DB);
    expect(() => runtimeConfigSchema.parse({ ...cfg, pro: { ...PRO, extra: 1 } })).toThrow();
    expect(() => runtimeConfigSchema.parse({ ...cfg, pro: { ...PRO, plan_id: "plan-1" } })).toThrow();
  });
});

describe("runtime config — trial.replay_enabled (FR-027)", () => {
  it("is true when absent, which is today's behaviour", async () => {
    const cfg = await getRuntimeConfig(env.DB);
    expect(cfg.trial.replay_enabled).toBe(true);
  });

  it("parses false", async () => {
    const cfg = await getRuntimeConfig(env.DB);
    const parsed = runtimeConfigSchema.parse({ ...cfg, trial: { ...cfg.trial, replay_enabled: false } });
    expect(parsed.trial.replay_enabled).toBe(false);
  });
});
