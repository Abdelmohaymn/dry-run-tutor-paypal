import 'package:dry_run/core/router/app_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the PayPal return link maps to /pro/return', () {
    expect(deepLinkLocation(Uri.parse('dryruntutor://pro/return')), '/pro/return');
  });

  test('a problem link maps to /p/<id>', () {
    expect(deepLinkLocation(Uri.parse('dryruntutor://p/two-sum')), '/p/two-sum');
  });

  test('an in-app path is left to the normal guards', () {
    expect(deepLinkLocation(Uri.parse('/settings/plan')), isNull);
  });
}
