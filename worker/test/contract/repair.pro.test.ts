import { env, SELF, fetchMock } from "cloudflare:test";
import { afterEach, beforeAll, describe, expect, it } from "vitest";
import {
  GROQ_CHAT_PATH,
  GROQ_ORIGIN,
  deviceHashOf,
  groqCompletionBody,
  mintInstallId,
  seedSubscription,
  setProConfig,
  setRepairConfig,
} from "./helpers";

beforeAll(() => {
  fetchMock.activate();
  fetchMock.disableNetConnect();
});

afterEach(() => {
  fetchMock.assertNoPendingInterceptors();
});

const TRANSCRIPT = "I would use a hash map to store each number I have seen and then look up the complement";

function repairNoKey(installId: string) {
  return SELF.fetch("https://worker.test/v1/repair", {
    method: "POST",
    headers: { "X-Install-Id": installId, "content-type": "application/json" },
    body: JSON.stringify({ problem_id: "vp-0001", transcript: TRANSCRIPT }),
  });
}

async function proSpent(): Promise<number> {
  const row = await env.DB.prepare("SELECT COALESCE(SUM(tokens_spent), 0) AS n FROM pro_spend").first<{ n: number }>();
  return row!.n;
}

async function freeSpent(): Promise<number> {
  const row = await env.DB.prepare("SELECT COALESCE(SUM(tokens_spent), 0) AS n FROM provider_day").first<{ n: number }>();
  return row!.n;
}

function mockRepair() {
  fetchMock
    .get(GROQ_ORIGIN)
    .intercept({ path: GROQ_CHAT_PATH, method: "POST" })
    .reply(200, groqCompletionBody(TRANSCRIPT, { prompt_tokens: 40, completion_tokens: 20 }));
}

// Feature 009: the keyless repair call spends the Pro ledger for a Pro device.
describe("POST /v1/repair — no-key branch and the Pro ledger", () => {
  it("a Pro device's repair is charged to pro_spend, not the free pool", async () => {
    await setRepairConfig();
    await setProConfig();
    const installId = await mintInstallId();
    await seedSubscription(deviceHashOf(installId), { status: "active" });
    mockRepair();
    expect((await repairNoKey(installId)).status).toBe(200);
    expect(await proSpent()).toBe(60);
    expect(await freeSpent()).toBe(0);
  });

  it("a free device's repair is charged to the free pool as before", async () => {
    await setRepairConfig();
    await setProConfig();
    const installId = await mintInstallId();
    mockRepair();
    expect((await repairNoKey(installId)).status).toBe(200);
    expect(await proSpent()).toBe(0);
    expect(await freeSpent()).toBe(60);
  });

  it("at Pro capacity a Pro device's repair falls back to the free pool", async () => {
    await setRepairConfig();
    await setProConfig({ daily_token_ceiling: 1 });
    await env.DB.prepare("INSERT INTO pro_spend (date, tokens_spent) VALUES (?1, 5)")
      .bind(new Date().toISOString().slice(0, 10))
      .run();
    const installId = await mintInstallId();
    await seedSubscription(deviceHashOf(installId), { status: "active" });
    mockRepair();
    expect((await repairNoKey(installId)).status).toBe(200);
    expect(await proSpent()).toBe(5);
    expect(await freeSpent()).toBe(60);
  });
});
