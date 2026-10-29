import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { proCapacityOk, proLedger } from "../../src/lib/pro-spend";
import { TRIAL_ESTIMATE_CHAT, TRIAL_ESTIMATE_JUDGE } from "../../src/lib/trial-pool";
import { getRuntimeConfig, runtimeConfigSchema, type ProConfig } from "../../src/lib/runtime-config";

const NOW = new Date("2026-10-20T12:00:00Z");
const DATE = "2026-10-20";

const PRO: ProConfig = {
  enabled: true,
  plan_id: "P-1AB23456CD789012E",
  price_label: "$4.99 / month",
  sessions_per_day: 5,
  voice_seconds_per_day: 900,
  daily_token_ceiling: 10_000,
  total_token_ceiling: 30_000,
  recheck_after_seconds: 21600,
  manage_url: "https://www.sandbox.paypal.com/myaccount/autopay/",
};

async function proSpent(date = DATE): Promise<number | null> {
  const row = await env.DB.prepare("SELECT tokens_spent FROM pro_spend WHERE date = ?1")
    .bind(date)
    .first<{ tokens_spent: number }>();
  return row ? row.tokens_spent : null;
}

async function providerDayRows(): Promise<number> {
  const row = await env.DB.prepare("SELECT COUNT(*) AS n FROM provider_day").first<{ n: number }>();
  return row!.n;
}

describe("proLedger", () => {
  it("reserve, settle and release write only pro_spend, never the free pool's rows", async () => {
    const before = await providerDayRows();
    await proLedger.reserve(env.DB, DATE, "groq", TRIAL_ESTIMATE_CHAT);
    expect(await proSpent()).toBe(TRIAL_ESTIMATE_CHAT);
    await proLedger.settle(env.DB, NOW, "groq", "chat", 700);
    expect(await proSpent()).toBe(700);
    await proLedger.reserve(env.DB, DATE, "groq", TRIAL_ESTIMATE_JUDGE);
    await proLedger.release(env.DB, DATE, "groq", TRIAL_ESTIMATE_JUDGE);
    expect(await proSpent()).toBe(700);
    expect(await providerDayRows()).toBe(before);
  });

  it("release never goes below zero", async () => {
    await proLedger.reserve(env.DB, DATE, "groq", 100);
    await proLedger.release(env.DB, DATE, "groq", 500);
    expect(await proSpent()).toBe(0);
  });

  it("does not enforce a pool member's own free budget", () => {
    expect(proLedger.enforceMemberBudget).toBe(false);
  });
});

describe("proCapacityOk", () => {
  it("is true on a quiet day", async () => {
    const cfg = await getRuntimeConfig(env.DB);
    expect(await proCapacityOk(PRO, cfg, env.DB, NOW)).toBe(true);
  });

  it("is false at the daily ceiling, but not once the day has rolled over", async () => {
    const cfg = await getRuntimeConfig(env.DB);
    await env.DB.prepare("INSERT INTO pro_spend (date, tokens_spent) VALUES (?1, ?2)").bind(DATE, 10_000).run();
    expect(await proCapacityOk(PRO, cfg, env.DB, NOW)).toBe(false);
    expect(await proCapacityOk(PRO, cfg, env.DB, new Date("2026-10-21T12:00:00Z"))).toBe(true);
  });

  it("is false at the total ceiling, summed over every day", async () => {
    const cfg = await getRuntimeConfig(env.DB);
    await env.DB.prepare("INSERT INTO pro_spend (date, tokens_spent) VALUES ('2026-10-18', 15000), ('2026-10-19', 15000)").run();
    expect(await proCapacityOk(PRO, cfg, env.DB, NOW)).toBe(false);
  });

  it("is false when no pool member is eligible (all cooling down)", async () => {
    const cfg = await getRuntimeConfig(env.DB);
    const until = new Date(NOW.getTime() + 60_000).toISOString();
    for (const m of cfg.trial.pool) {
      await env.DB.prepare(
        "INSERT INTO provider_day (date, provider_id, tokens_spent, cooldown_until) VALUES (?1, ?2, 0, ?3)",
      )
        .bind(DATE, m.id, until)
        .run();
    }
    expect(await proCapacityOk(PRO, cfg, env.DB, NOW)).toBe(false);
  });

  it("ignores a member's spent free budget (Pro has its own ledger)", async () => {
    const cfg = await getRuntimeConfig(env.DB);
    for (const m of cfg.trial.pool) {
      await env.DB.prepare("INSERT INTO provider_day (date, provider_id, tokens_spent) VALUES (?1, ?2, ?3)")
        .bind(DATE, m.id, m.daily_token_budget + 1)
        .run();
    }
    expect(await proCapacityOk(PRO, cfg, env.DB, NOW)).toBe(true);
  });

  it("the test config still parses with a pro block (sanity)", async () => {
    const cfg = await getRuntimeConfig(env.DB);
    expect(() => runtimeConfigSchema.parse({ ...cfg, pro: PRO })).not.toThrow();
  });
});
