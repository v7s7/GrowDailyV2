// One phone, one device token on the account.
//
// On 2026-09-24 نور's account held two fcmTokens docs, one refreshed that
// morning and one not since 13 Sep, and every room push reached her twice.
// The app wrote each new token and never removed the one it replaced, and it
// never rewrote an unchanged token, so the server could not tell a phone in
// use from one left behind. tokenSyncPlan is that decision, pure.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/services/push_notification_service.dart';

void main() {
  final now = DateTime(2026, 9, 24, 7, 30);
  PushRegistration last(String uid, String token, Duration ago) =>
      PushRegistration(uid: uid, token: token, writtenAt: now.subtract(ago));

  test('a fresh install writes its token and deletes nothing', () {
    final plan = tokenSyncPlan(uid: 'noor', token: 'T2', last: null, now: now);
    expect(plan.write, isTrue);
    expect(plan.deleteToken, isNull);
  });

  test('a replaced token is written and the old one is deleted', () {
    final plan = tokenSyncPlan(
      uid: 'noor',
      token: 'T2',
      last: last('noor', 'T1', const Duration(hours: 2)),
      now: now,
    );
    expect(plan.write, isTrue);
    expect(plan.deleteToken, 'T1');
  });

  test('an unchanged token written today is left alone', () {
    final plan = tokenSyncPlan(
      uid: 'noor',
      token: 'T1',
      last: last('noor', 'T1', const Duration(hours: 3)),
      now: now,
    );
    expect(plan.write, isFalse);
    expect(plan.deleteToken, isNull);
  });

  test('an unchanged token is rewritten once a day so the server sees it used',
      () {
    // Opened at 08:00 yesterday and 07:30 today: 23.5 hours, still rewritten.
    final plan = tokenSyncPlan(
      uid: 'noor',
      token: 'T1',
      last: last('noor', 'T1', const Duration(hours: 23, minutes: 30)),
      now: now,
    );
    expect(plan.write, isTrue);
    expect(plan.deleteToken, isNull);
    // Well inside the server's one-week rule for a token left behind.
    expect(kPushTokenRefreshEvery, lessThan(const Duration(days: 1)));
  });

  test('another account on the same phone writes and deletes nothing', () {
    // The old doc lives under the other account, and sign-out removed it.
    final plan = tokenSyncPlan(
      uid: 'aziz',
      token: 'T1',
      last: last('noor', 'T1', const Duration(minutes: 5)),
      now: now,
    );
    expect(plan.write, isTrue);
    expect(plan.deleteToken, isNull);
  });

  test('a clock that moved backwards does not force a write', () {
    final plan = tokenSyncPlan(
      uid: 'noor',
      token: 'T1',
      last: PushRegistration(
        uid: 'noor',
        token: 'T1',
        writtenAt: now.add(const Duration(hours: 1)),
      ),
      now: now,
    );
    expect(plan.write, isFalse);
  });
}
