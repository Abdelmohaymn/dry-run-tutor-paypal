import { env, SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { runtimeConfigSchema } from "../../src/lib/runtime-config";

async function putPro(pro: unknown): Promise<void> {
  const row = await env.DB.prepare("SELECT payload FROM config WHERE id = 1").first<{
    payload: string;
  }>();
  const cfg = JSON.parse(row!.payload);
  if (pro === undefined) delete cfg.pro;
  else cfg.pro = pro;
  await env.DB.prepare("UPDATE config SET payload = ? WHERE id = 1")
    .bind(JSON.stringify(cfg))
    .run();
}

async function served(): Promise<Record<string, any>> {
  return (await (await SELF.fetch("https://worker.test/v1/config")).json()) as Record<string, any>;
}

const GOOD = {
  enabled: true,
  plan_id: "P-1AB23456CD789012E",
  price_label: "$4.99 / month",
  sessions_per_day: 5,
  voice_seconds_per_day: 900,
  daily_token_ceiling: 1875000,
  total_token_ceiling: 37500000,
  recheck_after_seconds: 60,
};

// Feature 009. `pro` is optional and the server-only fields never leave the Worker.
describe("GET /v1/config — the pro block", () => {
  it("serves only the app-facing fields", async () => {
    await putPro(GOOD);
    const body = await served();
    expect(body.pro).toEqual({
      enabled: true,
      price_label: "$4.99 / month",
      sessions_per_day: 5,
      voice_seconds_per_day: 900,
      manage_url: "https://www.sandbox.paypal.com/myaccount/autopay/",
    });
    for (const k of ["plan_id", "daily_token_ceiling", "total_token_ceiling", "recheck_after_seconds"]) {
      expect(body.pro).not.toHaveProperty(k);
    }
    await putPro(undefined);
  });

  it("leaves pro absent when the config has none", async () => {
    await putPro(undefined);
    const body = await served();
    expect(body).not.toHaveProperty("pro");
    expect(() => runtimeConfigSchema.parse(body)).not.toThrow();
  });

  it("refuses a malformed pro block rather than serving it", async () => {
    await putPro({ ...GOOD, manage_url: "https://www.paypal.com/x" });
    expect((await SELF.fetch("https://worker.test/v1/config")).status).toBe(502);
    await putPro(undefined);
  });

  it("serves trial.replay_enabled when the config sets it", async () => {
    const row = await env.DB.prepare("SELECT payload FROM config WHERE id = 1").first<{ payload: string }>();
    const cfg = JSON.parse(row!.payload);
    cfg.trial.replay_enabled = false;
    await env.DB.prepare("UPDATE config SET payload = ? WHERE id = 1").bind(JSON.stringify(cfg)).run();
    expect((await served()).trial.replay_enabled).toBe(false);
    delete cfg.trial.replay_enabled;
    await env.DB.prepare("UPDATE config SET payload = ? WHERE id = 1").bind(JSON.stringify(cfg)).run();
  });
});
