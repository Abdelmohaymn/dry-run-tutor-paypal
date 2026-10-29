import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_route.dart';
import '../../keys/presentation/key_prompt_dialog.dart';
import '../domain/replay_gate.dart';

/// Explains that "Practice again" and the problem picker are Pro Plus (or
/// own-key) on this relay, instead of calling it (FR-027). Pushes, never `go`s,
/// so the conversation stays underneath.
Future<void> showReplayLockedPrompt(BuildContext context, ReplayGate gate) async {
  final KeyPromptChoice choice = await showKeyPromptWithPro(
    context,
    KeyPromptReason.replayLocked,
    offerPro: gate.offerPro,
  );
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
