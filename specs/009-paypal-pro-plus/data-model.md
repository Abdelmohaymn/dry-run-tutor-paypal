# Data Model: Pro Plus (009)

Part A is the relay (D1 and the config row). Part B is the app. Nothing here stores payer data
(FR-022, SC-007).

---

## Part A — Relay

### A1. Migration `worker/migrations/0013_pro_plus.sql` (new)

```sql
-- 009: Pro Plus (PayPal sandbox). Cap-enforcing data only: no payer name,
-- email, address or payment detail is ever stored (spec FR-022).
CREATE TABLE pro_subscriptions (
  subscription_id TEXT PRIMARY KEY,          -- PayPal "I-..." id
  device_hash     TEXT NOT NULL,             -- devices.device_hash, fixed at checkout (FR-005)
  status          TEXT NOT NULL,             -- research.md R-6 table
  period_end      TEXT,                      -- ISO-8601; NULL until PayPal reports one
  confirmed_at    TEXT NOT NULL              -- last time PayPal was read (or row created)
);
CREATE INDEX pro_subscriptions_device ON pro_subscriptions (device_hash);

-- Operator-key tokens spent by Pro devices, per UTC day. Apart from
-- provider_day so Pro and free never drain each other (FR-018).
CREATE TABLE pro_spend (
  date         TEXT PRIMARY KEY,
  tokens_spent INTEGER NOT NULL DEFAULT 0
);

-- The device's current Pro session and today's count (FR-011).
ALTER TABLE devices ADD COLUMN pro_day_date     TEXT;
ALTER TABLE devices ADD COLUMN pro_day_sessions INTEGER NOT NULL DEFAULT 0;
ALTER TABLE devices ADD COLUMN pro_problem_id   TEXT;
```

The migration does **not** seed a `pro` config block. Absent means off (A3).

### A2. `pro_subscriptions.status`

The values are `pending | approved | active | payment_failed | cancelled | suspended | expired`.
They are derived from PayPal by `deriveStatus()` (research.md R-6). There is no transition logic:
every write is "set to what PayPal says now".

```ts
// worker/src/lib/pro.ts
export function isEntitled(row: { status: string; period_end: string | null }, now: Date): boolean {
  if (row.status === "active") return true;
  if (row.status === "cancelled" && row.period_end !== null) return new Date(row.period_end) > now;
  return false;
}
```

Writes:

| When | Statement |
|---|---|
| Checkout created | `INSERT INTO pro_subscriptions VALUES (?id, ?device, 'pending', NULL, ?now)` |
| Any re-read from PayPal | `UPDATE pro_subscriptions SET status = ?s, period_end = COALESCE(?pe, period_end), confirmed_at = ?now WHERE subscription_id = ?id` |
| `/paypal/cancel`, PayPal still `APPROVAL_PENDING` | `DELETE FROM pro_subscriptions WHERE subscription_id = ?id AND status = 'pending'` |
| Checkout, housekeeping | `DELETE FROM pro_subscriptions WHERE device_hash = ?d AND status = 'pending' AND confirmed_at < ?now_minus_3h` |

The device's **current subscription** (what the status endpoint reports) is the first entitled
row, else the row with the latest `confirmed_at`, else none.

### A3. Config block `pro` (in `worker/src/lib/runtime-config.ts`)

This is optional, like `voice`. Absent or `enabled: false` means Pro is off everywhere (FR-017,
Constitution X.9 "off by default").

```ts
const proSchema = z
  .object({
    enabled: z.boolean(),
    plan_id: z.string().regex(/^P-[A-Z0-9]{8,40}$/),
    price_label: z.string().min(1).max(40),            // "$4.99 / month"
    sessions_per_day: z.number().int().min(1).max(50),
    voice_seconds_per_day: z.number().int().min(0).max(3600),
    daily_token_ceiling: z.number().int().min(0),
    total_token_ceiling: z.number().int().min(0),
    recheck_after_seconds: z.number().int().min(60).default(21600),
    manage_url: z.string().url().startsWith("https://www.sandbox.paypal.com/")
      .default("https://www.sandbox.paypal.com/myaccount/autopay/"),
  })
  .strict();
// in runtimeConfigSchema: `pro: proSchema.optional(),`
export function proConfig(cfg: RuntimeConfig): NonNullable<RuntimeConfig["pro"]> | null {
  return cfg.pro && cfg.pro.enabled ? cfg.pro : null;
}
```

Also add `pro` to `specs/001-proxy-content-contract/contracts/config.schema.json`, mirroring the
Zod above, so `runtime-config.test.ts` and the schema stay in step.

The starting values are in quickstart.md §3 and research.md R-4.

`GET /v1/config` serves `pro` **without** `plan_id`, `daily_token_ceiling`,
`total_token_ceiling` or `recheck_after_seconds`. When `pro` is absent, it stays absent.

### A4. Pro session slot on `devices`

A Pro session is one problem on one UTC day, the same identity the free path uses.

| Function (`worker/src/lib/pro-session.ts`) | Behaviour |
|---|---|
| `proSessionState(db, device, problemId, date, cap): "in_flight" \| "available" \| "sessions_used"` | `in_flight` when `pro_problem_id = problemId AND pro_day_date = date`. Otherwise `available` while today's count is below `cap`, else `sessions_used` |
| `claimProSession(db, device, problemId, date, cap, nowIso): "in_flight" \| "claimed" \| "refused"` | One statement, below. Returns `in_flight` when the slot already holds this session |
| `releaseProSession(db, device, problemId, date)` | Undoes a `claimed` whose provider never answered (Constitution VIII): `pro_day_sessions = MAX(0, pro_day_sessions - 1), pro_problem_id = NULL WHERE device_hash = ?1 AND pro_problem_id = ?2 AND pro_day_date = ?3` |
| `resetProSession(db, device, problemId, date)` | Called by `POST /v1/session/reset` (`reason` ≠ `recover`): `pro_problem_id = NULL WHERE …matches…`. The count is **not** refunded, so a replay is a new Pro session |

```sql
-- claimProSession
INSERT INTO devices (device_hash, created_at, pro_problem_id, pro_day_date, pro_day_sessions)
VALUES (?1, ?5, ?2, ?3, 1)
ON CONFLICT(device_hash) DO UPDATE SET
  pro_day_sessions = CASE WHEN devices.pro_day_date IS ?3 THEN devices.pro_day_sessions ELSE 0 END + 1,
  pro_problem_id   = ?2,
  pro_day_date     = ?3
WHERE NOT (devices.pro_problem_id IS ?2 AND devices.pro_day_date IS ?3)
  AND CASE WHEN devices.pro_day_date IS ?3 THEN devices.pro_day_sessions ELSE 0 END < ?4
RETURNING device_hash
```

If nothing is returned, re-select the slot. Matching `(problemId, date)` → `in_flight`; anything
else → `refused`.

The Pro branch never reads or writes any `trial_*` column, so Pro sessions never count toward
`trial.sessions_per_device` (research.md R-5).

### A5. Spend ledger (`worker/src/lib/pro-spend.ts` + `trial-pool.ts`)

```ts
// trial-pool.ts
export interface BudgetLedger {
  /** false: selectMember skips the member's own daily_token_budget check (cooldown still applies). */
  readonly enforceMemberBudget: boolean;
  reserve(db: D1Database, date: string, memberId: string, estimate: number): Promise<void>;
  release(db: D1Database, date: string, memberId: string, estimate: number): Promise<void>;
  settle(db: D1Database, now: Date, memberId: string, leg: TrialLeg, actual: number): Promise<void>;
}
export const freeLedger: BudgetLedger;   // today's reserveEstimate/releaseEstimate/settleTrialBudget bodies
```

`proLedger` (in `pro-spend.ts`) ignores `memberId` and writes `pro_spend`:
- **reserve**: `INSERT INTO pro_spend (date, tokens_spent) VALUES (?1, ?2) ON CONFLICT(date) DO UPDATE SET tokens_spent = pro_spend.tokens_spent + ?2`
- **release**: `UPDATE pro_spend SET tokens_spent = MAX(tokens_spent - ?2, 0) WHERE date = ?1`
- **settle**: `UPDATE pro_spend SET tokens_spent = tokens_spent - ?2 + ?3 WHERE date = ?1`, with estimate `estimateFor(leg)` → export `estimateFor` from `trial-pool.ts`

```ts
// pro-spend.ts
export async function proCapacityOk(pro: ProConfig, cfg: RuntimeConfig, db: D1Database, now: Date): Promise<boolean>
// true iff today's pro_spend < pro.daily_token_ceiling
//      AND SUM(pro_spend.tokens_spent) < pro.total_token_ceiling
//      AND selectMember("chat", cfg, db, now, new Set(), false) !== null
```

`settleTrialBudget()` stays exported with its current signature and is used by
`lib/practice-turn.ts` unchanged. `freeLedger.settle` calls it.

### A6. Entitlement in one call

```ts
// worker/src/lib/pro.ts
export interface ProTier {
  pro: ProConfig;            // proConfig(cfg), non-null
  capacityOk: boolean;       // proCapacityOk(...)
}
/** null unless Pro is on AND this device has an entitled subscription. One D1 read + the capacity reads. */
export async function resolveProTier(cfg: RuntimeConfig, db: D1Database, deviceHash: string, now: Date): Promise<ProTier | null>
```

Used by `routes/trial.ts`, `routes/stt.ts`, `routes/repair.ts` and `routes/pro.ts`.

---

## Part B — App

### B1. Config (`lib/core/network/dto/config_dto.dart`, `lib/core/config/runtime_config.dart`)

`ProConfigDto` (json_serializable, `fieldRename: snake`, the same style as `VoiceConfigDto`) has
`enabled`, `priceLabel`, `sessionsPerDay`, `voiceSecondsPerDay` and `manageUrl`. `ConfigDto` gains
`final ProConfigDto? pro;`. `RuntimeConfig` gains `final ProConfig? pro`, mapped in `fromDto`
like `voice`: a null DTO or `enabled: false` gives `null`. Add `pro` to `props`.

### B2. `PlanStatus` (`lib/features/plan/domain/plan_status.dart`)

This is a plain immutable class with Equatable, built from the DTO of `GET /v1/pro/status`
(contracts/worker-api.md §2).

```dart
enum PlanKind { free, pro }
enum SubscriptionState { pending, approved, active, paymentFailed, cancelled, suspended, expired }
enum ProLimit { ok, sessionsUsed, capacity }
enum SessionsPeriod { day, lifetime }

class PlanStatus extends Equatable {
  final bool offerEnabled;
  final PlanKind plan;
  final SubscriptionState? subscription;   // null: never subscribed on this device
  final DateTime? periodEnd;               // UTC, from the relay
  final ProLimit? proLimit;                // null unless plan == pro
  final int sessionsUsed, sessionsLimit;
  final SessionsPeriod sessionsPeriod;
  final int voiceSecondsUsed, voiceSecondsLimit;
  final DateTime asOf;                     // relay time of this answer; shown as "last checked"
}
```

An unknown enum string from the wire is parsed as `null` (subscription) or `ok` (limit). It is
never a crash.

### B3. Cache

`PlanRepositoryImpl` keeps the last `GET /v1/pro/status` JSON in `SharedPreferences` under
`plan.last_status`. `cached()` returns it parsed, or `null`. The cache is for display only (the
offline Plan screen). It is never used to grant anything (spec Edge Cases).

### B4. `PlanState` (freezed, `lib/features/plan/presentation/plan_state.dart`)

```dart
@freezed
sealed class PlanState with _$PlanState {
  const factory PlanState.loading() = PlanLoading;
  const factory PlanState.ready({required PlanStatus status, required bool ownKey, required bool stale, PlanNotice? notice}) = PlanReady;
  const factory PlanState.checkingOut() = PlanCheckingOut;        // POST in flight, then browser open
  const factory PlanState.awaitingReturn() = PlanAwaitingReturn;  // browser open, waiting for resume
  const factory PlanState.confirming({required int elapsedSeconds}) = PlanConfirming;
  const factory PlanState.unavailable() = PlanUnavailable;        // first load failed, no cache
}
enum PlanNotice { activated, notCompleted, paypalUnavailable, alreadyActive }
```

`ownKey` = `KeyRepository.read() != null`. `stale` = served from the cache after a failed refresh.

### B5. Local Drift

There is no Drift change. The plan is not learner data and is not kept beyond the one prefs entry.
