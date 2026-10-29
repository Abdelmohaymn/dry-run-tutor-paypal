// ReplayGate (FR-027): decides, before the relay is called, whether "Practice
// again" and the problem picker should show the Pro Plus offer instead.
import 'package:dry_run/core/config/runtime_config.dart';
import 'package:dry_run/core/errors/relay_error.dart';
import 'package:dry_run/core/errors/result.dart';
import 'package:dry_run/features/keys/domain/learner_key.dart';
import 'package:dry_run/features/plan/domain/plan_status.dart';
import 'package:dry_run/features/plan/domain/replay_gate.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_config_repository.dart';
import '../fakes/fake_key_repository.dart';
import '../fakes/fake_plan_repository.dart';

const ProConfig _pro = ProConfig(
  enabled: true,
  priceLabel: r'$4.99 / month',
  sessionsPerDay: 5,
  voiceSecondsPerDay: 900,
  manageUrl: 'https://www.sandbox.paypal.com/myaccount/autopay/',
);

RuntimeConfig _config({required bool replayEnabled, ProConfig? pro = _pro}) => RuntimeConfig(
      minSupportedVersion: '1.0.0',
      killedProblemIds: const <String>[],
      chat: const ChatConfig(turnCap: 4, wrapUpAtTurn: 3, minTurnChars: 5),
      trial: TrialConfig(turnCap: 4, replayEnabled: replayEnabled),
      keyedProviders: const <String>['groq'],
      pro: pro,
    );

void main() {
  late FakeRemoteConfigRepository config;
  late FakeKeyRepository keys;
  late FakePlanRepository plans;
  late ReplayGate gate;

  setUp(() {
    config = FakeRemoteConfigRepository();
    keys = FakeKeyRepository();
    plans = FakePlanRepository();
    gate = ReplayGate(configRepository: config, keyRepository: keys, planRepository: plans);
  });

  test('with no config yet it is unlocked', () async {
    expect(await gate.isLocked(), isFalse);
  });

  test('lever on (today\'s behaviour) → unlocked, whatever the plan', () async {
    config.cachedValue = _config(replayEnabled: true);
    plans.cachedStatus = freeStatus();
    expect(await gate.isLocked(), isFalse);
    expect(plans.refreshCalls, 0);
  });

  test('lever off + an own key → unlocked', () async {
    config.cachedValue = _config(replayEnabled: false);
    keys.storedKey = const LearnerKey(providerId: 'groq', value: 'gsk_x');
    expect(await gate.isLocked(), isFalse);
    expect(plans.refreshCalls, 0);
  });

  test('lever off + cached Pro → unlocked', () async {
    config.cachedValue = _config(replayEnabled: false);
    plans.cachedStatus = proStatus();
    expect(await gate.isLocked(), isFalse);
    expect(plans.refreshCalls, 0);
  });

  test('lever off + cached free → locked, without a network call', () async {
    config.cachedValue = _config(replayEnabled: false);
    plans.cachedStatus = freeStatus();
    expect(await gate.isLocked(), isTrue);
    expect(plans.refreshCalls, 0);
  });

  test('lever off + nothing cached + Pro on → asks the relay first (Pro → unlocked)', () async {
    config.cachedValue = _config(replayEnabled: false);
    plans.refreshResults.add(Ok<PlanStatus>(proStatus()));
    expect(await gate.isLocked(), isFalse);
    expect(plans.refreshCalls, 1);
  });

  test('lever off + nothing cached + Pro on → asks the relay first (free → locked)', () async {
    config.cachedValue = _config(replayEnabled: false);
    plans.refreshResults.add(Ok<PlanStatus>(freeStatus()));
    expect(await gate.isLocked(), isTrue);
    expect(plans.refreshCalls, 1);
  });

  test('lever off + nothing cached + the relay unreachable → locked', () async {
    config.cachedValue = _config(replayEnabled: false);
    plans.refreshResults.add(const Err<PlanStatus>(RelayError.transport()));
    expect(await gate.isLocked(), isTrue);
  });

  test('lever off + Pro not configured → locked, and the relay is not asked about a plan it does not sell', () async {
    config.cachedValue = _config(replayEnabled: false, pro: null);
    expect(await gate.isLocked(), isTrue);
    expect(plans.refreshCalls, 0);
  });

  test('offerPro follows the pro block of the config', () {
    config.cachedValue = _config(replayEnabled: false);
    expect(gate.offerPro, isTrue);
    config.cachedValue = _config(replayEnabled: false, pro: null);
    expect(gate.offerPro, isFalse);
    config.cachedValue = null;
    expect(gate.offerPro, isFalse);
  });
}
