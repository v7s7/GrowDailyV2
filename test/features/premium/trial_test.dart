// The legacy Premium trial: what is left of the old seven-day new-install
// trial after Aziz ended it for new installs on 2026-09-17.
//
// ── What this file pins ───────────────────────────────────────────────────
// 1. The window math, pure, the same way the history gate's is: no
//    Riverpod, no RevenueCat, no real clock.
// 2. The decision itself, through a real ProviderContainer and a Hive box:
//    a fresh install never gets a trial (and nothing writes one), an install
//    that already holds a start keeps exactly its remaining days, and a
//    trial seen closed stays closed for good, whatever the clock says
//    afterwards.
// 3. The two hardening rules for those legacy holders: a start ahead of the
//    clock is ignored (not ended), and the re-check timer can never loop.
//
// The settings box is opened IN MEMORY in setUp. Reading and latching go
// through LocalStoreService.settingsBox, which answers the already-open box,
// so no test awaits real file I/O (which hangs a testWidgets body silently,
// and the timer tests below run on fake time).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';
import 'package:hive/hive.dart';

const _startKey = 'premium_trial_start_v1';
const _endedKey = 'premium_trial_ended_v1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final start = DateTime(2026, 8, 28, 10);

  group('trialIsActive', () {
    test('open the moment it starts', () {
      expect(trialIsActive(start: start, now: start), isTrue);
    });

    test('open just before the window closes', () {
      final now = start
          .add(const Duration(days: kTrialDays))
          .subtract(const Duration(minutes: 1));
      expect(trialIsActive(start: start, now: now), isTrue);
    });

    test('closed exactly at the boundary and after', () {
      final end = start.add(const Duration(days: kTrialDays));
      expect(trialIsActive(start: start, now: end), isFalse);
      expect(
        trialIsActive(start: start, now: end.add(const Duration(days: 30))),
        isFalse,
      );
    });
  });

  group('trialDaysLeft', () {
    test('a full window reports every day', () {
      expect(trialDaysLeft(start: start, now: start), kTrialDays);
    });

    test('a partial day still counts as a day, never zero while open', () {
      final now = start
          .add(const Duration(days: kTrialDays - 1))
          .add(const Duration(hours: 12));
      expect(trialDaysLeft(start: start, now: now), 1);
    });

    test('zero once closed, never negative', () {
      final end = start.add(const Duration(days: kTrialDays));
      expect(trialDaysLeft(start: start, now: end), 0);
      expect(
        trialDaysLeft(start: start, now: end.add(const Duration(days: 5))),
        0,
      );
    });

    test('never more than the trial is long, even a few minutes ahead', () {
      // A stamp inside the future tolerance still counts, and ceil() would
      // otherwise call seven days and five minutes an eighth day.
      final now = start.subtract(const Duration(minutes: 5));
      expect(trialDaysLeft(start: start, now: now), kTrialDays);
    });
  });

  group('the pure legacy rules', () {
    test('a start ahead of the clock past the tolerance is not believed', () {
      expect(
        trialStartIsPlausible(
          start: start,
          now: start.subtract(kTrialFutureTolerance),
        ),
        isTrue,
        reason: 'exactly at the tolerance still counts',
      );
      expect(
        trialStartIsPlausible(
          start: start,
          now: start
              .subtract(kTrialFutureTolerance)
              .subtract(const Duration(seconds: 1)),
        ),
        isFalse,
      );
      expect(
        trialStartIsPlausible(
          start: start,
          now: start.add(const Duration(days: 400)),
        ),
        isTrue,
        reason: 'a start in the past is always believable; the window '
            'decides the rest',
      );
    });

    test('open only with a start, no latch, a plausible stamp and time left',
        () {
      final inside = start.add(const Duration(days: 2));
      expect(
        legacyTrialIsOpen(start: start, ended: false, now: inside),
        isTrue,
      );
      expect(
        legacyTrialIsOpen(start: null, ended: false, now: inside),
        isFalse,
      );
      expect(
        legacyTrialIsOpen(start: start, ended: true, now: inside),
        isFalse,
        reason: 'the latch wins over a clock that says the window is open',
      );
      expect(
        legacyTrialIsOpen(
          start: start,
          ended: false,
          now: start.subtract(const Duration(days: 1)),
        ),
        isFalse,
      );
      expect(
        legacyTrialIsOpen(
          start: start,
          ended: false,
          now: start.add(const Duration(days: kTrialDays)),
        ),
        isFalse,
      );
    });

    test('latches only on a real close, and only once', () {
      final end = start.add(const Duration(days: kTrialDays));
      final after = end.add(kTrialLatchGrace);
      expect(
        legacyTrialShouldLatchEnded(
          start: start,
          ended: false,
          now: end.add(const Duration(hours: 20)),
        ),
        isFalse,
        reason: 'closed, but inside the grace day: a trip east must not '
            'latch away hours that are still owed',
      );
      expect(
        legacyTrialShouldLatchEnded(start: start, ended: false, now: after),
        isTrue,
      );
      expect(
        legacyTrialShouldLatchEnded(start: start, ended: true, now: after),
        isFalse,
        reason: 'already latched',
      );
      expect(
        legacyTrialShouldLatchEnded(start: null, ended: false, now: after),
        isFalse,
        reason: 'no trial, nothing to end',
      );
      expect(
        legacyTrialShouldLatchEnded(
          start: start,
          ended: false,
          now: start.add(const Duration(days: 3)),
        ),
        isFalse,
        reason: 'still open',
      );
      expect(
        legacyTrialShouldLatchEnded(
          start: start,
          ended: false,
          now: start.subtract(const Duration(days: 30)),
        ),
        isFalse,
        reason: 'a stamp ahead of the clock is ignored, not ended: no window '
            'was seen to close',
      );
    });

    group('trialRecheckDelay', () {
      test('one second past the end when the end is near', () {
        final now = start
            .add(const Duration(days: kTrialDays))
            .subtract(const Duration(minutes: 20));
        expect(
          trialRecheckDelay(start: start, now: now),
          const Duration(minutes: 20, seconds: 1),
        );
      });

      test('capped for a far end, so no timer can overflow and loop', () {
        expect(trialRecheckDelay(start: start, now: start), kTrialRecheckCap);
        expect(
          trialRecheckDelay(
            start: start,
            now: start.subtract(const Duration(days: 3650)),
          ),
          kTrialRecheckCap,
          reason: 'a stamp ten years ahead waits the cap, not ten years',
        );
        expect(
          kTrialRecheckCap <= const Duration(hours: 6),
          isTrue,
          reason: 'at most every few hours',
        );
      });

      test('never shorter than a second, so it cannot spin', () {
        final end = start.add(const Duration(days: kTrialDays));
        expect(
          trialRecheckDelay(start: start, now: end),
          kTrialRecheckCap,
          reason: 'closed: it waits for the latch moment, capped, not a '
              'one-second spin through the grace day',
        );
        expect(
          trialRecheckDelay(
            start: start,
            now: end.add(kTrialLatchGrace).subtract(const Duration(minutes: 5)),
          ),
          const Duration(minutes: 5, seconds: 1),
        );
        expect(
          trialRecheckDelay(
            start: start,
            now: end.add(const Duration(days: 2)),
          ),
          const Duration(seconds: 1),
        );
      });
    });
  });

  group('the decision, through Hive and the providers', () {
    late Directory tmp;
    late Box<dynamic> settings;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('legacy_trial_');
      Hive.init(tmp.path);
      settings =
          await Hive.openBox<dynamic>('box_settings', bytes: Uint8List(0));
    });

    tearDown(() async {
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    /// A container the way main.dart builds one: the loaded trial seeded,
    /// the real entitlement as given, and the trial clock pinned to [clock].
    ProviderContainer boot(
      LegacyTrial trial, {
      required DateTime Function() clock,
      bool entitled = false,
    }) {
      final c = ProviderContainer(
        overrides: [
          premiumProvider
              .overrideWith((ref) => PremiumNotifier(initial: entitled)),
          legacyTrialProvider.overrideWithValue(trial),
          trialClockProvider.overrideWithValue(clock),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    /// Lets the latch's fire-and-forget Hive write land.
    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 20));

    final now = DateTime(2026, 9, 17, 12);

    test('a fresh install never gets a trial, and nothing writes one',
        () async {
      final trial = await loadLegacyTrial();
      expect(trial.start, isNull);
      expect(trial.ended, isFalse);
      expect(trial.needsRecheck, isFalse);

      final c = boot(trial, clock: () => now);
      expect(
        c.read(premiumAccessProvider),
        isFalse,
        reason: 'no entitlement and no trial is the free tier, from the '
            'first frame',
      );
      expect(trial.daysLeftAt(now), 0, reason: 'so the paywall shows no line');
      await settle();

      expect(
        settings.containsKey(_startKey),
        isFalse,
        reason: 'the loader used to stamp now here on first boot',
      );
      expect(
        settings.containsKey(_endedKey),
        isFalse,
        reason: 'there was never a window to close',
      );
      final again = await loadLegacyTrial();
      expect(again.start, isNull, reason: 'and a second boot is still fresh');
    });

    test('a fresh install that buys is Premium the ordinary way', () async {
      final c = boot(await loadLegacyTrial(), clock: () => now, entitled: true);
      expect(c.read(premiumAccessProvider), isTrue);
      expect(settings.containsKey(_startKey), isFalse);
    });

    test('a legacy start 2 days ago is open with 5 days left', () async {
      final legacyStart = now.subtract(const Duration(days: 2));
      await settings.put(_startKey, legacyStart.toIso8601String());

      final trial = await loadLegacyTrial();
      expect(trial.start, legacyStart);
      expect(trial.ended, isFalse);

      final c = boot(trial, clock: () => now);
      expect(
        c.read(premiumAccessProvider),
        isTrue,
        reason: 'existing holders keep their remaining days',
      );
      expect(trial.daysLeftAt(now), 5);
      await settle();
      expect(
        settings.get(_startKey),
        legacyStart.toIso8601String(),
        reason: 'the stored start is never moved',
      );
      expect(
        settings.containsKey(_endedKey),
        isFalse,
        reason: 'an open window is not latched',
      );
    });

    test('a legacy start 8 days ago is closed and writes the ended latch',
        () async {
      await settings.put(
        _startKey,
        now.subtract(const Duration(days: 8)).toIso8601String(),
      );

      final trial = await loadLegacyTrial();
      final c = boot(trial, clock: () => now);
      expect(c.read(premiumAccessProvider), isFalse);
      expect(trial.ended, isTrue, reason: 'latched in memory at once');
      expect(
        trial.needsRecheck,
        isFalse,
        reason: 'so resume and the timer stop looking',
      );
      await settle();
      expect(settings.get(_endedKey), isTrue, reason: 'and on disk');
      expect(
        (await loadLegacyTrial()).ended,
        isTrue,
        reason: 'the next boot reads it back',
      );
    });

    test('after the latch, a clock set back inside the window stays closed',
        () async {
      final legacyStart = now.subtract(const Duration(days: 8));
      await settings.put(_startKey, legacyStart.toIso8601String());

      var wall = now;
      final trial = await loadLegacyTrial();
      final c = boot(trial, clock: () => wall);
      expect(c.read(premiumAccessProvider), isFalse);
      await settle();

      // Same process: the date is set back to day 2 of the old window and
      // the app resumes, which invalidates the access provider.
      wall = legacyStart.add(const Duration(days: 2));
      expect(
        legacyTrialIsOpen(start: legacyStart, ended: false, now: wall),
        isTrue,
        reason: 'without the latch this clock would reopen every gate',
      );
      c.invalidate(premiumAccessProvider);
      expect(c.read(premiumAccessProvider), isFalse);
      expect(trial.daysLeftAt(wall), 0);

      // Next cold start, clock still set back.
      final reloaded = await loadLegacyTrial();
      expect(reloaded.ended, isTrue);
      final c2 = boot(reloaded, clock: () => wall);
      expect(c2.read(premiumAccessProvider), isFalse);
      expect(reloaded.daysLeftAt(wall), 0);
    });

    test('a window that closes while the app sleeps re-locks on resume',
        () async {
      // The re-check timer does not run while suspended; main.dart
      // invalidates the provider on resume instead. This is that path.
      final legacyStart = now.subtract(const Duration(days: 6));
      await settings.put(_startKey, legacyStart.toIso8601String());

      var wall = now;
      final trial = await loadLegacyTrial();
      final c = boot(trial, clock: () => wall);
      final seen = <bool>[];
      c.listen<bool>(
        premiumAccessProvider,
        (_, next) => seen.add(next),
        fireImmediately: true,
      );
      expect(seen, [true]);

      wall = now.add(const Duration(days: 2));
      expect(
        trial.needsRecheck,
        isTrue,
        reason: 'what main.dart checks before invalidating',
      );
      c.invalidate(premiumAccessProvider);
      c.read(premiumAccessProvider);
      expect(seen, [true, false]);
      await settle();
      expect(settings.get(_endedKey), isTrue);
    });

    test('an entitled holder still latches its old window closed', () async {
      await settings.put(
        _startKey,
        now.subtract(const Duration(days: 9)).toIso8601String(),
      );
      final trial = await loadLegacyTrial();
      final c = boot(trial, clock: () => now, entitled: true);
      expect(c.read(premiumAccessProvider), isTrue, reason: 'they bought it');
      expect(
        trial.ended,
        isTrue,
        reason: 'so a later refund cannot fall back into a reopened trial',
      );
    });

    test('a start ahead of the clock is ignored, not ended', () async {
      final ahead = now.add(const Duration(days: 365));
      await settings.put(_startKey, ahead.toIso8601String());

      final trial = await loadLegacyTrial();
      expect(
        trial.start,
        ahead,
        reason: 'the loader keeps it; plausibility is judged per read',
      );
      final c = boot(trial, clock: () => now);
      expect(
        c.read(premiumAccessProvider),
        isFalse,
        reason: 'a year-ahead stamp once read as a year of Premium',
      );
      expect(trial.daysLeftAt(now), 0, reason: 'and a 372-day line');
      await settle();
      expect(
        settings.containsKey(_endedKey),
        isFalse,
        reason: 'no window was seen to close, so nothing latches',
      );
      expect(trial.needsRecheck, isTrue);
    });

    test('a recent stamp read after a trip west comes back, not lost',
        () async {
      // Stamped a few hours ago on a Bahrain wall clock, read on a clock
      // that is seven hours behind: it looks hours ahead until the local
      // clock catches up.
      final legacyStart = DateTime(2026, 9, 17, 10);
      await settings.put(_startKey, legacyStart.toIso8601String());
      var wall = DateTime(2026, 9, 17, 6);

      final trial = await loadLegacyTrial();
      final c = boot(trial, clock: () => wall);
      expect(c.read(premiumAccessProvider), isFalse);

      wall = DateTime(2026, 9, 17, 9, 55);
      c.invalidate(premiumAccessProvider);
      expect(
        c.read(premiumAccessProvider),
        isTrue,
        reason: 'inside the tolerance it counts again',
      );
      expect(trial.daysLeftAt(wall), kTrialDays);
      expect(trial.ended, isFalse);
    });

    test('the ended event is reported once', () async {
      await settings.put(
        _startKey,
        now.subtract(const Duration(days: 10)).toIso8601String(),
      );
      final trial = await loadLegacyTrial();
      expect(trial.observe(now, entitled: false), isTrue);
      expect(trial.observe(now, entitled: false), isFalse);
      expect(
        trial.observe(now.add(const Duration(days: 1)), entitled: true),
        isFalse,
      );
      await settle();
      final reloaded = await loadLegacyTrial();
      expect(
        reloaded.observe(now, entitled: false),
        isFalse,
        reason: 'nor again on the next launch',
      );
    });
  });

  group('the re-check timer', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('legacy_trial_timer_');
      Hive.init(tmp.path);
      await Hive.openBox<dynamic>('box_settings', bytes: Uint8List(0));
    });

    tearDown(() async {
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    testWidgets('a far-ahead start re-checks at the cap, not in a loop',
        (tester) async {
      final now = DateTime(2026, 9, 17, 12);
      var reads = 0;
      final trial = LegacyTrial(start: now.add(const Duration(days: 3650)));
      final c = ProviderContainer(
        overrides: [
          premiumProvider.overrideWith((ref) => PremiumNotifier()),
          legacyTrialProvider.overrideWithValue(trial),
          trialClockProvider.overrideWithValue(() {
            reads++;
            return now;
          }),
        ],
      );
      final sub = c.listen<bool>(premiumAccessProvider, (_, __) {});
      expect(sub.read(), isFalse);
      expect(reads, 1);

      await tester.pump(kTrialRecheckCap - const Duration(seconds: 1));
      expect(reads, 1, reason: 'nothing fired early, so nothing fired at once');
      await tester.pump(const Duration(seconds: 1));
      expect(reads, 2, reason: 'one re-check at the cap');
      await tester.pump(const Duration(minutes: 1));
      expect(reads, 2, reason: 'the re-armed timer waits again');
      await tester.pump(kTrialRecheckCap);
      expect(reads, 3, reason: 'and fires once more, a cap later');

      sub.close();
      c.dispose();
    });

    testWidgets('an open trial re-locks by itself one second past its end',
        (tester) async {
      final now = DateTime(2026, 9, 17, 12);
      final legacyStart = now
          .subtract(const Duration(days: kTrialDays))
          .add(const Duration(minutes: 30));
      var wall = now;
      final trial = LegacyTrial(start: legacyStart);
      final c = ProviderContainer(
        overrides: [
          premiumProvider.overrideWith((ref) => PremiumNotifier()),
          legacyTrialProvider.overrideWithValue(trial),
          trialClockProvider.overrideWithValue(() => wall),
        ],
      );
      final seen = <bool>[];
      final sub = c.listen<bool>(
        premiumAccessProvider,
        (_, next) => seen.add(next),
        fireImmediately: true,
      );
      expect(seen, [true]);

      Future<void> advance(Duration by) async {
        wall = wall.add(by);
        await tester.pump(by);
      }

      await advance(const Duration(minutes: 30));
      expect(seen, [true], reason: 'exactly at the end, a second early');
      await advance(const Duration(seconds: 1));
      expect(seen, [true, false]);
      expect(
        trial.ended,
        isFalse,
        reason: 'access closed at the end, the latch waits a grace day',
      );
      await advance(kTrialLatchGrace);
      expect(seen, [true, false], reason: 'no reopening during the grace');
      expect(trial.ended, isTrue);
      expect(
        trial.needsRecheck,
        isFalse,
        reason: 'latched, so no further timer is armed',
      );

      sub.close();
      c.dispose();
    });
  });
}
