// The retry ladder behind device-token registration.
//
// On 2026-09-05 the room push feature was measured against production: both
// Cloud Functions running, the callable invoked from phones that day, every
// room event claimed, and 0 of 113 accounts holding a device token. The
// client had exactly one attempt at launch and gave up after five seconds.
// The ladder is what replaces "one attempt": short early rungs for the
// normal case where APNs simply had not answered yet, and a hard end so a
// phone that genuinely cannot register is not kept busy forever.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/services/push_notification_service.dart';

void main() {
  test('the early rungs are short, since APNs usually answers within a minute',
      () {
    expect(pushRetryDelay(1), const Duration(seconds: 10));
    expect(pushRetryDelay(2), const Duration(seconds: 30));
    expect(pushRetryDelay(3), const Duration(seconds: 60));
  });

  test('the ladder climbs and then ends, rather than polling forever', () {
    expect(pushRetryDelay(4), const Duration(minutes: 2));
    expect(pushRetryDelay(5), const Duration(minutes: 3));
    expect(pushRetryDelay(6), isNull);
    expect(pushRetryDelay(100), isNull);
  });

  test('the whole ladder fits inside the first ten minutes of a session', () {
    var total = Duration.zero;
    for (var i = 1; pushRetryDelay(i) != null; i++) {
      total += pushRetryDelay(i)!;
    }
    expect(total, lessThanOrEqualTo(const Duration(minutes: 10)));
  });
}
