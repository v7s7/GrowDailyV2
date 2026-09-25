// What the plant grows on (lib/features/app_icon/app_icon_providers.dart):
// full days, the days that reached 80% of their habits, over all time.
//
// Pinned: the count is the days whose record says so ('streakEarnedToday',
// the streak's own mark), for this account and no other, and a guest's
// come from the phone. It is asked again only when a day could have just
// become full, never while the dashboard is still a placeholder, and never
// on an iPhone-less platform.
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/constants/game_constants.dart';
import 'package:grow_daily_v2/features/app_icon/app_icon_providers.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:hive/hive.dart';

import 'app_icon_fakes.dart';

class _User extends Fake implements User {
  _User(this.uid);

  @override
  final String uid;
}

typedef _Marks = ({DateTime? last, bool today});

void main() {
  group('the count', () {
    test('an account: only its days that reached the bar', () async {
      final db = FakeFirebaseFirestore();
      Future<void> day(String path, Map<String, dynamic> data) =>
          db.doc(path).set(data);
      await day('users/u1/daily/2026-09-01', {'streakEarnedToday': true});
      await day('users/u1/daily/2026-09-02', {'streakEarnedToday': false});
      await day('users/u1/daily/2026-09-03', {
        'habitCompletions': {'fajr': 1},
      });
      await day('users/u1/daily/2026-09-04', {'streakEarnedToday': true});
      await day('users/u2/daily/2026-09-04', {'streakEarnedToday': true});
      expect(await FullDayCounter(db).count('u1'), 2);
      expect(await FullDayCounter(db).count('u3'), 0);
    });

    test('a guest: the days on this phone', () async {
      final tmp = await Directory.systemTemp.createTemp('full_days_');
      addTearDown(() => tmp.delete(recursive: true));
      Hive.init(tmp.path);
      final box = await Hive.openBox<dynamic>(GameConstants.boxDailyLogs);
      addTearDown(Hive.close);
      await box.put('2026-09-01', {'streakEarnedToday': true});
      await box.put('2026-09-02', {
        'habitCompletions': {'a': 1},
      });
      await box.put('2026-09-03', {'streakEarnedToday': true});
      expect(await const FullDayCounter().count(null), 2);
    });
  });

  group('when it is asked', () {
    late ProviderContainer c;
    late FakeFullDayCounter counter;
    final marks = StateProvider<_Marks?>((ref) => null);

    setUp(() {
      counter = FakeFullDayCounter([40, 41, 42]);
      c = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream.value(_User('u1'))),
          // Through select, as the real one reads the dashboard: an equal pair
          // of marks is no change.
          fullDayMarksProvider.overrideWith(
            (ref) => ref.watch(marks.select((m) => m)),
          ),
          fullDayCounterProvider.overrideWithValue(counter),
        ],
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      c.dispose();
    });

    test('once the dashboard is real, again only when a day becomes full',
        () async {
      await c.read(authStateProvider.future);
      c.listen(plantFullDaysProvider, (_, __) {});
      expect(
        await c.read(plantFullDaysProvider.future),
        isNull,
        reason: 'placeholder numbers are not a count of zero',
      );
      expect(counter.askedFor, isEmpty);

      c.read(marks.notifier).state =
          (last: DateTime(2026, 9, 24), today: false);
      expect(await c.read(plantFullDaysProvider.future), 40);
      expect(counter.askedFor, ['u1']);

      // A reload with nothing new: no read.
      c.read(marks.notifier).state =
          (last: DateTime(2026, 9, 24), today: false);
      await pumpEventQueue();
      expect(counter.askedFor, ['u1']);
      expect(c.read(plantFullDaysProvider).valueOrNull, 40);

      // Today reaches the bar.
      c.read(marks.notifier).state = (last: DateTime(2026, 9, 25), today: true);
      expect(await c.read(plantFullDaysProvider.future), 41);
      expect(counter.askedFor, ['u1', 'u1']);
    });

    test('nothing at all off an iPhone', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await c.read(authStateProvider.future);
      c.read(marks.notifier).state =
          (last: DateTime(2026, 9, 24), today: false);
      expect(await c.read(plantFullDaysProvider.future), isNull);
      expect(counter.askedFor, isEmpty);
    });
  });
}
