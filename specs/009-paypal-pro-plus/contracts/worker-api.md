# Worker API Contract: Pro Plus (009)

Every error uses the existing envelope and the existing sixteen codes (research.md R-2).
Install-auth routes need `X-Install-Id`, as today.

Mounting, in `worker/src/index.ts`:

```ts
app.use("/v1/pro/*", installAuth);
app.route("/v1/pro", proRoute);                 // routes/pro.ts: GET /status, POST /checkout
app.route("/v1/paypal", paypalWebhookRoute);    // routes/paypal-webhook.ts: POST /webhook — NO installAuth
app.route("/paypal", paypalReturnRoute);        // routes/paypal-return.ts: GET /return, GET /cancel — public HTML, outside /v1 like /privacy
```

---

## 1. `POST /v1/pro/checkout` (install-auth)

**Request**: empty body.

**Steps, in order**:
1. `proConfig(cfg)` is null → `BAD_REQUEST`.
2. `c.env.PRO_RL.limit({ key: deviceHash })` fails → `RATE_LIMITED`.
3. The device already has an entitled row → `200 {"already_active": true}`. No PayPal call.
4. Delete this device's `pending` rows older than 3 h (data-model.md A2).
5. Call PayPal create subscription (contracts/paypal-integration.md §2), with `return_url` =
   `${origin}/paypal/return` and `cancel_url` = `${origin}/paypal/cancel`, where `origin =
   new URL(c.req.url).origin`.
6. PayPal fails, times out, returns no `approve` link, or the link host is not
   `www.sandbox.paypal.com` → `UNCLEAR_RETRY`. No row is written.
7. Insert the `pending` row, then `200 {"approve_url": "<href>"}`.

**Response headers**: `cache-control: private, no-store`.

## 2. `GET /v1/pro/status` (install-auth)

**Steps**:
1. `pro = proConfig(cfg)`. If non-null, recheck this device's rows with PayPal per research.md
   R-12. Rechecks are sequential, best-effort, and errors are swallowed.
2. Build the body.

```json
{
  "offer_enabled": true,
  "plan": "pro",
  "subscription": { "status": "active", "period_end": "2026-11-20T10:00:00Z", "confirmed_at": "2026-10-20T10:00:03Z" },
  "pro_limit": "ok",
  "usage": {
    "sessions_used": 2, "sessions_limit": 5, "sessions_period": "day",
    "voice_seconds_used": 120, "voice_seconds_limit": 900
  },
  "as_of": "2026-10-20T10:05:00Z"
}
```

| Field | Rule |
|---|---|
| `offer_enabled` | `proConfig(cfg) !== null` |
| `plan` | `"pro"` iff `resolveProTier()` is non-null (on, entitled). Capacity does not change `plan` |
| `subscription` | The device's current subscription (data-model.md A2), or `null`. Also sent when Pro is off. The app ignores it then |
| `pro_limit` | Only when `plan = "pro"`: `"capacity"` if `!capacityOk`, else `"sessions_used"` if today's `pro_day_sessions ≥ sessions_per_day`, else `"ok"`. `null` for free |
| `usage`, Pro | `pro_day_sessions` for today (0 if `pro_day_date` ≠ today) / `sessions_per_day`, `"day"`. Voice: `getVoiceSecondsUsed()` / `pro.voice_seconds_per_day` |
| `usage`, free | `trialSessionsClaimed(getTrialConsumed())` / `cfg.trial.sessions_per_device`, `"lifetime"`. Voice: used / `voice.seconds_per_device`, or 0/0 when voice is off |
| `as_of` | `nowIso()` |

**Response headers**: `cache-control: private, no-store`.

## 3. `POST /v1/paypal/webhook` (public, PayPal → relay)

1. Body text over 65,536 bytes, or not valid JSON → `400 BAD_REQUEST`.
2. Any of the five `PAYPAL-*` headers missing → `400 BAD_REQUEST`.
3. Verify (contracts/paypal-integration.md §4). Anything other than `SUCCESS`, or PayPal
   unreachable → `400 BAD_REQUEST`. **Nothing is written.**
4. Find the subscription id:

   | `event_type` | Id is in |
   |---|---|
   | `BILLING.SUBSCRIPTION.*` | `resource.id` |
   | `PAYMENT.SALE.*` | `resource.billing_agreement_id` |
   | anything else | none: `200 {"ok":true}` |

5. The id is not in `pro_subscriptions` → `200 {"ok":true}`. It is not ours, or not bound.
6. Re-read the subscription from PayPal and update the row (research.md R-6). If the re-read fails
   → `500` with the `UNCLEAR_RETRY` envelope, so PayPal redelivers. On success → `200 {"ok":true}`.

**Never**: log the body, store it, or put any part of it in an error (FR-023). Only the
subscription id and the derived status are kept.

## 4. `GET /paypal/return` and `GET /paypal/cancel` (public HTML)

**Query**: PayPal appends `subscription_id`, `ba_token` and `token`. Only `subscription_id` is
read. It must match `^I-[A-Z0-9]{6,40}$`, otherwise it is ignored.

- **`/return`**: if the id is in `pro_subscriptions`, re-read it from PayPal (best-effort, errors
  swallowed).
- **`/cancel`**: if the id is in `pro_subscriptions` with status `pending`, re-read it. If PayPal
  still says `APPROVAL_PENDING`, delete the row.

Both serve `200 text/html; charset=utf-8`, `cache-control: no-store`. This is a minimal page in
the style of `routes/privacy.ts` (inline CSS, no script beyond the one line below):

- `/return`: heading "Back to Dry Run", line "You can close this page and return to the app.",
  link `<a href="dryruntutor://pro/return">Open Dry Run</a>`.
- `/cancel`: heading "Subscription not completed", same link with `?result=cancel`.
- `<script>location.href = "dryruntutor://pro/return…";</script>` as one attempt. The link is the
  real path (research.md R-9).

The product name comes from the same constant `privacy.ts` uses, if one exists. Otherwise the
literal "Dry Run".

## 5. Changes to existing routes

### `POST /v1/trial` (`routes/trial.ts`)

Insert one block **after** the practice-problem branch and **before** the
`gateNewSession`/`consumed` logic. The hint and practice branches stay free and untouched.

```ts
const tier = await resolveProTier(cfg, db, installId, now);
if (tier) {
  const state = await proSessionState(db, installId, body.problem_id, date, tier.pro.sessions_per_day);
  if (state === "in_flight" || (state === "available" && tier.capacityOk)) {
    return servePro(c, body, problem, { db, installId, date, now, cfg, pro: tier.pro, secretFor });
  }
  // else: fall through to the free path unchanged (FR-016). If it refuses, the app reads
  // pro_limit from /v1/pro/status to explain why (research.md R-2).
}
```

`servePro` (in `lib/pro-session.ts`) mirrors the trial chat and judge branches, with these
differences:
- Ledger: `proLedger` for every `runLeg`/settle. Use the pooled-call builder (below).
- `turnCap: cfg.trial.turn_cap`, `groundTruthTier: cfg.trial.ground_truth_tier`,
  `condenseEnabled: cfg.trial.condense`. Per-session limits are unchanged (FR-015).
- Chat: `EMPTY_TURN` check as on the trial path. `onBeforeProviderCall` →
  `claimProSession(...)`. If `refused`, throw `TRIAL_CONSUMED`; if `claimed`, remember it.
  `onProviderCallUnanswered` → `releaseProSession(...)` only if this call claimed.
- Judge: `claimProSession` first (`refused` → `TRIAL_CONSUMED`). Then `runJudge`. On a throw,
  `releaseProSession` if claimed, then rethrow. **No** `markTrialCompleted`, and no `trial_*`
  write anywhere.

**Pooled-call builder**: create `lib/pooled-calls.ts` exporting

```ts
export function pooledCalls(args: { cfg; db; now; secretFor; ledger: BudgetLedger }): {
  streamChat(systemPrompt, messages): Promise<{ stream; providerId; model }>;
  condenseCallOptions(): Promise<{ baseUrl; apiKey; model }>;
  finishCheck(systemPrompt, userContent, jsonSchema): Promise<{ result; providerId; model }>;
  judgeStructuredCompletion(systemPrompt, userContent, jsonSchema): Promise<{ result; providerId; model }>;
}
```

Its bodies are the four closures now inline in `routes/trial.ts` (the `streamChat`,
`condenseCallOptions` and `finishCheck` args, and the judge's `structuredCompletion`), moved
verbatim. The only changes:
- `settleTrialBudget(db, now, id, leg, n)` → `ledger.settle(db, now, id, leg, n)`;
- `runLeg(..., secretFor)` → `runLeg(..., secretFor, ledger)`;
- `selectMember("chat", cfg, db, now)` → `selectMember("chat", cfg, db, now, new Set(), ledger.enforceMemberBudget)`.

`routes/trial.ts` then calls `pooledCalls({ ..., ledger: freeLedger })`. The free path's
behaviour is byte-identical, and every existing `trial*.test.ts` must pass unmodified.

### `POST /v1/stt` (`routes/stt.ts`)

After `voiceConfig(cfg)` passes (voice on):

```ts
const tier = await resolveProTier(cfg, c.env.DB, deviceHash, new Date());
const cap = tier && tier.capacityOk ? tier.pro.voice_seconds_per_day : voice.seconds_per_device;
```

Use `cap` everywhere `voice.seconds_per_device` is used today. Voice off still means
`VOICE_UNAVAILABLE` for everyone. Pro does not turn voice on.

### `POST /v1/repair` (`routes/repair.ts`)

In the no-key branch, pass `proLedger` as the new last argument to `runTrialRepair` when
`resolveProTier()` is non-null and `capacityOk`. Otherwise leave the call exactly as it is.

### `POST /v1/session/reset` (`routes/session-reset.ts`)

In the non-`recover` branch, after `resetTrialSession(...)`, also call
`resetProSession(db, deviceHash, problemId, date)`.

### `GET /v1/config` (`routes/config.ts`)

Strip the server-only `pro` fields. Destructure `pro` out like `voice`, and when it is present add
back:

```json
"pro": { "enabled": true, "price_label": "$4.99 / month", "sessions_per_day": 5,
         "voice_seconds_per_day": 900, "manage_url": "https://www.sandbox.paypal.com/myaccount/autopay/" }
```

### `GET /privacy` (`routes/privacy.ts`)

Add one section before "What we never collect" (FR-024), and bump the page's "last updated" date:

> **Pro Plus (test payments)**
> Pro Plus is billed through PayPal's test environment; no real money moves. Subscribing happens on
> PayPal's own pages, which handle your PayPal login under PayPal's privacy policy. Our server keeps
> only the subscription's id, its status, which device it belongs to, when the current period ends,
> and when we last checked it with PayPal. PayPal also tells us the subscriber's name and email; we
> discard them and never store them.

## 6. Env and bindings (`worker/src/types.ts`, `wrangler.jsonc`, `.dev.vars`)

```ts
// types.ts — Env
PAYPAL_CLIENT_ID: string;      // sandbox REST app; secret only
PAYPAL_CLIENT_SECRET: string;  // sandbox REST app; secret only
PAYPAL_WEBHOOK_ID: string;     // sandbox webhook id; secret only
PRO_RL: RateLimit;             // POST /v1/pro/checkout, per device
```

- `wrangler.jsonc`: add `{ "name": "PRO_RL", "namespace_id": "7005", "simple": { "limit": 5,
  "period": 60 } }` to the top-level, `dev` and `prod` `ratelimits` arrays. Extend the secrets
  comment with the three PayPal names.
- `.dev.vars`: add placeholder values (`PAYPAL_CLIENT_ID="test-client"`,
  `PAYPAL_CLIENT_SECRET="test-secret"`, `PAYPAL_WEBHOOK_ID="WH-TEST"`). These are placeholders
  only, like the existing ones.
