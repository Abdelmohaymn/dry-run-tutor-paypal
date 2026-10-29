import 'package:flutter/material.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/app_theme.dart';

/// A small "Pro" chip. Shown on Settings and the Plan screen while Pro Plus is
/// active, and nowhere on the conversation screen (research.md R-14, FR-021).
class ProBadge extends StatelessWidget {
  const ProBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        l10n.proBadgeLabel,
        style: context.appTypography.monoLabel.copyWith(color: scheme.onPrimaryContainer),
      ),
    );
  }
}
