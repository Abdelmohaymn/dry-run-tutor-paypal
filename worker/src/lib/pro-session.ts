// Pro Plus session slot (feature 009, data-model.md A4). A Pro session is one
// problem on one UTC day, the same identity the free path uses, kept in its own
// `devices.pro_*` columns. Nothing here reads or writes the free path's columns,
// so Pro sessions never count toward `trial.sessions_per_device` (research.md R-5).
import type { Context } from "hono";
import type { Env, Variables } from "../types";
import { AppError } from "./errors";
import { groqProvider } from "./provider-groq";
import { runConversationalTurn } from "./chat-core";
import { runJudge } from "./judge-core";
import { pooledCalls } from "./pooled-calls";
import { proLedger } from "./pro-spend";
import { nowIso } from "./time";
import type { ProConfig, RuntimeConfig } from "./runtime-config";
import type { TrialRequest } from "./schemas";
import type { Problem } from "../../../tools/problem-types";

export type ProSessionState = "in_flight" | "available" | "sessions_used";
export type ProClaim = "in_flight" | "claimed" | "refused";

interface SlotRow {
  pro_problem_id: string | null;
  pro_day_date: string | null;
  pro_day_sessions: number;
}

async function readSlot(db: D1Database, device: string): Promise<SlotRow | null> {
  return db
    .prepare("SELECT pro_problem_id, pro_day_date, pro_day_sessions FROM devices WHERE device_hash = ?1")
    .bind(device)
    .first<SlotRow>();
}

function countToday(row: SlotRow | null, date: string): number {
  return row && row.pro_day_date === date ? row.pro_day_sessions : 0;
}

/** `in_flight` when the slot already holds this session; else `available` while today's count is under `cap`. */
export async function proSessionState(
  db: D1Database,
  device: string,
  problemId: string,
  date: string,
  cap: number,
): Promise<ProSessionState> {
  const row = await readSlot(db, device);
  if (row && row.pro_problem_id === problemId && row.pro_day_date === date) return "in_flight";
  return countToday(row, date) < cap ? "available" : "sessions_used";
}

/** How many Pro sessions this device has started today (UTC). */
export async function proSessionsToday(db: D1Database, device: string, date: string): Promise<number> {
  return countToday(await readSlot(db, device), date);
}

/** Takes a Pro session slot in one statement; `in_flight` when the slot already holds this session. */
export async function claimProSession(
  db: D1Database,
  device: string,
  problemId: string,
  date: string,
  cap: number,
  nowIso: string,
): Promise<ProClaim> {
  const written = await db
    .prepare(
      `INSERT INTO devices (device_hash, created_at, pro_problem_id, pro_day_date, pro_day_sessions)
       VALUES (?1, ?5, ?2, ?3, 1)
       ON CONFLICT(device_hash) DO UPDATE SET
         pro_day_sessions = CASE WHEN devices.pro_day_date IS ?3 THEN devices.pro_day_sessions ELSE 0 END + 1,
         pro_problem_id   = ?2,
         pro_day_date     = ?3
       WHERE NOT (devices.pro_problem_id IS ?2 AND devices.pro_day_date IS ?3)
         AND CASE WHEN devices.pro_day_date IS ?3 THEN devices.pro_day_sessions ELSE 0 END < ?4
       RETURNING device_hash`,
    )
    .bind(device, problemId, date, cap, nowIso)
    .first();
  if (written) return "claimed";
  const row = await readSlot(db, device);
  return row?.pro_problem_id === problemId && row.pro_day_date === date ? "in_flight" : "refused";
}

/** Undoes a `claimed` whose provider never answered (Constitution VIII). */
export async function releaseProSession(
  db: D1Database,
  device: string,
  problemId: string,
  date: string,
): Promise<void> {
  await db
    .prepare(
      `UPDATE devices
         SET pro_day_sessions = MAX(0, pro_day_sessions - 1), pro_problem_id = NULL
       WHERE device_hash = ?1 AND pro_problem_id = ?2 AND pro_day_date = ?3`,
    )
    .bind(device, problemId, date)
    .run();
}

/** Called by POST /v1/session/reset. The count is NOT refunded, so a replay is a new Pro session. */
export async function resetProSession(
  db: D1Database,
  device: string,
  problemId: string,
  date: string,
): Promise<void> {
  await db
    .prepare(
      `UPDATE devices SET pro_problem_id = NULL
       WHERE device_hash = ?1 AND pro_problem_id = ?2 AND pro_day_date = ?3`,
    )
    .bind(device, problemId, date)
    .run();
}

export interface ServeProArgs {
  db: D1Database;
  installId: string;
  date: string;
  now: Date;
  cfg: RuntimeConfig;
  pro: ProConfig;
  secretFor: (bindingName: string) => string;
}

/**
 * Serves one `/v1/trial` call under Pro rules (worker-api.md §5). It mirrors the
 * free path's chat and judge branches with three differences: the spend lands
 * in the Pro ledger, the session slot is the `pro_*` one, and nothing here
 * reads or writes the free allowance. Per-session limits are unchanged
 * (FR-015): `trial.turn_cap`, the ground-truth tier and condensation.
 */
export async function servePro(
  c: Context<{ Bindings: Env; Variables: Variables }>,
  body: TrialRequest,
  problem: Problem,
  args: ServeProArgs,
): Promise<Response> {
  const { db, installId, date, now, cfg, pro, secretFor } = args;
  const pooled = pooledCalls({ cfg, db, now, secretFor, ledger: proLedger });
  const claim = () => claimProSession(db, installId, body.problem_id, date, pro.sessions_per_day, nowIso());
  let claimed = false;

  if (body.mode === "chat") {
    const lastMessage = body.messages[body.messages.length - 1];
    if (lastMessage.text.replace(/\s+/g, "").length < cfg.chat.min_turn_chars) {
      throw new AppError("EMPTY_TURN");
    }
    return runConversationalTurn(
      c,
      body,
      {
        db,
        installId,
        problemId: body.problem_id,
        date,
        cfg,
        provider: groqProvider,
        turnCap: cfg.trial.turn_cap,
        groundTruthTier: cfg.trial.ground_truth_tier,
        condenseEnabled: cfg.trial.condense,
        streamChat: pooled.streamChat,
        condenseCallOptions: pooled.condenseCallOptions,
        finishCheck: pooled.finishCheck,
        onBeforeProviderCall: async () => {
          const result = await claim();
          if (result === "refused") throw new AppError("TRIAL_CONSUMED");
          claimed = result === "claimed";
        },
        onProviderCallUnanswered: async () => {
          if (claimed) await releaseProSession(db, installId, body.problem_id, date);
        },
      },
      problem,
    );
  }

  // mode === "judge"
  const result = await claim();
  if (result === "refused") throw new AppError("TRIAL_CONSUMED");
  claimed = result === "claimed";
  try {
    const assessment = await runJudge(
      {
        db,
        installId,
        problemId: body.problem_id,
        date,
        finishCheckTimeoutMs: cfg.finish_offer.timeout_ms,
        structuredCompletion: pooled.judgeStructuredCompletion,
      },
      body,
      problem,
    );
    return c.json(assessment, 200);
  } catch (err) {
    // No assessment came back, so nothing was spent (Constitution VIII).
    if (claimed) await releaseProSession(db, installId, body.problem_id, date);
    throw err;
  }
}
