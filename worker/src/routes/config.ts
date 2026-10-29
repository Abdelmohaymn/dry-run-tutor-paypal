// GET /v1/config — contracts/openapi.yaml. The only remote-control
// surface. Gates app launch, so the payload stays small (FR-033).
//
// CLIENT FAIL-OPEN OBLIGATION (research.md R-010, Constitution X.3): if
// this endpoint is unreachable, the app MUST fall back to its last cached
// response rather than blocking launch. Config must never be able to lock
// a learner out — see worker/README.md for the client-side contract this
// implies (T099).
import { Hono } from "hono";
import type { Env, Variables } from "../types";
import { getRuntimeConfig } from "../lib/runtime-config";

export const configRoute = new Hono<{ Bindings: Env; Variables: Variables }>();

configRoute.get("/", async (c) => {
  const cfg = await getRuntimeConfig(c.env.DB);
  // `web` (feature 007) is the landing site's own levers; `rotation` is read
  // by GET /v1/daily (006). The app has no use for either, so neither leaves
  // the Worker in this payload. `voice.model` (feature 008) is the Worker's
  // own STT model choice, so it is dropped from the `voice` block too; an
  // absent `voice` stays absent (voice off). Likewise `pro.plan_id`,
  // `pro.daily_token_ceiling`, `pro.total_token_ceiling` and
  // `pro.recheck_after_seconds` (feature 009) stay on the Worker; an absent
  // `pro` stays absent.
  const { web: _web, rotation: _rotation, voice, pro, ...rest } = cfg;
  const withVoice = voice
    ? {
        ...rest,
        voice: {
          enabled: voice.enabled,
          seconds_per_device: voice.seconds_per_device,
          max_clip_seconds: voice.max_clip_seconds,
        },
      }
    : rest;
  const appCfg = pro
    ? {
        ...withVoice,
        pro: {
          enabled: pro.enabled,
          price_label: pro.price_label,
          sessions_per_day: pro.sessions_per_day,
          voice_seconds_per_day: pro.voice_seconds_per_day,
          manage_url: pro.manage_url,
        },
      }
    : withVoice;
  const body = JSON.stringify(appCfg);
  // A stable ETag over the served bytes, not a per-request random value —
  // it changes only when the lever payload itself changes.
  const etag = `"${await sha256Hex(body)}"`;
  return new Response(body, {
    status: 200,
    headers: {
      "content-type": "application/json",
      "cache-control": "public, max-age=300",
      etag,
    },
  });
});

async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
