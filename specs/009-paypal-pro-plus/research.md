# Research: Pro Plus (009)

Every decision below is final for the implementer. Each one names what was chosen, why, and what
was rejected. PayPal field names were checked against PayPal's published OpenAPI files
(`developer.paypal.com/api/subscriptions/v1/schema.json`, `.../webhooks/v1/schema.json`) on
2026-10-20.

---

## R-1. Pro rides on `POST /v1/trial`, decided per request on the server

**Decision**: A Pro device uses the free (trial) path exactly as today, from the app's side. On
each `/v1/trial` call the Worker checks whether the device has an entitled subscription. If so,
the call is served under Pro rules (Pro session count, Pro spend ledger). If not, or if Pro
capacity is used up for a new session, the existing free code runs unchanged.

**Rationale**:
- The app picks trial vs keyed once, at session creation (`lib/features/chat/data/session_repository_impl.dart:110-111`:
  trial when `KeyRepository.read()` is null). A learner with a key stays keyed, so FR-013 ("key
  takes precedence") holds with no app routing change.
- The relay decides Pro, never the app (FR-004, spec Edge Cases "Pro is never granted from the
  device's own record").
- No new chat/judge endpoint means no change to `RelayClient.trialChat`/`trialJudge`, the outbox
  replay (`lib/core/queue/outbox_drain_bloc.dart:169,205`), or the session path enum.

**Rejected**:
- A new `/v1/pro` chat/judge route: duplicates ~300 lines of `routes/trial.ts` and needs a third
  app path through every repository and the outbox.
- An app-side "Pro path": the app would be asserting entitlement.

## R-2. No new error codes

**Decision**: The closed set of sixteen codes (`worker/src/lib/errors.ts`) stays at sixteen.
- A Pro device that falls back to free and is refused gets the free path's own code
  (`TRIAL_CONSUMED`, `TRIAL_UNAVAILABLE`, `TRIAL_IP_LIMIT`). The app then refreshes
  `GET /v1/pro/status` and, when that says the device is Pro, shows Pro copy instead of the
  free-taster copy, using `pro_limit` (`sessions_used` or `capacity`).
- Checkout errors reuse existing codes: Pro switched off or misconfigured → `BAD_REQUEST`; PayPal
  unreachable or non-2xx → `UNCLEAR_RETRY`; too many checkouts → `RATE_LIMITED`.

**Rationale**: SC-006 says every existing relay and app test passes unmodified.
`worker/test/unit/errors.test.ts` asserts exactly sixteen codes, and the app's `RelayError` is a
sealed union switched without `default:` everywhere (`lib/core/errors/relay_error.dart`). New
codes would force edits in both.

**Rejected**: `PRO_CAPACITY` and `PRO_SESSIONS_USED` codes. They are clearer on the wire, but they
cost two contract tests and every `RelayError` switch site.

## R-3. Separate spend ledger: `pro_spend`, through a `BudgetLedger` parameter

**Decision**: `runLeg()` and `runTrialRepair()` in `worker/src/lib/trial-pool.ts` gain an optional
last parameter `ledger: BudgetLedger = freeLedger`. `freeLedger` is today's
`provider_day.tokens_spent` reserve/release/settle code, moved behind the interface. `proLedger`
(new, `worker/src/lib/pro-spend.ts`) writes the same estimates to a new `pro_spend(date,
tokens_spent)` table. `selectMember()` gains an optional `enforceBudget = true` parameter, and
`proLedger` calls set it to `false`. That way a free pool member whose free daily budget is spent
still serves Pro, and Pro spend never fills a member's free budget (FR-018). Cooldowns stay on
`provider_day` for both, because a rate limit belongs to the real upstream key, which both tiers
share.

**Rationale**: It reuses the pool's routing and retry code (RATE_LIMITED, timeouts, tryElsewhere)
as it is. The default parameters leave every existing call site and test byte-identical.

**Rejected**:
- Prefixing `provider_id` with `pro:` in `provider_day`. It mixes the cooldown rows and makes
  `selectMember` read the wrong row.
- A second pool config for Pro. That means two copies of the same keys to keep in sync.

## R-4. Spend ceilings are in tokens, sized from Nebius prices

**Decision**: `pro.daily_token_ceiling` and `pro.total_token_ceiling`, in tokens (input + output,
as `settleTrialBudget` already counts). `total` is `SUM(tokens_spent)` over all `pro_spend`
rows. The operator resets the campaign by deleting rows.

Conversion: Nemotron 3 Super on Token Factory costs $0.30/1M input and $0.90/1M output. The
working blend is ~$0.40/1M (`hackathon/judging-plan.md` §Budget).

| Spec figure | Tokens at $0.40/1M | Config value |
|---|---|---|
| $0.75 / day | 1,875,000 | `daily_token_ceiling: 1875000` |
| $15 total | 37,500,000 | `total_token_ceiling: 37500000` |

**Rationale**: The Worker never sees dollars. Every existing budget (`daily_token_budget`) is
already in tokens.

**Ceiling semantics**: the ceiling gates **new** Pro sessions only. A Pro session already in flight
runs to its end, mirroring the free path's FR-032d. Worst-case overshoot is the sessions in flight
× ~100k tokens (≈ $0.04 each). The spec's US5 test ("the next Pro request after one session is
served free") holds, because that next request is a new session.

> **Owner decision still open: total credit.** Two things draw on the same Nebius credit, even
> with separate deployments (R-16), because both use the operator's one Nebius key. The
> Nebius judging plan sizes the **free** budget at 3,000,000 tokens/day (~$1.20/day, ~$18 over
> Dec 1–15). The spec allows Pro up to $15 total. Together that is more than the ~$20 the spec
> says is left. The code is the same whatever the numbers are, so the levers ship and the owner
> sets them. Before enabling `pro`, read the remaining credit in the Token Factory console. Then
> set `trial.pool[*].daily_token_budget + pro.daily_token_ceiling` so that
> (remaining credit ÷ $0.40/1M) ÷ days left to 2026-12-15 is not exceeded.

## R-5. The free path in prod is not "one lifetime session"

**Finding**: The spec's Assumptions say the free path is a "single lifetime trial session". It is
not. The Nebius rules require the app to be usable "free of charge and without any restriction"
until 2026-12-15, so prod runs `trial.sessions_per_device: 50`, `ip_daily_session_cap: 0`, and
"Practice this problem again" (`hackathon/judging-plan.md` §1).

**Decision (revised 2026-10-22)**: Leave the Nebius prod deployment untouched, and run Pro Plus on
a **separate deployment** with its own free levers (R-16). Tightening the free path on prod would
risk the Nebius entry; tightening it on a PayPal-only deployment does not.

On the PayPal deployment the free path is deliberately smaller, so Pro is a real difference:

| Lever | Nebius prod | PayPal free | PayPal Pro |
|---|---|---|---|
| `trial.sessions_per_device` (lifetime) | 50 | 3 | not counted |
| Sessions per day | effectively unlimited | 1 (today's problem) | `pro.sessions_per_day` (5) |
| Practice again / problem picker | everyone | off (shows the offer) | on |
| `voice.seconds_per_device` | 1200 | 300 | `pro.voice_seconds_per_day` (900) |
| `trial.practice_turn_cap` | 10 | 5 | 10 |
| `trial.ip_daily_session_cap` | 0 (off) | 15 | not counted |

Pro also keeps its own budget: when the free budget is spent, Pro devices keep practising, and Pro
sessions never touch `trial_sessions_done`.

**Code consequence**: "Practice again", the problem picker and `POST /v1/session/reset` shipped
with no switch (`hackathon/judging-plan.md` §2). One lever, `trial.replay_enabled` (default
`true`, so Nebius prod is unchanged), gates the **free trial path** only: with it off, a free
device's new session must be today's daily problem, and not after a reset today
(`devices.replay_reset_date`). Keyed devices never call `/v1/trial`, and Pro devices are served
before the gate, so neither is affected. The app's `ReplayGate` shows the Pro Plus offer before
calling the relay, so a free learner never spends a reset on a refusal. Full design: tasks.md
"Replay lever design".

The Plan screen shows the real numbers from the relay, so it never claims a difference that does
not exist. The owner should correct the spec's Assumptions line (not done here).

## R-6. Entitlement is derived from PayPal's own subscription object

**Decision**: On every signal (webhook, return page, status recheck), the Worker re-reads
`GET /v1/billing/subscriptions/{id}` and derives our stored status from it.

| PayPal `status` | Extra condition | Stored `status` | Entitled? |
|---|---|---|---|
| `APPROVAL_PENDING` | — | `pending` | no |
| `APPROVED` | — | `approved` | no (activation follows in seconds) |
| `ACTIVE` | `billing_info.failed_payments_count > 0` | `payment_failed` | no (FR-009) |
| `ACTIVE` | otherwise | `active` | yes |
| `CANCELLED` | — | `cancelled` | yes while `period_end > now` (FR-009) |
| `SUSPENDED` | — | `suspended` | no |
| `EXPIRED` | — | `expired` | no |

`period_end` = `billing_info.next_billing_time` when present. Otherwise it is kept from the stored
row (`COALESCE`), because PayPal drops `next_billing_time` once a subscription is cancelled. A
cancelled row with no `period_end` ever stored is not entitled.

**Rationale**:
- **Order-safe and idempotent by construction (FR-008).** A webhook is only a trigger to re-read,
  never a state change. Duplicates and late arrivals converge on PayPal's current truth.
- **A missed webhook heals** on the next status check (FR-010).

**Rejected**: Applying webhook events as state transitions. That needs event ordering,
`status_update_time` comparisons, and dedupe storage.

## R-7. Webhook verification: PayPal's verify API, raw body spliced in

**Decision**: `POST /v1/paypal/webhook` reads the raw body as text (refuse > 64 KiB), checks
`JSON.parse` succeeds, then calls `POST {SANDBOX}/v1/notifications/verify-webhook-signature`. The
body is built by string concatenation, so the event bytes are passed unchanged:

```
{"auth_algo":<json str>,"cert_url":<json str>,"transmission_id":<json str>,
 "transmission_sig":<json str>,"transmission_time":<json str>,"webhook_id":<json str>,
 "webhook_event":<RAW BODY TEXT>}
```

The header sources are `PAYPAL-AUTH-ALGO`, `PAYPAL-CERT-URL`, `PAYPAL-TRANSMISSION-ID`,
`PAYPAL-TRANSMISSION-SIG` and `PAYPAL-TRANSMISSION-TIME`. Only `verification_status ===
"SUCCESS"` proceeds. Anything else (missing header, `FAILURE`, PayPal unreachable) → 400 and no
row changes (FR-007, SC-004).

**Rationale**: Re-serialising a parsed event changes key order or number formatting, and the
signature then fails. Offline verification (CRC32 plus an X.509 certificate chain in a Worker)
is far more code to get right.

**Known sandbox caveat**: events sent from the Developer Dashboard's *Webhooks Simulator* do not
verify. Test with real sandbox events: subscribe, then suspend, activate and cancel through
`worker/tools/paypal-admin.ts` (quickstart §4).

## R-8. Device binding at creation; the client never presents a subscription id

**Decision**: `POST /v1/pro/checkout` (install-auth) creates the PayPal subscription
server-to-server and immediately inserts `(subscription_id, device_hash, 'pending', NULL, now)`.
No endpoint accepts a subscription id from the app. `GET /paypal/return` and `GET /paypal/cancel`
read `subscription_id` from PayPal's redirect, but only to **re-read that id from PayPal** when it
already exists in `pro_subscriptions`. They never bind or rebind it.

**Rationale**: FR-005 holds structurally: one subscription has exactly one device, fixed when the
checkout is created. A subscription id copied to another phone does nothing. Nothing about the
device is sent to PayPal (no `custom_id`).

**Rejected**: Sending the device hash as `custom_id` and binding on webhook. That sends a device
identifier to a third party for no gain.

## R-9. Return to the app: resume polling, plus a best-effort deep link

**Decision**:
- **Checkout**: the app opens the `approve` link with
  `launchUrl(uri, mode: LaunchMode.externalApplication)`. `url_launcher ^6.3.2` is already a
  dependency, used the same way in `lib/core/update/update_required_screen.dart:62`.
- **After the approval page**: PayPal redirects to `https://<worker>/paypal/return` (or
  `/paypal/cancel`). The Worker re-reads the subscription, then serves a tiny HTML page. It has a
  "Back to Dry Run" link to `dryruntutor://pro/return`, and the same URL is attempted once on
  load. The scheme is already declared: `android/app/src/main/AndroidManifest.xml:44-49`,
  `deepLinkScheme = "dryruntutor"`.
- **The source of truth on return**: the Plan screen listens with `AppLifecycleListener`. On
  `resumed` while a checkout is open, `PlanCubit.onResumed()` calls `GET /v1/pro/status`:
  - entitled → **Active**;
  - `approved` → **Confirming**, poll every 3 s for up to 60 s (US1-4);
  - `pending`, or no subscription → **Not completed** at once (US1-3). PayPal sets `APPROVED`
    before it redirects, so `APPROVAL_PENDING` after return means the learner did not approve.
- **The deep link**: `GoRoute(path: '/pro/return', redirect: (_, _) =>
  AppRoute.settingsPlan.path)`, next to the existing `/p/:problemId` (`app_router.dart:275`). On a
  cold launch it opens the Plan screen. On a warm one, Android brings the app forward and
  `resumed` does the rest. No native `onNewIntent` work is needed.

**Rationale**: Chrome may block a custom-scheme redirect that has no user gesture. The deep link is
a convenience; resume polling is what makes SC-002 hold.

**`return_url`/`cancel_url`**: these are set in `application_context`. PayPal's schema marks it
`deprecated` but it is still accepted, and the Subscriptions v1 schema offers no replacement for
PayPal-wallet subscriptions (`subscriber.payment_source` lists only `card`). Use it. If PayPal
ignores it, the learner returns by the back button and resume polling still works.

## R-10. Sandbox-only by construction

**Decision**: The PayPal API base is a constant, `PAYPAL_API_BASE =
"https://api-m.sandbox.paypal.com"`, in `worker/src/lib/paypal.ts`. It is not configurable. A new
unit test, `paypal-sandbox-only.test.ts`, scans `WORKER_SOURCE` (the binding
`vitest.config.ts` already injects for `operator-key.test.ts`) and fails on `api-m.paypal.com`,
`api.paypal.com` and `www.paypal.com`. The checkout also refuses an `approve` href whose host is
not `www.sandbox.paypal.com`.

**Rationale**: Constitution X.9, "No build, config, or secret may contain live PayPal
credentials". Pointing at live would take a code change, and that change fails a test.

## R-11. PayPal OAuth token: per-isolate cache

**Decision**: `getAccessToken(env)` posts `grant_type=client_credentials` with HTTP Basic
`PAYPAL_CLIENT_ID:PAYPAL_CLIENT_SECRET` to `/v1/oauth2/token`. It caches
`{token, expiresAtMs = now + (expires_in − 60) × 1000}` in module scope and exports
`resetPayPalTokenCache()` for tests. Every PayPal call uses a 10 s `AbortSignal.timeout`.

**Rationale**: Sandbox tokens last ~9 h, so one fetch per isolate is plenty. No KV or D1 write is
needed.

## R-12. Recheck policy (FR-010)

**Decision**: `GET /v1/pro/status` re-reads from PayPal every row of this device that is `pending`
or `approved`, or whose `confirmed_at` is older than `pro.recheck_after_seconds` (default 21600 =
6 h). If PayPal fails, the stored row is served as is, and the stale `confirmed_at` is what the
app shows ("last checked …"). The app calls status:
- at launch, in the background after config loads, only when `config.pro?.enabled`;
- on Plan screen open;
- while confirming;
- after a trial refusal (R-2).

`/v1/trial`, `/v1/stt` and `/v1/repair` read D1 only and never call PayPal on the hot path.

## R-13. Voice quota on the device after activation

**Finding**: The app trusts its stored `seconds_left` for the same UTC day
(`lib/features/cloud_voice/data/cloud_voice_repository_impl.dart:128`). A free device at 0 that
becomes Pro would keep skipping cloud voice until midnight.

**Decision**: Add `VoiceQuotaStore.clear()`. `PlanRepositoryImpl` calls it when entitlement flips
from not-Pro to Pro. The next clip then reads `config.voice.secondsPerDevice` as an upper bound,
the relay answers with the real Pro `seconds_left`, and that value is stored.

## R-14. Where the Pro badge goes

**Decision**: The Pro badge appears on the **Settings** app bar and on the Plan tile and Plan
screen. It does **not** go on `daily_screen.dart`'s app bar.

**Rationale**: `daily_screen.dart` *is* the conversation screen (composer, Finish button). FR-021
and Constitution X.9 ("never reaches the conversation") forbid plan UI there. The spec's "app
header outside the practice session" is, in this app, the Settings screen's header.

## R-15. Allowed edits to existing tests

SC-006 is honoured, with exactly one recorded exception:
`test/unit/router_guards_test.dart:190` `hasLength(22)` → `hasLength(23)`, for the one new
`AppRoute.settingsPlan`. That test is an inventory count, not behaviour. **No other existing test
may change.** If one fails, stop and report.

## R-16. A separate deployment for the PayPal entry

**Decision**: Pro Plus runs on its own Worker and D1, never on the Nebius prod deployment.

| | Nebius entry | PayPal entry |
|---|---|---|
| Git | `main` | `paypal-hackathon` |
| Worker env | `prod` (`dry-run-tutor`) | new `paypal` env (`dry-run-tutor-paypal`) in `worker/wrangler.jsonc` |
| D1 | `dry-run-tutor` | new `dry-run-tutor-paypal`, same migrations |
| `config` row | generous free levers, no `pro` block | tight free levers (R-5), `pro` block enabled |
| APK | current release | built with `--dart-define=RELAY_BASE_URL=<paypal worker URL>` (`lib/core/config/relay.dart`) |
| Secrets | unchanged | own `INSTALL_HMAC_SECRET`, PayPal secrets, and the same operator Nebius / Groq keys |

**Rationale**: Both judging periods run to 2026-12-15. The Nebius rules require the free path to be
usable "without any restriction" until then, and its judges' installs point at prod. A separate
deployment lets the PayPal free path be rational without changing what Nebius judges see. The app
already takes its relay URL at build time, so no app code is needed for the split.

**Alternatives rejected**: one deployment with per-build config (needs a build flag sent on every
request and two config rows; more code, same result); tightening prod (risks the Nebius entry).

**Shared cost**: both deployments spend the same Nebius credit. See the R-4 budget note.
