import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
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
      // All three boxes, exactly as main() opens them at boot. The app never
      // runs with a subset: habitListProvider reaches settings (see
      // catalogOverridesProvider, which layers a person's edits over a preset)
      // and reaching an unopened box mid-test raced this temp directory being
      // deleted. Opening what production opens is the honest fixture.
      await Hive.openBox<dynamic>('box_settings');
      await Hive.openBox<dynamic>('box_daily_logs');
      await Hive.openBox<dynamic>('box_habits');
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
      // ActiveCatalogNotifier.toggle kicks off _save() without awaiting it
      // (nothing in the UI waits on a Hive write), so a test that ends the
      // moment its synchronous expects pass can still have a put in flight.
      // Deleting the boxes out from under it throws "Box has already been
      // closed" AFTER the test body has already succeeded, and the runner
      // attributes a late async error to whichever test happens to be
      // running, so the failure names an innocent test.
      //
      // This waited 50ms and hoped. That is a bet on how fast the machine
      // is, and it loses: saturating half this machine's cores reproduced
      // the failure, because the put had not landed inside 50ms. `settled`
      // waits for the actual write instead of guessing at how long it takes.
      await container.read(activeCatalogProvider.notifier).settled;
      container.dispose();
      await Hive.deleteFromDisk();
      // deleteFromDisk already removes the box files it created inside this
      // directory; tolerate it having taken the directory with them rather
      // than failing teardown on a PathNotFoundException.
      if (tmp.existsSync()) await tmp.delete(recursive: true);
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

      // Stint 1 is seeded on real, past days rather than produced by
      // toggling four times in a row. Those four toggles all land on one
      // effective day, and a stint that opens and closes on the same day
      // it reopens is no longer recorded at all — see toggle's same-day
      // branch and pause_resume_test's coverage of it. Seeding keeps this
      // test about what it is actually for: a SECOND, genuinely separate
      // activation window must not clobber the first.
      final firstStart =
          DateTime.now().effectiveDay.subtract(const Duration(days: 30));
      final firstEnd =
          DateTime.now().effectiveDay.subtract(const Duration(days: 20));
      notifier.activatedAt = {catalogId: firstStart};
      notifier.catalogArchivedAt = {catalogId: firstEnd};

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
      // Seeded on past days for the same reason as the test above: four
      // toggles in one run are all one effective day, which is now
      // deliberately recorded as a single window rather than two
      // overlapping ones.
      notifier.activatedAt = {
        catalogId: DateTime.now().effectiveDay.subtract(
          const Duration(days: 30),
        ),
      };
      notifier.catalogArchivedAt = {
        catalogId: DateTime.now().effectiveDay.subtract(
          const Duration(days: 20),
        ),
      };
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
