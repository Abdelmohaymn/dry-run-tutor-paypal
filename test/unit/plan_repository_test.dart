// PlanRepositoryImpl: DTO → PlanStatus mapping (an unknown enum string never
// crashes), the cache it writes and serves, and the voice-quota reset on a
// free → Pro flip (research.md R-13).
import 'package:dry_run/core/errors/relay_error.dart';
import 'package:dry_run/core/errors/result.dart';
import 'package:dry_run/core/network/dto/pro_dto.dart';
import 'package:dry_run/core/network/relay_client.dart';
import 'package:dry_run/features/cloud_voice/data/voice_quota_store.dart';
import 'package:dry_run/features/cloud_voice/domain/voice_quota.dart';
import 'package:dry_run/features/plan/data/plan_repository_impl.dart';
import 'package:dry_run/features/plan/domain/plan_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_install_repository.dart';
import '../fakes/mock_relay_client.dart';

ProStatusDto _dto({
  String plan = 'free',
  String? subscription,
  String? proLimit,
  String sessionsPeriod = 'lifetime',
}) => ProStatusDto(
  offerEnabled: true,
  plan: plan,
  subscription: subscription == null
      ? null
      : ProSubscriptionDto(
          status: subscription,
          periodEnd: '2026-11-20T10:00:00Z',
          confirmedAt: '2026-10-20T10:00:03Z',
        ),
  proLimit: proLimit,
  usage: ProUsageDto(
    sessionsUsed: 2,
    sessionsLimit: 5,
    sessionsPeriod: sessionsPeriod,
    voiceSecondsUsed: 120,
    voiceSecondsLimit: 900,
  ),
  asOf: '2026-10-20T10:05:00Z',
);

void main() {
  late MockRelayClient relay;
  late SharedPreferences prefs;
  late VoiceQuotaStore quota;
  late PlanRepositoryImpl repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    relay = MockRelayClient();
    quota = VoiceQuotaStore(prefs);
    repo = PlanRepositoryImpl(
      relayClient: relay,
      installRepository: FakeInstallRepository(),
      prefs: prefs,
      voiceQuotaStore: quota,
    );
  });

  test('maps a Pro answer into a PlanStatus', () async {
    when(() => relay.proStatus(installId: any(named: 'installId'))).thenAnswer(
      (_) async => _dto(plan: 'pro', subscription: 'active', proLimit: 'sessions_used', sessionsPeriod: 'day'),
    );
    final Result<PlanStatus> result = await repo.refresh();
    final PlanStatus status = (result as Ok<PlanStatus>).value;
    expect(status.plan, PlanKind.pro);
    expect(status.subscription, SubscriptionState.active);
    expect(status.proLimit, ProLimit.sessionsUsed);
    expect(status.sessionsPeriod, SessionsPeriod.day);
    expect(status.periodEnd, DateTime.utc(2026, 11, 20, 10));
    expect(status.asOf, DateTime.utc(2026, 10, 20, 10, 5));
  });

  test('an unknown subscription string is null and an unknown limit is ok, never a crash', () async {
    when(() => relay.proStatus(installId: any(named: 'installId'))).thenAnswer(
      (_) async => _dto(plan: 'pro', subscription: 'on_hold_somehow', proLimit: 'who_knows'),
    );
    final PlanStatus status = (await repo.refresh() as Ok<PlanStatus>).value;
    expect(status.subscription, isNull);
    expect(status.proLimit, ProLimit.ok);
  });

  test('a free answer has no pro limit', () async {
    when(() => relay.proStatus(installId: any(named: 'installId')))
        .thenAnswer((_) async => _dto(proLimit: 'capacity'));
    final PlanStatus status = (await repo.refresh() as Ok<PlanStatus>).value;
    expect(status.plan, PlanKind.free);
    expect(status.proLimit, isNull);
  });

  test('writes the cache on Ok, and cached() serves it', () async {
    expect(repo.cached(), isNull);
    when(() => relay.proStatus(installId: any(named: 'installId')))
        .thenAnswer((_) async => _dto(plan: 'pro', subscription: 'active'));
    final PlanStatus fresh = (await repo.refresh() as Ok<PlanStatus>).value;
    expect(repo.cached(), fresh);
  });

  test('a failed refresh is an Err and leaves the cache as it was', () async {
    when(() => relay.proStatus(installId: any(named: 'installId')))
        .thenAnswer((_) async => _dto(plan: 'pro', subscription: 'active'));
    final PlanStatus before = (await repo.refresh() as Ok<PlanStatus>).value;
    when(() => relay.proStatus(installId: any(named: 'installId')))
        .thenThrow(const RelayException(RelayError.transport()));
    expect(await repo.refresh(), isA<Err<PlanStatus>>());
    expect(repo.cached(), before);
  });

  test('a corrupt cache reads as null', () async {
    await prefs.setString('plan.last_status', '{not json');
    expect(repo.cached(), isNull);
  });

  group('voice quota on a free → Pro flip', () {
    const VoiceQuota stored = VoiceQuota(date: '2026-10-20', secondsLeft: 0, maxClipSeconds: 120);

    test('is cleared when the plan flips from free to Pro', () async {
      await quota.write(stored);
      when(() => relay.proStatus(installId: any(named: 'installId'))).thenAnswer((_) async => _dto());
      await repo.refresh();
      expect(quota.read(), stored, reason: 'still free');
      when(() => relay.proStatus(installId: any(named: 'installId')))
          .thenAnswer((_) async => _dto(plan: 'pro', subscription: 'active'));
      await repo.refresh();
      expect(quota.read(), isNull);
    });

    test('is kept while the plan stays Pro', () async {
      when(() => relay.proStatus(installId: any(named: 'installId')))
          .thenAnswer((_) async => _dto(plan: 'pro', subscription: 'active'));
      await repo.refresh();
      await quota.write(stored);
      await repo.refresh();
      expect(quota.read(), stored);
    });
  });

  group('startCheckout', () {
    test('Ok(uri) for an https approve link', () async {
      when(() => relay.proCheckout(installId: any(named: 'installId'))).thenAnswer(
        (_) async => ProCheckoutDto(approveUrl: 'https://www.sandbox.paypal.com/webapps/billing/subscriptions?ba_token=BA-1'),
      );
      final Result<Uri?> r = await repo.startCheckout();
      expect((r as Ok<Uri?>).value?.host, 'www.sandbox.paypal.com');
    });

    test('Ok(null) when already active', () async {
      when(() => relay.proCheckout(installId: any(named: 'installId')))
          .thenAnswer((_) async => ProCheckoutDto(alreadyActive: true));
      expect((await repo.startCheckout() as Ok<Uri?>).value, isNull);
    });

    test('a missing or non-https link is an Err', () async {
      when(() => relay.proCheckout(installId: any(named: 'installId')))
          .thenAnswer((_) async => ProCheckoutDto(approveUrl: 'http://example.com/'));
      expect(await repo.startCheckout(), isA<Err<Uri?>>());
      when(() => relay.proCheckout(installId: any(named: 'installId')))
          .thenAnswer((_) async => ProCheckoutDto());
      expect(await repo.startCheckout(), isA<Err<Uri?>>());
    });

    test('a relay error is an Err', () async {
      when(() => relay.proCheckout(installId: any(named: 'installId')))
          .thenThrow(const RelayException(RelayError.unclearRetry()));
      expect(await repo.startCheckout(), isA<Err<Uri?>>());
    });
  });
}
