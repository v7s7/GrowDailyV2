// Searching for a note you cannot date.
//
// «ابحث في العادات أو الملاحظات» only ever searched the month on screen, and
// said nothing about it. So a hit in September read as "that is everything I
// ever wrote" while four more sat unread in March, and finding them meant
// flipping months and retyping the query in each one.
//
// The walk is affordable only because the note index exists: it visits ONLY
// months that actually hold writing, so the cost is bounded by how much
// someone has written rather than by how long they have used the app. These
// pin that bound, and the free-tier ceiling, which is the pair that would
// silently rot into "read the whole collection".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/features/grid/notifiers/note_index_notifier.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';

void main() {
  // Same shape the screen builds: index keys to months, dropped to what the
  // account may open, newest first.
  List<DateTime> searchable({
    required Map<String, Set<int>> index,
    required DateTime now,
    required bool isPremium,
  }) =>
      index.keys
          .map(monthFromKey)
          .whereType<DateTime>()
          .where((m) => canBrowseHistoryMonth(
                monthStart: m,
                now: now,
                isPremium: isPremium,
              ))
          .toList()
        ..sort((a, b) => b.compareTo(a));

  group('monthFromKey', () {
    test('round-trips with monthKeyOf', () {
      expect(monthFromKey(monthKeyOf('2026-09-08')), DateTime(2026, 9));
      expect(monthFromKey('2025-12'), DateTime(2025, 12));
    });

    test('a malformed key is skipped, not guessed at', () {
      // The index is read straight off a document, so one hand-edited key
      // must not take the picker or the walk with it.
      for (final bad in ['', '2026', '2026-13', 'garbage', '2026-00']) {
        expect(monthFromKey(bad), isNull, reason: 'accepted "$bad"');
      }
    });
  });

  group('which months the walk visits', () {
    final now = DateTime(2026, 9, 8); // free floor: 2026-07-01

    test('only months that hold writing, newest first', () {
      final months = searchable(
        index: {
          '2026-09': {4, 8},
          '2026-07': {19},
          '2026-08': {2},
        },
        now: now,
        isPremium: true,
      );
      expect(months, [DateTime(2026, 9), DateTime(2026, 8), DateTime(2026, 7)],
          reason: 'newest first, so the results read the same direction the '
              'month view does and the likeliest hit lands first');
    });

    test('an account with nothing written walks nowhere', () {
      expect(searchable(index: const {}, now: now, isPremium: true), isEmpty,
          reason: 'the scope line must not offer a search over zero months');
    });

    test('a free account never walks past its own window', () {
      final index = {
        '2026-09': {1},
        '2026-08': {1},
        '2026-07': {1},
        '2026-06': {1},
        '2025-01': {1},
      };
      final free = searchable(index: index, now: now, isPremium: false);
      expect(free, [DateTime(2026, 9), DateTime(2026, 8), DateTime(2026, 7)]);
      expect(free.length, kFreeHistoryMonths,
          reason: 'the count in the line is the count actually walked, so a '
              'free account is told 3 and never teased with 30');

      final premium = searchable(index: index, now: now, isPremium: true);
      expect(premium.length, 5);
    });

    test('the bound is the writing, not the calendar', () {
      // Three years of daily use with notes in two months costs two month
      // reads, which is the whole reason the index earns its keep.
      final index = {'2024-03': {7}, '2026-09': {2}};
      expect(searchable(index: index, now: now, isPremium: true), hasLength(2));
    });
  });

  group('the scope line copy', () {
    test('counts read naturally in Arabic at 1, 2, few and many', () {
      const ar = S(Locale('ar'));
      expect(ar.gridJournalSearchAllMonths(1), contains('الشهر'));
      expect(ar.gridJournalSearchAllMonths(2), contains('الشهرين'));
      // 3 to 10 takes شهور, 11+ takes شهر. Getting this wrong is the kind of
      // thing that reads as machine translation.
      expect(ar.gridJournalSearchAllMonths(4), contains('شهور'));
      expect(ar.gridJournalSearchAllMonths(14), contains('14 شهر'));
    });

    test('English pluralises too', () {
      const en = S(Locale('en'));
      expect(en.gridJournalSearchAllMonths(1), contains('1 month'));
      expect(en.gridJournalSearchAllMonths(6), contains('6 months'));
    });

    test('every string differs between the two languages', () {
      const ar = S(Locale('ar'));
      const en = S(Locale('en'));
      expect(ar.gridJournalSearchThisMonth, isNot(en.gridJournalSearchThisMonth));
      expect(ar.gridJournalSearchBackToMonth,
          isNot(en.gridJournalSearchBackToMonth));
      expect(ar.gridJournalSearchProgress(1, 3),
          isNot(en.gridJournalSearchProgress(1, 3)));
    });
  });
}
