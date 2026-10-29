// Pro Plus entitlement (feature 009, data-model.md A2 / A6, research.md R-6 / R-12).
// Entitlement is derived from PayPal's own subscription object: every signal
// (webhook, return page, stale status check) re-reads the subscription and
// stores what PayPal says now. There is no transition logic to get wrong.
import type { Env } from "../types";
import { deriveStatus, getSubscription } from "./paypal";
import { proConfig, type ProConfig, type RuntimeConfig } from "./runtime-config";
import { proCapacityOk } from "./pro-spend";

export interface ProSubscriptionRow {
  subscription_id: string;
  device_hash: string;
  status: string;
  period_end: string | null;
  confirmed_at: string;
}

/** Active, or cancelled but paid up to a future `period_end` (FR-009). */
export function isEntitled(row: { status: string; period_end: string | null }, now: Date): boolean {
  if (row.status === "active") return true;
  if (row.status === "cancelled" && row.period_end !== null) return new Date(row.period_end) > now;
  return false;
}

async function rowsFor(db: D1Database, deviceHash: string): Promise<ProSubscriptionRow[]> {
  const { results } = await db
    .prepare(
      "SELECT subscription_id, device_hash, status, period_end, confirmed_at FROM pro_subscriptions WHERE device_hash = ?1 ORDER BY confirmed_at DESC",
    )
    .bind(deviceHash)
    .all<ProSubscriptionRow>();
  return results;
}

/** The device's current subscription: the first entitled row, else the latest `confirmed_at`, else null. */
export async function currentSubscription(
  db: D1Database,
  deviceHash: string,
  now: Date,
): Promise<ProSubscriptionRow | null> {
  const rows = await rowsFor(db, deviceHash);
  return rows.find((r) => isEntitled(r, now)) ?? rows[0] ?? null;
}

/**
 * Re-reads one subscription from PayPal and stores the derived status. Throws
 * (UNCLEAR_RETRY) when PayPal cannot be read, leaving the row unchanged.
 */
export async function refreshSubscription(
  env: Env,
  db: D1Database,
  subscriptionId: string,
  now: Date,
): Promise<{ status: string; periodEnd: string | null }> {
  const view = await getSubscription(env, subscriptionId);
  const { status, periodEnd } = deriveStatus(view);
  await db
    .prepare(
      `UPDATE pro_subscriptions
         SET status = ?2, period_end = COALESCE(?3, period_end), confirmed_at = ?4
       WHERE subscription_id = ?1`,
    )
    .bind(subscriptionId, status, periodEnd, now.toISOString())
    .run();
  return { status, periodEnd };
}

/**
 * R-12: re-reads every row of this device that is pending or approved, or whose
 * last PayPal read is older than `pro.recheck_after_seconds`. Sequential and
 * best-effort: a PayPal failure leaves the stored row as it is.
 */
export async function recheckDevice(
  env: Env,
  db: D1Database,
  deviceHash: string,
  pro: ProConfig,
  now: Date,
): Promise<void> {
  const staleBefore = now.getTime() - pro.recheck_after_seconds * 1000;
  for (const row of await rowsFor(db, deviceHash)) {
    const settling = row.status === "pending" || row.status === "approved";
    if (!settling && new Date(row.confirmed_at).getTime() >= staleBefore) continue;
    try {
      await refreshSubscription(env, db, row.subscription_id, now);
    } catch {
      // Best effort (R-12).
    }
  }
}

export interface ProTier {
  /** `proConfig(cfg)`, non-null. */
  pro: ProConfig;
  /** `proCapacityOk(...)`: whether a NEW Pro session may start. */
  capacityOk: boolean;
}

/** null unless Pro is on AND this device has an entitled subscription. One D1 read + the capacity reads. */
export async function resolveProTier(
  cfg: RuntimeConfig,
  db: D1Database,
  deviceHash: string,
  now: Date,
): Promise<ProTier | null> {
  const pro = proConfig(cfg);
  if (!pro) return null;
  const sub = await currentSubscription(db, deviceHash, now);
  if (!sub || !isEntitled(sub, now)) return null;
  return { pro, capacityOk: await proCapacityOk(pro, cfg, db, now) };
}
