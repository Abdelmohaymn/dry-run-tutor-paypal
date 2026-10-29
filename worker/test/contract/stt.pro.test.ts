import { env, fetchMock } from "cloudflare:test";
import { afterEach, beforeAll, describe, expect, it } from "vitest";
import {
  GROQ_ORIGIN,
  GROQ_STT_PATH,
  deviceHashOf,
  groqTranscriptionBody,
  mintInstallId,
  postStt,
  seedSubscription,
  setProConfig,
  setVoiceConfig,
} from "./helpers";

beforeAll(() => {
  fetchMock.activate();
  fetchMock.disableNetConnect();
});

afterEach(() => {
  fetchMock.assertNoPendingInterceptors();
});

const AUDIO = new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8]);
const today = () => new Date().toISOString().slice(0, 10);

function groqOk(text: string, duration: number): void {
  fetchMock
    .get(GROQ_ORIGIN)
    .intercept({ path: GROQ_STT_PATH, method: "POST" })
    .reply(200, groqTranscriptionBody(text, duration));
}

async function spend(installId: string, seconds: number): Promise<void> {
  await env.DB.prepare("UPDATE devices SET voice_date = ?, voice_seconds = ? WHERE device_hash = ?")
    .bind(today(), seconds, deviceHashOf(installId))
    .run();
}

async function code(res: Response): Promise<string> {
  return ((await res.json()) as any).error.code;
}

// Feature 009: a Pro device's daily voice allowance is pro.voice_seconds_per_day.
describe("POST /v1/stt — Pro voice allowance", () => {
  it("a Pro device transcribes past the free cap, up to the Pro cap", async () => {
    await setVoiceConfig({ seconds_per_device: 300, max_clip_seconds: 120 });
    await setProConfig({ voice_seconds_per_day: 900 });
    const installId = await mintInstallId();
    await seedSubscription(deviceHashOf(installId), { status: "active" });
    await spend(installId, 400); // a free device would be out at 300

    groqOk("hello", 50);
    const res = await postStt(installId, AUDIO);
    expect(res.status).toBe(200);
    expect(((await res.json()) as any).seconds_left).toBe(900 - 400 - 50);
  });

  it("a free device with the same usage is out", async () => {
    await setVoiceConfig({ seconds_per_device: 300, max_clip_seconds: 120 });
    await setProConfig({ voice_seconds_per_day: 900 });
    const installId = await mintInstallId();
    await spend(installId, 400);
    const res = await postStt(installId, AUDIO);
    expect(res.status).toBe(429);
    expect(await code(res)).toBe("VOICE_EXHAUSTED");
  });

  it("a Pro device is out at the Pro cap", async () => {
    await setVoiceConfig({ seconds_per_device: 300, max_clip_seconds: 120 });
    await setProConfig({ voice_seconds_per_day: 900 });
    const installId = await mintInstallId();
    await seedSubscription(deviceHashOf(installId), { status: "active" });
    await spend(installId, 900);
    expect(await code(await postStt(installId, AUDIO))).toBe("VOICE_EXHAUSTED");
  });

  it("at Pro capacity the free cap applies", async () => {
    await setVoiceConfig({ seconds_per_device: 300, max_clip_seconds: 120 });
    await setProConfig({ voice_seconds_per_day: 900, daily_token_ceiling: 1 });
    await env.DB.prepare("INSERT INTO pro_spend (date, tokens_spent) VALUES (?1, 5)").bind(today()).run();
    const installId = await mintInstallId();
    await seedSubscription(deviceHashOf(installId), { status: "active" });
    await spend(installId, 400);
    expect(await code(await postStt(installId, AUDIO))).toBe("VOICE_EXHAUSTED");
  });

  it("with Pro switched off the free cap applies", async () => {
    await setVoiceConfig({ seconds_per_device: 300, max_clip_seconds: 120 });
    await setProConfig({ enabled: false });
    const installId = await mintInstallId();
    await seedSubscription(deviceHashOf(installId), { status: "active" });
    await spend(installId, 400);
    expect(await code(await postStt(installId, AUDIO))).toBe("VOICE_EXHAUSTED");
  });

  it("voice off is VOICE_UNAVAILABLE even for a Pro device", async () => {
    await setVoiceConfig({ enabled: false });
    await setProConfig();
    const installId = await mintInstallId();
    await seedSubscription(deviceHashOf(installId), { status: "active" });
    const res = await postStt(installId, AUDIO);
    expect(res.status).toBe(503);
    expect(await code(res)).toBe("VOICE_UNAVAILABLE");
  });
});
