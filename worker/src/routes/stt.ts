// POST /v1/stt?language=en — server-side speech-to-text (feature 008).
// The body is the raw audio clip. The Worker forwards it to Groq Whisper on
// the operator key and charges the device's daily voice seconds from Groq's
// own measured duration. Step order matters: nothing reaches Groq unless voice
// is on, the device has seconds left, the request is well formed, and a full
// clip's worth of seconds is held for it.
//
// Privacy: neither the audio nor the transcript is logged, stored or put in an
// error. The transcript only travels back in the `text` field of the 200.
import { Hono } from "hono";
import type { Env, Variables } from "../types";
import { AppError } from "../lib/errors";
import { getRuntimeConfig, voiceConfig } from "../lib/runtime-config";
import { resolveProTier } from "../lib/pro";
import {
  getVoiceSecondsUsed,
  reserveVoiceSeconds,
  settleVoiceSeconds,
  voiceSecondsLeft,
} from "../lib/voice-quota";
import { parseAudioType, transcribeWithGroq } from "../lib/stt-groq";
import { nowIso, utcDate } from "../lib/time";

export const sttRoute = new Hono<{ Bindings: Env; Variables: Variables }>();

const MAX_STT_BYTES = 4 * 1024 * 1024;

const LANGUAGE_PATTERN = /^[a-z]{2}$/;

sttRoute.post("/", async (c) => {
  // 1. Voice must be on.
  const cfg = await getRuntimeConfig(c.env.DB);
  const voice = voiceConfig(cfg);
  if (!voice) throw new AppError("VOICE_UNAVAILABLE");

  // 2-3. Seconds left today, checked before the body is read.
  const today = utcDate();
  const deviceHash = c.get("installId");
  // Pro Plus (feature 009): an entitled device, while Pro has capacity, gets
  // the Pro daily allowance. Voice off still means off for everyone above.
  const tier = await resolveProTier(cfg, c.env.DB, deviceHash, new Date());
  const cap = tier && tier.capacityOk ? tier.pro.voice_seconds_per_day : voice.seconds_per_device;
  const used = await getVoiceSecondsUsed(c.env.DB, deviceHash, today);
  if (voiceSecondsLeft(cap, used) <= 0) throw new AppError("VOICE_EXHAUSTED");

  // 4. Validate content type, language and size.
  const contentType = parseAudioType(c.req.header("content-type"));
  if (contentType === null) throw new AppError("BAD_REQUEST");

  const language = c.req.query("language");
  if (language !== undefined && !LANGUAGE_PATTERN.test(language)) {
    throw new AppError("BAD_REQUEST");
  }

  const declared = c.req.header("content-length");
  if (declared !== undefined) {
    const declaredBytes = Number(declared);
    if (!Number.isFinite(declaredBytes) || declaredBytes < 1 || declaredBytes > MAX_STT_BYTES) {
      throw new AppError("BAD_REQUEST");
    }
  }
  const audio = await c.req.arrayBuffer();
  if (audio.byteLength < 1 || audio.byteLength > MAX_STT_BYTES) {
    throw new AppError("BAD_REQUEST");
  }

  // 5. Hold a full clip's seconds. The hold is the real gate: step 3 only
  // saves reading the body when the device is plainly out.
  const reserved = voice.max_clip_seconds;
  if (!(await reserveVoiceSeconds(c.env.DB, deviceHash, today, reserved, cap, nowIso()))) {
    throw new AppError("VOICE_EXHAUSTED");
  }

  // 6. Transcribe. Groq failures throw VOICE_UNAVAILABLE / VOICE_BUSY /
  // BAD_REQUEST and the hold is refunded.
  let result: Awaited<ReturnType<typeof transcribeWithGroq>>;
  try {
    result = await transcribeWithGroq({
      apiKey: c.env.STT_KEY_GROQ,
      model: voice.model,
      audio,
      contentType,
      language,
    });
  } catch (err) {
    await settleVoiceSeconds(c.env.DB, deviceHash, today, reserved, 0);
    throw err;
  }
  const { text, durationSeconds } = result;

  // 7. Swap the hold for Groq's measured length (the full clip limit when Groq
  // omitted it). A clip that overran the limit is charged in full and its
  // transcript is still returned: Groq has already been paid for it.
  const billable = Math.ceil(durationSeconds ?? voice.max_clip_seconds);
  const newUsed = await settleVoiceSeconds(c.env.DB, deviceHash, today, reserved, billable);

  // 8.
  return c.json(
    {
      text,
      seconds_left: voiceSecondsLeft(cap, newUsed),
      max_clip_seconds: voice.max_clip_seconds,
    },
    200,
    { "cache-control": "private, no-store" },
  );
});
