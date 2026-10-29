import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/config/runtime_config.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/plan_status.dart';
import 'plan_cubit.dart';
import 'plan_state.dart';
import 'widgets/pro_badge.dart';

/// `/settings/plan` (app-client.md §7): the learner's plan, today's usage, the
/// Pro Plus offer, and the way into PayPal. It lives in Settings, never on the
/// conversation screen (FR-021). Everything shown comes from the relay (or its
/// cached answer, marked stale); the screen never decides entitlement.
class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    final PlanCubit cubit = context.read<PlanCubit>();
    _lifecycle = AppLifecycleListener(onResume: cubit.onResumed);
    cubit.load();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return BlocConsumer<PlanCubit, PlanState>(
      listenWhen: (PlanState previous, PlanState next) => next is PlanReady && next.notice != null,
      listener: (BuildContext context, PlanState state) {
        if (state is PlanReady && state.notice != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(_noticeText(l10n, state.notice!))));
        }
      },
      builder: (BuildContext context, PlanState state) {
        final bool isPro = state is PlanReady && state.status.plan == PlanKind.pro;
        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.planTitle),
            actions: <Widget>[
              if (isPro)
                const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: Center(child: ProBadge()),
                ),
            ],
          ),
          body: SafeArea(child: _body(context, l10n, state)),
        );
      },
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n, PlanState state) {
    return switch (state) {
      PlanLoading() => const Center(child: CircularProgressIndicator()),
      PlanUnavailable() => _Message(
          text: l10n.planUnavailable,
          action: OutlinedButton(
            onPressed: () => context.read<PlanCubit>().load(),
            child: Text(l10n.planRetry),
          ),
        ),
      PlanCheckingOut() || PlanConfirming() => _Progress(text: l10n.planConfirming),
      PlanAwaitingReturn() => _Message(text: l10n.planAwaitingReturn),
      PlanReady() => _ReadyView(state: state),
    };
  }

  static String _noticeText(AppLocalizations l10n, PlanNotice notice) => switch (notice) {
        PlanNotice.activated => l10n.planActivated,
        PlanNotice.notCompleted => l10n.planNotCompleted,
        PlanNotice.paypalUnavailable => l10n.planPayPalUnavailable,
        PlanNotice.alreadyActive => l10n.planAlreadyActive,
      };
}

class _Progress extends StatelessWidget {
  const _Progress({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(text, style: context.appTypography.sansBody),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(text, style: context.appTypography.sansBody, textAlign: TextAlign.center),
            if (action != null) ...<Widget>[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class _ReadyView extends StatelessWidget {
  const _ReadyView({required this.state});

  final PlanReady state;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final MaterialLocalizations material = MaterialLocalizations.of(context);
    final PlanStatus status = state.status;
    final PlanCubit cubit = context.read<PlanCubit>();
    final ProConfig? pro = cubit.proConfig;
    final bool offered = status.offerEnabled && status.plan == PlanKind.free && pro != null;

    // 1. The first that holds: an own key wins over any plan (FR-013).
    final String planName = state.ownKey
        ? l10n.planOwnKey
        : status.plan == PlanKind.pro
            ? l10n.planProName
            : l10n.planFreeName;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        Text(planName, style: context.appTypography.sansHeadline),
        if (state.ownKey && status.offerEnabled) ...<Widget>[
          const SizedBox(height: 8),
          Text(l10n.planOwnKeyProNote, style: context.appTypography.sansBody),
        ],
        const SizedBox(height: 24),

        // 2. Usage.
        Text(l10n.planUsageHeading, style: context.appTypography.monoLabel),
        const SizedBox(height: 8),
        Text(
          status.sessionsPeriod == SessionsPeriod.day
              ? l10n.planSessionsUsage(status.sessionsUsed, status.sessionsLimit)
              : l10n.planSessionsUsageLifetime(status.sessionsUsed, status.sessionsLimit),
          style: context.appTypography.sansBody,
        ),
        if (status.voiceSecondsLimit > 0) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            l10n.planVoiceUsage(_minutes(status.voiceSecondsUsed), _minutes(status.voiceSecondsLimit)),
            style: context.appTypography.sansBody,
          ),
        ],

        // 3. Pro details.
        if (status.offerEnabled && status.subscription != null) ...<Widget>[
          const SizedBox(height: 24),
          ..._details(context, l10n, material, status),
        ],

        // 4. The offer.
        if (offered) ...<Widget>[
          const SizedBox(height: 32),
          _Offer(pro: pro),
        ],

        // 5. Manage.
        if (status.plan == PlanKind.pro) ...<Widget>[
          const SizedBox(height: 24),
          OutlinedButton(onPressed: cubit.manage, child: Text(l10n.planManage)),
        ],

        // 6. Stale: the relay's own time, never the phone's clock.
        if (state.stale) ...<Widget>[
          const SizedBox(height: 24),
          Text(
            l10n.planLastChecked(material.formatMediumDate(status.asOf.toLocal())),
            style: context.appTypography.sansCaption,
          ),
        ],
      ],
    );
  }

  static int _minutes(int seconds) => (seconds + 59) ~/ 60;

  List<Widget> _details(
    BuildContext context,
    AppLocalizations l10n,
    MaterialLocalizations material,
    PlanStatus status,
  ) {
    final TextStyle style = context.appTypography.sansBody;
    final List<Widget> lines = <Widget>[];
    void add(String text) {
      if (lines.isNotEmpty) {
        lines.add(const SizedBox(height: 4));
      }
      lines.add(Text(text, style: style));
    }

    final DateTime? end = status.periodEnd;
    switch (status.subscription) {
      case SubscriptionState.active:
        if (end != null) {
          add(l10n.planRenews(material.formatMediumDate(end.toLocal())));
        }
      case SubscriptionState.cancelled:
        // Paid up until the end of the period; after that it is simply over.
        // Judged against the relay's own time.
        if (end != null && end.isAfter(status.asOf)) {
          add(l10n.planEnds(material.formatMediumDate(end.toLocal())));
        } else {
          add(l10n.planEndedNotice);
        }
      case SubscriptionState.suspended || SubscriptionState.paymentFailed || SubscriptionState.expired:
        add(l10n.planEndedNotice);
      case SubscriptionState.pending || SubscriptionState.approved || null:
        break;
    }
    switch (status.proLimit) {
      case ProLimit.sessionsUsed:
        add(l10n.planProSessionsUsed);
      case ProLimit.capacity:
        add(l10n.planProCapacity);
      case ProLimit.ok || null:
        break;
    }
    return lines;
  }
}

class _Offer extends StatelessWidget {
  const _Offer({required this.pro});

  final ProConfig pro;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.planOfferTitle, style: context.appTypography.sansHeadline),
            const SizedBox(height: 4),
            Text(pro.priceLabel, style: context.appTypography.monoBody),
            const SizedBox(height: 8),
            Text(
              l10n.planOfferLimits(pro.sessionsPerDay, (pro.voiceSecondsPerDay + 59) ~/ 60),
              style: context.appTypography.sansBody,
            ),
            const SizedBox(height: 8),
            Text(l10n.planOfferPayPal, style: context.appTypography.sansCaption),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => context.read<PlanCubit>().subscribe(),
                child: Text(l10n.planSubscribe),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
