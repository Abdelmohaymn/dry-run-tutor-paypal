import { env, SELF, fetchMock } from "cloudflare:test";
import { afterEach, beforeAll, describe, expect, it } from "vitest";
import {
  GROQ_CHAT_PATH,
  GROQ_ORIGIN,
  deviceHashOf,
  groqCompletionBody,
  groqStreamBody,
  interceptEvidenceCheck,
  interceptFinalCheckUnusable,
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

function trialChat(installId: string, problemId: string, text: string, extra: Record<string, unknown> = {}) {
  return SELF.fetch("https://worker.test/v1/trial", {
    method: "POST",
    headers: { "X-Install-Id": installId, "content-type": "application/json" },
    body: JSON.stringify({ mode: "chat", problem_id: problemId, messages: [{ role: "user", text }], ...extra }),
  });
}

function trialJudge(installId: string, problemId: string) {
  return SELF.fetch("https://worker.test/v1/trial", {
    method: "POST",
    headers: { "X-Install-Id": installId, "content-type": "application/json" },
    body: JSON.stringify({
      mode: "judge",
      problem_id: problemId,
      ended_by: "user",
      conversation: [{ role: "user", text: "I would use a hash map." }],
    }),
  });
}

function mockChatReply(text = "Let's think this through.") {
  fetchMock
    .get(GROQ_ORIGIN)
    .intercept({ path: GROQ_CHAT_PATH, method: "POST" })
    .reply(200, groqStreamBody(text), { headers: { "content-type": "text/event-stream" } });
}

function mockJudgeReply() {
  interceptFinalCheckUnusable();
  fetchMock
    .get(GROQ_ORIGIN)
    .intercept({ path: GROQ_CHAT_PATH, method: "POST" })
    .reply(
      200,
      groqCompletionBody(
        JSON.stringify({
          approach_quote: "I would use a hash map",
          matched_approach: "hashmap",
          matched_verdict: "optimal",
          insights_hit: [{ quote: "I would use a hash map", key: "complement_lookup" }],
          insights_missed: [],
          wrong_turns_taken: [],
          complexity: {
            user_claimed_time: null,
            user_claimed_space: null,
            reference_time: "O(n)",
            reference_space: "O(n)",
            assessment: "not_stated",
          },
          verdict: "unclear",
          confidence: 0.5,
          feedback: "Some feedback here.",
        }),
      ),
    );
  interceptEvidenceCheck();
}

/** A Pro device: Pro on, an active subscription bound to a fresh install. */
async function proDevice(proOverrides: Parameters<typeof setProConfig>[0] = {}): Promise<{ installId: string; hash: string }> {
  await setProConfig(proOverrides);
  const installId = await mintInstallId();
  const hash = deviceHashOf(installId);
  await seedSubscription(hash, { status: "active" });
  return { installId, hash };
}

async function deviceRow(hash: string) {
  return env.DB.prepare(
    `SELECT trial_started_at, trial_problem_id, trial_date, trial_completed_at, trial_sessions_done,
            trial_day_sessions, pro_day_date, pro_day_sessions, pro_problem_id
       FROM devices WHERE device_hash = ?1`,
  )
    .bind(hash)
    .first<Record<string, any>>();
}

async function proSpent(): Promise<number> {
  const row = await env.DB.prepare("SELECT COALESCE(SUM(tokens_spent), 0) AS n FROM pro_spend").first<{ n: number }>();
  return row!.n;
}

async function freeSpent(): Promise<number> {
  const row = await env.DB.prepare("SELECT COALESCE(SUM(tokens_spent), 0) AS n FROM provider_day").first<{ n: number }>();
  return row!.n;
}

async function code(res: Response): Promise<string> {
  return ((await res.json()) as any).error.code;
}

// Feature 009. A Pro device rides on POST /v1/trial; the relay decides per request.
describe("POST /v1/trial — a Pro device", () => {
  it("is served beyond the free sessions_per_device, and spends only the Pro ledger", async () => {
    await setTrialConfig({ sessions_per_device: 1 });
    const { installId, hash } = await proDevice();

    mockChatReply("First.");
    const first = await trialChat(installId, "vp-0001", "first problem");
    expect(first.status).toBe(200);
    await readChatSSE(first);

    mockChatReply("Second.");
    const second = await trialChat(installId, "vp-0002", "second problem");
    expect(second.status).toBe(200);
    const meta = (await readChatSSE(second)).find((f) => f.event === "meta")!.data as { turn_index: number };
    expect(meta.turn_index).toBe(1);

    const row = await deviceRow(hash);
    expect(row).toMatchObject({ pro_day_date: TODAY(), pro_day_sessions: 2, pro_problem_id: "vp-0002" });
    expect(await proSpent()).toBeGreaterThan(0);
    expect(await freeSpent()).toBe(0);
  });

  it("never touches the free allowance (trial_* columns)", async () => {
    const { installId, hash } = await proDevice();
    mockChatReply();
    await readChatSSE(await trialChat(installId, "vp-0001", "first problem"));
    expect(await deviceRow(hash)).toMatchObject({
      trial_started_at: null,
      trial_problem_id: null,
      trial_date: null,
      trial_completed_at: null,
      trial_sessions_done: 0,
      trial_day_sessions: 0,
    });
  });

  it("a second turn of the same session is still in flight, and is not a second session", async () => {
    const { installId, hash } = await proDevice({ sessions_per_day: 1 });
    mockChatReply("One.");
    await readChatSSE(await trialChat(installId, "vp-0001", "first turn"));
    mockChatReply("Two.");
    const again = await trialChat(installId, "vp-0001", "second turn");
    expect(again.status).toBe(200);
    await again.text();
    expect((await deviceRow(hash))!.pro_day_sessions).toBe(1);
  });

  it("a judge call is served under Pro and marks no free session complete", async () => {
    const { installId, hash } = await proDevice();
    mockChatReply();
    await readChatSSE(await trialChat(installId, "vp-0001", "I would use a hash map."));
    mockJudgeReply();
    const res = await trialJudge(installId, "vp-0001");
    expect(res.status).toBe(200);
    expect(((await res.json()) as any).verdict).toBeDefined();
    expect(await deviceRow(hash)).toMatchObject({ trial_completed_at: null, trial_started_at: null, pro_day_sessions: 1 });
    expect(await freeSpent()).toBe(0);
  });

  it("when sessions_per_day is reached the next new session falls to the free path, then TRIAL_CONSUMED", async () => {
    await setTrialConfig({ sessions_per_device: 1 });
    const { installId, hash } = await proDevice({ sessions_per_day: 1 });

    mockChatReply("Pro.");
    await readChatSSE(await trialChat(installId, "vp-0001", "first problem"));
    expect(await proSpent()).toBeGreaterThan(0);

    // Day's Pro session spent: this one is served by the free path.
    mockChatReply("Free.");
    const free = await trialChat(installId, "vp-0002", "second problem");
    expect(free.status).toBe(200);
    await readChatSSE(free);
    expect(await deviceRow(hash)).toMatchObject({ trial_problem_id: "vp-0002", pro_day_sessions: 1 });
    expect(await freeSpent()).toBeGreaterThan(0);

    // And with the free session spent as well, the free path's own refusal comes through.
    const refused = await trialChat(installId, "vp-0003", "third problem");
    expect(refused.status).toBe(409);
    expect(await code(refused)).toBe("TRIAL_CONSUMED");
  });

  it("with Pro off, a device with an active subscription is served exactly as a free device", async () => {
    const { installId, hash } = await proDevice({ enabled: false });
    mockChatReply();
    await readChatSSE(await trialChat(installId, "vp-0001", "first problem"));
    expect(await deviceRow(hash)).toMatchObject({ trial_problem_id: "vp-0001", pro_day_sessions: 0 });
    expect(await proSpent()).toBe(0);
    expect(await freeSpent()).toBeGreaterThan(0);
  });

  it("a device with no subscription is a free device even with Pro on", async () => {
    await setProConfig();
    const installId = await mintInstallId();
    mockChatReply();
    await readChatSSE(await trialChat(installId, "vp-0001", "first problem"));
    expect(await proSpent()).toBe(0);
  });

  it("an expired subscription is a free device", async () => {
    await setProConfig();
    const installId = await mintInstallId();
    await seedSubscription(deviceHashOf(installId), { status: "cancelled", periodEnd: "2020-01-01T00:00:00Z" });
    mockChatReply();
    await readChatSSE(await trialChat(installId, "vp-0001", "first problem"));
    expect(await proSpent()).toBe(0);
  });

  it("the turn cap is still trial.turn_cap (FR-015)", async () => {
    await setTrialConfig({ turn_cap: 2 });
    const { installId } = await proDevice();
    for (const n of [1, 2]) {
      mockChatReply(`reply ${n}`);
      const res = await trialChat(installId, "vp-0001", `turn ${n} — I would check every pair`);
      expect(res.status).toBe(200);
      await res.text();
    }
    const third = await trialChat(installId, "vp-0001", "turn 3 — one more");
    expect(third.status).toBe(409);
    expect(await code(third)).toBe("TURN_CAP_REACHED");
  });

  it("a provider failure hands the claimed Pro session back", async () => {
    const { installId, hash } = await proDevice();
    fetchMock
      .get(GROQ_ORIGIN)
      .intercept({ path: GROQ_CHAT_PATH, method: "POST" })
      .reply(500, { error: "upstream down" });
    const res = await trialChat(installId, "vp-0001", "first problem");
    expect((await readChatSSE(res))[0].event).toBe("error");
    expect(await deviceRow(hash)).toMatchObject({ pro_day_sessions: 0, pro_problem_id: null });
    expect(await proSpent()).toBe(0);
  });

  it("a whitespace-only turn is EMPTY_TURN and claims nothing", async () => {
    const { installId, hash } = await proDevice();
    const res = await trialChat(installId, "vp-0001", "   ");
    expect(res.status).toBe(400);
    expect(await code(res)).toBe("EMPTY_TURN");
    expect((await deviceRow(hash))!.pro_day_sessions).toBe(0);
  });

  it("a hint pull stays free and untouched", async () => {
    const { installId, hash } = await proDevice();
    const res = await trialChat(installId, "vp-0001", "", { hint_requested: true, messages: [] });
    expect(res.status).toBe(200);
    await res.text();
    expect((await deviceRow(hash))!.pro_day_sessions).toBe(0);
    expect(await proSpent()).toBe(0);
  });
});

// research.md R-4: the ceilings gate NEW Pro sessions only. A session already
// in flight runs to its end, and a refusal falls to the free path, never to an error.
describe("POST /v1/trial — Pro spend ceilings (US5)", () => {
  it("at the daily ceiling a NEW session falls to the free path", async () => {
    const { installId, hash } = await proDevice({ daily_token_ceiling: 1 });

    mockChatReply("Pro.");
    await readChatSSE(await trialChat(installId, "vp-0001", "first problem"));
    expect(await proSpent()).toBeGreaterThan(1);

    mockChatReply("Free.");
    const next = await trialChat(installId, "vp-0002", "second problem");
    expect(next.status).toBe(200);
    await readChatSSE(next);
    expect(await deviceRow(hash)).toMatchObject({ trial_problem_id: "vp-0002", pro_day_sessions: 1 });
    expect(await freeSpent()).toBeGreaterThan(0);
  });

  it("an in-flight Pro session still serves after the ceiling is reached", async () => {
    const { installId, hash } = await proDevice({ daily_token_ceiling: 1 });

    mockChatReply("One.");
    await readChatSSE(await trialChat(installId, "vp-0001", "first turn"));
    const afterFirst = await proSpent();

    mockChatReply("Two.");
    const again = await trialChat(installId, "vp-0001", "second turn");
    expect(again.status).toBe(200);
    await readChatSSE(again);
    expect(await proSpent()).toBeGreaterThan(afterFirst);
    expect(await deviceRow(hash)).toMatchObject({ trial_problem_id: null, pro_problem_id: "vp-0001", pro_day_sessions: 1 });
    expect(await freeSpent()).toBe(0);
  });

  it("the total ceiling gates new sessions the same way", async () => {
    await setTrialConfig({ sessions_per_device: 1 });
    const { installId, hash } = await proDevice({ total_token_ceiling: 1 });
    // Spent on an earlier day: the daily ceiling alone would not stop this.
    await env.DB.prepare("INSERT INTO pro_spend (date, tokens_spent) VALUES ('2020-01-01', 5)").run();

    mockChatReply("Free.");
    await readChatSSE(await trialChat(installId, "vp-0001", "first problem"));
    expect(await deviceRow(hash)).toMatchObject({ trial_problem_id: "vp-0001", pro_day_sessions: 0 });
  });

  it("a ceiling of 0 is Pro effectively off, with nothing erroring", async () => {
    const { installId, hash } = await proDevice({ daily_token_ceiling: 0 });
    mockChatReply();
    const res = await trialChat(installId, "vp-0001", "first problem");
    expect(res.status).toBe(200);
    await readChatSSE(res);
    expect(await deviceRow(hash)).toMatchObject({ trial_problem_id: "vp-0001", pro_day_sessions: 0 });
  });

  it("when the pool is cooling down, Pro does not start a session either", async () => {
    const { installId, hash } = await proDevice();
    const until = new Date(Date.now() + 60_000).toISOString();
    await env.DB.prepare("INSERT INTO provider_day (date, provider_id, tokens_spent, cooldown_until) VALUES (?1, 'groq', 0, ?2)")
      .bind(TODAY(), until)
      .run();
    const res = await trialChat(installId, "vp-0001", "first problem");
    expect(res.status).toBe(503);
    expect(await code(res)).toBe("TRIAL_UNAVAILABLE");
    expect((await deviceRow(hash))!.pro_day_sessions).toBe(0);
  });
});

