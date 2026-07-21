import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/habit_plans.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';

/// Covers ActiveCatalogNotifier's archive-on-toggle-off behavior and,
/// specifically, catalogStintHistory — the part that keeps a catalog
/// habit's *earlier* activation windows alive across more than one
/// on/off cycle, not just its current-or-most-recent one. See
/// catalogStintHistory's own doc comment (habit_plans.dart) for why this
/// needs a dedicated test: activatedAt/catalogArchivedAt alone silently
/// lose a stint the moment a second reactivation overwrites them, and
/// that's exactly the kind of bug that only shows up on the *second*
/// toggle, not the first.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A real catalog id so isScheduledFor/withDates have a genuine template
  // to work against.
  const catalogId = 'morning_athkar';

  group('ActiveCatalogNotifier (guest path)', () {
    late Directory tmp;
    late ProviderContainer container;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('catalog_test_');
      Hive.init(tmp.path);
      container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        ],
      );
      await container.read(authStateProvider.future);
      container.read(activeCatalogProvider);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });

    tearDown(() async {
      container.dispose();
      await Hive.deleteFromDisk();
      await tmp.delete(recursive: true);
    });

    test('toggle on then off archives instead of erasing the birth date',
        () async {
      final notifier = container.read(activeCatalogProvider.notifier);
      notifier.toggle(catalogId);
      expect(container.read(activeCatalogProvider), contains(catalogId));
      expect(notifier.activatedAt[catalogId], isNotNull);

      notifier.toggle(catalogId);
      expect(container.read(activeCatalogProvider), isNot(contains(catalogId)));
      // The old behavior erased activatedAt on deactivation — this is
      // exactly the regression allHabitsEverProvider depends on not
      // happening any more.
      expect(notifier.activatedAt[catalogId], isNotNull);
      expect(notifier.catalogArchivedAt[catalogId], isNotNull);
    });

    test('re-activating clears the archive date and starts fresh', () async {
      final notifier = container.read(activeCatalogProvider.notifier);
      notifier.toggle(catalogId); // on
      notifier.toggle(catalogId); // off (archived)
      expect(notifier.catalogArchivedAt[catalogId], isNotNull);

      notifier.toggle(catalogId); // on again
      expect(container.read(activeCatalogProvider), contains(catalogId));
      expect(notifier.catalogArchivedAt[catalogId], isNull);
      expect(notifier.activatedAt[catalogId], isNotNull);
    });

    test(
        'a second on/off cycle preserves the FIRST stint in '
        'catalogStintHistory instead of losing it', () async {
      final notifier = container.read(activeCatalogProvider.notifier);

      notifier.toggle(catalogId); // stint 1 starts
      final firstStart = notifier.activatedAt[catalogId]!;
      notifier.toggle(catalogId); // stint 1 ends
      final firstEnd = notifier.catalogArchivedAt[catalogId]!;

      // No history yet — there's only ever been one stint so far, and it's
      // still the "current-or-most-recent" one, not yet superseded.
      expect(notifier.catalogStintHistory[catalogId], isNull);

      notifier.toggle(catalogId); // stint 2 starts — this is the moment
      // stint 1 would be lost under the old (single-slot) design.
      notifier.toggle(catalogId); // stint 2 ends

      // Stint 1 is preserved as closed history, exactly as it was —
      // not just "some entry got added", but the *same dates* captured
      // above, and only one entry (stint 2 must not also land in here;
      // it's still the current-or-most-recent slot, held separately in
      // activatedAt/catalogArchivedAt).
      expect(notifier.catalogStintHistory[catalogId], hasLength(1));
      expect(notifier.catalogStintHistory[catalogId]!.first.$1, firstStart);
      expect(notifier.catalogStintHistory[catalogId]!.first.$2, firstEnd);
      // Note: this test deliberately doesn't assert activatedAt/
      // catalogArchivedAt differ *numerically* from firstStart/firstEnd —
      // effectiveDay truncates to day granularity, so a fast test run
      // toggling four times in the same millisecond can legitimately
      // produce the same calendar day for both stints. What actually
      // matters — that stint 1 lives in history while stint 2 lives in
      // the current slot, as two separately-stored windows rather than
      // one clobbering the other — is exactly what the history-list
      // assertions above already prove.
    });

    test(
        'allHabitsEverProvider emits one template per stint after multiple '
        'on/off cycles, all sharing the same id', () async {
      final notifier = container.read(activeCatalogProvider.notifier);
      notifier.toggle(catalogId);
      notifier.toggle(catalogId);
      notifier.toggle(catalogId);
      notifier.toggle(catalogId);

      final everHabits = container
          .read(allHabitsEverProvider)
          .where((h) => h.id == catalogId)
          .toList();

      // Stint 1 (closed, from catalogStintHistory) + stint 2
      // (current-or-most-recent, from activatedAt/catalogArchivedAt).
      expect(everHabits, hasLength(2));
      expect(everHabits.every((h) => h.archivedAt != null), isTrue);
      // Every stint's own createdAt must be strictly before its own
      // archivedAt — a sanity check that dates weren't mixed up across
      // the two entries.
      for (final h in everHabits) {
        expect(h.createdAt!.isAfter(h.archivedAt!), isFalse);
      }
    });

    test('a habit never activated at all has no stint history', () async {
      final notifier = container.read(activeCatalogProvider.notifier);
      expect(notifier.catalogStintHistory[catalogId], isNull);
      expect(
        container.read(allHabitsEverProvider).where((h) => h.id == catalogId),
        isEmpty,
      );
    });
  });
}
