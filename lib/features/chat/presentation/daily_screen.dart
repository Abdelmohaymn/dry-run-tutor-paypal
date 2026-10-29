import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_copy.dart';
import '../../../core/errors/relay_error.dart';
import '../../../core/errors/result.dart';
import '../../../core/l10n/generated/app_localizations.dart';
// `Verdict` here is `daily_session_state.dart`'s Cubit state, not the wire
// enum of the same name — hidden to resolve the clash, exactly as the
// Cubit does.
import '../../../core/models/wire_enums.dart' hide Verdict;
import '../../../core/router/app_route.dart';
import '../../../core/text/math_notation.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../hints/presentation/hint_action.dart';
import '../../keys/presentation/key_prompt_dialog.dart';
import '../../plan/domain/plan_repository.dart';
import '../../plan/domain/plan_status.dart';
import '../../plan/domain/replay_gate.dart';
import '../../plan/presentation/replay_locked_prompt.dart';
import '../../problem/domain/problem.dart';
import '../../problem/presentation/examples_action.dart';
import '../domain/message.dart';
import '../domain/session.dart';
import 'daily_session_cubit.dart';
import 'daily_session_state.dart';
import 'widgets/composer.dart';
import 'widgets/inline_recorder.dart';
import 'widgets/inline_review.dart';
import 'widgets/message_list.dart';
import 'widgets/rate_limit_dialog.dart';
import 'widgets/turn_gauge.dart';
import 'widgets/typing_indicator.dart';
import 'widgets/finish_offer_card.dart';
import 'widgets/wrap_up_banner.dart';

/// The daily loop (prototype screen 1): opens straight onto the problem,
/// the problem collapses to a card, and chat owns the rest of the screen
/// — no menu, no list, no archive (FR-035).
///
/// **The whole turn happens here.** Speaking, watching the transcript
/// land, and editing it before sending were three screens; they are now
/// three states of this one screen's composer slot, so the conversation
/// stays visible from the first word to the last. `/session/record` and
/// `/session/review` still exist as routes and screens — nothing routes
/// to them any more (`DailySessionShell._routeFor`).
class DailyScreen extends StatefulWidget {
  /// Feature 009 (Pro Plus). All three are optional and default to "no Pro":
  /// [planRepository] and [proOffered] let a free-limit prompt offer Pro Plus,
  /// and [replayGate] lets "Practice again" and the problem picker show the
  /// offer instead of calling the relay when replay is a Pro or own-key
  /// feature. Nothing is added to this screen's app bar or composer (FR-021).
  const DailyScreen({
    this.planRepository,
    this.proOffered = false,
    this.replayGate,
    super.key,
  });

  final PlanRepository? planRepository;
  final bool proOffered;
  final ReplayGate? replayGate;

  @override
  State<DailyScreen> createState() => _DailyScreenState();
}

class _DailyScreenState extends State<DailyScreen> {
  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Scaffold(
      // The prototype draws no chrome at all (docs/ui-prototype.html —
      // twelve screens, none with a nav bar), because it never had to
      // solve how `/streak` and `/settings` get reached: FR-035 bans a
      // menu or list *of past days*, not a way to the two screens this
      // feature adds that aren't part of that history. Two icons, not a
      // drawer or a tab bar — and a short bar, because every pixel it
      // takes is one the conversation does not get.
      appBar: AppBar(
        toolbarHeight: 44,
        title: const SizedBox.shrink(),
        centerTitle: false,
        actions: <Widget>[
          // FR-023 needs ending the session to be reachable, not to be
          // one of the controls sitting between the conversation and the
          // composer — it is the once-per-day action on this screen, and
          // it was costing a whole row of the chat's height every turn.
          BlocBuilder<DailySessionCubit, DailySessionState>(
            buildWhen: (DailySessionState previous, DailySessionState current) =>
                _canEndSession(previous) != _canEndSession(current),
            builder: (BuildContext context, DailySessionState state) {
              if (!_canEndSession(state)) {
                return const SizedBox.shrink();
              }
              // Labelled, not an icon. A glyph is something a learner has
              // to tap to understand, and this one ends their session —
              // the single action they most need to recognise on sight,
              // and the one a first real run showed they never found.
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: TextButton.icon(
                  onPressed: () => context.read<DailySessionCubit>().endSessionUser(),
                  icon: const Icon(Icons.task_alt, size: 18),
                  label: Text(l10n.finishActionLabel),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTokens.accent,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.local_fire_department_outlined, size: 20),
            tooltip: l10n.dailyStreakTooltip,
            onPressed: () => context.push(AppRoute.streak.path),
          ),
          IconButton(
            icon: const Icon(Icons.replay, size: 20),
            tooltip: l10n.verdictPracticeAgainAction,
            onPressed: () async {
              if (await _replayLocked(context)) {
                return;
              }
              if (!context.mounted) {
                return;
              }
              final Result<void> result = await context.read<DailySessionCubit>().practiceAgain();
              if (!context.mounted) {
                return;
              }
              if (result case Err<void>(:final error)) {
                final copy = resolveErrorCopy(l10n, error);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${copy.message} (${copy.code})')),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.list_alt_outlined, size: 20),
            tooltip: l10n.problemPickerTitle,
            onPressed: () async {
              if (await _replayLocked(context)) {
                return;
              }
              if (context.mounted) {
                await context.push(AppRoute.problemPicker.path);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 20),
            tooltip: l10n.dailySettingsTooltip,
            onPressed: () => context.push(AppRoute.settings.path),
          ),
        ],
      ),
      body: SafeArea(
        // A key prompt is a dialog, not a redirect. TRIAL_CONSUMED and
        // TRIAL_UNAVAILABLE used to drop the learner straight onto a
        // password field mid-conversation, and QUOTA_EXHAUSTED said its
        // piece in a footer under the composer — neither ever explained
        // itself. `listenWhen` compares the *reason*, not the state, so
        // this raises once per transition into one: a dismissed dialog
        // stays dismissed, and coming back from the form does not raise
        // it again. RATE_LIMITED raises its own popup the same way, once
        // per entry, and that one closes itself when the Cubit resends.
        child: BlocConsumer<DailySessionCubit, DailySessionState>(
          listenWhen: (DailySessionState previous, DailySessionState current) =>
              _promptReasonFor(previous) != _promptReasonFor(current) ||
              (!isRateLimited(previous) && isRateLimited(current)),
          listener: (BuildContext context, DailySessionState state) {
            if (state case Failure(error: RateLimited(:final retryAfter))) {
              unawaited(showRateLimitDialog(context, retryAfter));
              return;
            }
            unawaited(_promptForKey(context, _promptReasonFor(state)));
          },
          builder: (BuildContext context, DailySessionState state) {
            final DailySessionCubit cubit = context.read<DailySessionCubit>();
            return switch (state) {
              Opening() || Reading() || ProblemUnavailable() => const Center(child: CircularProgressIndicator()),
              Composing(:final session, :final notice) => _DailyBody(
                  session: session,
                  notice: notice,
                  showControls: true,
                  showFinishNudge: _shouldNudgeToFinish(session),
                  footer: Composer(
                    onMicTap: () => _onMicTap(context),
                    onSubmit: cubit.sendTyped,
                  ),
                ),
              // Speaking, in the conversation. No screen change, and the
              // controls step aside so the recording bar is the only thing
              // that can be tapped by mistake mid-turn.
              Recording(:final session, :final elapsed, :final levels, :final warned, :final partialText, :final limit) =>
                _DailyBody(
                  session: session,
                  footer: InlineRecorder(
                    elapsed: elapsed,
                    levels: levels,
                    warned: warned,
                    partialText: partialText,
                    limit: limit,
                    onStop: cubit.stopRecording,
                    onCancel: cubit.cancelRecording,
                  ),
                ),
              Recognising(:final session) => _DailyBody(
                  session: session,
                  footer: const _TranscribingNotice(),
                ),
              VoiceUploadFailed(:final session) => _DailyBody(
                  session: session,
                  footer: const _VoiceRetryNotice(),
                ),
              ReviewingTranscript(:final session, :final draft) => _DailyBody(
                  session: session,
                  footer: InlineReview(
                    draft: draft,
                    glossaryTerms: session.problem.glossaryTerms,
                    onChanged: cubit.updateDraftText,
                    onGlossaryApply: cubit.applyGlossaryChipEdit,
                    onSend: cubit.send,
                    onSecondary: draft.inputMode == InputMode.voice ? cubit.reRecord : cubit.discardDraft,
                    onRevert: cubit.revertRepair,
                  ),
                ),
              // The waiting shows as a tutor bubble in the conversation
              // (`MessageList.awaitingReply`), not as a spinner in the
              // composer: it belongs where the reply is about to land.
              Sending(:final session) => _DailyBody(
                  session: session,
                  awaitingReply: true,
                  footer: const SizedBox.shrink(),
                ),
              // A hint that has been paid for and is on the wire. Same
              // treatment as a turn, for the same reason: the waiting
              // belongs where the hint is about to appear, and the
              // controls step aside so the video cannot be bought twice
              // by a second tap.
              PullingHint(:final session) => _DailyBody(
                  session: session,
                  awaitingReply: true,
                  footer: const SizedBox.shrink(),
                ),
              Streaming(:final session, :final partialText) => _DailyBody(
                  session: session,
                  // Tokens arrive one at a time; until the first one does,
                  // the bubble keeps the dots rather than flashing empty.
                  streamingText: partialText.isEmpty ? null : partialText,
                  awaitingReply: partialText.isEmpty,
                  footer: const SizedBox.shrink(),
                ),
              WrappingUp(:final session) => _DailyBody(
                  session: session,
                  banner: WrapUpBanner(
                    onFinish: session.counters.turnIndex > 0 ? cubit.endSessionUser : null,
                  ),
                  showControls: true,
                  footer: Composer(
                    onMicTap: () => _onMicTap(context),
                    onSubmit: cubit.sendTyped,
                  ),
                ),
              FinishOffered(:final session) => _DailyBody(
                  session: session,
                  banner: FinishOfferCard(
                    onFinish: cubit.acceptFinishOffer,
                    onKeepGoing: cubit.dismissFinishOffer,
                  ),
                  showControls: true,
                  footer: Composer(
                    onMicTap: () => _onMicTap(context),
                    onSubmit: cubit.sendTyped,
                  ),
                ),
              CapReached(:final session) =>
                _DailyBody(session: session, footer: _CapReachedNotice(session: session)),
              SessionClosed(:final session) =>
                _DailyBody(session: session, footer: const _SessionClosedNotice()),
              Judging(:final session) => _DailyBody(session: session, footer: const _JudgingNotice()),
              // Reached by backing out of the verdict rather than by the
              // state machine (`VerdictScreen`'s own back). The assessment
              // is already in hand, so this is a way back to it — never a
              // dead end on a screen with nothing left to do.
              Verdict(:final session) || Revealed(:final session) => _DailyBody(
                  session: session,
                  footer: _AssessmentReadyNotice(cubit: cubit, replayGate: widget.replayGate),
                ),
              Failure(:final session, :final error) =>
                _DailyBody(session: session, footer: _FailureNotice(error: error)),
              ConfirmSolutionRelease() || RecognitionUnavailable() =>
                const Center(child: CircularProgressIndicator()),
            };
          },
        ),
      ),
    );
  }

  /// The [KeyPromptReason] a state has earned, or `null` for every state
  /// that is not a key-shaped failure.
  static KeyPromptReason? _promptReasonFor(DailySessionState state) =>
      state is Failure ? keyPromptReasonFor(state.error) : null;

  /// True, after showing the Pro Plus offer, when "Practice again" or the
  /// problem picker is a Pro or own-key feature on this relay and this learner
  /// has neither. Asked before the relay is called, so nothing is spent on a
  /// refusal (FR-027).
  Future<bool> _replayLocked(BuildContext context) async {
    final ReplayGate? gate = widget.replayGate;
    if (gate == null || !await gate.isLocked()) {
      return false;
    }
    if (context.mounted) {
      await showReplayLockedPrompt(context, gate);
    }
    return true;
  }

  /// Explains the situation, and only then opens the form — **pushed**,
  /// so the conversation is still on the stack underneath it and backing
  /// out returns here rather than closing the app.
  ///
  /// With Pro Plus on offer (feature 009) a free-limit refusal first asks the
  /// relay for the plan: a Pro device is told which Pro limit it hit, and a
  /// free one is offered Pro Plus next to the key.
  Future<void> _promptForKey(BuildContext context, KeyPromptReason? reason) async {
    if (reason == null) {
      return;
    }
    KeyPromptReason shown = reason;
    bool offerPro = false;
    final PlanRepository? plans = widget.planRepository;
    final bool freeLimit = reason == KeyPromptReason.trialConsumed ||
        reason == KeyPromptReason.trialUnavailable ||
        reason == KeyPromptReason.trialIpLimited;
    if (freeLimit && plans != null && widget.proOffered) {
      final Result<PlanStatus> refreshed = await plans.refresh();
      if (!context.mounted) {
        return;
      }
      if (refreshed case Ok<PlanStatus>(:final value)) {
        if (value.plan == PlanKind.pro) {
          shown = switch (value.proLimit) {
            ProLimit.sessionsUsed => KeyPromptReason.proSessionsUsed,
            ProLimit.capacity => KeyPromptReason.proCapacity,
            ProLimit.ok || null => reason,
          };
        } else {
          offerPro = true;
        }
      }
    }
    final KeyPromptChoice choice = await showKeyPromptWithPro(context, shown, offerPro: offerPro);
    if (!context.mounted) {
      return;
    }
    switch (choice) {
      case KeyPromptChoice.addKey:
        await context.push(AppRoute.keysEntry.path);
      case KeyPromptChoice.getPro:
        await context.push(AppRoute.settingsPlan.path);
      case KeyPromptChoice.dismiss:
        break;
    }
  }

  /// After this many turns, a learner who has not finished is very likely
  /// not to know they can. Deliberately below the wrap-up threshold: the
  /// wrap-up card fires when the *allowance* is nearly gone, which is a
  /// different thing from "you have said enough to be assessed".
  static const int _nudgeToFinishAfterTurn = 4;

  static bool _shouldNudgeToFinish(Session session) =>
      session.counters.turnIndex >= _nudgeToFinishAfterTurn;

  /// Ending the session needs something to assess (FR-023, US4 scenario
  /// 1) and a session still open to end — the same three states
  /// `endSessionUser()` itself accepts.
  static bool _canEndSession(DailySessionState state) => switch (state) {
        Composing(:final session) ||
        WrappingUp(:final session) ||
        FinishOffered(:final session) ||
        CapReached(:final session) =>
          session.counters.turnIndex > 0,
        _ => false,
      };

  Future<void> _onMicTap(BuildContext context) async {
    final DailySessionCubit cubit = context.read<DailySessionCubit>();
    if (await cubit.shouldShowMicRationale()) {
      if (context.mounted) {
        context.go(AppRoute.sessionMicRationale.path);
      }
      return;
    }
    await cubit.startRecording();
  }
}

class _DailyBody extends StatelessWidget {
  const _DailyBody({
    required this.session,
    required this.footer,
    this.banner,
    this.showControls = false,
    this.showFinishNudge = false,
    this.streamingText,
    this.awaitingReply = false,
    this.notice,
  });

  final Session session;
  final Widget footer;
  final Widget? banner;

  /// A non-error explanation for why the composer is back, resolved
  /// against the ARB here rather than in the Cubit (see
  /// `DailySessionCubit.nothingHeardNotice`).
  final String? notice;

  /// Hint, examples, and ask-for-the-answer. Live in [Composing] and
  /// [WrappingUp] (FR-028); [CapReached] embeds its own copy inside
  /// `_CapReachedNotice` alongside the end-session affordance, so it is
  /// left off there rather than shown twice, and mid-turn states hide it
  /// so nothing competes with the one control that ends the turn.
  final bool showControls;

  /// Puts the finish action in the conversation itself, once the learner
  /// has been talking long enough that not knowing about it is costing
  /// them the assessment.
  final bool showFinishNudge;
  final String? streamingText;
  final bool awaitingReply;

  /// Resolves [notice] against the ARB; null when there is nothing to say
  /// (or the id is not one this body knows).
  String? _noticeText(AppLocalizations l10n) => switch (notice) {
        DailySessionCubit.nothingHeardNotice => l10n.recordingNothingHeardNotice,
        DailySessionCubit.cloudVoiceFailedNotice => l10n.recordingCloudFailedNotice,
        DailySessionCubit.cloudVoiceFallbackNotice => l10n.recordingCloudFallbackNotice,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _ProblemCard(problem: session.problem),
        // Before the first `meta` frame ever arrives, `ServerCounters`
        // is still `.initial` — `turnsRemaining: 0` is a placeholder,
        // not a real "the cap is reached" claim (FR-019: the app never
        // computes a counter, and that includes not manufacturing one to
        // fill this gap). Showing the gauge before there is anything
        // server-sourced to show would read as a false "no turns left"
        // to a learner who has not sent a single turn yet — found live
        // on a physical device during T083/T164's walkthrough.
        if (session.counters.turnIndex > 0) TurnGauge(counters: session.counters),
        ?banner,
        // One `StreamBuilder` over both the conversation and the controls:
        // how many examples are already revealed is counted off the
        // message rows (the same trick the hint ordinal uses), so the
        // control that reveals the next one has to read the same stream
        // the list does rather than duplicating the count in state.
        Expanded(
          child: StreamBuilder<List<Message>>(
            stream: context.read<DailySessionCubit>().watchMessages(session.id),
            builder: (BuildContext context, AsyncSnapshot<List<Message>> snapshot) {
              final List<Message> messages = snapshot.data ?? const <Message>[];
              final int examplesRevealed =
                  messages.where((Message m) => m.kind == MessageKind.example).length;
              return Column(
                children: <Widget>[
                  Expanded(
                    child: MessageList(
                      messages: messages,
                      hintCount: session.problem.hintCount,
                      exampleCount: session.problem.examples.length,
                      streamingText: streamingText,
                      awaitingReply: awaitingReply,
                      onRetry: context.read<DailySessionCubit>().retryFailedTurn,
                    ),
                  ),
                  if (showFinishNudge) const _FinishNudge(),
                  if (showControls)
                    _SessionControls(session: session, examplesRevealed: examplesRevealed),
                ],
              );
            },
          ),
        ),
        if (_noticeText(AppLocalizations.of(context)!) case final String text)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Text(
              text,
              style: context.appTypography.sansCaption.copyWith(color: AppTokens.amber),
              textAlign: TextAlign.center,
            ),
          ),
        Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 8), child: footer),
      ],
    );
  }
}

/// Says out loud what a first real run showed nobody guesses: the tutor
/// will keep asking forever, and the assessment is something the learner
/// asks for. Amber and bordered so it reads as a nudge, never as an error.
class _FinishNudge extends StatelessWidget {
  const _FinishNudge();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppTokens.amberDim,
        border: Border.all(color: AppTokens.amberBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.task_alt, size: 18, color: AppTokens.amber),
          const SizedBox(width: 10),
          Expanded(
            child: Text(l10n.finishNudgeBody, style: context.appTypography.sansCaption),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => context.read<DailySessionCubit>().endSessionUser(),
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            child: Text(l10n.finishActionLabel),
          ),
        ],
      ),
    );
  }
}

/// One line for everything the learner can ask of the session that is not
/// a turn.
///
/// It was three stacked captioned controls plus a shared cost notice —
/// four rows of chrome between the conversation and the composer. Ending
/// the session moved to the app bar (once-per-day, not per-turn), and the
/// cost notice went entirely: it was a standing sentence of small print
/// about two buttons that spend nothing, which is exactly the kind of
/// reassurance nobody reads twice.
class _SessionControls extends StatelessWidget {
  const _SessionControls({required this.session, required this.examplesRevealed});

  final Session session;
  final int examplesRevealed;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final DailySessionCubit cubit = context.read<DailySessionCubit>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
      // A `Wrap`, not a `Row`: these do not fit on one line at the larger
      // accessibility text sizes, and a `Row` clips them silently rather
      // than reflowing (T159).
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 2,
        children: <Widget>[
          HintAction(session: session, onPressed: cubit.pullHint),
          ExamplesAction(
            problem: session.problem,
            revealed: examplesRevealed,
            dense: true,
            onPressed: cubit.pullExample,
          ),
          // The tutor is Socratic by design — it asks rather than tells,
          // and never says "correct" or "wrong" (FR-030, tutor prompt
          // §HOW TO REPLY). Without an explicit way to ask for the answer,
          // a learner who is stuck has no exit but to burn every turn. The
          // first tap is an ordinary turn; a second routes to FR-021's
          // unskippable warning.
          if (session.counters.turnIndex > 0)
            TextButton(
              onPressed: cubit.requestSolution,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: Text(l10n.askForAnswerLabel),
            ),
        ],
      ),
    );
  }
}

/// FR-035's "the problem collapses to a card" is a *default*, not a
/// ceiling: clipping the statement with no way past it left the learner
/// unable to read the problem they were being asked to talk through, and
/// hid the authored `constraints` entirely — both found on a physical
/// device. Collapsed stays the default so the conversation still owns the
/// screen; expanding is one tap and scrolls within a bounded box so a long
/// statement can never push the composer off-screen.
class _ProblemCard extends StatefulWidget {
  const _ProblemCard({required this.problem});

  final Problem problem;

  @override
  State<_ProblemCard> createState() => _ProblemCardState();
}

class _ProblemCardState extends State<_ProblemCard> {
  bool _expanded = false;
  // Owned here so the always-visible scrollbar has a controller to track;
  // without one it falls back to the PrimaryScrollController — the
  // conversation's — and asserts.
  final ScrollController _statementScroll = ScrollController();

  @override
  void dispose() {
    _statementScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final Problem problem = widget.problem;
    // Only offer the control when there is something behind it: a short
    // statement with no constraints already shows everything it has.
    final bool hasMore = problem.constraints.isNotEmpty || problem.statement.length > 120;
    // With the keyboard up there is no room for the full statement and the
    // composer both — an expanded card pushed the composer 98px off-screen
    // on a physical device. It folds back while typing and returns to
    // whatever the learner chose once the keyboard closes. Read from the
    // `View`, not `MediaQuery`: the Scaffold strips the keyboard inset from
    // its body's MediaQuery, so that always said 0 here and the expanded
    // card shoved the review field under the keyboard.
    final bool keyboardUp = View.of(context).viewInsets.bottom > 0;
    final bool expanded = _expanded && !keyboardUp;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: InkWell(
        onTap: hasMore ? () => setState(() => _expanded = !_expanded) : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(problem.title, style: context.appTypography.sansHeadline),
                  ),
                  if (hasMore)
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: AppTokens.accent,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              if (expanded)
                ConstrainedBox(
                  // A third of the screen at most, then
                  // it scrolls — the composer and the conversation keep
                  // their room.
                  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height / 3),
                  // Always visible and in the accent: a statement clipped at the
                  // box edge reads as finished unless something says there is more.
                  child: RawScrollbar(
                    controller: _statementScroll,
                    thumbVisibility: true,
                    thumbColor: AppTokens.accent,
                    thickness: 3,
                    radius: const Radius.circular(2),
                    // Insets the track so the thumb runs shorter than the box.
                    mainAxisMargin: 24,
                    child: SingleChildScrollView(
                      controller: _statementScroll,
                      // Keeps the text clear of the thumb.
                      padding: const EdgeInsets.only(right: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(problem.statement, style: context.appTypography.sansBody),
                          if (problem.constraints.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 12),
                            Text(l10n.problemConstraintsLabel, style: context.appTypography.monoLabel),
                            const SizedBox(height: 4),
                            for (final String constraint in problem.constraints)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    // A drawn bullet rather than a literal
                                    // dash in the Text: authored constraint
                                    // copy is the only string here, and
                                    // `arb_completeness_test` rightly refuses
                                    // any bare literal handed to Text().
                                    const Padding(
                                      padding: EdgeInsets.only(top: 6, right: 6),
                                      child: Icon(Icons.remove, size: 10, color: AppTokens.faint),
                                    ),
                                    Expanded(
                                      // `1000000000` says nothing about the
                                      // order of magnitude a constraint
                                      // exists to state; `10⁹` does.
                                      child: Text(
                                        MathNotation.format(constraint),
                                        style: context.appTypography.monoBody
                                            .copyWith(color: AppTokens.muted),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                )
              else
                Text(
                  problem.statement,
                  style: context.appTypography.sansBody,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TranscribingNotice extends StatelessWidget {
  const _TranscribingNotice();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        const TypingIndicator(dotSize: 6),
        const SizedBox(width: 12),
        Text(
          l10n.recordingTranscribingLabel,
          style: context.appTypography.sansCaption.copyWith(color: AppTokens.muted),
        ),
      ],
    );
  }
}

class _JudgingNotice extends StatelessWidget {
  const _JudgingNotice();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        const TypingIndicator(dotSize: 6),
        const SizedBox(width: 12),
        Text(l10n.judgingNotice, style: context.appTypography.sansCaption),
      ],
    );
  }
}

/// The verdict exists and the learner walked back to the conversation.
class _AssessmentReadyNotice extends StatelessWidget {
  const _AssessmentReadyNotice({required this.cubit, this.replayGate});

  final DailySessionCubit cubit;
  final ReplayGate? replayGate;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(l10n.assessmentReadyTitle, style: context.appTypography.sansHeadline),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            FilledButton(
              onPressed: () => context.go(AppRoute.sessionVerdict.path),
              child: Text(l10n.assessmentReadyAction),
            ),
            OutlinedButton(
              onPressed: () async {
                if (await replayGate?.isLocked() ?? false) {
                  if (context.mounted) {
                    await showReplayLockedPrompt(context, replayGate!);
                  }
                  return;
                }
                if (!context.mounted) {
                  return;
                }
                final Result<void> result = await cubit.practiceAgain();
                if (!context.mounted) {
                  return;
                }
                if (result case Err<void>(:final error)) {
                  final ErrorCopy copy = resolveErrorCopy(l10n, error);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${copy.message} (${copy.code})')),
                  );
                }
              },
              child: Text(l10n.assessmentPracticeAgainAction),
            ),
          ],
        ),
      ],
    );
  }
}

/// FR-028: hints stay live at the cap. FR-023: so does the learner's own
/// ability to close the session — the cap bounds conversation, not either
/// of those, which is why `CapReached` and (Phase 6's) `SessionClosed` are
/// separate states.
class _CapReachedNotice extends StatelessWidget {
  const _CapReachedNotice({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(l10n.capReachedTitle, style: context.appTypography.sansHeadline),
        const SizedBox(height: 4),
        Text(l10n.capReachedBody, style: context.appTypography.sansCaption, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            HintAction(session: session, onPressed: () => context.read<DailySessionCubit>().pullHint()),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: () => context.read<DailySessionCubit>().endSessionUser(),
              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
              child: Text(l10n.endSessionLabel),
            ),
          ],
        ),
      ],
    );
  }
}

/// FR-034 scenario 4: a stray turn or hint landed after the verdict was
/// already delivered. Told the session is closed, with a way back to the
/// assessment this install already holds — never a bare failure.
class _SessionClosedNotice extends StatelessWidget {
  const _SessionClosedNotice();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(l10n.sessionClosedTitle, style: context.appTypography.sansHeadline),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => context.read<DailySessionCubit>().openClosedAssessment(),
          child: Text(l10n.sessionClosedReviewAction),
        ),
      ],
    );
  }
}

/// Footer for [VoiceUploadFailed]: the recorded clip is still saved, so the
/// learner can re-upload it or throw it away. No error code line; the cause
/// is a dropped connection or a busy service, not something to look up.
class _VoiceRetryNotice extends StatelessWidget {
  const _VoiceRetryNotice();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final DailySessionCubit cubit = context.read<DailySessionCubit>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          l10n.recordingCloudRetryTitle,
          style: context.appTypography.sansBody,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          l10n.recordingCloudRetryBody,
          style: context.appTypography.sansCaption,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        FilledButton(onPressed: cubit.retryVoiceUpload, child: Text(l10n.retryAction)),
        TextButton(
          onPressed: cubit.discardVoiceClip,
          child: Text(l10n.recordingCloudDiscardAction),
        ),
      ],
    );
  }
}

class _FailureNotice extends StatelessWidget {
  const _FailureNotice({required this.error});

  final RelayError error;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ErrorCopy copy = resolveErrorCopy(l10n, error);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(copy.message, style: context.appTypography.sansBody, textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(
          l10n.errorCodeLabel(copy.code),
          style: context.appTypography.sansCaption.copyWith(color: AppTokens.faint),
        ),
        const SizedBox(height: 8),
        if (copy.nextAction case ErrorNextAction.reEnterKey || ErrorNextAction.waitOrReplaceKey)
          // INVALID_KEY and QUOTA_EXHAUSTED: resending with the same key
          // would fail identically, so this is a prompt to re-enter or
          // replace it (FR-005c, FR-008d) rather than `retry()`.
          FilledButton(
            // `push`, not `go`: replacing the stack leaves the key form
            // with nothing to pop back to, and the system back gesture
            // then closes the app instead of returning to the
            // conversation.
            onPressed: () => context.push(AppRoute.keysEntry.path),
            child: Text(l10n.errorReEnterKeyAction),
          )
        else
          // Also shown for RATE_LIMITED (automaticRetry): a retry that runs
          // by itself but is invisible looks like a dead end, and a learner
          // who just fixed their key wants to retry now. The cubit cancels
          // its pending timer when this is tapped.
          FilledButton(
            onPressed: () => context.read<DailySessionCubit>().retry(),
            child: Text(l10n.retryAction),
          ),
      ],
    );
  }
}
