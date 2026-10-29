import { env, SELF, fetchMock } from "cloudflare:test";
import { afterEach, beforeAll, describe, expect, it } from "vitest";
import { getPublicManifest, PRACTICE_COLLECTION } from "../../src/lib/content";
import { pickDaily } from "../../src/lib/daily-pick";
import { getRuntimeConfig } from "../../src/lib/runtime-config";
import {
  GROQ_CHAT_PATH,
  GROQ_ORIGIN,
  deviceHashOf,
  groqStreamBody,
  mintInstallId,
  readChatSSE,
  seedSubscription,
  setProConfig,
  setTrialConfig,
} from "./helpers";

beforeAll(() => {
  fetchMock.activate();
  fetchMock.disableNetConnect();
});

afterEach(() => {
  fetchMock.assertNoPendingInterceptors();
});

const TODAY = () => new Date().toISOString().slice(0, 10);

async function problems(): Promise<{ daily: string; other: string; another: string; practice: string }> {
  const cfg = await getRuntimeConfig(env.DB);
  const manifest = getPublicManifest().problems;
  const daily = pickDaily(manifest, cfg, TODAY())!.id;
  const ordinary = manifest
    .filter((p) => !(p.collections ?? []).includes(PRACTICE_COLLECTION) && p.id !== daily)
    .map((p) => p.id);
  const practice = manifest.find((p) => (p.collections ?? []).includes(PRACTICE_COLLECTION))!.id;
  return { daily, other: ordinary[0], another: ordinary[1], practice };
}

function mockChatReply(text = "Go on.") {
  fetchMock
    .get(GROQ_ORIGIN)
    .intercept({ path: GROQ_CHAT_PATH, method: "POST" })
    .reply(200, groqStreamBody(text), { headers: { "content-type": "text/event-stream" } });
}

function trialChat(installId: string, problemId: string, text = "I would use a hash map.") {
  return SELF.fetch("https://worker.test/v1/trial", {
    method: "POST",
    headers: { "X-Install-Id": installId, "content-type": "application/json" },
    body: JSON.stringify({ mode: "chat", problem_id: problemId, messages: [{ role: "user", text }] }),
  });
}

async function served(installId: string, problemId: string): Promise<void> {
  mockChatReply();
  const res = await trialChat(installId, problemId);
  expect(res.status).toBe(200);
  await readChatSSE(res);
}

async function refused(installId: string, problemId: string): Promise<void> {
  const res = await trialChat(installId, problemId);
  expect(res.status).toBe(409);
  expect(((await res.json()) as any).error.code).toBe("TRIAL_CONSUMED");
}

function reset(installId: string, problemId: string) {
  return SELF.fetch("https://worker.test/v1/session/reset", {
    method: "POST",
    headers: { "X-Install-Id": installId, "content-type": "application/json" },
    body: JSON.stringify({ problem_id: problemId, reason: "practice" }),
  });
}

// FR-026, FR-027. trial.replay_enabled gates the FREE trial path only.
describe("POST /v1/trial — trial.replay_enabled", () => {
  it("lever absent: a second problem is served as today", async () => {
    await setTrialConfig({ sessions_per_device: 3 });
    const p = await problems();
    const installId = await mintInstallId();
    await served(installId, p.other);
    await served(installId, p.another);
  });

  it("lever true is the same as absent", async () => {
    await setTrialConfig({ sessions_per_device: 3, replay_enabled: true });
    const p = await problems();
    const installId = await mintInstallId();
    await served(installId, p.other);
    await served(installId, p.daily);
  });

  it("false: a problem that is not today's is TRIAL_CONSUMED, and nothing is claimed", async () => {
    await setTrialConfig({ sessions_per_device: 3, replay_enabled: false });
    const p = await problems();
    const installId = await mintInstallId();
    await refused(installId, p.other);
    const row = await env.DB.prepare("SELECT trial_problem_id FROM devices WHERE device_hash = ?1")
      .bind(deviceHashOf(installId))
      .first<{ trial_problem_id: string | null }>();
    expect(row!.trial_problem_id).toBeNull();
  });

  it("false: today's problem is served", async () => {
    await setTrialConfig({ sessions_per_device: 3, replay_enabled: false });
    const p = await problems();
    const installId = await mintInstallId();
    await served(installId, p.daily);
  });

  it("false: the session in flight carries on, turn after turn", async () => {
    await setTrialConfig({ sessions_per_device: 3, replay_enabled: false });
    const p = await problems();
    const installId = await mintInstallId();
    await served(installId, p.daily);
    await served(installId, p.daily);
  });

  it("false + a reset today: that problem is TRIAL_CONSUMED", async () => {
    await setTrialConfig({ sessions_per_device: 3, replay_enabled: false });
    const p = await problems();
    const installId = await mintInstallId();
    await served(installId, p.daily);
    expect((await reset(installId, p.daily)).status).toBe(200);
    await refused(installId, p.daily);
  });

  it("false + a reset recorded yesterday: today's problem is served", async () => {
    await setTrialConfig({ sessions_per_device: 3, replay_enabled: false });
    const p = await problems();
    const installId = await mintInstallId();
    await env.DB.prepare("UPDATE devices SET replay_reset_date = '2020-01-01' WHERE device_hash = ?1")
      .bind(deviceHashOf(installId))
      .run();
    await served(installId, p.daily);
  });

  it("false + a Pro device: a problem that is not today's is served by the Pro branch", async () => {
    await setTrialConfig({ sessions_per_device: 3, replay_enabled: false });
    await setProConfig();
    const p = await problems();
    const installId = await mintInstallId();
    await seedSubscription(deviceHashOf(installId), { status: "active" });
    await served(installId, p.other);
    const row = await env.DB.prepare("SELECT pro_problem_id, trial_problem_id FROM devices WHERE device_hash = ?1")
      .bind(deviceHashOf(installId))
      .first<Record<string, any>>();
    expect(row).toMatchObject({ pro_problem_id: p.other, trial_problem_id: null });
  });

  it("false + a Pro device that replays after a reset is still served", async () => {
    await setTrialConfig({ sessions_per_device: 3, replay_enabled: false });
    await setProConfig();
    const p = await problems();
    const installId = await mintInstallId();
    await seedSubscription(deviceHashOf(installId), { status: "active" });
    await served(installId, p.daily);
    await reset(installId, p.daily);
    await served(installId, p.daily);
  });

  it("false: the onboarding walkthrough is not gated", async () => {
    await setTrialConfig({ sessions_per_device: 3, replay_enabled: false });
    const p = await problems();
    const installId = await mintInstallId();
    await served(installId, p.practice);
  });

  it("false: a hint pull is not gated", async () => {
    await setTrialConfig({ sessions_per_device: 3, replay_enabled: false });
    const p = await problems();
    const installId = await mintInstallId();
    const res = await SELF.fetch("https://worker.test/v1/trial", {
      method: "POST",
      headers: { "X-Install-Id": installId, "content-type": "application/json" },
      body: JSON.stringify({ mode: "chat", problem_id: p.other, messages: [], hint_requested: true }),
    });
    expect(res.status).toBe(200);
    await res.text();
  });
});
