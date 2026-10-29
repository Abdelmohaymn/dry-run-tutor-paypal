// POST /v1/session/reset — retire today's local session so it can be
// replayed without granting an additional trial session.
import { Hono } from "hono";
import type { Env, Variables } from "../types";
import { AppError } from "../lib/errors";
import { sessionResetRequestSchema } from "../lib/schemas";
import { utcDate } from "../lib/time";
import { reopenTrialJudge, resetTrialSession } from "../lib/trial-pool";
import { releaseLostJudgeClaim } from "../lib/turn-cap";
import { resetProSession } from "../lib/pro-session";

export const sessionResetRoute = new Hono<{ Bindings: Env; Variables: Variables }>();

sessionResetRoute.post("/", async (c) => {
  const rawBody = await c.req.json().catch(() => null);
  const parsed = sessionResetRequestSchema.safeParse(rawBody);
  if (!parsed.success) throw new AppError("BAD_REQUEST");

  const deviceHash = c.get("installId");
  const date = utcDate();
  const problemId = parsed.data.problem_id;

  if (parsed.data.reason === "recover") {
    // The verdict was produced (or the Worker was cut off) but never
    // reached the app, and the relay keeps no assessment. Hand the claim
    // back and nothing else: the session stays the same session, so the
    // re-judge neither counts as a new trial session nor passes the
    // new-session gates, and today's counters stay as they were.
    await releaseLostJudgeClaim(c.env.DB, { installId: deviceHash, problemId, date });
    await reopenTrialJudge(c.env.DB, deviceHash, problemId, date);
    return c.json({ ok: true }, 200);
  }

  await c.env.DB
    .prepare("DELETE FROM device_day WHERE device_hash = ?1 AND date = ?2 AND problem_id = ?3")
    .bind(deviceHash, date, problemId)
    .run();
  await resetTrialSession(c.env.DB, deviceHash, problemId, date);
  // Feature 009. A Pro session's slot is freed too (its count is not refunded,
  // so a replay is a new Pro session), and today's date is recorded so the
  // replay lever (trial.replay_enabled) can refuse a free device's second go.
  await resetProSession(c.env.DB, deviceHash, problemId, date);
  await c.env.DB
    .prepare("UPDATE devices SET replay_reset_date = ?2 WHERE device_hash = ?1")
    .bind(deviceHash, date)
    .run();

  return c.json({ ok: true }, 200);
});
