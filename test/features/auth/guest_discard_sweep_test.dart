import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:flutter/widgets.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';

/// The 7-day grace period the guest copy gets after someone answers the
/// reconnect offer, either way.
///
/// The sweep is the one piece of this feature that deletes something
/// irreversible, so the tests that matter most here are the ones that
/// prove it does NOT run: while a guest session is live, before the
/// deadline, and when nobody has answered at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late Box<dynamic> settings;
  late Box<dynamic> habits;
  late Box<dynamic> daily;

  final now = DateTime(2026, 9, 1, 12);

  Future<void> seedGuestData() async {
    await settings.put(LocalStoreService.activeCatalogIdsKey, ['witr']);
    await settings.put(LocalStoreService.guestDashboardKey, {'level': 4});
    await habits.put(LocalStoreService.guestCustomHabitsKey, [
      {'id': 'h1'}
    ]);
    await daily.put('2026-08-30', {
      'habitCompletions': {'witr': 1}
    });
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('guest_discard_');
    Hive.init(tmp.path);
    settings = await Hive.openBox<dynamic>('box_settings');
    habits = await Hive.openBox<dynamic>('box_habits');
    daily = await Hive.openBox<dynamic>('box_daily_logs');
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  group('marking', () {
    test('sets a deadline one grace period out', () async {
      await LocalStoreService.markGuestDataForDiscard(now);
      final deadline = await LocalStoreService.guestDiscardDeadline();
      expect(
        deadline,
        DateTime(2026, 9, 1 + LocalStoreService.guestDiscardGraceDays, 12),
      );
    });

    test('a second answer does not push the deadline further out', () async {
      // One device, two accounts, two answers. The second must not keep
      // the data alive for another full week.
      await LocalStoreService.markGuestDataForDiscard(now);
      await LocalStoreService.markGuestDataForDiscard(
          now.add(const Duration(days: 3)));
      final deadline = await LocalStoreService.guestDiscardDeadline();
      expect(
        deadline,
        DateTime(2026, 9, 1 + LocalStoreService.guestDiscardGraceDays, 12),
      );
    });

    test('re-entering guest mode cancels the countdown', () async {
      await LocalStoreService.markGuestDataForDiscard(now);
      await LocalStoreService.clearGuestDiscardMark();
      expect(await LocalStoreService.guestDiscardDeadline(), isNull);
    });
  });

  group('sweeping', () {
    test('deletes everything once the deadline has passed', () async {
      await seedGuestData();
      await LocalStoreService.markGuestDataForDiscard(now);

      final swept = await LocalStoreService.sweepDiscardedGuestData(
        now: now.add(const Duration(days: 8)),
        inGuestMode: false,
      );

      expect(swept, isTrue);
      expect(await LocalStoreService.hasGuestProgress(), isFalse);
      expect(settings.get(LocalStoreService.activeCatalogIdsKey), isNull);
      expect(habits.get(LocalStoreService.guestCustomHabitsKey), isNull);
      expect(daily.isEmpty, isTrue);
      // The bookkeeping goes with it, so nothing is left counting down on
      // data that is no longer there.
      expect(await LocalStoreService.guestDiscardDeadline(), isNull);
    });

    test('does nothing before the deadline', () async {
      await seedGuestData();
      await LocalStoreService.markGuestDataForDiscard(now);

      final swept = await LocalStoreService.sweepDiscardedGuestData(
        now: now.add(const Duration(days: 6)),
        inGuestMode: false,
      );

      expect(swept, isFalse);
      expect(await LocalStoreService.hasGuestProgress(), isTrue);
    });

    test('does nothing when nobody has answered', () async {
      // No deadline means no decision has been made, so the data is not
      // stranded — it may still be someone's live guest session.
      await seedGuestData();
      final swept = await LocalStoreService.sweepDiscardedGuestData(
        now: now.add(const Duration(days: 400)),
        inGuestMode: false,
      );
      expect(swept, isFalse);
      expect(await LocalStoreService.hasGuestProgress(), isTrue);
    });

    test('refuses to run during a guest session even when overdue', () async {
      // The hard veto. This clears the daily box, which a live guest
      // session reads and writes continuously.
      await seedGuestData();
      await LocalStoreService.markGuestDataForDiscard(now);

      final swept = await LocalStoreService.sweepDiscardedGuestData(
        now: now.add(const Duration(days: 30)),
        inGuestMode: true,
      );

      expect(swept, isFalse);
      expect(await LocalStoreService.hasGuestProgress(), isTrue);
      expect(daily.isNotEmpty, isTrue);
    });
  });

  group('decided accounts', () {
    test('records each account separately', () async {
      // One device can sign into more than one account, and each is
      // entitled to the offer once while the data is still there.
      expect(await LocalStoreService.hasDecidedReconnect('a'), isFalse);
      await LocalStoreService.markReconnectDecided('a');
      expect(await LocalStoreService.hasDecidedReconnect('a'), isTrue);
      expect(await LocalStoreService.hasDecidedReconnect('b'), isFalse);
      await LocalStoreService.markReconnectDecided('b');
      expect(await LocalStoreService.hasDecidedReconnect('a'), isTrue);
      expect(await LocalStoreService.hasDecidedReconnect('b'), isTrue);
    });

    test('the sweep forgets them, since the data they answered about is gone',
        () async {
      await seedGuestData();
      await LocalStoreService.markReconnectDecided('a');
      await LocalStoreService.markGuestDataForDiscard(now);

      await LocalStoreService.sweepDiscardedGuestData(
        now: now.add(const Duration(days: 8)),
        inGuestMode: false,
      );

      expect(await LocalStoreService.hasDecidedReconnect('a'), isFalse);
    });
  });

  // ── Copy ────────────────────────────────────────────────────────────
  //
  // The sheet and banner drop a day count into the middle of a sentence,
  // which the shared daysCount (a standalone stat label: "3 Days") reads
  // wrong for - it showed "deleted in 1 Days" on a device holding a
  // single day.

  group('daysInSentence', () {
    test('English is lower case and respects the singular', () {
      const s = S(Locale('en'));
      expect(s.daysInSentence(1), '1 day');
      expect(s.daysInSentence(2), '2 days');
      expect(s.daysInSentence(7), '7 days');
    });

    test('Arabic keeps the dual and the 3-10 plural', () {
      const s = S(Locale('ar'));
      expect(s.daysInSentence(1), 'يوم واحد');
      expect(s.daysInSentence(2), 'يومان');
      expect(s.daysInSentence(7), '7 أيام');
    });

    test('the reconnect copy names one habit and one day correctly', () {
      const s = S(Locale('en'));
      expect(s.reconnectFound(1, 1, 1),
          'Found on this device: 1 habit, 1 day, level 1.');
      expect(s.reconnectFound(3, 12, 4),
          'Found on this device: 3 habits, 12 days, level 4.');
    });
  });
}
