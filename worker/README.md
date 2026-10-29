# dry-run-worker

The tutor & assessment relay (Cloudflare Worker). See `specs/001-proxy-content-contract/` for the full spec, plan, and task list.

## Local setup

```sh
cd worker
npm install
npm run build:content                              # content/problems/*.json -> src/generated/*
npx wrangler d1 migrations apply dry-run-dev --local --env dev
npm run dev                                         # picks up worker/.dev.vars — http://localhost:8787
```

`worker/.dev.vars` is committed with **placeholder** values only (`INSTALL_HMAC_SECRET`, `TRIAL_KEY_GROQ`) — enough for `npm test` (provider stubbed) but not for a real call. For a live `wrangler dev` session against a real provider, put your own values in an env-suffixed override instead of editing the tracked file: `worker/.dev.vars.dev` (gitignored), same `KEY="value"` shape, then run `wrangler dev --env dev` so it's picked up. Never commit a real key.

Offline checks (no key, no network — the gate that runs on every PR):

```sh
npm run typecheck
npm run validate:content
npm run verify:examples  # each problem's reference solution vs its public examples
npm test              # unit + contract, provider stubbed
```

Adding a problem: follow `content/AUTHORING.md`, and run `npm run check:content` (validate, verify examples, build).

`npm run test:harness` additionally needs a real `GROQ_API_KEY` and the full three-problem content set; see `specs/001-proxy-content-contract/quickstart.md` §7.

## Replaying a tutor turn (`npm run replay:tutor`)

Reproduces one tutor turn from a real conversation against live Groq and reports, per run, what the leak filter did with the draft: `CLEAN`, `REWRITTEN` (the one retry with the blocked words named), `CUT TO CLEAN LEAD`, or `FALLBACK`. Needs a real key and spends real tokens:

```sh
GROQ_API_KEY=gsk_... npm run replay:tutor -- tools/replay-samples/pair-sum-full-answer.json --runs 8
```

The file is a JSON array of `{"role": "user" | "tutor", "text"}` turns ending on the learner's, the same shape as `messages` on `POST /v1/chat`. Options: `--problem` (default `vp-0001`), `--runs`, `--gap` (seconds between calls; a free key hits Groq's tokens-per-minute limit fast), `--model`. The config values it builds the prompt with are constants at the top of `tools/replay-tutor.ts`.

## Client fail-open obligation (GET /v1/config)

`GET /v1/config` gates app launch. If it is unreachable — network error, timeout, non-2xx — **the client MUST fall back to its last cached response** rather than blocking. Config must never be able to lock a learner out (Constitution X.3). This is a client-side requirement; the Worker's only job is to serve the current levers with a `Cache-Control` and `ETag` header so the client has something to cache in the first place (`worker/src/routes/config.ts`).

## Changing a lever with no redeploy

Every lever lives in the single `config` row (`contracts/config.schema.json`). Read the current payload, edit the JSON, write it back:

```sh
npx wrangler d1 execute dry-run-dev --local \
  --command "SELECT payload FROM config WHERE id = 1"

# edit the JSON, then:
npx wrangler d1 execute dry-run-dev --local \
  --command "UPDATE config SET payload = '<edited JSON>', updated_at = datetime('now') WHERE id = 1"
```

Drop `--local` (and use the `dev`/`prod` D1 database name) to change a deployed environment. `GET /v1/config` reflects the change on its next read (no cache on the server side — see the client fail-open note above for the client's own cache).

Levers, one line each — full detail in `contracts/config.schema.json` and `specs/001-proxy-content-contract/data-model.md` §A5:

| Lever | Effect |
|---|---|
| `chat.turn_cap` | The primary quota lever — turns allowed per session. |
| `chat.wrap_up_at_turn` | Turn index from which the tutor prompt nudges toward a close. |
| `chat.min_turn_chars` | Below this, `EMPTY_TURN` before the provider is called. |
| `model` / `provider` | Which model and which upstream serve chat and judge. |
| `trim.verbatim_turns` / `trim.narrow_after_turn` / `trim.narrow_margin` / `trim.condense_model` | Condensation window and ground-truth narrowing. |
| `killed_problem_ids` | Pull a problem same-day, no release. |
| `rotation.start_problem_id` / `rotation.anchor_date` | The global daily pointer — see below. |
| `ads.enabled` | `false` takes both ad surfaces off every install — see below. |
| `trial.turn_cap` / `trial.ground_truth_tier` / `trial.condense` / `trial.daily_session_cap` / `trial.pool` | The trial funnel's own profile and provider pool. |
| `voice.enabled` / `voice.seconds_per_device` / `voice.max_clip_seconds` | Server-side speech-to-text (`POST /v1/stt`): on/off, seconds per device per UTC day, longest clip. Absent means off. |
| `trial.replay_enabled` | `false` limits a free device to today's problem, once: no "Practice again", no problem picker (Pro and keyed devices unaffected). Absent means `true`. See "Replay lever". |
| `pro.enabled` / `pro.plan_id` / `pro.price_label` / `pro.sessions_per_day` / `pro.voice_seconds_per_day` / `pro.daily_token_ceiling` / `pro.total_token_ceiling` / `pro.recheck_after_seconds` / `pro.manage_url` | Pro Plus (PayPal sandbox): on/off, the plan, what it shows and gives, the operator-credit ceilings, how often a subscription is re-read. Absent means off. `plan_id`, the ceilings and `recheck_after_seconds` never leave the Worker. See "Pro lever". |
| `trial.pool[].structured_extra_body` / `providers.<id>.structured_extra_body` | Extra body fields for structured calls (judge, finish check) only. Nemotron needs thinking off here — see below. |

Switching a key or model, for the trial pool or for learner keys: follow [`docs/switching-models.md`](../docs/switching-models.md).

### Structured calls on Nemotron

Nemotron reasons by default. Inside a strict-schema call that reasoning sometimes leaves a hollow assessment (empty insight lists, feedback `..`): 19% of judge calls in the 2026-10-07 review, at 3.4x the latency (`specs/review-tutor-judge-findings.md` F2). Turn it off for structured calls on every Nemotron pool member, and for the keyed `nebius` provider. Leave the tutor stream alone: it is better with thinking on.

```bash
npx wrangler d1 execute <db> --remote \
  --command "UPDATE config SET payload = json_set(payload, '\$.trial.pool[0].structured_extra_body', json('{\"chat_template_kwargs\":{\"enable_thinking\":false}}'), '\$.providers.nebius.structured_extra_body', json('{\"chat_template_kwargs\":{\"enable_thinking\":false}}')), updated_at = datetime('now') WHERE id = 1"
```

Use the right pool index for each Nemotron member (`SELECT json_extract(payload, '$.trial.pool') FROM config`).

### Voice lever

Voice ships dormant: a config row without a `voice` block means `POST /v1/stt` answers 503 `VOICE_UNAVAILABLE` and every device uses on-device speech recognition. The Groq key is a Worker secret, set only with `npx wrangler secret put STT_KEY_GROQ --env <dev|prod>` (paste it interactively; never put it in a file, a command line, or `.dev.vars`).

Turn voice on (300 seconds per device per UTC day, 120 seconds per clip):

```sh
npx wrangler d1 execute dry-run-dev --env dev --remote \
  --command "UPDATE config SET payload = json_set(payload, '\$.voice', json('{\"enabled\":true,\"seconds_per_device\":300,\"max_clip_seconds\":120}')), updated_at = datetime('now') WHERE id = 1"
```

Kill switch. Every device falls back to on-device recognition on its next tap, with no release:

```sh
npx wrangler d1 execute dry-run-dev --env dev --remote \
  --command "UPDATE config SET payload = json_set(payload, '\$.voice.enabled', json('false')), updated_at = datetime('now') WHERE id = 1"
```

Use `dry-run-prod` and `--env prod` for production, and enable the lever last, once the app release that uses it is live.

### Pro lever

Pro Plus (feature 009) ships dormant: a config row without a `pro` block means every Pro route is a no-op and no device is ever served under Pro rules. It is **PayPal sandbox only**: the API base is a constant (`worker/src/lib/paypal.ts`), and a unit test fails the build if a live PayPal host appears in the source. Routes it adds:

| Route | Who calls it | Notes |
|---|---|---|
| `POST /v1/pro/checkout` | the app (install-auth) | Creates a sandbox subscription bound to the calling device and returns PayPal's approve link. |
| `GET /v1/pro/status` | the app (install-auth) | The device's plan, subscription and usage. Re-reads PayPal when a row is pending or stale. |
| `POST /v1/paypal/webhook` | PayPal | No install-auth. Verified through PayPal's verify API, then the subscription is re-read. |
| `GET /paypal/return`, `GET /paypal/cancel` | the learner's browser | Public pages PayPal sends the browser back to. |

Secrets (set with `npx wrangler secret put <NAME> --env <env>`, entered interactively, never in a file): `PAYPAL_CLIENT_ID`, `PAYPAL_CLIENT_SECRET`, `PAYPAL_WEBHOOK_ID`. `worker/.dev.vars` carries placeholders for the tests.

Turn Pro on (read the budget note in `specs/009-paypal-pro-plus/research.md` R-4 first and size the two ceilings against the remaining operator credit):

```sh
npx wrangler d1 execute <db> --env <env> --remote \
  --command "UPDATE config SET payload = json_set(payload, '\$.pro', json('{\"enabled\":true,\"plan_id\":\"P-XXXX\",\"price_label\":\"\$4.99 / month\",\"sessions_per_day\":5,\"voice_seconds_per_day\":900,\"daily_token_ceiling\":1875000,\"total_token_ceiling\":37500000}')), updated_at = datetime('now') WHERE id = 1"
```

Kill switch. Pro devices are served by the free path on their next request; nothing errors and nothing is refunded:

```sh
npx wrangler d1 execute <db> --env <env> --remote \
  --command "UPDATE config SET payload = json_set(payload, '\$.pro.enabled', json('false')), updated_at = datetime('now') WHERE id = 1"
```

The ceilings gate **new** Pro sessions only; a Pro session already in flight runs to its end. Pro spend is its own ledger (`pro_spend`), apart from the free pool's budget. `npm run paypal:setup` creates the sandbox product and plan and prints the plan id; `npm run paypal:admin -- <suspend|activate|cancel|show> <I-id>` drives a subscription to produce real webhook events.

### Replay lever

`trial.replay_enabled: false` makes the **free** trial path give a device today's daily problem, once. A second go (after "Practice again", which calls `POST /v1/session/reset`) or any other problem is refused with `TRIAL_CONSUMED`. Keyed learners never call `/v1/trial`, and Pro devices are served before the gate, so neither is affected. Absent means `true`, which is how the Nebius deployment behaves. Set it only on the PayPal deployment's config row.

### PayPal deployment

Pro Plus runs on its own Worker and D1, never on the Nebius `prod` deployment (research.md R-16). The `paypal` env in `wrangler.jsonc` is `dry-run-tutor-paypal`. Owner steps, once:

```sh
npx wrangler d1 create dry-run-tutor-paypal          # paste the id into wrangler.jsonc, env.paypal
npx wrangler d1 migrations apply dry-run-tutor-paypal --env paypal --remote
# copy the prod config row into it, then run hackathon/paypal-config.sql with --env paypal
npx wrangler secret put INSTALL_HMAC_SECRET --env paypal   # a new value, not prod's
npx wrangler secret put TRIAL_KEY_GROQ --env paypal         # and any other TRIAL_KEY_* / STT_KEY_GROQ, same values as prod
npx wrangler secret put PAYPAL_CLIENT_ID --env paypal
npx wrangler secret put PAYPAL_CLIENT_SECRET --env paypal
npx wrangler secret put PAYPAL_WEBHOOK_ID --env paypal
npx wrangler deploy --env paypal
```

Build the matching APK with `flutter build apk --release --dart-define=RELAY_BASE_URL=https://dry-run-tutor-paypal.<subdomain>.workers.dev`. Full sequence and the end-to-end scenarios: `specs/009-paypal-pro-plus/quickstart.md` §3–§4.

## The daily pointer (`rotation`)

`rotation` decides which problem **every** device gets on a given day. It is applied by the Worker in `GET /v1/daily` (and is never sent to the app), so the answer is the same for a year-old install and one made this morning:

```
problem = evergreen_pool_sorted_by_id[ index(start_problem_id) + whole_days_since(anchor_date) ]
```

wrapped around the end of the pool. It advances on its own — set it once, not daily.

Restart everyone at the first problem, one write, no release:

```sh
npx wrangler d1 execute dry-run-prod --remote \
  --command "UPDATE config SET payload = json_set(payload, '\$.rotation.start_problem_id', 'vp-0000', '\$.rotation.anchor_date', date('now')), updated_at = datetime('now') WHERE id = 1"
```

Devices pick it up the next time they fetch the daily problem; a problem already cached for today stays until the next day (or until it is killed).

Four things worth knowing before you move it:

- **Omit `rotation` entirely** and the pick is `dayNumber(date) % pool.length` over the id-sorted pool — still the same problem for every device. The old per-install "walk my un-attempted problems" behaviour is gone: the server cannot see local history.
- **A problem authored for exactly today outranks the pointer.** Dated problems are an explicit override and are not in the rotation pool.
- **A bad pointer is a loud failure, not a quiet one.** A `start_problem_id` or `anchor_date` that fails the schema makes `GET /v1/config` return 502 rather than serving a wrong problem everywhere; a well-formed id that is withdrawn or not yet in the manifest degrades to the top of the pool.
- **The pointer does not erase local history.** A learner who has seen today's problem before still gets `isRepeat` recorded locally (FR-035c) and sees no marker for it (FR-035b); the app computes it from its own completed sessions.

## The ad kill switch (`ads.enabled`)

Turns off both ad surfaces — the rewarded hint video and the assessment interstitial — on every install, with no release and no store review:

```sh
npx wrangler d1 execute dry-run-prod --remote \
  --command "UPDATE config SET payload = json_set(payload, '\$.ads.enabled', json('false')), updated_at = datetime('now') WHERE id = 1"
```

Back on: `json('true')`. Installs pick it up on their next launch.

- **This row is the only thing that decides.** There is no compile-time ads switch any more: no `ADS_ENABLED` dart-define, no app-side config file. One place to look, and it is reachable without a release.
- **Off is the default.** Omit `ads`, serve a config written before this key existed, or fail to reach the relay on a first launch, and the answer is no ads. Absent means off, not "ask someone else".
- **It takes a launch to turn ads ON.** `AdsService.initialize()` only starts the SDKs once the config says yes, so a fresh install with ads enabled picks them up after `/seeding` has fetched the config. Turning them OFF needs no init at all and takes effect on the next check.
- **Switching ads off never costs a learner anything.** The hint still arrives when the rewarded video is skipped (FR-004); the assessment opens without the interstitial (FR-009).
- **Mid-session changes wait.** The flag is re-read on every check rather than captured at startup, but a learner already inside a session keeps the surfaces that session started with.

## Two-environment deploy

```sh
npx wrangler deploy --env dev
npx wrangler deploy --env prod
```

(A third, `--env paypal`, exists for the Pro Plus entry; see "PayPal deployment" above.)

Each environment has its own D1 database (`wrangler.jsonc`) and its own secrets (`wrangler secret put INSTALL_HMAC_SECRET --env dev`, one `TRIAL_KEY_*` per enabled pool member, and `STT_KEY_GROQ` for voice — set only via `wrangler secret put STT_KEY_GROQ --env dev`, never in a file).
