# Tasks: Pro Plus — PayPal Sandbox Subscription

**Input**: Design documents from `specs/009-paypal-pro-plus/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/ (worker-api.md,
paypal-integration.md, app-client.md), quickstart.md

**Branch**: `paypal-hackathon`. **Implementer**: Claude Sonnet 5.5.

## Rules for the implementer

1. Execute tasks in ID order unless marked [P]. Each task names its files and the exact design
   section it implements. **The design section is the spec for that task: read it before writing
   code.** Where a task and a design doc disagree, the task wins (it is newer), except
   `## Replay lever design` below, which overrides research.md R-5's "Code consequence" paragraph.
2. Do not redesign, add dependencies, add error codes, or rename anything named here.
3. **SC-006**: no existing test may be edited. The only exception is
   `test/unit/router_guards_test.dart:190` `hasLength(22)` → `hasLength(23)` (T068). If any other
   existing test fails, **stop and report**; do not "fix" the test.
4. After every task that touches `worker/`, run `cd worker && npm run typecheck && npm test`.
   After every task that touches `lib/` or `test/`, run `flutter analyze` (zero issues) and the
   affected tests. After any freezed/json_serializable change, run
   `dart run build_runner build --delete-conflicting-outputs` first.
5. Tasks marked **OWNER** need PayPal or Cloudflare credentials. Do not attempt them. Stop at the
   first OWNER task and report what is ready.
6. Mark each task `[x]` in this file as soon as it is done.

## Replay lever design (FR-026, FR-027; overrides research.md R-5 "Code consequence")

The gate sits on the **free trial path only**, where the cost is. Keyed learners never call
`/v1/trial`, so they are never gated. Pro devices are served by the Pro branch before the gate.
`/v1/session/reset`, `/v1/daily?problem_id=` and `/v1/problems` stay open (they cost nothing).

- **Lever**: `trial.replay_enabled: z.boolean().default(true)`. `true` (and absent) is today's
  behaviour exactly, so Nebius prod is unchanged.
- **Column**: migration 0013 also adds `devices.replay_reset_date TEXT`.
- **Reset**: `routes/session-reset.ts` non-`recover` branch writes
  `UPDATE devices SET replay_reset_date = ?2 WHERE device_hash = ?1` with today's date.
- **Gate** (`routes/trial.ts`, free path): immediately before **each** of the two existing
  `await gateNewSession()` calls, call `await gateReplayLever()`:

  ```ts
  // FR-027: with replay off, a free device gets today's daily problem, once.
  const gateReplayLever = async (): Promise<void> => {
    if (cfg.trial.replay_enabled) return;
    const today = pickDaily(getPublicManifest().problems, cfg, date);
    if (!today || today.id !== body.problem_id) throw new AppError("TRIAL_CONSUMED");
    const row = await db
      .prepare("SELECT replay_reset_date FROM devices WHERE device_hash = ?1")
      .bind(installId)
      .first<{ replay_reset_date: string | null }>();
    if (row?.replay_reset_date === date) throw new AppError("TRIAL_CONSUMED");
  };
  ```

- **App**: `ReplayGate` (`lib/features/plan/domain/replay_gate.dart`) decides whether to show the
  "Practice again / other problems are Pro" prompt **before** calling the relay, so a free learner
  never spends a reset on a refusal:

  ```dart
  class ReplayGate {
    ReplayGate({required RemoteConfigRepository configRepository,
        required KeyRepository keyRepository, required PlanRepository planRepository});
    /// True when replay is off, there is no own key, and the relay last said "free".
    Future<bool> isLocked() async {
      final RuntimeConfig? cfg = _config.cached();
      if (cfg == null || cfg.trial.replayEnabled) return false;
      if (await _keys.read() != null) return false;
      PlanStatus? status = _plan.cached();
      if (status == null && cfg.pro != null) {
        final Result<PlanStatus> r = await _plan.refresh();
        if (r case Ok<PlanStatus>(:final value)) status = value;
      }
      return status?.plan != PlanKind.pro;
    }
    bool get offerPro => _config.cached()?.pro != null;
  }
  ```

  Locked taps on "Practice again" or the problem picker call
  `showReplayLockedPrompt(context, gate)` instead of the relay.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: US1 … US5 from spec.md

---

## Phase 1: Setup (worker env and bindings)

- [x] T001 Add `{ "name": "PRO_RL", "namespace_id": "7005", "simple": { "limit": 5, "period": 60 } }` to the top-level, `dev` and `prod` `ratelimits` arrays, and add a new `"paypal"` env (name `dry-run-tutor-paypal`, `vars.ENVIRONMENT: "paypal"`, one D1 binding `DB` → `database_name: "dry-run-tutor-paypal"`, `database_id: "00000000-0000-0000-0000-000000000000"` with the comment `// OWNER: paste the id from \`npx wrangler d1 create dry-run-tutor-paypal\``, `migrations_dir: "migrations"`, and the three ratelimits WEB_EVENT_RL 7003, INSTALL_RL 7004, PRO_RL 7005). Extend the secrets comment with `PAYPAL_CLIENT_ID`, `PAYPAL_CLIENT_SECRET`, `PAYPAL_WEBHOOK_ID`, in `worker/wrangler.jsonc` (research.md R-16; worker-api.md §6)
- [x] T002 [P] Add `PAYPAL_CLIENT_ID: string; PAYPAL_CLIENT_SECRET: string; PAYPAL_WEBHOOK_ID: string; PRO_RL: RateLimit;` to `Env`, each with the comment from worker-api.md §6, in `worker/src/types.ts`
- [x] T003 [P] Add `PAYPAL_CLIENT_ID="test-client"`, `PAYPAL_CLIENT_SECRET="test-secret"`, `PAYPAL_WEBHOOK_ID="WH-TEST"` placeholders in `worker/.dev.vars` (and in the vitest bindings, if the contract project reads bindings from `worker/vitest.config.ts` rather than `.dev.vars`)
- [x] T004 [P] Add `"paypal:setup": "NODE_PATH=./node_modules tsx tools/paypal-setup.ts"` and `"paypal:admin": "NODE_PATH=./node_modules tsx tools/paypal-admin.ts"` to `scripts` in `worker/package.json`

**Checkpoint**: `npm run typecheck && npm test` green, no behaviour change.

---

## Phase 2: Foundational (blocks every story)

### Worker: storage and config

- [x] T005 Create `worker/migrations/0013_pro_plus.sql` exactly as data-model.md A1, plus one more line at the end: `ALTER TABLE devices ADD COLUMN replay_reset_date TEXT;` with the comment `-- FR-027: the UTC date this device last reset a session (replay lever).`
- [x] T006 Add `proSchema`, `pro: proSchema.optional()` and `export function proConfig()` (data-model.md A3) and `replay_enabled: z.boolean().default(true)` inside `trial` (with a one-line doc comment naming FR-027) in `worker/src/lib/runtime-config.ts`. Export `type ProConfig = NonNullable<RuntimeConfig["pro"]>`
- [x] T007 [P] Mirror T006 in `specs/001-proxy-content-contract/contracts/config.schema.json`: a `pro` object (all fields, `additionalProperties: false`, `enabled`/`plan_id`/`price_label`/`sessions_per_day`/`voice_seconds_per_day`/`daily_token_ceiling`/`total_token_ceiling` required) and `trial.properties.replay_enabled` `{ "type": "boolean", "default": true }`
- [x] T008 In `worker/src/routes/config.ts`, destructure `pro` out like `voice` and, when present, add back only `enabled`, `price_label`, `sessions_per_day`, `voice_seconds_per_day`, `manage_url` (worker-api.md §5 "GET /v1/config"). Extend the existing comment to name the stripped fields
- [x] T009 [P] Write `worker/test/unit/runtime-config.pro.test.ts` (quickstart.md §2 row) plus: `trial.replay_enabled` absent → `true`; `false` parses
- [x] T010 [P] Write `worker/test/contract/config.pro-lever.test.ts` (quickstart.md §2 row)

### Worker: ledger refactor (behaviour-neutral)

- [x] T011 In `worker/src/lib/trial-pool.ts`: add `BudgetLedger` and `freeLedger` (data-model.md A5; bodies are today's reserve/release/settle code, `freeLedger.settle` calls `settleTrialBudget`), export `estimateFor`, add optional last param `ledger: BudgetLedger = freeLedger` to `runLeg()` and `runTrialRepair()`, and optional `enforceBudget = true` to `selectMember()` (research.md R-3). Every existing call site keeps compiling unchanged
- [x] T012 Create `worker/src/lib/pooled-calls.ts` exporting `pooledCalls()` and move the four closures out of `worker/src/routes/trial.ts` verbatim with only the three substitutions in worker-api.md §5 "Pooled-call builder"; make `routes/trial.ts` call `pooledCalls({ cfg, db, now, secretFor, ledger: freeLedger })`. **Run the full worker suite: zero test edits, all green** (plan.md step 2)

### Worker: PayPal client and Pro core

- [x] T013 Create `worker/src/lib/paypal.ts` per contracts/paypal-integration.md §0–§5 (constants, `getAccessToken` with per-isolate cache and `resetPayPalTokenCache`, `createSubscription`, `getSubscription`, `verifyWebhook`, `deriveStatus` per research.md R-6, narrow non-strict Zod parse, 10 s timeouts, `UNCLEAR_RETRY` on failure, never log bodies). Export `type StoredStatus = "pending" | "approved" | "active" | "payment_failed" | "cancelled" | "suspended" | "expired"`
- [x] T014 [P] Create `worker/src/lib/pro-spend.ts`: `proLedger: BudgetLedger` (SQL in data-model.md A5, `enforceMemberBudget: false`) and `proCapacityOk()`
- [x] T015 [P] Create `worker/src/lib/pro-session.ts` with `proSessionState`, `claimProSession`, `releaseProSession`, `resetProSession` (data-model.md A4, SQL verbatim). Leave a `// servePro: added in T030` marker only; do not write `servePro` yet
- [x] T016 Create `worker/src/lib/pro.ts`: `isEntitled` (data-model.md A2), `currentSubscription(db, deviceHash, now)` (first entitled row, else latest `confirmed_at`, else null), `refreshSubscription(env, db, id, now)` (re-read via `getSubscription` + `deriveStatus`, then the "Any re-read" UPDATE from A2), `recheckDevice(env, db, deviceHash, pro, now)` (research.md R-12: sequential, errors swallowed), `ProTier`, `resolveProTier()` (A6)
- [x] T017 [P] Add `PAYPAL_ORIGIN`, `interceptPayPalToken()` (`.persist()`), `interceptPayPalCreate(id, approveHref)`, `interceptPayPalGet(id, view)`, `interceptPayPalVerify(status)` to `worker/test/contract/helpers.ts` (paypal-integration.md §7), following the existing Groq intercept style
- [x] T018 [P] Write `worker/test/unit/paypal-derive.test.ts` (quickstart.md §2 row; `resetPayPalTokenCache()` in `beforeEach`)
- [x] T019 [P] Write `worker/test/unit/paypal-sandbox-only.test.ts` (quickstart.md §2 row; scan `WORKER_SOURCE` as `operator-key.test.ts` does)
- [x] T020 [P] Write `worker/test/unit/pro-entitlement.test.ts` (quickstart.md §2 row)
- [x] T021 [P] Write `worker/test/unit/pro-session.test.ts` (quickstart.md §2 row)
- [x] T022 [P] Write `worker/test/unit/pro-spend.test.ts` (quickstart.md §2 row)

### App: config, DTOs, repository

- [x] T023 [P] In `lib/core/network/dto/config_dto.dart`: add `ProConfigDto` (data-model.md B1), `ConfigDto.pro` (`ProConfigDto?`), and `TrialConfigDto.replayEnabled` as `@JsonKey(defaultValue: true) final bool replayEnabled;` with constructor `TrialConfigDto({required this.turnCap, this.replayEnabled = true})`. Update the class comment that says `turn_cap` is the only trial field read
- [x] T024 In `lib/core/config/runtime_config.dart`: add `ProConfig` (enabled, priceLabel, sessionsPerDay, voiceSecondsPerDay, manageUrl), `RuntimeConfig.pro` (null when DTO null or `enabled: false`, mapped in `fromDto` like `voice`, added to `props`), and `TrialConfig({required this.turnCap, this.replayEnabled = true})` with `replayEnabled` in `props` and mapped from the DTO. Run build_runner
- [x] T025 [P] Create `lib/core/network/dto/pro_dto.dart`: `ProStatusDto`, `ProSubscriptionDto`, `ProUsageDto`, `ProCheckoutDto` (app-client.md §2; json_serializable, `fieldRename: snake`); add `proStatus()` and `proCheckout()` to `lib/core/network/relay_client.dart` and update the header-rules comment (lines 46–50). Run build_runner
- [x] T026 [P] Add `Future<void> clear()` (removes its prefs keys) to `lib/features/cloud_voice/data/voice_quota_store.dart`
- [x] T027 Create `lib/features/plan/domain/plan_status.dart` (data-model.md B2, with a `static PlanStatus fromDto(ProStatusDto)` that maps unknown enum strings to null/`ok`), `lib/features/plan/domain/plan_repository.dart` (app-client.md §1) and `lib/features/plan/data/plan_repository_impl.dart` (cache key `plan.last_status`, data-model.md B3; `voiceQuotaStore.clear()` on a free→pro flip, research.md R-13)
- [x] T028 Create `lib/features/plan/domain/replay_gate.dart` exactly as `## Replay lever design` above; register `PlanRepository` (app-client.md §4) and `ReplayGate` as lazy singletons in `lib/core/di/service_locator.dart`
- [x] T029 [P] Create `test/fakes/fake_plan_repository.dart` (style of `FakeKeyRepository`) and write `test/unit/config_pro_test.dart` (app-client.md §9 row, plus `trial.replay_enabled` absent → `true`) and `test/unit/plan_repository_test.dart` (app-client.md §9 row)

**Checkpoint**: both gates green; Pro code exists but nothing serves it; free path byte-identical.

---

## Phase 3: User Story 1 — Subscribe and keep practising without a key (P1) 🎯 MVP

**Goal**: free device → Plan → Subscribe → PayPal sandbox → back → "Pro Plus is active" → sessions
run on the operator key under Pro limits.

**Independent test**: quickstart.md §4 E1, E2, E3.

### Worker

- [x] T030 [US1] Add `servePro()` to `worker/src/lib/pro-session.ts` (worker-api.md §5 "POST /v1/trial", every bullet; uses `pooledCalls({ ..., ledger: proLedger })`; no `trial_*` read or write)
- [x] T031 [US1] Insert the Pro block in `worker/src/routes/trial.ts` after the practice-problem branch and before the `gateNewSession`/`consumed` logic (worker-api.md §5 code block verbatim)
- [x] T032 [US1] Create `worker/src/routes/pro.ts` with `POST /checkout` (worker-api.md §1, steps 1–7) and `GET /status` (worker-api.md §2, field table; recheck via `recheckDevice`)
- [x] T033 [P] [US1] Create `worker/src/routes/paypal-return.ts` with `GET /return` and `GET /cancel` (worker-api.md §4; HTML in the style of `routes/privacy.ts`)
- [x] T034 [US1] Mount `/v1/pro/*` (installAuth), `/v1/pro`, `/paypal` in `worker/src/index.ts` (worker-api.md mounting block; `/v1/paypal` is added in T048)
- [x] T035 [P] [US1] Write `worker/test/contract/pro.checkout.test.ts` (quickstart.md §2 row)
- [x] T036 [P] [US1] Write `worker/test/contract/pro.status.test.ts` (quickstart.md §2 row) plus (FR-005): device A has an active subscription → device B's `GET /v1/pro/status` returns `free`
- [x] T037 [P] [US1] Write `worker/test/contract/pro.return-pages.test.ts` (quickstart.md §2 row)
- [x] T038 [P] [US1] Write `worker/test/contract/trial.pro.test.ts`, all cases except the two ceiling cases (those are T053): beyond-free session served, spend in `pro_spend` only, `trial_*` untouched, `sessions_per_day` reached → free path, Pro off → identical to free, turn cap still `trial.turn_cap`, provider failure releases the claim

### App

- [x] T039 [US1] Create `lib/features/plan/presentation/plan_state.dart` (data-model.md B4, freezed) and `lib/features/plan/presentation/plan_cubit.dart` (app-client.md §6: `load`, `subscribe`, `onResumed`, polling, `manage`; injectable `openUrl`, `pollEvery`, `pollFor`). Run build_runner
- [x] T040 [US1] Create `lib/features/plan/presentation/plan_screen.dart` with sections 1 (current plan), 4 (offer) and the state views and notices from app-client.md §7; `AppLifecycleListener(onResume: cubit.onResumed)` in `initState`, disposed in `dispose`. Sections 2, 3, 5, 6 are added in T055
- [x] T041 [US1] Add `settingsPlan('/settings/plan')` after `settingsKey` in `lib/core/router/app_route.dart`; in `lib/core/router/app_router.dart` add optional `PlanRepository? planRepository` and `ReplayGate? replayGate` params to `buildAppRouter`, the `settingsPlan` GoRoute, the placeholder-loop exclusion, and `GoRoute(path: '/pro/return', redirect: ...)` (app-client.md §5)
- [x] T042 [US1] Pass `planRepository: sl<PlanRepository>()` and `replayGate: sl<ReplayGate>()` to `buildAppRouter` in `lib/main.dart`
- [x] T043 [US1] Add the Plan `ListTile` after the Provider key tile in `lib/features/settings/presentation/settings_screen.dart` (app-client.md §7 "Settings", first two bullets; `SettingsScreen` gains `PlanStatus? planStatus`, passed by the router from `planRepository?.cached()`)
- [x] T044 [US1] In `lib/features/keys/presentation/key_prompt_dialog.dart`: add `KeyPromptReason.proSessionsUsed`, `proCapacity`, `KeyPromptChoice`, `showKeyPromptWithPro()`, and make `showKeyPrompt` the wrapper (app-client.md §7 "Free-limit prompt")
- [x] T045 [US1] In `lib/features/chat/presentation/daily_screen.dart`: add optional `PlanRepository? planRepository`, `bool proOffered = false`, `ReplayGate? replayGate` constructor params (router passes them; `proOffered` = `configRepository.cached()?.pro != null`), and rewrite `_promptForKey` per app-client.md §7 "Daily screen". Nothing added to the app bar or composer
- [x] T046 [US1] Add every ARB key named in app-client.md §7–§8 with `@key` descriptions and placeholders to `lib/l10n/app_en.arb`; run `flutter gen-l10n` (or the build step the repo uses)
- [x] T047 [P] [US1] Write `test/unit/plan_cubit_test.dart` (app-client.md §9 row) and `test/widget/key_prompt_pro_test.dart` (app-client.md §9 row)

**Checkpoint**: E1–E3 pass against a dev relay with sandbox credentials (needs T074–T077).

---

## Phase 4: User Story 2 — The subscription's status stays true (P1)

**Goal**: cancel / suspend / reactivate / payment failure in PayPal is reflected by the next
request; bad signatures change nothing.

**Independent test**: quickstart.md §4 E4, E5, E6, E11.

- [x] T048 [US2] Create `worker/src/routes/paypal-webhook.ts` (`POST /webhook`, worker-api.md §3 steps 1–6, verification via `verifyWebhook`, re-read via `refreshSubscription`) and mount `app.route("/v1/paypal", paypalWebhookRoute)` **without** installAuth in `worker/src/index.ts`
- [x] T049 [P] [US2] Write `worker/test/contract/pro.webhook.test.ts` (quickstart.md §2 row, every case including the SC-007 D1 scan) plus (FR-023): spy on `console.log/info/warn/error` during a valid and an invalid webhook and assert no logged argument contains the raw request body
- [x] T050 [US2] In `lib/main.dart`, after `configRefreshed` completes: `if (sl<RemoteConfigRepository>().cached()?.pro != null) unawaited(sl<PlanRepository>().refresh());` (app-client.md §4)

**Checkpoint**: webhook suite green; a stale or pending row heals on the next status call.

---

## Phase 5: User Story 5 — The operator's credit cannot run out by surprise (P1)

**Goal**: daily/total ceilings and the kill switch fall Pro back to free, with no release.

**Independent test**: quickstart.md §4 E8, E9.

- [x] T051 [P] [US5] In `worker/src/routes/stt.ts`, after `voiceConfig(cfg)` passes, compute `cap` from `resolveProTier()` and use it everywhere `voice.seconds_per_device` is used (worker-api.md §5 "POST /v1/stt")
- [x] T052 [P] [US5] In `worker/src/routes/repair.ts` no-key branch, pass `proLedger` as the last argument to `runTrialRepair` when `resolveProTier()` is non-null and `capacityOk` (worker-api.md §5 "POST /v1/repair")
- [x] T053 [P] [US5] Add the two ceiling cases to `worker/test/contract/trial.pro.test.ts`: ceiling reached → a new session falls to free; an in-flight Pro session still serves
- [x] T054 [P] [US5] Write `worker/test/contract/stt.pro.test.ts` (quickstart.md §2 row)
- [x] T055 [P] [US5] (needs T040) Add a case to `test/widget/plan_screen_test.dart` (create the file): `offerEnabled: false` hides the offer (US5-2)

**Checkpoint**: setting `pro.enabled` false or a ceiling of 1 drops Pro devices to free; nothing errors.

---

## Phase 6: Replay lever — free vs Pro difference (FR-026, FR-027; serves US1)

**Goal**: on the PayPal deployment, free = today's problem once; Practice again and other problems
are Pro (or own key). With the lever absent, behaviour is exactly today's.

**Independent test**: with `trial.replay_enabled: false`, a free device's "Practice again" shows
the Pro prompt; a Pro device replays; a keyed device replays.

- [x] T056 [US1] In `worker/src/routes/session-reset.ts` non-`recover` branch, after `resetTrialSession(...)`: call `resetProSession(c.env.DB, deviceHash, problemId, date)` (worker-api.md §5) and run `UPDATE devices SET replay_reset_date = ?2 WHERE device_hash = ?1` bound to `(deviceHash, date)`
- [x] T057 [US1] Add `gateReplayLever` to `worker/src/routes/trial.ts` exactly as `## Replay lever design`, called immediately before each of the two `await gateNewSession()` calls. Import `pickDaily` from `../lib/daily-pick` and `getPublicManifest` from `../lib/content` if not already imported
- [x] T058 [P] [US1] Write `worker/test/contract/session-reset.pro.test.ts` (quickstart.md §2 row) plus: reset writes `replay_reset_date` = today
- [x] T059 [P] [US1] Write `worker/test/contract/trial.replay-lever.test.ts`: lever absent → a second problem is served as today; `false` → a non-daily problem gets `TRIAL_CONSUMED`; `false` → today's daily problem is served; `false` + reset today → `TRIAL_CONSUMED` for that problem; `false` + `replay_reset_date` = yesterday → served; `false` + Pro device → a non-daily problem is served by the Pro branch
- [x] T060 [US1] Add `KeyPromptReason.replayLocked` with ARB keys `keyPromptReplayLockedTitle` ("Practice again is part of Pro Plus") and `keyPromptReplayLockedBody` ("Free practice is today's problem, once. Pro Plus adds Practice again and the other problems. Your own key unlocks them too."), reusing the `trialConsumed` primary and dismiss labels, in `lib/features/keys/presentation/key_prompt_dialog.dart` and `lib/l10n/app_en.arb`
- [x] T061 [US1] Create `lib/features/plan/presentation/replay_locked_prompt.dart`: `Future<void> showReplayLockedPrompt(BuildContext context, ReplayGate gate)` → `showKeyPromptWithPro(context, KeyPromptReason.replayLocked, offerPro: gate.offerPro)`; `addKey` → `context.push(AppRoute.keysEntry.path)`; `getPro` → `context.push(AppRoute.settingsPlan.path)`
- [x] T062 [US1] Gate the five call sites with `if (await replayGate?.isLocked() ?? false) { if (context.mounted) await showReplayLockedPrompt(context, replayGate!); return; }` at the top of each handler: `lib/features/chat/presentation/daily_screen.dart` app-bar replay button (~line 108), app-bar picker button (~line 124) and the assessment-ready OutlinedButton (~line 734); `lib/features/assessment/presentation/verdict_screen.dart` replay button (~line 69) and picker button (~line 58). `VerdictScreen` gains an optional `ReplayGate? replayGate` constructor param; the router passes `replayGate` to both screens. Widgets without a gate behave exactly as today
- [x] T063 [P] [US1] Write `test/unit/replay_gate_test.dart` (lever on → unlocked; off + key → unlocked; off + cached pro → unlocked; off + cached free → locked; off + no cache + pro on → refreshes first) and `test/widget/replay_locked_prompt_test.dart` (copy shown; "Get Pro Plus" only when `offerPro`)

**Checkpoint**: both gates green with zero edits to existing tests.

---

## Phase 7: User Story 3 — See the plan and manage it (P2)

**Goal**: Plan screen shows usage, limits, renewal/end date, Manage or cancel; Pro badge in Settings.

**Independent test**: quickstart.md §4 E6, E10.

- [x] T064 [US3] Add Plan screen sections 2 (usage), 3 (Pro details), 5 (Manage) and 6 (stale `planLastChecked` from `asOf`, never `DateTime.now()`), plus the own-key note, to `lib/features/plan/presentation/plan_screen.dart` (app-client.md §7)
- [x] T065 [P] [US3] Create `lib/features/plan/presentation/widgets/pro_badge.dart` (small chip, `l10n.proBadgeLabel`); show it in the Plan `AppBar.actions` when Pro, on the Plan tile trailing and in the Settings `AppBar.actions` when the cached status is Pro (`lib/features/settings/presentation/settings_screen.dart`; research.md R-14). Nothing on `daily_screen.dart`
- [x] T066 [P] [US3] Complete `test/widget/plan_screen_test.dart` with the remaining app-client.md §9 cases (own-key note, manage button only for Pro, stale line shows `asOf`, no error styling on notCompleted)
- [x] T067 [P] [US3] Add the "Pro Plus (test payments)" section and bump "last updated" in `worker/src/routes/privacy.ts` (worker-api.md §5 "GET /privacy", FR-024)
- [x] T068 [US3] Change `hasLength(22)` → `hasLength(23)` at `test/unit/router_guards_test.dart:190` (the one allowed existing-test edit, research.md R-15)

**Checkpoint**: full `flutter test` and worker suite green.

---

## Phase 8: User Story 4 — Judges can test it end to end (P2)

**Goal**: a judge reaches "Pro Plus active" from the README alone in under 5 minutes.

**Independent test**: quickstart.md §4 E1 and E7 by someone following only the README.

- [x] T069 [P] [US4] Create `worker/tools/paypal-setup.ts` and `worker/tools/paypal-admin.ts` (paypal-integration.md §6; import `PAYPAL_API_BASE` from `../src/lib/paypal`)
- [x] T070 [P] [US4] In `worker/README.md`: add the new routes and secrets to the lever table, a "Pro lever" section in the style of "Voice lever" (kill switch command from quickstart.md §3 step 7), a "Replay lever" line for `trial.replay_enabled`, and a "PayPal deployment" section with the commands in T074–T078
- [x] T071 [US4] Add the "Pro Plus (PayPal sandbox)" subsection to README "For judges" (quickstart.md §5) with placeholders `<SANDBOX_BUYER_EMAIL>` / `<SANDBOX_BUYER_PASSWORD>` and `<PAYPAL_APK_URL>`, the E1 steps, the test-environment note, the "new work during the submission period" statement, and one line that this APK talks to a separate relay from the Nebius entry, in `README.md`
- [x] T072 [US4] Add `.github/workflows` support for a PayPal APK only if the existing app workflow already takes a `RELAY_BASE_URL` input; otherwise skip and note in the README that the PayPal APK is built with `flutter build apk --release --dart-define=RELAY_BASE_URL=https://dry-run-tutor-paypal.<subdomain>.workers.dev`
- [x] T073 [US4] Write `hackathon/paypal-config.sql`: one `UPDATE config SET payload = json_set(payload, '$.trial.sessions_per_device', 3, '$.trial.ip_daily_session_cap', 15, '$.trial.practice_turn_cap', 5, '$.trial.replay_enabled', json('false'), '$.voice.seconds_per_device', 300, '$.pro', json('{...}')), updated_at = datetime('now') WHERE id = 1;` with the `pro` block from quickstart.md §3 step 7 and `plan_id` left as `P-REPLACE-ME`. Header comment: "PayPal deployment ONLY (--env paypal). Never run against prod." (research.md R-5, R-16)

### OWNER steps (credentials; the implementer stops here)

- [x] T074 OWNER: `npx wrangler d1 create dry-run-tutor-paypal`; paste the id into the `paypal` env in `worker/wrangler.jsonc`; `npx wrangler d1 migrations apply dry-run-tutor-paypal --env paypal --remote`
- [x] T075 OWNER: copy the prod config row into the new DB: `npx wrangler d1 execute dry-run-tutor --env prod --remote --json --command "SELECT payload FROM config WHERE id = 1"`, then insert that payload into `dry-run-tutor-paypal` (`--env paypal`) with `INSERT OR REPLACE INTO config (id, payload, updated_at) VALUES (1, '<payload>', datetime('now'))`
- [ ] T076 OWNER: set secrets with `--env paypal`: `INSTALL_HMAC_SECRET` (new value), `TRIAL_KEY_*` and `STT_KEY_GROQ` (same values as prod), `TURNSTILE_SECRET` if used, `PAYPAL_CLIENT_ID`, `PAYPAL_CLIENT_SECRET`, `PAYPAL_WEBHOOK_ID`; then `npx wrangler deploy --env paypal`
- [ ] T077 OWNER: PayPal sandbox setup, quickstart.md §3 steps 1–3 and 6 (REST app, `npm run paypal:setup`, webhook to `https://dry-run-tutor-paypal.<subdomain>.workers.dev/v1/paypal/webhook`, sandbox Personal buyer account)
- [ ] T078 OWNER: put the real `plan_id` in `hackathon/paypal-config.sql`, check the ceilings against remaining Nebius credit (research.md R-4 note), run it with `--env paypal`; build the APK with `--dart-define=RELAY_BASE_URL=<paypal worker URL>`; fill the README placeholders
- [ ] T079 OWNER + implementer: run quickstart.md §4 E1–E11 on a device; then `SELECT * FROM pro_subscriptions` shows only the five columns (SC-007). Also record: (a) SC-001, one person new to the project follows only the README to "Pro Plus active", timed (pass < 5 min); (b) SC-002, 10 approvals, seconds from return to "active" for each (pass: ≥ 9 under 10 s, all under 60 s). Write the numbers into `quickstart.md` §4

---

## Phase 9: Polish and cross-cutting

- [x] T080 Run both gates (quickstart.md §1). Confirm `git diff --stat main -- test/ worker/test/` shows only new files plus the one-line `router_guards_test.dart` change (SC-006)
- [x] T081 Confirm Nebius prod is untouched: `git diff main -- worker/wrangler.jsonc` shows only `PRO_RL` additions and the new `paypal` env; no task wrote to `--env prod`
- [ ] T082 OWNER: copy the constitution 4.1.0 amendment (Principle X constraint 9) from `.specify/memory/constitution.md` to the source of record `../docs/constitution.md`, and commit both (spec C-1)

---

## Dependencies

- Phase 1 → Phase 2 → all stories.
- **US1 (Phase 3)** needs Phase 2. It is the MVP.
- **US2 (Phase 4)** needs T016 and T034; it can run alongside US1's app tasks.
- **US5 (Phase 5)** needs T030–T031 (Pro branch exists); T055 also needs T040 (Plan screen).
- **Replay lever (Phase 6)** needs T015, T028, T041, T044.
- **US3 (Phase 7)** needs T040.
- **US4 (Phase 8)** code tasks need nothing beyond Phase 2; OWNER tasks need everything else merged.
- Polish last.

## Parallel examples

- Phase 2 worker tests: T018, T019, T020, T021, T022 together once T013–T016 are done.
- Phase 2 app: T023, T025, T026 together; then T024, T027, T028 in order.
- US1: T033, T035, T036, T037, T038 together after T032; T047 after T039 and T044.
- US5: T051, T052, T053, T054, T055 all together.
- Replay lever: T058, T059, T063 together after their code tasks.

## Implementation strategy

1. **MVP**: Phases 1–3. Subscribe and practise on Pro against a dev relay.
2. **Trustworthy**: Phases 4–5. Status follows PayPal and cost is capped. This is the minimum to
   hand to judges.
3. **Rational free tier**: Phase 6.
4. **Polish for judging**: Phases 7–8, then the OWNER deploy.
5. Deadline: 2026-11-12 12:00 PT. Plan for MVP + Phases 4–6 by 2026-11-05, leaving a week for
   OWNER deploy, E1–E11 and the demo video.
