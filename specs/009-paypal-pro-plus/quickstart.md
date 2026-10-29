# Quickstart & Validation: Pro Plus (009)

This guide covers validation only. The design lives in [data-model.md](data-model.md) and
[contracts/](contracts/).

## 1. Gates (every PR, no credentials)

```bash
cd worker && npm run typecheck && npm test        # unit + contract, PayPal stubbed
cd .. && flutter analyze                          # zero issues
LD_LIBRARY_PATH=/tmp/shim flutter test            # see README for the shim
```

SC-006: every pre-existing test passes **unmodified**. The one exception is
`test/unit/router_guards_test.dart` 22 → 23 (research.md R-15).

## 2. New Worker tests (must exist and pass)

| File | Proves |
|---|---|
| `test/unit/paypal-sandbox-only.test.ts` | `WORKER_SOURCE` contains no `api-m.paypal.com`, `api.paypal.com` or `www.paypal.com` (R-10) |
| `test/unit/paypal-derive.test.ts` | `deriveStatus` matches every row of research.md R-6, including `ACTIVE` + `failed_payments_count: 1` → `payment_failed` |
| `test/unit/pro-entitlement.test.ts` | `isEntitled`: active yes; cancelled with a future `period_end` yes, past no, null no; suspended / expired / payment_failed / pending / approved no |
| `test/unit/pro-session.test.ts` | `claimProSession`: first call `claimed`; same problem and day `in_flight` (count unchanged); new problem `claimed` until `cap`, then `refused`; a new day resets the count; `releaseProSession` refunds; `resetProSession` keeps the count |
| `test/unit/pro-spend.test.ts` | `proLedger` reserve/settle/release write only `pro_spend`, never `provider_day.tokens_spent`; `proCapacityOk` false at the daily ceiling, false at the total ceiling, false with no eligible member |
| `test/unit/runtime-config.pro.test.ts` | `pro` absent parses; full block parses; `manage_url` on a non-sandbox host is rejected; `proConfig()` returns null when disabled |
| `test/contract/config.pro-lever.test.ts` | `/v1/config` serves `pro` without `plan_id`, ceilings or `recheck_after_seconds`; absent stays absent |
| `test/contract/pro.checkout.test.ts` | Off → `BAD_REQUEST`; on → `approve_url` and a `pending` row bound to this device; already entitled → `already_active` with no PayPal call; PayPal 500 → `UNCLEAR_RETRY` and no row; approve host not sandbox → `UNCLEAR_RETRY` |
| `test/contract/pro.status.test.ts` | Free usage shape (lifetime); a pending row is rechecked and becomes active; a fresh active row is **not** rechecked (no intercept registered); a stale one is; PayPal failure serves the stored row; `pro_limit` is `capacity` / `sessions_used` / `ok` |
| `test/contract/pro.webhook.test.ts` | Bad signature → 400 and no change (SC-004); missing header → 400; good signature + `BILLING.SUBSCRIPTION.SUSPENDED` → re-read → `suspended`; the same event twice → same result; a late `ACTIVATED` after a cancel still converges on PayPal's current `CANCELLED` (FR-008); `PAYMENT.SALE.COMPLETED` uses `billing_agreement_id`; unknown id → 200 and no write; the body is never stored (scan D1 for the event's `email_address` value — SC-007) |
| `test/contract/pro.return-pages.test.ts` | `/paypal/return` re-reads a known id and serves HTML with `dryruntutor://pro/return`; `/paypal/cancel` deletes a still-`APPROVAL_PENDING` row; a malformed `subscription_id` is ignored |
| `test/contract/trial.pro.test.ts` | Pro device: a session beyond `trial.sessions_per_device` is served; spend lands in `pro_spend`, `provider_day.tokens_spent` unchanged (FR-018); `trial_*` columns untouched; `sessions_per_day` reached → falls to the free path (gets `TRIAL_CONSUMED` once free is spent); ceiling reached → a new session falls to free, but an **in-flight** Pro session still serves; Pro off → identical to free; turn cap still `trial.turn_cap` (FR-015); a provider failure releases the claimed Pro session |
| `test/contract/stt.pro.test.ts` | A Pro device gets `voice_seconds_per_day`; at capacity it gets the free cap; voice off → `VOICE_UNAVAILABLE` even for Pro |
| `test/contract/session-reset.pro.test.ts` | Reset clears `pro_problem_id` and does not refund `pro_day_sessions` |

## 3. Sandbox setup (once, by the owner)

1. Go to developer.paypal.com → Apps & Credentials → **Sandbox** → create a REST app. Note the
   client id and secret.
2. Create the plan:

   ```bash
   cd worker
   PAYPAL_CLIENT_ID=… PAYPAL_CLIENT_SECRET=… npm run paypal:setup   # prints P-…
   ```

3. Add a webhook to the sandbox app. URL `https://<worker host>/v1/paypal/webhook`. Events:
   `BILLING.SUBSCRIPTION.ACTIVATED`, `.CANCELLED`, `.SUSPENDED`, `.RE-ACTIVATED`, `.EXPIRED`,
   `.PAYMENT.FAILED`, `.UPDATED`, and `PAYMENT.SALE.COMPLETED`. Note the webhook id.
4. Set the secrets, entering each one interactively and never in a file:

   ```bash
   npx wrangler secret put PAYPAL_CLIENT_ID --env dev
   npx wrangler secret put PAYPAL_CLIENT_SECRET --env dev
   npx wrangler secret put PAYPAL_WEBHOOK_ID --env dev
   ```

5. Apply the migration: `npx wrangler d1 migrations apply dry-run-tutor-dev --env dev --remote`.
6. Create a sandbox **Personal** account (Sandbox → Accounts) for judges. Don't change its
   password after it is published.
7. Before turning Pro on, re-read research.md R-4's budget note and set the ceilings against the
   remaining Token Factory credit. Then turn it on:

   ```bash
   npx wrangler d1 execute dry-run-tutor-dev --env dev --remote --command "UPDATE config SET payload = json_set(payload, '\$.pro', json('{\"enabled\":true,\"plan_id\":\"P-XXXX\",\"price_label\":\"\$4.99 / month\",\"sessions_per_day\":5,\"voice_seconds_per_day\":900,\"daily_token_ceiling\":1875000,\"total_token_ceiling\":37500000}')), updated_at = datetime('now') WHERE id = 1"
   ```

   Kill switch: `json_set(payload, '$.pro.enabled', json('false'))`.

Do the same for prod (`--env prod`, `dry-run-tutor`) only after the APK that uses Pro is
published. Turn the lever on last.

## 4. End-to-end scenarios (device + dev relay)

| # | Steps | Expected |
|---|---|---|
| E1 (US1, SC-001/002) | Fresh install. Settings → Plan → Subscribe → log in with the sandbox buyer → approve → return | "Pro Plus is active" within 10 s; Plan shows Pro limits; a session runs with no key |
| E2 (US1-3) | Subscribe → Cancel on PayPal's page (or back out) | "Subscription not completed", no error style, still Free |
| E3 (US1-4) | Approve, then return immediately | "Confirming with PayPal…" then active, within 60 s |
| E4 (US2) | `npm run paypal:admin -- suspend I-…` | Within seconds of the webhook, the next `/v1/trial` new session is served free; Plan shows ended |
| E5 (US2-3) | `paypal:admin -- activate I-…` | Pro returns on the next request |
| E6 (US2-2) | Plan → Manage or cancel → cancel in PayPal | Plan shows "Ends on <date>"; Pro still serves until then |
| E7 (US4-2) | Two phones, the same sandbox buyer | Each phone gets its own subscription; cancelling one leaves the other Pro |
| E8 (US5) | Set `daily_token_ceiling` to 1, then run one Pro session | The next new session gets free behaviour; when free refuses, the prompt shows the Pro capacity copy |
| E9 (US5-2) | `pro.enabled` false | No offer anywhere; the Pro device is served free; nothing errors |
| E10 (FR-013) | Pro device adds its own key | The new session runs keyed; Plan says "Your own key" |
| E11 (webhook missed) | Delete the webhook in the dashboard, suspend via admin, open Plan | The status recheck (stale row or pending) catches it after `recheck_after_seconds`. Set it to 60 for this test |

Read D1 after E1–E6 to confirm SC-007:
`SELECT * FROM pro_subscriptions` shows only id / device / status / period_end / confirmed_at.

## 5. README (FR-025)

Add a "Pro Plus (PayPal sandbox)" subsection to README "For judges" containing:
- the sandbox buyer email and password;
- the steps from E1, with a note that this is PayPal's test environment and no money moves;
- a statement that Pro Plus is new work during the PayPal hackathon's submission period.

Add the new routes and secrets to `worker/README.md`'s lever table, and a "Pro lever" section in
the style of "Voice lever".
