import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/router/app_route.dart';
import '../../../core/theme/app_theme.dart';
import '../../plan/domain/plan_status.dart';
import '../../plan/presentation/widgets/pro_badge.dart';

/// `/settings` — four rows, each its own screen (FR-006, FR-048a,
/// FR-039f, and the Plan row of feature 009). The prototype draws no settings
/// screen at all (spec.md's "screens the prototype does not draw"); built in
/// the same tokens and one-thing-per-row discipline as the rest.
class SettingsScreen extends StatelessWidget {
  /// [planStatus] is the relay's last answer about the plan (the router passes
  /// the cached one), used only to show the Pro badge. It grants nothing.
  const SettingsScreen({this.planStatus, super.key});

  final PlanStatus? planStatus;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final bool isPro = planStatus?.plan == PlanKind.pro;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsScreenTitle),
        actions: <Widget>[
          if (isPro)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(child: ProBadge()),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.vpn_key_outlined),
              title: Text(l10n.settingsKeyManagementLabel, style: context.appTypography.sansBody),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(AppRoute.settingsKey.path),
            ),
            ListTile(
              leading: const Icon(Icons.workspace_premium_outlined),
              title: Text(l10n.settingsPlanLabel, style: context.appTypography.sansBody),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (isPro) ...<Widget>[const ProBadge(), const SizedBox(width: 8)],
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap: () => context.push(AppRoute.settingsPlan.path),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: Text(l10n.settingsReminderLabel, style: context.appTypography.sansBody),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(AppRoute.settingsReminder.path),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(l10n.settingsWipeLabel, style: context.appTypography.sansBody),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(AppRoute.settingsWipe.path),
            ),
          ],
        ),
      ),
    );
  }
}
