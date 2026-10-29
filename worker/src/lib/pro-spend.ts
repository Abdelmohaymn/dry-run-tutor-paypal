// Pro Plus spend ledger (feature 009, research.md R-3 / R-4, data-model.md A5).
// Operator-key tokens spent by Pro devices live in `pro_spend`, one row per UTC
// day, apart from the free pool's own budget rows so the two tiers never drain
// each other (FR-018). Cooldowns stay with the pool members, because a rate
// limit belongs to the real upstream key both tiers share.
import type { ProConfig, RuntimeConfig } from "./runtime-config";
import { estimateFor, selectMember, type BudgetLedger } from "./trial-pool";

export const proLedger: BudgetLedger = {
  // A pool member whose free daily budget is spent still serves Pro.
  enforceMemberBudget: false,

  async reserve(db, date, _memberId, estimate) {
    await db
      .prepare(
        `INSERT INTO pro_spend (date, tokens_spent) VALUES (?1, ?2)
         ON CONFLICT(date) DO UPDATE SET tokens_spent = pro_spend.tokens_spent + ?2`,
      )
      .bind(date, estimate)
      .run();
  },

  async release(db, date, _memberId, estimate) {
    await db
      .prepare("UPDATE pro_spend SET tokens_spent = MAX(tokens_spent - ?2, 0) WHERE date = ?1")
      .bind(date, estimate)
      .run();
  },

  async settle(db, now, _memberId, leg, actual) {
    await db
      .prepare("UPDATE pro_spend SET tokens_spent = tokens_spent - ?2 + ?3 WHERE date = ?1")
      .bind(now.toISOString().slice(0, 10), estimateFor(leg), actual)
      .run();
  },
};

/**
 * True while Pro may start a NEW session: today's spend is under the daily
 * ceiling, the all-time spend is under the total ceiling, and the pool has a
 * member that is not cooling down. A session already in flight is never
 * gated by this (research.md R-4 "Ceiling semantics").
 */
export async function proCapacityOk(
  pro: ProConfig,
  cfg: RuntimeConfig,
  db: D1Database,
  now: Date,
): Promise<boolean> {
  const date = now.toISOString().slice(0, 10);
  const today = await db
    .prepare("SELECT tokens_spent FROM pro_spend WHERE date = ?1")
    .bind(date)
    .first<{ tokens_spent: number }>();
  if ((today?.tokens_spent ?? 0) >= pro.daily_token_ceiling) return false;

  const total = await db
    .prepare("SELECT COALESCE(SUM(tokens_spent), 0) AS n FROM pro_spend")
    .first<{ n: number }>();
  if ((total?.n ?? 0) >= pro.total_token_ceiling) return false;

  return (await selectMember("chat", cfg, db, now, new Set(), false)) !== null;
}
