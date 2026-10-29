import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/errors/error_copy.dart';
import '../../../core/errors/result.dart';
import '../../../core/models/wire_enums.dart' show MatchedVerdict;
import '../../../core/router/app_route.dart';
import '../../../core/text/markdown_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../chat/presentation/daily_session_cubit.dart';
import '../../chat/presentation/daily_session_state.dart';
import '../../plan/domain/replay_gate.dart';
import '../../plan/presentation/replay_locked_prompt.dart';
import '../../streak/presentation/share_card.dart';
import '../domain/assessment.dart';
import '../domain/complexity.dart';
import 'assessment_copy.dart';
import 'dispute_action.dart';

/// Prototype screen 6: a hedged chip pairing hue with a word, insight
/// ticks and misses as distinct glyphs, dispute one tap away and always
/// present. **No red anywhere on this screen** (design-tokens.md) — a
/// verdict is never presented as a failure.
class VerdictScreen extends StatelessWidget {
  /// [replayGate] (feature 009) lets "Practice again" and the problem picker
  /// show the Pro Plus offer instead of calling the relay when replay is a
  /// Pro or own-key feature. Without it both behave exactly as before.
  const VerdictScreen({this.replayGate, super.key});

  final ReplayGate? replayGate;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    // This screen is reached with `go` — the assessment ends the session,
    // so there is deliberately no stack under it to pop. Without this,
    // system back found nothing to pop and closed the app outright
    // (found on a physical device). Back returns to the conversation,
    // which now offers a way straight back here.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) {
          context.go(AppRoute.daily.path);
        }
      },
      child: _NotificationNudgeHost(
      child: Scaffold(
      appBar: AppBar(
        title: Text(l10n.verdictScreenTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: l10n.backAction,
          onPressed: () => context.go(AppRoute.daily.path),
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.list_alt_outlined),
            tooltip: l10n.problemPickerTitle,
            onPressed: () async {
              if (await replayGate?.isLocked() ?? false) {
                if (context.mounted) {
                  await showReplayLockedPrompt(context, replayGate!);
                }
                return;
              }
              if (context.mounted) {
                await context.push(AppRoute.problemPicker.path);
              }
            },
          ),
          BlocBuilder<DailySessionCubit, DailySessionState>(
            buildWhen: (_, state) => state is Verdict || state is Revealed,
            builder: (BuildContext context, DailySessionState state) {
              if (state is! Verdict && state is! Revealed) {
                return const SizedBox.shrink();
              }
              return IconButton(
                icon: const Icon(Icons.replay),
                tooltip: l10n.verdictPracticeAgainAction,
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
                  final Result<void> result = await context.read<DailySessionCubit>().practiceAgain();
                  if (!context.mounted) {
                    return;
                  }
                  switch (result) {
                    case Ok<void>():
                      context.go(AppRoute.daily.path);
                    case Err<void>(:final error):
                      final copy = resolveErrorCopy(l10n, error);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${copy.message} (${copy.code})')),
                      );
                  }
                },
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: BlocBuilder<DailySessionCubit, DailySessionState>(
          builder: (BuildContext context, DailySessionState state) {
            if (state is! Verdict) {
              return const SizedBox.shrink();
            }
            final DailySessionCubit cubit = context.read<DailySessionCubit>();
            final Assessment assessment = state.assessment;
            final VerdictCopy verdictCopy = resolveVerdictCopy(l10n, assessment.verdict);

            return ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                _VerdictChip(copy: verdictCopy),
                const SizedBox(height: 16),
                Text(
                  resolveMatchedVerdictCopy(l10n, assessment.matchedVerdict),
                  style: context.appTypography.sansBody,
                ),
                if (assessment.revealAtIndex != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    l10n.verdictSolutionReleaseNotice,
                    style: context.appTypography.sansCaption.copyWith(color: AppTokens.muted),
                  ),
                ],
                if (assessment.matchedVerdict == MatchedVerdict.none) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    l10n.verdictComplexityUnlistedNotice,
                    style: context.appTypography.sansCaption.copyWith(color: AppTokens.muted),
                  ),
                ],
                const SizedBox(height: 20),
                Text(l10n.verdictComplexityLabel, style: context.appTypography.sansHeadline),
                const SizedBox(height: 6),
                _ComplexityDetail(complexity: assessment.complexity),
                const SizedBox(height: 20),
                _InsightGlyphList(
                  label: l10n.verdictInsightsHitLabel,
                  insights: assessment.insightsHit,
                  glyph: Icons.circle,
                  assisted: assessment.insightsAssisted.toSet(),
                ),
                const SizedBox(height: 12),
                _InsightGlyphList(
                  label: l10n.verdictInsightsMissedLabel,
                  insights: assessment.insightsMissed,
                  glyph: Icons.circle_outlined,
                ),
                const SizedBox(height: 20),
                // The judge writes Markdown — `**like this**` — and this
                // used to paint the asterisks.
                MarkdownText(assessment.feedback),
                const SizedBox(height: 24),
                // The share used to live only behind Streak -> Review
                // today, which is three taps from the one screen where a
                // learner has just been handed something worth sharing.
                _ShareSection(
                  assessment: assessment,
                  problemTitle: state.session.problem.title,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () {
                    cubit.revealAssessment();
                    context.go(AppRoute.sessionReveal.path);
                  },
                  child: Text(l10n.verdictReadEditorialAction),
                ),
                const SizedBox(height: 12),
                DisputeAction(disputed: state.session.disputed, onPressed: cubit.disputeAssessment),
              ],
            );
          },
        ),
      ),
      ),
      ),
    );
  }
}

/// Asks once, the first time a daily verdict is on screen, for the
/// notifications the daily reminder needs. The repository decides whether
/// it is due; this only waits for the verdict and shows the popup.
class _NotificationNudgeHost extends StatefulWidget {
  const _NotificationNudgeHost({required this.child});

  final Widget child;

  @override
  State<_NotificationNudgeHost> createState() => _NotificationNudgeHostState();
}

class _NotificationNudgeHostState extends State<_NotificationNudgeHost> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_maybeAsk(context.read<DailySessionCubit>().state));
      }
    });
  }

  Future<void> _maybeAsk(DailySessionState state) async {
    if (_checked || state is! Verdict) {
      return;
    }
    _checked = true;
    final DailySessionCubit cubit = context.read<DailySessionCubit>();
    if (!await cubit.takeNotificationNudge() || !mounted) {
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final bool accepted =
        await showDialog<bool>(
          context: context,
          // Only the two buttons close it: no tapping outside, no back.
          barrierDismissible: false,
          builder: (BuildContext dialogContext) => PopScope(
            canPop: false,
            child: AlertDialog(
            icon: const Icon(Icons.notifications_active_outlined),
            title: Text(l10n.notificationNudgeTitle),
            content: Text(l10n.notificationNudgeBody),
            // One row, always: AlertDialog stacks its actions vertically as
            // soon as they don't fit, which read as two separate choices.
            actions: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: Text(l10n.notificationNudgeDismiss),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: Text(l10n.notificationNudgeAction),
                    ),
                  ),
                ],
              ),
            ],
          ),
          ),
        ) ??
        false;
    if (!accepted || !mounted) {
      return;
    }
    await cubit.enableDailyReminder();
    if (mounted) {
      // The time picker lives there, and it re-reads the permission when
      // the learner comes back from Android's settings.
      unawaited(context.push(AppRoute.settingsReminder.path));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<DailySessionCubit, DailySessionState>(
      listener: (BuildContext context, DailySessionState state) => unawaited(_maybeAsk(state)),
      child: widget.child,
    );
  }
}

/// The share card, once the streak it prints has resolved.
///
/// Stateful, and the read happens exactly once in [initState]: this screen
/// rebuilds on every Cubit emission (a dispute, for one), and starting a
/// fresh future in `build` would re-query the streak each time and flash
/// the card away and back while it resolved.
class _ShareSection extends StatefulWidget {
  const _ShareSection({required this.assessment, required this.problemTitle});

  final Assessment assessment;
  final String problemTitle;

  @override
  State<_ShareSection> createState() => _ShareSectionState();
}

class _ShareSectionState extends State<_ShareSection> {
  int? _streakLength;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final int length = await context.read<DailySessionCubit>().currentStreakLength();
    if (mounted) {
      setState(() => _streakLength = length);
    }
  }

  @override
  Widget build(BuildContext context) {
    final int? streakLength = _streakLength;
    if (streakLength == null) {
      return const SizedBox.shrink();
    }
    return ShareCard(
      assessment: widget.assessment,
      streakLength: streakLength,
      problemTitle: widget.problemTitle,
    );
  }
}

class _VerdictChip extends StatelessWidget {
  const _VerdictChip({required this.copy});
  final VerdictCopy copy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: copy.hue.withValues(alpha: 0.14),
        border: Border.all(color: copy.hue.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        copy.word,
        style: context.appTypography.sansHeadline.copyWith(color: copy.hue),
      ),
    );
  }
}

/// The complexity the learner claimed, beside the reference, beside the
/// judge's call on the two.
///
/// This was one of three fixed phrases — "differs from the reference" —
/// with none of the four values the judge actually returns behind it, so
/// a learner told their complexity differed had no way to see how, or to
/// disagree with the comparison. `user_claimed_time`, `user_claimed_space`,
/// `reference_time` and `reference_space` were all already on the wire and
/// already stored; nothing rendered them.
class _ComplexityDetail extends StatelessWidget {
  const _ComplexityDetail({required this.complexity});

  final Complexity complexity;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final String? claimed = _pair(complexity.userClaimedTime, complexity.userClaimedSpace);
    final String? reference = _pair(complexity.referenceTime, complexity.referenceSpace);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (claimed != null) _row(context, l10n.verdictComplexityYoursLabel, claimed),
        if (reference != null) _row(context, l10n.verdictComplexityReferenceLabel, reference),
        const SizedBox(height: 4),
        Text(
          resolveComplexityCopy(l10n, complexity.assessment),
          style: context.appTypography.sansCaption.copyWith(color: AppTokens.muted),
        ),
      ],
    );
  }

  static String? _pair(String? time, String? space) {
    final String t = time?.trim() ?? '';
    final String sp = space?.trim() ?? '';
    if (t.isEmpty && sp.isEmpty) {
      return null;
    }
    if (t.isEmpty) {
      return sp;
    }
    if (sp.isEmpty) {
      return t;
    }
    return '$t time, $sp space';
  }

  Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // The label column has to grow with the text size or the label
          // runs straight into the value: at the largest supported scale
          // "Reference" fills a fixed 84px exactly, and the row rendered as
          // "ReferenceO(n) time, O(n) space" on a real device (FR-054,
          // SC-014). Scaling the width keeps the two rows aligned, and the
          // gap below keeps the glyphs apart even at the boundary.
          SizedBox(
            width: MediaQuery.textScalerOf(context).scale(84),
            child: Text(
              label,
              style: context.appTypography.monoLabel.copyWith(color: AppTokens.faint),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: context.appTypography.monoBody)),
        ],
      ),
    );
  }
}

class _InsightGlyphList extends StatelessWidget {
  const _InsightGlyphList({
    required this.label,
    required this.insights,
    required this.glyph,
    this.assisted = const <String>{},
  });

  final String label;
  final List<String> insights;
  final IconData glyph;

  /// Entries of [insights] to tag "with a nudge". Only the Reached list
  /// passes this (PLAN_07 D11).
  final Set<String> assisted;

  @override
  Widget build(BuildContext context) {
    if (insights.isEmpty) {
      return const SizedBox.shrink();
    }
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: context.appTypography.sansHeadline),
        const SizedBox(height: 6),
        for (final String insight in insights)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(glyph, size: 14, color: AppTokens.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: <Widget>[
                      Text(humaniseInsightKey(insight), style: context.appTypography.sansBody),
                      if (assisted.contains(insight))
                        Text(
                          l10n.verdictInsightAssistedTag,
                          style: context.appTypography.sansCaption.copyWith(color: AppTokens.muted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
