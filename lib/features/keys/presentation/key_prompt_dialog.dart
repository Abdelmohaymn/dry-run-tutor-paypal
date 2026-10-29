import 'package:flutter/material.dart';

import '../../../core/config/brand.dart';
import '../../../core/errors/relay_error.dart';
import '../../../core/l10n/generated/app_localizations.dart';

/// The three situations that are resolved by the learner putting a
/// provider key in, and which therefore earn a dialog rather than an
/// inline line of text.
///
/// Two of them (`trialConsumed`, `trialUnavailable`) used to route
/// straight to `/keys/entry` with no explanation at all — the learner
/// landed on a password field mid-conversation and had to infer why. The
/// third (`quotaExhausted`) said its piece in a footer under the
/// composer, where it was easy to miss entirely.
enum KeyPromptReason {
  /// `TRIAL_CONSUMED`: the free sessions this device is allowed (`trial.sessions_per_device`) are used. FR-007.
  trialConsumed,

  /// `TRIAL_UNAVAILABLE`: the shared taster is full **for everyone**
  /// today. Must never borrow quota copy — nothing is wrong with this
  /// learner's allowance.
  trialUnavailable,

  /// `TRIAL_IP_LIMIT`: this network has used today's free sessions.
  trialIpLimited,

  /// `QUOTA_EXHAUSTED`: the learner's own key hit its provider limit.
  /// FR-008d.
  quotaExhausted,

  /// A Pro Plus device whose day's Pro sessions are spent (feature 009). Not
  /// raised by a relay error code of its own: the daily screen reads
  /// `pro_limit` from `/v1/pro/status` after a free-path refusal.
  proSessionsUsed,

  /// A Pro Plus device while the operator's Pro allowance is full. Capacity,
  /// not anything the learner spent.
  proCapacity,

  /// Replay is a Pro Plus (or own-key) feature on this relay (FR-027). Raised
  /// by `ReplayGate` before anything is sent, so no reset is spent.
  replayLocked,
}

/// What the learner chose in a key prompt that may also offer Pro Plus.
enum KeyPromptChoice { addKey, getPro, dismiss }

/// Which [KeyPromptReason], if any, a [RelayError] deserves.
///
/// Exhaustive with no `default:` branch, for the reason [RelayError]
/// itself gives: a twelfth catalogue code must be a compile error here,
/// not a silent `null` that drops a learner back into an unexplained
/// form.
KeyPromptReason? keyPromptReasonFor(RelayError error) => switch (error) {
  TrialConsumed() => KeyPromptReason.trialConsumed,
  TrialUnavailable() => KeyPromptReason.trialUnavailable,
  TrialIpLimited() => KeyPromptReason.trialIpLimited,
  QuotaExhausted() => KeyPromptReason.quotaExhausted,
  // Everything else is either automatic, inline, or has a screen of
  // its own. `InvalidKey` is deliberately not here: FR-005c asks for
  // a prompt the learner taps, and `_FailureNotice` already is one.
  RateLimited() => null,
  InvalidKey() => null,
  UnclearRetry() => null,
  TurnCapReached() => null,
  SessionAlreadyJudged() => null,
  EmptyTurn() => null,
  ProblemKilled() => null,
  BadRequest() => null,
  TransportFailure() => null,
};

/// Explains why a key is being asked for, and returns `true` if the
/// learner chose to go and add one.
///
/// **This function does not navigate.** The caller pushes
/// `/keys/entry` — pushes, never `go`s, so the conversation stays on the
/// stack underneath and leaving the form returns to it instead of
/// closing the app.
Future<bool> showKeyPrompt(BuildContext context, KeyPromptReason reason) async {
  final KeyPromptChoice choice = await showKeyPromptWithPro(
    context,
    reason,
    offerPro: false,
  );
  return choice == KeyPromptChoice.addKey;
}

/// The same dialog as [showKeyPrompt], plus a third "Get Pro Plus" button when
/// [offerPro] (the relay has Pro Plus switched on). **Does not navigate**: the
/// caller pushes `/keys/entry` for [KeyPromptChoice.addKey] and the Plan
/// screen for [KeyPromptChoice.getPro].
Future<KeyPromptChoice> showKeyPromptWithPro(
  BuildContext context,
  KeyPromptReason reason, {
  required bool offerPro,
}) async {
  final AppLocalizations l10n = AppLocalizations.of(context)!;
  final KeyPromptChoice? chose = await showDialog<KeyPromptChoice>(
    context: context,
    builder: (BuildContext dialogContext) {
      void pop(KeyPromptChoice choice) =>
          Navigator.of(dialogContext).pop(choice);
      return AlertDialog(
        title: Text(_title(l10n, reason)),
        content: Text(_body(l10n, reason)),
        // Three actions do not fit one row: stack them full width, Pro Plus
        // first (it is what this relay offers), dismiss last and quietest.
        actions: offerPro
            ? <Widget>[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    FilledButton(
                      onPressed: () => pop(KeyPromptChoice.getPro),
                      child: Text(l10n.keyPromptProAction),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () => pop(KeyPromptChoice.addKey),
                      child: Text(_primaryLabel(l10n, reason)),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () => pop(KeyPromptChoice.dismiss),
                      child: Text(_dismissLabel(l10n, reason)),
                    ),
                  ],
                ),
              ]
            : <Widget>[
                TextButton(
                  onPressed: () => pop(KeyPromptChoice.dismiss),
                  child: Text(_dismissLabel(l10n, reason)),
                ),
                FilledButton(
                  onPressed: () => pop(KeyPromptChoice.addKey),
                  child: Text(_primaryLabel(l10n, reason)),
                ),
              ],
      );
    },
  );
  return chose ?? KeyPromptChoice.dismiss;
}

String _title(AppLocalizations l10n, KeyPromptReason reason) =>
    switch (reason) {
      KeyPromptReason.trialConsumed => l10n.keyPromptTrialTitle,
      KeyPromptReason.trialUnavailable => l10n.keyPromptTrialUnavailableTitle,
      KeyPromptReason.trialIpLimited => l10n.keyPromptTrialIpLimitedTitle,
      KeyPromptReason.quotaExhausted => l10n.keyPromptQuotaTitle,
      KeyPromptReason.proSessionsUsed => l10n.keyPromptProSessionsTitle,
      KeyPromptReason.proCapacity => l10n.keyPromptProCapacityTitle,
      KeyPromptReason.replayLocked => l10n.keyPromptReplayLockedTitle,
    };

String _body(AppLocalizations l10n, KeyPromptReason reason) => switch (reason) {
  KeyPromptReason.trialConsumed => l10n.keyPromptTrialBody(AppBrand.name),
  KeyPromptReason.trialUnavailable => l10n.keyPromptTrialUnavailableBody(
    AppBrand.name,
  ),
  KeyPromptReason.trialIpLimited => l10n.keyPromptTrialIpLimitedBody(
    AppBrand.name,
  ),
  KeyPromptReason.quotaExhausted => l10n.keyPromptQuotaBody,
  KeyPromptReason.proSessionsUsed => l10n.keyPromptProSessionsBody,
  KeyPromptReason.proCapacity => l10n.keyPromptProCapacityBody,
  KeyPromptReason.replayLocked => l10n.keyPromptReplayLockedBody,
};

String _primaryLabel(AppLocalizations l10n, KeyPromptReason reason) =>
    switch (reason) {
      KeyPromptReason.trialConsumed ||
      KeyPromptReason.trialUnavailable ||
      KeyPromptReason.trialIpLimited ||
      KeyPromptReason.proSessionsUsed ||
      KeyPromptReason.proCapacity ||
      KeyPromptReason.replayLocked => l10n.keyPromptAddAction,
      // The learner already has a key; the only thing that continues
      // today is a different one (ErrorNextAction.waitOrReplaceKey).
      KeyPromptReason.quotaExhausted => l10n.keyPromptReplaceAction,
    };

String _dismissLabel(AppLocalizations l10n, KeyPromptReason reason) =>
    switch (reason) {
      KeyPromptReason.trialConsumed ||
      KeyPromptReason.trialUnavailable ||
      KeyPromptReason.trialIpLimited ||
      KeyPromptReason.proSessionsUsed ||
      KeyPromptReason.proCapacity ||
      KeyPromptReason.replayLocked => l10n.keyPromptDismissAction,
      KeyPromptReason.quotaExhausted => l10n.keyPromptQuotaDismissAction,
    };
