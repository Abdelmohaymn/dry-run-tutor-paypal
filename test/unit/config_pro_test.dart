// Feature 009: the app reads `pro` (five fields) and `trial.replay_enabled`
// from /v1/config, and nothing else of the Pro lever.
import 'package:dry_run/core/config/runtime_config.dart';
import 'package:dry_run/core/network/dto/config_dto.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _base({Map<String, dynamic>? pro, Map<String, dynamic>? trial}) => <String, dynamic>{
      'min_supported_version': '1.0.0',
      'killed_problem_ids': <String>[],
      'chat': <String, dynamic>{'turn_cap': 12, 'wrap_up_at_turn': 9, 'min_turn_chars': 8},
      'trial': trial ?? <String, dynamic>{'turn_cap': 4},
      'keyed_providers': <String>['groq'],
      'pro': ?pro,
    };

const Map<String, dynamic> _fullPro = <String, dynamic>{
  'enabled': true,
  'price_label': r'$4.99 / month',
  'sessions_per_day': 5,
  'voice_seconds_per_day': 900,
  'manage_url': 'https://www.sandbox.paypal.com/myaccount/autopay/',
};

RuntimeConfig _parse(Map<String, dynamic> json) => RuntimeConfig.fromDto(ConfigDto.fromJson(json));

void main() {
  group('pro block', () {
    test('absent → null (Pro off)', () {
      expect(_parse(_base()).pro, isNull);
    });

    test('enabled: false → null', () {
      expect(_parse(_base(pro: <String, dynamic>{..._fullPro, 'enabled': false})).pro, isNull);
    });

    test('a full block parses', () {
      final ProConfig? pro = _parse(_base(pro: _fullPro)).pro;
      expect(pro, isNotNull);
      expect(pro!.priceLabel, r'$4.99 / month');
      expect(pro.sessionsPerDay, 5);
      expect(pro.voiceSecondsPerDay, 900);
      expect(pro.manageUrl, 'https://www.sandbox.paypal.com/myaccount/autopay/');
    });

    test('unknown keys (plan_id, ceilings) are ignored, not readable', () {
      final ProConfig? pro = _parse(
        _base(pro: <String, dynamic>{..._fullPro, 'plan_id': 'P-1ABCDEFGH', 'daily_token_ceiling': 1}),
      ).pro;
      expect(pro, isNotNull);
    });
  });

  group('trial.replay_enabled', () {
    test('absent → true', () {
      expect(_parse(_base()).trial.replayEnabled, isTrue);
    });

    test('false parses', () {
      final RuntimeConfig cfg = _parse(
        _base(trial: <String, dynamic>{'turn_cap': 4, 'replay_enabled': false}),
      );
      expect(cfg.trial.replayEnabled, isFalse);
      expect(cfg.trial.turnCap, 4);
    });
  });
}
