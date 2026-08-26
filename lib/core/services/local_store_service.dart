import 'package:hive_flutter/hive_flutter.dart';

import '../constants/game_constants.dart';

class LocalStoreService {
  LocalStoreService._();

  static const String guestDashboardKey = 'guest_dashboard_state';
  static const String guestFocusPrefix = 'guest_focus_plan_';
  static const String guestCustomHabitsKey = 'guest_custom_habits';
  static const String guestArchivedCustomHabitsKey =
      'guest_archived_custom_habits';

  /// Closed pause windows for CUSTOM habits: habitId -> [{start, end}].
  ///
  /// The catalog side has had this for a while (activeCatalogStintHistory);
  /// custom habits had nothing, so resuming one erased the fact that it had
  /// ever been paused. That is what let a room re-grade a paused stretch as
  /// missed the moment the habit came back. Same shape and same reasoning as
  /// ActiveCatalogNotifier.catalogStintHistory, kept beside the habits rather
  /// than inside them so no copy-constructor can silently drop it.
  static const String guestCustomStintHistoryKey =
      'guest_custom_habit_stints';
  static const String guestMatrixTasksKey = 'guest_matrix_tasks';
  static const String guestMatrixQuadrantsKey = 'guest_matrix_quadrants';
  static const String guestCharacterKey = 'guest_character_state';
  // Deliberately its own key, not folded into guestCharacterKey above:
  // putSettingsMap does a plain Hive .put() (a full overwrite at that key,
  // no auto-merge - see that method below), so sharing a key between two
  // independent notifiers (CharacterNotifier and PrestigeNotifier) would
  // have one silently clobber the other's guest data on every save.
  static const String guestPrestigeKey = 'guest_prestige_state';

  /// When paused habits should come back by themselves: `{habitId: ISO8601}`.
  ///
  /// Deliberately local, and deliberately NOT a field on the habit itself.
  /// A catalog habit's paused state lives in ActiveCatalogNotifier's
  /// catalogArchivedAt map while a custom habit carries archivedAt on the
  /// template, so putting a return date on "the habit" would mean changing
  /// two separate persistence schemas, both of which sync, for what is only
  /// ever a convenience. The pause itself still syncs; only the reminder to
  /// undo it stays on the device that set it, which is the right trade for
  /// something a second device would simply find already resumed.
  ///
  /// Scoped per signed-in identity via [habitResumeDatesKeyFor]. The premise
  /// that let this be device-global — "a habit id is unique per account" — is
  /// true for custom habits (Uuid ids) but FALSE for catalog presets, whose
  /// ids are const template strings ('tahajjud', ...) shared by every account.
  /// On a shared device that let account A's booking for a preset resolve, or
  /// be pruned, against account B's own paused copy of the same preset: A's
  /// "back on Sep 1" would auto-resume B's deliberately-indefinite pause, and
  /// pruneMissing could never sweep it because the id resolves to a real (wrong
  /// account's) habit. Namespacing by uid keeps each account's bookings to
  /// itself; a guest gets its own bucket too.
  static const String habitResumeDatesKey = 'habit_resume_dates';

  /// The per-identity key an account's return bookings live under. [uid] null
  /// is a guest session, which gets its own bucket rather than sharing the
  /// signed-out global one.
  static String habitResumeDatesKeyFor(String? uid) =>
      '${habitResumeDatesKey}_${uid ?? 'guest'}';

  static Future<Box<dynamic>> settingsBox() => _open(GameConstants.boxSettings);
  static Future<Box<dynamic>> dailyBox() => _open(GameConstants.boxDailyLogs);
  static Future<Box<dynamic>> habitsBox() => _open(GameConstants.boxHabits);

  static Future<Box<dynamic>> _open(String name) =>
      Hive.isBoxOpen(name)
          ? Future.value(Hive.box<dynamic>(name))
          : Hive.openBox<dynamic>(name);

  static String dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Map<String, dynamic> asStringMap(Object? value) {
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return <String, dynamic>{};
  }

  static List<Map<String, dynamic>> asMapList(Object? value) {
    if (value is List) {
      return value
          .whereType<Map>()
          .map((item) => item.map((key, val) => MapEntry(key.toString(), val)))
          .toList();
    }
    return const [];
  }

  static Future<Map<String, dynamic>> getSettingsMap(String key) async =>
      asStringMap((await settingsBox()).get(key));

  static Future<void> putSettingsMap(String key, Map<String, dynamic> value) async =>
      (await settingsBox()).put(key, value);

  static Future<Map<String, dynamic>> getDailyMap(String dateKey) async =>
      asStringMap((await dailyBox()).get(dateKey));

  /// Every stored day at once, keyed by dateKey — what the guest side of
  /// the yearly strip aggregates from. The box is in memory, so unlike the
  /// Firestore daily collection there is no per-day read cost to avoid.
  static Future<Map<String, Map<String, dynamic>>> allDailyMaps() async {
    final box = await dailyBox();
    return {
      for (final key in box.keys) key.toString(): asStringMap(box.get(key)),
    };
  }

  static Future<void> putDailyMap(String dateKey, Map<String, dynamic> value) async =>
      (await dailyBox()).put(dateKey, value);

  // ── Serialized day writes ────────────────────────────────────────────────
  //
  // One stored day is a single map holding fields owned by four different
  // notifiers: habitCompletions and completedAtMinutes from the dashboard,
  // squareStates and squareNotes from the grid, the intention fields, and the
  // night review's answers. Hive writes the map WHOLE, so every one of those
  // writers has to read the day, change its own field, and put the whole
  // thing back.
  //
  // Two of those overlapping is a lost update, and it was not hypothetical.
  // Correcting a green square to red called uncompleteHabit and then the
  // square write without awaiting the first: the square write read the day
  // before the uncomplete had put it back, so it saved its own change on top
  // of a stale copy and restored habitCompletions to 1. The square went red
  // and the habit still counted as done, for XP, for the streak and in every
  // report. See test/features/grid/palette_correction_race_test.dart.
  //
  // Awaiting at that one call site fixed that one path. This makes the whole
  // class impossible: every read, modify, write for a given day goes through
  // here and they queue behind each other, so a caller can no longer create a
  // lost update by forgetting an await.

  /// The writes still in flight for a day, so the next one can queue behind
  /// them. The entry is REMOVED once the last one settles, which matters: a
  /// day with nothing in flight must start its write immediately, exactly as
  /// the hand rolled read then put did, rather than being pushed onto a later
  /// microtask behind a future that already completed.
  static final Map<String, Future<void>> _dailyWriteChains = {};

  /// Reads day [dateKey], hands it to [mutate], and writes it back, with the
  /// whole sequence serialized against every other call for the same day.
  ///
  /// [mutate] must be synchronous. An async mutator would reopen exactly the
  /// window this exists to close.
  static Future<void> updateDailyMap(
    String dateKey,
    void Function(Map<String, dynamic> day) mutate,
  ) {
    Future<void> run() async {
      final box = await dailyBox();
      final day = asStringMap(box.get(dateKey));
      mutate(day);
      await box.put(dateKey, day);
    }

    final inFlight = _dailyWriteChains[dateKey];
    final next = inFlight == null ? run() : inFlight.then((_) => run());

    // The QUEUE swallows failures so one bad write cannot wedge the day for
    // the rest of the session. The future handed back still reports the
    // error to whoever asked for this write.
    late final Future<void> guarded;
    guarded = next.then((_) {}, onError: (_) {}).whenComplete(() {
      if (identical(_dailyWriteChains[dateKey], guarded)) {
        _dailyWriteChains.remove(dateKey);
      }
    });
    _dailyWriteChains[dateKey] = guarded;
    return next;
  }

  /// Waits for every queued day write to finish.
  ///
  /// Nothing in the app needs this: the boxes live as long as the process, so
  /// a write in flight always lands. Tests are the exception, because they
  /// tear the Hive directory down between cases, and a caller that fires a
  /// square write without awaiting it (which is most of them, since the
  /// square turns on the same frame either way) leaves work queued behind it.
  /// Call this before deleting the store.
  static Future<void> settleDailyWrites() async {
    while (_dailyWriteChains.isNotEmpty) {
      await Future.wait(_dailyWriteChains.values.toList());
    }
  }
}