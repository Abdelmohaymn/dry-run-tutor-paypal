import { env, SELF, fetchMock } from "cloudflare:test";
import { afterEach, beforeAll, describe, expect, it } from "vitest";
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

async function chat(installId: string, problemId = "vp-0001") {
  fetchMock
    .get(GROQ_ORIGIN)
    .intercept({ path: GROQ_CHAT_PATH, method: "POST" })
    .reply(200, groqStreamBody("Go on."), { headers: { "content-type": "text/event-stream" } });
  const res = await SELF.fetch("https://worker.test/v1/trial", {
    method: "POST",
    headers: { "X-Install-Id": installId, "content-type": "application/json" },
    body: JSON.stringify({ mode: "chat", problem_id: problemId, messages: [{ role: "user", text: "I would use a hash map." }] }),
  });
  expect(res.status).toBe(200);
  await readChatSSE(res);
}

function reset(installId: string, body: unknown = { problem_id: "vp-0001", reason: "practice" }) {
  return SELF.fetch("https://worker.test/v1/session/reset", {
    method: "POST",
    headers: { "X-Install-Id": installId, "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

async function row(installId: string) {
  return env.DB.prepare(
    "SELECT pro_problem_id, pro_day_date, pro_day_sessions, replay_reset_date FROM devices WHERE device_hash = ?1",
  )
    .bind(deviceHashOf(installId))
    .first<Record<string, any>>();
}

describe("POST /v1/session/reset — Pro Plus", () => {
  it("clears the Pro slot but does not refund the day's count", async () => {
    await setProConfig();
    const installId = await mintInstallId();
    await seedSubscription(deviceHashOf(installId), { status: "active" });
    await chat(installId);
    expect(await row(installId)).toMatchObject({ pro_problem_id: "vp-0001", pro_day_sessions: 1 });

    expect((await reset(installId)).status).toBe(200);
    expect(await row(installId)).toMatchObject({ pro_problem_id: null, pro_day_date: TODAY(), pro_day_sessions: 1 });
  });

  it("so a replay is a new Pro session", async () => {
    await setProConfig();
    const installId = await mintInstallId();
    await seedSubscription(deviceHashOf(installId), { status: "active" });
    await chat(installId);
    await reset(installId);
    await chat(installId);
    expect(await row(installId)).toMatchObject({ pro_problem_id: "vp-0001", pro_day_sessions: 2 });
  });

  it("a reset of another problem leaves the Pro slot alone", async () => {
    await setProConfig();
    const installId = await mintInstallId();
    await seedSubscription(deviceHashOf(installId), { status: "active" });
    await chat(installId);
    await reset(installId, { problem_id: "vp-0002", reason: "practice" });
    expect(await row(installId)).toMatchObject({ pro_problem_id: "vp-0001", pro_day_sessions: 1 });
  });

  it("recover touches neither the Pro slot nor the replay date", async () => {
    await setProConfig();
    const installId = await mintInstallId();
    await seedSubscription(deviceHashOf(installId), { status: "active" });
    await chat(installId);
    expect((await reset(installId, { problem_id: "vp-0001", reason: "recover" })).status).toBe(200);
    expect(await row(installId)).toMatchObject({ pro_problem_id: "vp-0001", pro_day_sessions: 1, replay_reset_date: null });
  });
});

describe("POST /v1/session/reset — the replay date (FR-027)", () => {
  it("a practice reset records today's date", async () => {
    await setTrialConfig({ sessions_per_device: 3 });
    const installId = await mintInstallId();
    await chat(installId);
    expect((await row(installId))!.replay_reset_date).toBeNull();
    expect((await reset(installId)).status).toBe(200);
    expect((await row(installId))!.replay_reset_date).toBe(TODAY());
  });

  it("works for a device with nothing to reset (the row exists from install)", async () => {
    const installId = await mintInstallId();
    expect((await reset(installId)).status).toBe(200);
    expect((await row(installId))!.replay_reset_date).toBe(TODAY());
  });
});
