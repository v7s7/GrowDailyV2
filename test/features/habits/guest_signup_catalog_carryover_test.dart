import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/habit_plans.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';

/// What a guest's catalog picks used to do to the account they created.
///
/// ActiveCatalogNotifier._load() (habit_plans.dart) falls back to this
/// device's own Hive box when the signed-in account has no
/// `activeCatalogIds` field. That rescue is right for the account it was
/// written for: one that signed in from the era when catalog picks were
/// Hive-only. It was also firing for every freshly registered account,
/// because AuthNotifier._createUserDoc did not write the field either, so
/// a guest who signed up silently carried their catalog habits over.
///
/// The fallback seeds ONLY the ids. `activatedAt` was already parsed from
/// the absent Firestore field into an empty map and is never re-read from
/// Hive on that path, so the habits arrived with no birth dates, and
/// _kickSave then wrote that emptiness back. The first test pins what
/// that costs; the second pins the property the fix relies on; the third
/// pins the fix itself — _createUserDoc now writes an empty
/// `activeCatalogIds` for a genuine registration, which says "this
/// account HAS an answer and it is none" and keeps the fallback out of
/// it, while the legacy sign-in path still gets rescued.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const catalogId = 'morning_athkar';

  late Directory tmp;
  ProviderContainer? container;

  Future<void> boot() async {
    final c = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
      ],
    );
    container = c;
    await c.read(authStateProvider.future);
    c.read(activeCatalogProvider);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('guest_carryover_test_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings');
    await Hive.openBox<dynamic>('box_daily_logs');
    await Hive.openBox<dynamic>('box_habits');
  });

  // Nullable and conditional because the hasGuestProgress group below never
  // boots a container - a nested tearDown ADDS to this one rather than
  // replacing it, so this has to cope with there being nothing to tear
  // down. `settled` waits for ActiveCatalogNotifier's fire-and-forget save
  // rather than guessing at a delay; see active_catalog_notifier_test.
  tearDown(() async {
    final c = container;
    if (c != null) {
      await c.read(activeCatalogProvider.notifier).settled;
      c.dispose();
      container = null;
    }
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test(
      'catalog ids without their activation dates paint every past day as '
      'scheduled', () async {
    // Exactly the state _load()'s local-seed fallback produces: the ids,
    // and nothing else.
    await Hive.box<dynamic>('box_settings')
        .put('active_catalog_ids_v1', <String>[catalogId]);
    await boot();

    final habits = container!.read(habitListProvider);
    final habit = habits.firstWhere((h) => h.id == catalogId);

    // No birth date survived the carry-over.
    expect(habit.createdAt, isNull);

    // So the habit claims it was running two months before this account
    // existed. Every surface that asks isScheduledFor (Grid squares, the
    // heatmap, insights, the weekly recap, room credit) gets a yes, and
    // there are no completions behind it.
    final longBefore =
        DateTime.now().effectiveDay.subtract(const Duration(days: 60));
    expect(habit.isScheduledFor(longBefore), isTrue);
  });

  test('the same ids WITH their activation dates do not', () async {
    final activatedOn =
        DateTime.now().effectiveDay.subtract(const Duration(days: 3));
    final settings = Hive.box<dynamic>('box_settings');
    await settings.put('active_catalog_ids_v1', <String>[catalogId]);
    await settings.put('active_catalog_activated_at_v1',
        {catalogId: activatedOn.toIso8601String()});
    await boot();

    final habits = container!.read(habitListProvider);
    final habit = habits.firstWhere((h) => h.id == catalogId);

    expect(habit.createdAt, isNotNull);
    final longBefore =
        DateTime.now().effectiveDay.subtract(const Duration(days: 60));
    expect(habit.isScheduledFor(longBefore), isFalse);
  });

  // ── hasGuestProgress ────────────────────────────────────────────────
  //
  // What the fresh-start warning is gated on now (auth_screen.dart). It
  // replaced `ref.watch(guestModeProvider)`, which is always false on that
  // screen and made the warning unrenderable: _AuthGate only builds the
  // auth screen when guest mode is off, and every path that sends a guest
  // there clears the flag before navigating.

  group('hasGuestProgress', () {
    test('false on a device that has never been used', () async {
      expect(await LocalStoreService.hasGuestProgress(), isFalse);
    });

    test('false when the guest keys exist but are empty', () async {
      // An empty list is what a guest who turned a habit on and back off
      // leaves behind. There is nothing there to lose, so it must not
      // trigger a warning about losing it.
      await Hive.box<dynamic>('box_settings')
          .put(LocalStoreService.activeCatalogIdsKey, <String>[]);
      await Hive.box<dynamic>('box_habits')
          .put(LocalStoreService.guestCustomHabitsKey, <dynamic>[]);
      expect(await LocalStoreService.hasGuestProgress(), isFalse);
    });

    test('true on catalog picks alone', () async {
      await Hive.box<dynamic>('box_settings')
          .put(LocalStoreService.activeCatalogIdsKey, <String>[catalogId]);
      expect(await LocalStoreService.hasGuestProgress(), isTrue);
    });

    test('true on a custom habit alone', () async {
      await Hive.box<dynamic>('box_habits').put(
        LocalStoreService.guestCustomHabitsKey,
        [
          {'id': 'abc', 'name': 'Read'}
        ],
      );
      expect(await LocalStoreService.hasGuestProgress(), isTrue);
    });

    test('true on a completed day alone', () async {
      // No habits left active, but the history is still theirs.
      await LocalStoreService.putDailyMap(
        LocalStoreService.dateKey(DateTime.now().effectiveDay),
        {
          'habitCompletions': {catalogId: 1}
        },
      );
      expect(await LocalStoreService.hasGuestProgress(), isTrue);
    });

    test('true on dashboard counters alone', () async {
      await LocalStoreService.putSettingsMap(
        LocalStoreService.guestDashboardKey,
        {'habitTotalCompletions': {catalogId: 4}},
      );
      expect(await LocalStoreService.hasGuestProgress(), isTrue);
    });
  });
}
