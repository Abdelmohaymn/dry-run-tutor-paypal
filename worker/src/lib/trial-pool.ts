// data-model.md §B8. Only routes/trial.ts calls this. The keyed paths
// (/v1/chat, /v1/judge) never touch provider_day and can never return
// TRIAL_UNAVAILABLE — the operator's allowance is fixed and shared by every
// new install, unlike a learner's own key.
import { AppError } from "./errors";
import { networkKey } from "./network-key";
import type { RuntimeConfig } from "./runtime-config";
import type { ProviderCallOptions } from "./provider";

export const TRIAL_ESTIMATE_CHAT = 1600;
export const TRIAL_ESTIMATE_JUDGE = 5100;

export type TrialLeg = "chat" | "judge";

export interface TrialPoolMember {
  id: string;
  secret_binding: string;
  base_url: string;
  model: string;
  daily_token_budget: number;
  structured_output: boolean;
  enabled: boolean;
  cooldown_ms: number;
  structured_extra_body?: Record<string, unknown>;
}

export function estimateFor(leg: TrialLeg): number {
  return leg === "chat" ? TRIAL_ESTIMATE_CHAT : TRIAL_ESTIMATE_JUDGE;
}

/**
 * Eligible members, budget/cooldown filtered, in priority order. `chat`
 * deliberately burns the abundant (non-structured-output) budget first —
 * a stable PARTITION, not a sort, so pool array order (the operator's
 * priority) survives inside each group. `judge` restricts to
 * `structured_output: true` members and never falls back past that: a
 * silent fallback would defeat FR-014's structural guarantee.
 */
export async function selectMember(
  leg: TrialLeg,
  cfg: RuntimeConfig,
  db: D1Database,
  now: Date,
  exclude: ReadonlySet<string> = new Set(),
  /**
   * false skips the member's own daily_token_budget check (the cooldown still
   * applies). Pro calls (feature 009) pass false: they are capped by their own
   * ledger, not by the free daily budget.
   */
  enforceBudget = true,
): Promise<TrialPoolMember | null> {
  const enabled = cfg.trial.pool.filter((m) => m.enabled && !exclude.has(m.id));
  const candidates =
    leg === "judge"
      ? enabled.filter((m) => m.structured_output)
      : [...enabled.filter((m) => !m.structured_output), ...enabled.filter((m) => m.structured_output)];

  const date = now.toISOString().slice(0, 10);
  for (const m of candidates) {
    const row = await db
      .prepare("SELECT tokens_spent, cooldown_until FROM provider_day WHERE date = ?1 AND provider_id = ?2")
      .bind(date, m.id)
      .first<{ tokens_spent: number; cooldown_until: string | null }>();
    if (row) {
      if (enforceBudget && row.tokens_spent >= m.daily_token_budget) continue;
      if (row.cooldown_until && new Date(row.cooldown_until) > now) continue;
    }
    return m;
  }
  return null;
}

/**
 * `selectMember()` for a caller that has no use for "none": throws
 * TRIAL_UNAVAILABLE instead. Lives here so that code stays in the files
 * trial-isolation.test.ts allows to throw it (pooled-calls.ts shares the
 * condensation lookup between the free and Pro paths).
 */
export async function selectMemberOrUnavailable(
  leg: TrialLeg,
  cfg: RuntimeConfig,
  db: D1Database,
  now: Date,
  enforceBudget = true,
): Promise<TrialPoolMember> {
  const member = await selectMember(leg, cfg, db, now, new Set(), enforceBudget);
  if (!member) throw new AppError("TRIAL_UNAVAILABLE");
  return member;
}

async function reserveEstimate(db: D1Database, date: string, providerId: string, estimate: number): Promise<void> {
  await db
    .prepare(
      `INSERT INTO provider_day (date, provider_id, tokens_spent)
       VALUES (?1, ?2, ?3)
       ON CONFLICT(date, provider_id) DO UPDATE SET tokens_spent = provider_day.tokens_spent + ?3`,
    )
    .bind(date, providerId, estimate)
    .run();
}

/**
 * Replaces the reserved estimate with the provider's real usage figure.
 * Exported because for a streaming chat leg the actual token count is only
 * known once the SSE stream has fully drained, well after `runLeg()` has
 * returned — so the caller settles the budget itself instead of `runLeg()`
 * doing it eagerly with a not-yet-known actual.
 */
export async function settleTrialBudget(
  db: D1Database,
  now: Date,
  providerId: string,
  leg: TrialLeg,
  actual: number,
): Promise<void> {
  const date = now.toISOString().slice(0, 10);
  await db
    .prepare(
      `UPDATE provider_day SET tokens_spent = tokens_spent - ?3 + ?4
       WHERE date = ?1 AND provider_id = ?2`,
    )
    .bind(date, providerId, estimateFor(leg), actual)
    .run();
}

/**
 * Undoes `reserveEstimate()` for a call that failed. The provider either
 * never answered or answered with nothing usable, so nothing is settled
 * later and the estimate would otherwise stay counted for the whole day
 * (docs/errors/2026-09-25-trial-judge-unclear-retry.md, bug 2).
 */
async function releaseEstimate(db: D1Database, date: string, providerId: string, estimate: number): Promise<void> {
  await db
    .prepare(
      `UPDATE provider_day SET tokens_spent = MAX(tokens_spent - ?3, 0)
       WHERE date = ?1 AND provider_id = ?2`,
    )
    .bind(date, providerId, estimate)
    .run();
}

async function setCooldown(db: D1Database, date: string, providerId: string, cooldownUntil: string): Promise<void> {
  await db
    .prepare(
      `INSERT INTO provider_day (date, provider_id, tokens_spent, cooldown_until)
       VALUES (?1, ?2, 0, ?3)
       ON CONFLICT(date, provider_id) DO UPDATE SET cooldown_until = ?3`,
    )
    .bind(date, providerId, cooldownUntil)
    .run();
}

/**
 * Where a pool call's token estimate is reserved, released and settled
 * (feature 009, data-model.md A5). The free path writes `provider_day`; Pro
 * writes `pro_spend` (pro-spend.ts), so the two never drain each other.
 */
export interface BudgetLedger {
  /** false: selectMember skips the member's own daily_token_budget check (cooldown still applies). */
  readonly enforceMemberBudget: boolean;
  reserve(db: D1Database, date: string, memberId: string, estimate: number): Promise<void>;
  release(db: D1Database, date: string, memberId: string, estimate: number): Promise<void>;
  settle(db: D1Database, now: Date, memberId: string, leg: TrialLeg, actual: number): Promise<void>;
}

/** The free trial path's ledger: `provider_day.tokens_spent`, exactly as before Pro Plus. */
export const freeLedger: BudgetLedger = {
  enforceMemberBudget: true,
  reserve: reserveEstimate,
  release: releaseEstimate,
  settle: settleTrialBudget,
};

export interface RunLegResult<T> {
  member: TrialPoolMember;
  result: T;
}

export interface TrialRepairResult {
  text: string;
  inputTokens: number;
  outputTokens: number;
}

/**
 * Runs a best-effort repair on the operator pool. Repair is charged as a
 * chat-sized pool leg because it uses the same non-structured pool members;
 * the reservation is replaced with the provider's measured token count.
 */
export async function runTrialRepair(
  cfg: RuntimeConfig,
  db: D1Database,
  call: (opts: ProviderCallOptions) => Promise<TrialRepairResult | null>,
  secretFor: (bindingName: string) => string,
  ledger: BudgetLedger = freeLedger,
): Promise<TrialRepairResult | null> {
  const now = new Date();
  let leg: RunLegResult<TrialRepairResult | null>;
  try {
    leg = await runLeg("chat", cfg, db, now, call, secretFor, ledger);
  } catch (error) {
    if (error instanceof AppError && error.code === "TRIAL_UNAVAILABLE") return null;
    throw error;
  }
  if (leg.result !== null) {
    await ledger.settle(
      db,
      now,
      leg.member.id,
      "chat",
      leg.result.inputTokens + leg.result.outputTokens,
    );
  }
  return leg.result;
}

/**
 * Runs one leg against the pool, routing around a RATE_LIMITED/
 * QUOTA_EXHAUSTED member (a routing signal, not an outcome — FR-031c) to
 * the next eligible one, so a 429 never reaches the caller (SC-010c).
 * `call` performs the actual provider request and should throw AppError on
 * failure exactly like provider.ts. The estimate is reserved before each
 * attempt and released again if that attempt throws; the CALLER settles a
 * successful one to the real figure via `settleTrialBudget()` once usage is
 * known (see that function's comment).
 */
export async function runLeg<T>(
  leg: TrialLeg,
  cfg: RuntimeConfig,
  db: D1Database,
  now: Date,
  call: (opts: ProviderCallOptions) => Promise<T>,
  secretFor: (bindingName: string) => string,
  ledger: BudgetLedger = freeLedger,
): Promise<RunLegResult<T>> {
  const tried = new Set<string>();
  const date = now.toISOString().slice(0, 10);
  const estimate = estimateFor(leg);
  let lastError: AppError | null = null;

  for (;;) {
    const member = await selectMember(leg, cfg, db, now, tried, ledger.enforceMemberBudget);
    if (!member) {
      // A member that answered badly says nothing about the pool's budget,
      // so the learner gets that retryable error, not "trial unavailable".
      throw lastError?.tryElsewhere ? lastError : new AppError("TRIAL_UNAVAILABLE");
    }
    tried.add(member.id);

    await ledger.reserve(db, date, member.id, estimate);

    try {
      const result = await call({
        baseUrl: member.base_url,
        model: member.model,
        apiKey: secretFor(member.secret_binding),
        structuredExtraBody: member.structured_extra_body,
      });
      return { member, result };
    } catch (err) {
      await ledger.release(db, date, member.id, estimate);
      // A member that is rate-limited, out of quota, or simply not
      // answering is a member this call should stop waiting on and the
      // next one should be tried — that is the whole reason the pool has
      // more than one member.
      //
      // A provider that never answered was previously rethrown here, which
      // meant a single slow member ended the call outright: on a physical
      // device the assessment failed roughly two times in three, always
      // after the provider's own 30-second timeout, while the other pool
      // member was healthy and answering in about a second. The cooldown
      // goes on too, exactly as for a rate limit — a member that just timed
      // out is very likely to time out again, and burning another 30
      // seconds to rediscover that is the learner's time, not ours.
      //
      // An upstream that answered with a 5xx or an unusable 200 is flagged
      // `tryElsewhere`: the next member gets the call, but this one is not
      // cooled down, since one bad answer is not a pattern. Any other error
      // status (400, 401) is about the request and surfaces straight to the
      // caller; `trial.session-identity` pins that for a lone member.
      const tryNextMember =
        err instanceof AppError &&
        (err.code === "RATE_LIMITED" || err.code === "QUOTA_EXHAUSTED" || err.memberUnavailable);
      if (tryNextMember) {
        await setCooldown(db, date, member.id, new Date(now.getTime() + member.cooldown_ms).toISOString());
        lastError = err;
        continue;
      }
      if (err instanceof AppError && err.tryElsewhere) {
        lastError = err;
        continue;
      }
      throw err;
    }
  }
}

// --- devices.trial_* (data-model.md §A2, FR-032, FR-032a) ---

export interface TrialConsumedRow {
  /** NULL while the taster is unclaimed (the `devices` row exists from /v1/install). */
  startedAt: string | null;
  completedAt: string | null;
  /**
   * The problem the taster was spent on. NULL on a pre-0002 row, and on a
   * row the walkthrough created before the taster proper was claimed
   * (0003) — `isTasterUnclaimed()` tells those two apart.
   */
  problemId: string | null;
  /** The UTC day it was spent on. NULL in the same two cases as above. */
  date: string | null;
  /** Walkthrough turns spent by this install, for life (0003). */
  practiceTurns: number;
  /** Sessions already retired out of the slot above (0008). */
  sessionsDone: number;
}

export async function getTrialConsumed(db: D1Database, installId: string): Promise<TrialConsumedRow | null> {
  const row = await db
    .prepare(
      "SELECT trial_started_at, trial_completed_at, trial_problem_id, trial_date, practice_turns, trial_sessions_done FROM devices WHERE device_hash = ?1",
    )
    .bind(installId)
    .first<{
      trial_started_at: string | null;
      trial_completed_at: string | null;
      trial_problem_id: string | null;
      trial_date: string | null;
      practice_turns: number;
      trial_sessions_done: number;
    }>();
  if (!row) return null;
  return {
    startedAt: row.trial_started_at,
    completedAt: row.trial_completed_at,
    problemId: row.trial_problem_id,
    date: row.trial_date,
    practiceTurns: row.practice_turns ?? 0,
    sessionsDone: row.trial_sessions_done ?? 0,
  };
}

/**
 * FR-032. True only for a call that belongs to the ONE session this install
 * already has open: same problem, same UTC day, not yet completed. Anything
 * else is a request for a SECOND session and must be refused.
 *
 * The identity check is the fix for the hole 0002 documents: without it,
 * `completed_at IS NULL` alone meant "in flight", and since completed_at is
 * only ever written after a successful judge, an abandoned session stayed in
 * flight for good — handing out a fresh trial.turn_cap on every new
 * problem_id and again every day, with the new-session budget gate skipped.
 */
export function isSameTrialSession(
  row: TrialConsumedRow,
  problemId: string,
  date: string,
): boolean {
  return row.completedAt === null && row.problemId === problemId && row.date === date;
}

/**
 * A row that exists but has never claimed the taster proper — written by
 * the walkthrough alone (0003), which counts its turns on this row without
 * pinning it to a problem or a day.
 *
 * Deliberately NOT the same shape as the pre-0002 rows this looks like:
 * those carry `completed_at = started_at`, written by 0002's own UPDATE
 * exactly so an unidentifiable open session could never be mistaken for a
 * live one. An unclaimed row is open AND unpinned; a legacy row is closed.
 */
export function isTasterUnclaimed(row: TrialConsumedRow): boolean {
  return row.completedAt === null && row.problemId === null;
}

/**
 * Free sessions this device has claimed: the ones retired out of the slot
 * (0008) plus the one the slot holds now. A walkthrough-only row claims none;
 * a pre-0002 row (closed, no problem) counts as the one session it spent.
 */
export function trialSessionsClaimed(row: TrialConsumedRow | null): number {
  if (!row) return 0;
  return row.sessionsDone + (isTasterUnclaimed(row) ? 0 : 1);
}

/** True while `trial.sessions_per_device` leaves room for another session. */
export function mayClaimAnotherSession(row: TrialConsumedRow | null, cfg: RuntimeConfig): boolean {
  return trialSessionsClaimed(row) < cfg.trial.sessions_per_device;
}

/** Practice turns already spent by this install, for life. */
export function practiceTurnsUsed(row: TrialConsumedRow | null): number {
  return row?.practiceTurns ?? 0;
}

/**
 * Counts one walkthrough turn against the taster row, creating that row if
 * the learner has not started the taster proper yet. `problem_id`/`date`
 * are left NULL: practice does not claim the session, it only spends from
 * the same lifetime allowance.
 */
export async function bumpPracticeTurn(
  db: D1Database,
  installId: string,
  startedAt: string,
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO devices (device_hash, created_at, practice_turns)
       VALUES (?1, ?2, 1)
       ON CONFLICT(device_hash) DO UPDATE SET practice_turns = devices.practice_turns + 1`,
    )
    .bind(installId, startedAt)
    .run();
}

/** Undoes bumpPracticeTurn() when the provider never answered (Constitution VIII). */
export async function releasePracticeTurn(db: D1Database, installId: string): Promise<void> {
  await db
    .prepare(
      "UPDATE devices SET practice_turns = MAX(0, practice_turns - 1) WHERE device_hash = ?1",
    )
    .bind(installId)
    .run();
}

/**
 * Written on the FIRST trial call that reaches the provider — never a
 * hint pull, which reaches none (FR-032a). A session already in flight must
 * not have its started_at, its problem or its date disturbed — those three
 * ARE the session's identity, and isSameTrialSession() reads them on every
 * later call.
 *
 * `sessionsPerDevice` is trial.sessions_per_device. The slot can be taken
 * over by a DIFFERENT problem/day only while sessions_done + 1 (the one the
 * slot holds) is still below it; the takeover retires the old session into
 * trial_sessions_done and clears completed_at for the new one.
 *
 * Every start also adds one to today's trial_day_sessions (0009), which the
 * daily caps sum.
 *
 * Returns false when the row was not written and does not already hold this
 * session: another request took the device's last session between the
 * route's mayClaimAnotherSession() check and this write. The caller must
 * refuse rather than serve a session nothing recorded.
 */
export async function markTrialStarted(
  db: D1Database,
  installId: string,
  startedAt: string,
  problemId: string,
  date: string,
  ipHash: string,
  sessionsPerDevice: number,
): Promise<boolean> {
  const written = await db
    .prepare(
      // DO UPDATE in two cases only (SQLite evaluates every SET against the
      // pre-update row):
      //  1. the row has not claimed the taster — the walkthrough may have
      //     created it (0003) with problem_id/date NULL and completed_at NULL;
      //  2. the slot holds an earlier session (open, completed or pre-0002),
      //     the call names a DIFFERENT problem or day, and the device still
      //     has a session left under ?6. 0002's guarantee holds at the
      //     default of 1: then 0 + 1 < 1 is false, so a claimed row is never
      //     re-pointed. The same problem on the same day is never re-pointed.
      `INSERT INTO devices (device_hash, created_at, trial_started_at, trial_problem_id, trial_date, trial_ip_hash,
                            trial_day_date, trial_day_sessions)
       VALUES (?1, ?2, ?2, ?3, ?4, ?5, ?4, 1)
       ON CONFLICT(device_hash) DO UPDATE
         SET trial_started_at = ?2, trial_problem_id = ?3, trial_date = ?4, trial_ip_hash = ?5,
             trial_completed_at = NULL,
             trial_day_sessions = CASE WHEN devices.trial_day_date IS ?4 THEN devices.trial_day_sessions ELSE 0 END + 1,
             trial_day_date = ?4,
             trial_sessions_done = devices.trial_sessions_done
               + CASE WHEN devices.trial_problem_id IS NULL AND devices.trial_completed_at IS NULL THEN 0 ELSE 1 END
         WHERE (devices.trial_problem_id IS NULL AND devices.trial_completed_at IS NULL)
            OR (NOT (devices.trial_problem_id IS ?3 AND devices.trial_date IS ?4)
                AND devices.trial_sessions_done + 1 < ?6)
       RETURNING device_hash`,
    )
    .bind(installId, startedAt, problemId, date, ipHash, sessionsPerDevice)
    .first();
  if (written) return true;

  // Not written: fine only when the slot already holds this very session
  // (a later turn, or a judge call, of the session in flight).
  const row = await db
    .prepare("SELECT trial_problem_id, trial_date FROM devices WHERE device_hash = ?1")
    .bind(installId)
    .first<{ trial_problem_id: string | null; trial_date: string | null }>();
  return row?.trial_problem_id === problemId && row.trial_date === date;
}

/**
 * Keyed hash of the caller's IP, so `devices` can count sessions per
 * network (IPv6 by /64, see network-key.ts) without ever storing an address. Keyed with the install secret, so
 * the stored value cannot be reversed by hashing the IPv4 space.
 */
export async function hashIp(ip: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`ip:${networkKey(ip)}`));
  return [...new Uint8Array(mac)]
    .slice(0, 16)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/**
 * False once this network has started `trial.ip_daily_session_cap` trial
 * sessions today. 0 disables the cap. Only consulted for a NEW session.
 */
export async function ipSessionGateOk(cfg: RuntimeConfig, db: D1Database, ipHash: string, date: string): Promise<boolean> {
  const cap = cfg.trial.ip_daily_session_cap;
  if (cap <= 0) return true;
  const row = await db
    .prepare(
      "SELECT COALESCE(SUM(trial_day_sessions), 0) AS n FROM devices WHERE trial_ip_hash = ?1 AND trial_day_date = ?2",
    )
    .bind(ipHash, date)
    .first<{ n: number }>();
  return (row?.n ?? 0) < cap;
}

/**
 * Undoes markTrialStarted() when the provider never answered — the trial-path
 * counterpart of refundTurn() and releaseJudgeClaim() (Constitution VIII: what
 * was never served is not spent).
 *
 * Guarded on `started_at`, which markTrialStarted() leaves untouched on an
 * existing row (ON CONFLICT DO NOTHING). So this removes ONLY a row the same
 * call just created; a failed turn in the middle of an established session
 * cannot clear that session. Matters more since 0002: the row pins the
 * taster to one problem on one day, so a claim written by a call that never
 * reached a provider would forfeit the taster outright.
 *
 * UPDATE, never DELETE (006): the `devices` row also holds `created_at` and
 * `practice_turns` and must survive.
 *
 * Takes back the start from today's trial_day_sessions (0009). trial_ip_hash
 * is kept: it still attributes any earlier sessions today to this network.
 */
export async function releaseTrialStart(db: D1Database, installId: string, startedAt: string): Promise<void> {
  await db
    .prepare(
      `UPDATE devices
         SET trial_started_at = NULL, trial_problem_id = NULL, trial_date = NULL,
             trial_day_sessions = MAX(0, trial_day_sessions - 1)
       WHERE device_hash = ?1 AND trial_started_at = ?2 AND trial_completed_at IS NULL`,
    )
    .bind(installId, startedAt)
    .run();
}

export async function markTrialCompleted(db: D1Database, installId: string, completedAt: string): Promise<void> {
  await db
    .prepare("UPDATE devices SET trial_completed_at = ?2 WHERE device_hash = ?1")
    .bind(installId, completedAt)
    .run();
}

/** New sessions started today, across all installs — data-model.md §B8's `sessionsStartedToday()`. */
export async function countSessionsStartedToday(db: D1Database, date: string): Promise<number> {
  const row = await db
    // Only markTrialStarted() writes trial_day_sessions, so a row the
    // walkthrough alone created counts 0 against the operator's cap.
    .prepare("SELECT COALESCE(SUM(trial_day_sessions), 0) AS n FROM devices WHERE trial_day_date = ?1")
    .bind(date)
    .first<{ n: number }>();
  return row?.n ?? 0;
}

/**
 * Reopens the trial slot's judge for the session it already holds, so a
 * verdict lost on the way back can be judged again. Leaves the slot, its
 * started_at and every counter alone: isSameTrialSession() then reads the
 * re-judge as the session in flight, not a new one.
 */
export async function reopenTrialJudge(
  db: D1Database,
  installId: string,
  problemId: string,
  date: string,
): Promise<void> {
  await db
    .prepare(
      `UPDATE devices SET trial_completed_at = NULL
       WHERE device_hash = ?1 AND trial_problem_id = ?2 AND trial_date = ?3`,
    )
    .bind(installId, problemId, date)
    .run();
}

/** Retires a reset session without creating a new activity row. */
export async function resetTrialSession(
  db: D1Database,
  installId: string,
  problemId: string,
  date: string,
): Promise<void> {
  await db
    .prepare(
      `UPDATE devices
       SET trial_sessions_done = trial_sessions_done + 1,
           trial_started_at = NULL,
           trial_problem_id = NULL,
           trial_date = NULL,
           trial_completed_at = NULL,
           trial_ip_hash = NULL
       WHERE device_hash = ?1
         AND trial_problem_id = ?2
         AND trial_date = ?3`,
    )
    .bind(installId, problemId, date)
    .run();
}

/**
 * data-model.md §A5: `trial.daily_session_cap` and `trial.pool[]` are both
 * read here, not in routes/trial.ts — the new-session gate is this
 * module's concern in full. Refuses only a NEW session (the device
 * has not claimed its taster yet); a session already in flight is the caller's
 * to allow regardless of this result.
 */
export async function newSessionGateOk(cfg: RuntimeConfig, db: D1Database, now: Date): Promise<boolean> {
  const member = await selectMember("chat", cfg, db, now);
  if (!member) return false;
  if (cfg.trial.daily_session_cap > 0) {
    const date = now.toISOString().slice(0, 10);
    const startedToday = await countSessionsStartedToday(db, date);
    if (startedToday >= cfg.trial.daily_session_cap) return false;
  }
  return true;
}
