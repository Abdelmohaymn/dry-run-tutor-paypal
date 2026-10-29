# App Client Contract: Pro Plus (009)

Paths are relative to the repo root. Follow the existing feature layout (`domain/`, `data/`,
`presentation/`; see `lib/features/keys/`). **No new pubspec dependency**: `url_launcher` is
already there.

## 1. New feature `lib/features/plan/`

```
lib/features/plan/
├── domain/plan_repository.dart        # abstract interface class PlanRepository
├── domain/plan_status.dart            # data-model.md B2
├── data/plan_repository_impl.dart     # RelayClient + SharedPreferences + VoiceQuotaStore
└── presentation/
    ├── plan_cubit.dart
    ├── plan_state.dart                # freezed, data-model.md B4
    ├── plan_screen.dart
    └── widgets/pro_badge.dart         # small "Pro" chip, l10n.proBadgeLabel
```

```dart
abstract interface class PlanRepository {
  /// GET /v1/pro/status; caches it on success. Err on transport/envelope.
  Future<Result<PlanStatus>> refresh();
  /// Last cached status, or null. Display only — never grants anything.
  PlanStatus? cached();
  /// POST /v1/pro/checkout. Ok(uri) to open, Ok(null) when already active.
  Future<Result<Uri?>> startCheckout();
}
```

`PlanRepositoryImpl({required RelayClient relayClient, required InstallRepository
installRepository, required SharedPreferences prefs, required VoiceQuotaStore voiceQuotaStore})`.
It gets the install id the same way `KeyRepositoryImpl` / other repositories do.
`refresh()` calls `voiceQuotaStore.clear()` when the previous cached `plan` was not `pro` and the
new one is (research.md R-13).

## 2. RelayClient (`lib/core/network/relay_client.dart`)

```dart
Future<ProStatusDto> proStatus({required String installId});     // GET  /v1/pro/status
Future<ProCheckoutDto> proCheckout({required String installId});  // POST /v1/pro/checkout, body {}
```

- Headers: `_headers(installId: installId)`, with no user key and no provider. Update the
  header-rules comment at lines 46–50.
- Errors go through `_mapTransportOrEnvelope`, like the others.
- DTOs go in `lib/core/network/dto/pro_dto.dart` (json_serializable, `fieldRename: snake`):
  - `ProStatusDto`, `ProSubscriptionDto`, `ProUsageDto`, matching contracts/worker-api.md §2;
  - `ProCheckoutDto { String? approveUrl; bool alreadyActive = false; }`.

## 3. Config

Add `ProConfigDto` and `RuntimeConfig.pro` (data-model.md B1).

## 4. DI (`lib/core/di/service_locator.dart`)

```dart
sl.registerLazySingleton<PlanRepository>(() => PlanRepositoryImpl(
  relayClient: sl<RelayClient>(), installRepository: sl<InstallRepository>(),
  prefs: sl<SharedPreferences>(), voiceQuotaStore: sl<VoiceQuotaStore>()));
```

`VoiceQuotaStore` is already registered (`service_locator.dart:211`). Add `Future<void>
clear()` to it, which removes its prefs keys.

In `main.dart`, after `configRefreshed` completes:
`if (sl<RemoteConfigRepository>().cached()?.pro != null) unawaited(sl<PlanRepository>().refresh());`
(research.md R-12, so a missed webhook heals).

## 5. Routes

- `lib/core/router/app_route.dart`: add `settingsPlan('/settings/plan')` after `settingsKey`.
- `lib/core/router/app_router.dart`:
  - `buildAppRouter` gains an **optional** `PlanRepository? planRepository`. Optional keeps every
    existing `buildAppRouter(...)` call in tests compiling. Pass it from `main.dart`.
  - Top-level `GoRoute` for `settingsPlan`:
    `builder: (_, _) => BlocProvider(create: (_) => PlanCubit(planRepository!, keyRepository:
    sl<KeyRepository>(), configRepository: configRepository), child: const PlanScreen())`.
    `sl` is allowed inside `BlocProvider(create:)`.
  - Add `route != AppRoute.settingsPlan` to the placeholder-loop exclusions (lines 276–294).
  - Add `GoRoute(path: '/pro/return', redirect: (_, _) => AppRoute.settingsPlan.path)` next to
    `/p/:problemId` (line 275).
- `test/unit/router_guards_test.dart:190`: `22` → `23`. This is the **only** existing-test edit
  allowed (research.md R-15).

## 6. `PlanCubit` behaviour

The constructor is `PlanCubit(PlanRepository repo, {required KeyRepository keyRepository,
required RemoteConfigRepository configRepository, Duration pollEvery = const Duration(seconds:
3), Duration pollFor = const Duration(seconds: 60)})`. Timing is injectable so tests run fast.

| Method | Effect |
|---|---|
| `load()` | Emit `loading`, then `refresh()`. Ok → `ready(stale: false)`. Err with a cache → `ready(cached, stale: true)`. Err without one → `unavailable` |
| `subscribe()` | Ignored unless `ready` and `offerEnabled` and `plan == free`. Emit `checkingOut`, then `startCheckout()`: Ok(null) → `refresh` → `ready(notice: alreadyActive)`; Ok(uri) → `launchUrl(uri, mode: LaunchMode.externalApplication)` → `awaitingReturn`; Err → `ready(notice: paypalUnavailable)`. Launching is done by an injected `Future<bool> Function(Uri) openUrl`, defaulting to the `url_launcher` call |
| `onResumed()` | Only acts in `awaitingReturn`. `refresh()`: entitled → `ready(notice: activated)`; `subscription == approved` → `confirming` and poll; otherwise → `ready(notice: notCompleted)` |
| polling | Every `pollEvery` until `pollFor`: entitled → `ready(activated)`; time up → `ready(notCompleted)`. Cancel the timer in `close()` |
| `manage()` | `openUrl(config.pro.manageUrl)` |

`PlanScreen` creates an `AppLifecycleListener(onResume: cubit.onResumed)` in `initState` and
disposes it.

## 7. Screens and copy

### Plan screen (`AppBar(title: Text(l10n.planTitle))`, a `ProBadge` in `actions` when Pro)

From top to bottom:
1. **Current plan**, the first that holds:
   - "Your own key" (`planOwnKey`) when `ownKey`;
   - "Pro Plus" (`planProName`) when `plan == pro`;
   - otherwise "Free" (`planFreeName`).

   With an own key, add `planOwnKeyProNote`: "Your own key is in use. Pro Plus is an alternative
   if you'd rather not use a key." (FR-013, US3-3). Show it only when `offerEnabled`.
2. **Today's usage**:
   - `planSessionsUsage(used, limit)` and `planVoiceUsage(usedMinutes, limitMinutes)`. Minutes are
     `ceil(seconds/60)`.
   - For `sessionsPeriod.lifetime`, use `planSessionsUsageLifetime(used, limit)` instead.
3. **Pro details**, when a subscription exists and `offerEnabled`:
   - `active`: `planRenews(date)`;
   - `cancelled`: `planEnds(date)`;
   - `suspended`, `paymentFailed` or `expired`: `planEndedNotice`;
   - `proLimit == sessionsUsed`: `planProSessionsUsed`;
   - `proLimit == capacity`: `planProCapacity`.
4. **Offer**, when `offerEnabled && plan == free`:
   - `planOfferTitle`;
   - `config.pro.priceLabel`, shown as a resolved value;
   - `planOfferLimits(sessions, minutes)`;
   - `planOfferPayPal`: "Billed through PayPal. This build uses PayPal's test environment, so no
     real money is charged." (FR-002);
   - a FilledButton `planSubscribe`.
5. **Manage**, when `plan == pro`: an OutlinedButton `planManage` ("Manage or cancel in PayPal").
6. **Stale**: when `stale`, show `planLastChecked(time)` with the time from `asOf`. Never use
   `DateTime.now()`; the `no_wall_clock` lint applies.

State views:
- `checkingOut` / `confirming`: a spinner with `planConfirming` ("Confirming with PayPal…").
- `awaitingReturn`: `planAwaitingReturn` ("Finish in PayPal, then come back here.").

Notices, as a `SnackBar` or inline line:
- `activated`: `planActivated` ("Pro Plus is active.");
- `notCompleted`: `planNotCompleted` ("Subscription not completed.");
- `paypalUnavailable`: `planPayPalUnavailable` ("PayPal is unavailable. Try again later.");
- `alreadyActive`: `planAlreadyActive`.

No notice uses error styling (US1-3).

### Settings (`lib/features/settings/presentation/settings_screen.dart`)

- Add a `ListTile` after the Provider key tile: `Icons.workspace_premium_outlined`,
  `l10n.settingsPlanLabel`, trailing `ProBadge` when the cached status is Pro, and
  `context.push(AppRoute.settingsPlan.path)`.
- The tile is always shown. The *offer* inside it follows `offerEnabled`.
- Add a `ProBadge` in the Settings `AppBar.actions` when the cached status is Pro (research.md
  R-14).
- `SettingsScreen` reads the cached status from a constructor parameter `PlanStatus?
  planStatus`, which the router passes from `planRepository?.cached()`. It never calls `sl`
  itself.

### Free-limit prompt (`lib/features/keys/presentation/key_prompt_dialog.dart`)

- `KeyPromptReason` gains `proSessionsUsed` and `proCapacity`. Give them their own
  title/body/primary/dismiss copy:
  - `keyPromptProSessionsTitle` / `Body`: "Today's Pro sessions are used. They come back
    tomorrow (UTC). Add your own key to keep going now."
  - `keyPromptProCapacityTitle` / `Body`: "Pro Plus is at capacity for now. Add your own key to
    keep going."
- Keep `showKeyPrompt(context, reason) → Future<bool>` (line 65) and its behaviour unchanged.
- Add `enum KeyPromptChoice { addKey, getPro, dismiss }` and
  `showKeyPromptWithPro(context, reason, {required bool offerPro}) → Future<KeyPromptChoice>`.
  It is the same dialog plus, when `offerPro`, a third `TextButton` `keyPromptProAction` ("Get
  Pro Plus").
- `showKeyPrompt` becomes a wrapper: `(await showKeyPromptWithPro(context, reason, offerPro:
  false)) == KeyPromptChoice.addKey`. The dialog then has one implementation, and every
  existing test sees identical widgets.

### Daily screen (`lib/features/chat/presentation/daily_screen.dart`)

- `DailyScreen` gains an optional `PlanRepository? planRepository` and `RuntimeConfig`-sourced
  `bool proOffered`, threaded from the router like the other dependencies.
- `_promptForKey`:
  1. If `reason` is one of `trialConsumed`, `trialUnavailable` or `trialIpLimited`, and
     `planRepository != null` and `proOffered`, first `await planRepository.refresh()`.
     - Ok with `plan == pro`: replace the reason with `proSessionsUsed` (when `proLimit ==
       sessionsUsed`) or `proCapacity` (when `proLimit == capacity`).
     - Ok with `plan == free`: `offerPro = true`.
  2. Call `showKeyPromptWithPro(context, reason, offerPro: offerPro)` instead of
     `showKeyPrompt`. On `addKey`, push `keysEntry` as today. On `getPro`,
     `context.push(AppRoute.settingsPlan.path)`.
- **Nothing** is added to the daily screen's app bar or composer (FR-021).

## 8. ARB (`lib/l10n/app_en.arb`)

Add every key named above, each with an `@key` description. Placeholders:
- `planSessionsUsage` and `planSessionsUsageLifetime` take `{used}` and `{limit}` (int);
- `planVoiceUsage` takes `{used}` and `{limit}` (int);
- `planRenews`, `planEnds` and `planLastChecked` take `{date}` (String, preformatted);
- `planOfferLimits` takes `{sessions}` and `{minutes}` (int).

Use `{appName}` where the product is named. Never use the words "correct" or "wrong"
(`no_absolutes_test`). Leave the existing "never charges you" / "cannot be charged" strings
unchanged. Sandbox billing keeps them literally true.

## 9. New tests (app)

| File | Covers |
|---|---|
| `test/unit/plan_repository_test.dart` | DTO→`PlanStatus` mapping (unknown enum → null/ok), cache written on Ok, cache served by `cached()`, `voiceQuotaStore.clear()` only on a free→pro flip |
| `test/unit/plan_cubit_test.dart` (bloc_test) | load ok / stale / unavailable; subscribe → awaitingReturn; resume → activated; resume `approved` → confirming → activated; resume pending → notCompleted; poll timeout → notCompleted; checkout Err → paypalUnavailable; already active |
| `test/widget/plan_screen_test.dart` | Offer hidden when `offerEnabled` false (US5-2); own-key note (US3-3); manage button only for Pro; stale line shows `asOf`; no error styling on notCompleted |
| `test/widget/key_prompt_pro_test.dart` | Pro reasons render their copy; `offerPro` shows "Get Pro Plus" |
| `test/unit/config_pro_test.dart` | `pro` absent → null; `enabled:false` → null; full block parses |
| `test/fakes/fake_plan_repository.dart` | Scripted `refresh`/`startCheckout` results, the same style as `FakeKeyRepository` |
