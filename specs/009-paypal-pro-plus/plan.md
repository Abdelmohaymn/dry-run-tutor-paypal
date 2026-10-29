# Implementation Plan: Pro Plus — PayPal Sandbox Subscription

**Branch**: `paypal-hackathon` | **Date**: 2026-10-20 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/009-paypal-pro-plus/spec.md`

**Implementer**: Claude Sonnet 5.5. Execute this plan literally. Every design choice is already
made; where something looks open, the answer is in the linked artifact. Do not redesign, add
dependencies, or add error codes. If reality contradicts the plan (a line moved, an existing test
fails, a PayPal response differs from contracts/paypal-integration.md), **stop and report**
rather than improvise.

## Summary

A device can subscribe to "Pro Plus" through PayPal's **sandbox** Subscriptions API. While the
subscription is entitled, the relay serves that device's `/v1/trial` sessions under Pro rules:
- N sessions per UTC day;
- a separate token ledger with daily and total ceilings;
- more cloud-voice seconds;
- "Practice again" and the problem picker, which the PayPal deployment turns off for free devices
  with the new `trial.replay_enabled` lever (default `true`).

Pro runs on its **own deployment**: a `paypal` Worker env with its own D1 and `config` row, and an
APK built with `--dart-define=RELAY_BASE_URL=<paypal worker>`. The Nebius prod deployment keeps its
config and behaviour unchanged (research.md R-5, R-16; FR-026, FR-027).

The app is unchanged in how it routes chat and judge calls. A new Plan screen (in Settings) runs
checkout in the system browser, confirms the result with the relay on return, and opens PayPal's
manage page. Status follows PayPal: every webhook (signature verified through PayPal's API) and
every stale status check **re-reads** the subscription from PayPal and stores only the derived
status. That is idempotent and order-safe by construction.

Technical approach, in one line per side:
- **Worker**: one migration, five new modules (`paypal.ts`, `pro.ts`, `pro-session.ts`,
  `pro-spend.ts`, `pooled-calls.ts`), three new route files, and small hooks in `trial`, `stt`,
  `repair`, `session-reset`, `config` and `privacy`.
- **App**: one new feature folder (`lib/features/plan/`), one route, a config block, and a Pro
  variant of the key prompt.

## Technical Context

| | |
|---|---|
| **Language/Version** | TypeScript 5.9 (Cloudflare Worker, Hono 4, Zod 4); Dart / Flutter (version pinned in `.fvmrc`) |
| **Primary Dependencies** | Worker: `hono`, `zod`, plain `fetch` to PayPal REST. App: `flutter_bloc`, `get_it`, `dio`, `freezed`, `json_serializable`, `url_launcher` (already present). **No new dependency** on either side |
| **Storage** | D1 migration `0013_pro_plus.sql` (two tables, three `devices` columns). App: one `SharedPreferences` entry. No Drift change |
| **Testing** | Worker: `npm run typecheck && npm test` (vitest `unit` + `contract`, PayPal stubbed via `fetchMock`). App: `flutter analyze` (zero issues) and `flutter test` |
| **Target Platform** | Cloudflare Workers (dev + prod); Android APK distributed directly to judges |
| **Project Type** | Mobile app + API (`lib/` + `worker/`) |
| **Performance Goals** | Activation visible in ≤ 10 s in 9 of 10 attempts, and ≤ 60 s always (SC-002). No PayPal call on the `/v1/trial`, `/v1/stt` or `/v1/repair` hot paths (D1 reads only) |
| **Constraints** | Sandbox only (API base is a constant, tested); no payer data stored or logged; free and keyed paths byte-identical; off by default; every lever server-side |
| **Scale/Scope** | Tens of judge devices. Worker ≈ 12 src files touched or added, ≈ 15 test files. App ≈ 15 files touched or added, 6 test files |

## Constitution Check

*GATE: evaluated before Phase 0 and re-checked after Phase 1. Constitution v4.1.0.*

| # | Principle / rule | Status | Note |
|---|---|---|---|
| G-1 | X first sentence + constraint 9 (sandbox tier) | **Pass (amended 4.1.0)** | Each 9 bullet maps to a mechanism. **No real money**: sandbox base URL constant plus a source-scan test (R-10). **Off by default**: an absent `pro` block means off (data-model A3). **Capped**: `pro_spend` with daily and total ceilings, falling back to free limits, never an error or a bill (R-3, R-4). **Never in the conversation**: no plan UI on `daily_screen` (R-14). **No payer data**: narrow parse, five stored fields (paypal-integration §0) |
| G-2 | X.1 a session stays inside the allowance | Pass | Relaxed for Pro devices only, inside the ceiling. A single Pro session keeps `trial.turn_cap`, tier and condense (FR-015) |
| G-3 | X.2 user never incurs a charge | Pass | Sandbox accounts cannot be charged. The existing "cannot be charged" copy stays literally true |
| G-4 | X.3 every lever server-side | Pass | Price label, limits, ceilings, plan id, kill switch and recheck age are all in the `config` row |
| G-5 | VI one host; developer key never in the app | Pass | The app's dio calls still go only to the relay (`HostAllowlistInterceptor` untouched). PayPal pages open in the system browser (4.1.0 wording). The PayPal secrets are Worker secrets |
| G-6 | VII / VIII voice and offline | Pass | Pro raises the cap only. Voice off still means off. The Plan screen works offline from its cache, marked stale; it never grants anything |
| G-7 | IX trusted time | Pass | All dates come from the relay (`as_of`, `period_end`). No `DateTime.now()` (lint `no_wall_clock`) |
| G-8 | I / V voice-first, transcript review | Pass | Nothing changes in the session flow |
| G-9 | Locked stack | Pass | Cubit plus freezed sealed state; repository interface in `domain/`; `sl` only in `service_locator.dart`, `main()` and `BlocProvider(create:)`; typed `AppRoute`; ARB strings only |
| G-10 | Quality Gates: no third-party analytics; minimal server data | Pass | PayPal is a payment processor reached server-to-server and via its own web pages. It is not an SDK in the app. D1 gains only cap-enforcing rows |
| G-11 | Governance: justified by something other than D7 | Pass, argued | The occasion is the PayPal AI Hackathon (stated in X.9). It does not claim to move D7. The cost is bounded by the ceiling and the kill switch |

**Post-design re-check**: no violations. Complexity Tracking is empty.

**Open owner items** (not gates; the code is identical either way):
1. **Total Nebius credit** (research.md R-4). Free-path judging for Nebius and the Pro ceiling
   draw on the same credit. Set the ceilings against the real balance before enabling.
2. **PayPal deployment free levers** (research.md R-5). Set them in the `paypal` env's `config`
   row before enabling `pro`. Never write them to the prod row.
3. **Constitution source of record** `../docs/constitution.md` still needs the 4.1.0 amendment
   (already listed in spec C-1).

## Project Structure

### Documentation (this feature)

```text
specs/009-paypal-pro-plus/
├── plan.md                          # This file
├── research.md                      # R-1 … R-15
├── data-model.md                    # D1 0013, config `pro`, ledger, Pro session slot, app models
├── quickstart.md                    # Gates, new-test map, sandbox setup, e2e E1–E11, README
├── contracts/
│   ├── worker-api.md                # New routes + exact changes to existing routes, env/bindings
│   ├── paypal-integration.md        # Outbound PayPal calls, verification, status derivation, tools
│   └── app-client.md                # Plan feature, RelayClient, routes, cubit, copy, tests
└── tasks.md                         # /speckit-tasks output (not created here)
```

### Source Code (repository root)

```text
worker/
├── migrations/0013_pro_plus.sql                 # NEW
├── wrangler.jsonc                               # + PRO_RL (top, dev, prod, paypal); new `paypal` env (own name + D1); secrets comment
├── .dev.vars                                    # + PayPal placeholders
├── package.json                                 # + paypal:setup, paypal:admin scripts
├── tools/paypal-setup.ts, tools/paypal-admin.ts # NEW (operator only, not deployed)
├── src/
│   ├── index.ts                                 # mount /v1/pro (installAuth), /v1/paypal, /paypal
│   ├── types.ts                                 # + PAYPAL_CLIENT_ID/SECRET/WEBHOOK_ID, PRO_RL
│   ├── lib/
│   │   ├── paypal.ts                            # NEW — token, create, get, verify, deriveStatus
│   │   ├── pro.ts                               # NEW — isEntitled, resolveProTier, current-subscription pick, recheck
│   │   ├── pro-session.ts                       # NEW — proSessionState/claim/release/reset + servePro
│   │   ├── pro-spend.ts                         # NEW — proLedger, proCapacityOk
│   │   ├── pooled-calls.ts                      # NEW — closures moved verbatim out of routes/trial.ts
│   │   ├── trial-pool.ts                        # BudgetLedger + freeLedger; runLeg/runTrialRepair ledger param; selectMember enforceBudget; export estimateFor
│   │   └── runtime-config.ts                    # + proSchema, proConfig(); trial.replay_enabled (default true)
│   └── routes/
│       ├── pro.ts                               # NEW — GET /status, POST /checkout
│       ├── paypal-webhook.ts                    # NEW — POST /webhook
│       ├── paypal-return.ts                     # NEW — GET /return, GET /cancel (HTML)
│       ├── trial.ts                             # Pro branch + use pooledCalls(freeLedger) + gateReplayLever (tasks.md)
│       ├── stt.ts, repair.ts, session-reset.ts  # small hooks (worker-api.md §5); reset also writes devices.replay_reset_date
│       ├── config.ts                            # strip server-only pro fields
│       └── privacy.ts                           # PayPal section
└── test/ (quickstart.md §2)

specs/001-proxy-content-contract/contracts/config.schema.json   # + pro block

lib/
├── core/network/relay_client.dart               # + proStatus, proCheckout
├── core/network/dto/pro_dto.dart                # NEW
├── core/network/dto/config_dto.dart             # + ProConfigDto
├── core/config/runtime_config.dart              # + ProConfig
├── core/di/service_locator.dart                 # + PlanRepository
├── core/router/app_route.dart, app_router.dart  # + settingsPlan, /pro/return
├── features/plan/…                              # NEW (app-client.md §1)
├── features/cloud_voice/data/voice_quota_store.dart   # + clear()
├── features/settings/presentation/settings_screen.dart # Plan tile + badge
├── features/keys/presentation/key_prompt_dialog.dart   # Pro reasons, showKeyPromptWithPro
├── features/chat/presentation/daily_screen.dart        # Pro-aware _promptForKey only
├── features/assessment/presentation/verdict_screen.dart     # "Practice again" / "Try another" → Pro offer when replay off and not Pro
├── features/problem/presentation/problem_picker_screen.dart # same gate
├── l10n/app_en.arb                              # new keys
└── main.dart                                    # pass planRepository; launch refresh

README.md, worker/README.md                      # judges' sandbox login; Pro lever docs
```

**Structure Decision**: This is the existing Mobile + API layout. Pro is a server-side tier on the
existing trial path (research.md R-1). The app gets one new feature folder.

## Implementation Order

Each step leaves both gates green.

| # | Step | Est. |
|---|---|---|
| 1 | Migration 0013 + `proSchema`/`proConfig` + config.schema.json + `/v1/config` strip, with tests | 1 h |
| 2 | `BudgetLedger` refactor in `trial-pool.ts` + `pooled-calls.ts` extraction from `trial.ts`. **Run the full suite: zero test edits** | 1.5 h |
| 3 | `paypal.ts` + `deriveStatus` + sandbox-only scan, with unit tests | 1.5 h |
| 4 | `pro.ts`, `pro-session.ts`, `pro-spend.ts`, with unit tests | 2 h |
| 5 | `routes/pro.ts` (checkout, status), `paypal-webhook.ts`, `paypal-return.ts`, bindings, with contract tests | 3 h |
| 6 | Hooks in `trial`, `stt`, `repair`, `session-reset`; privacy copy; contract tests | 2.5 h |
| 7 | Operator tools + worker README | 1 h |
| 8 | App: DTOs, RelayClient, config, `PlanRepository`, `VoiceQuotaStore.clear`, DI, with tests | 2 h |
| 9 | App: `PlanCubit`/state/screen, route, Settings tile/badge, with tests | 3 h |
| 10 | App: key prompt Pro variant + daily_screen wiring + ARB, with tests | 1.5 h |
| 10b | `trial.replay_enabled` lever: Worker gate on the free trial path, app `ReplayGate` on Practice again + picker, with tests. Default `true` keeps every existing test green | 2.5 h |
| 11 | `paypal` Worker env + D1 + secrets, PayPal-env `config` row (R-5 free levers + `pro`), APK with its `RELAY_BASE_URL`; sandbox setup + e2e E1–E11 on device + README judges section | 3 h |

Total: about 24.5 h, or 3 to 4 working days. The submission deadline is 2026-11-12 12:00 PT.

## Complexity Tracking

No constitution violations to justify.
