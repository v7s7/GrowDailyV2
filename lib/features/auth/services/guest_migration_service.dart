import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/services/local_store_service.dart';

/// What this device is holding, in the terms the offer is phrased in.
///
/// Counts only. The sheet names them back to the person ("3 habits, 12
/// days, level 4") and that is the whole point of showing them: on a
/// shared or handed-down phone, someone who just installed the app and
/// reads "level 22, 140 days" knows immediately that this is not theirs
/// and can say no. An abstract "bring your progress over?" cannot be
/// checked by the only person able to check it.
class GuestSnapshot {
  const GuestSnapshot({
    required this.habitCount,
    required this.dayCount,
    required this.level,
    required this.taskCount,
  });

  final int habitCount;
  final int dayCount;
  final int level;
  final int taskCount;

  /// Whether the four numbers this sheet actually NAMES are all blank — a
  /// device that only ever had the app opened once has keys but nothing in
  /// them.
  ///
  /// MUST NOT be used to decide whether to make the offer, and an audit
  /// that called this "dead code, wire it or delete it" is why the warning
  /// is written down rather than left to be re-derived. It counts habits,
  /// days, tasks and level; [GuestMigrationService.migrate] ALSO moves the
  /// guest's character, prestige, custom rewards and matrix quadrants. So
  /// someone whose only guest data is an avatar they picked reads as
  /// "empty" here while genuinely having something to lose — gating the
  /// offer on this would refuse to move it and then let the 7-day sweep
  /// delete it, having never asked. [LocalStoreService.hasGuestProgress] is
  /// the correct gate precisely because it asks the broader question.
  ///
  /// What it is legitimately for: deciding whether the summary LINE has
  /// anything to say.
  bool get isEmpty =>
      habitCount == 0 && dayCount == 0 && taskCount == 0 && level <= 1;
}

/// The outcome, so the caller can tell the person the truth rather than
/// always claiming success.
class GuestMigrationResult {
  const GuestMigrationResult({required this.movedDays, required this.failed});

  final int movedDays;
  final bool failed;
}

/// Moves a guest's local data onto the account they just created.
///
/// Runs ONLY from the reconnect offer, and only for a brand-new
/// registration. It is deliberately never wired to plain sign-in: merging
/// a guest's XP, streaks and completion history into an account that
/// already has its own is a reconciliation with no correct answer, and
/// silently picking one would corrupt real history.
///
/// Every write is `merge: true` and every document is keyed by something
/// stable (the date for a day, the habit's own id), so running this twice
/// lands the same data twice rather than duplicating it. That matters:
/// the source is not deleted on success (see
/// LocalStoreService.guestDiscardAtKey), precisely so a half-finished
/// migration can be run again from the Profile banner.
class GuestMigrationService {
  GuestMigrationService._();

  /// Firestore's hard limit is 500 writes per batch; the existing account
  /// deletion path already chunks at 400 for the same reason.
  static const int _chunkSize = 400;

  /// Swapped for a FakeFirebaseFirestore in tests.
  ///
  /// This class is the one place in the app where a single run writes to
  /// the profile document and four subcollections at once, and where the
  /// interesting failures are all shape-level: a String reaching a field
  /// every reader expects to be a Timestamp, a retry duplicating a
  /// person's habits, a future-dated day taking a whole batch down with
  /// it. None of that is reachable through FirebaseFirestore.instance in a
  /// unit test, and none of it is the kind of thing to verify by reading.
  @visibleForTesting
  static FirebaseFirestore? firestoreOverride;

  static FirebaseFirestore get _db =>
      firestoreOverride ?? FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      _db.collection('users').doc(uid);

  // ── The offer ───────────────────────────────────────────────────────

  /// Reads just enough to describe the data without interpreting it.
  static Future<GuestSnapshot> summarize() async {
    final settings = await LocalStoreService.settingsBox();
    final habits = await LocalStoreService.habitsBox();
    final daily = await LocalStoreService.dailyBox();

    final catalogIds = settings.get(LocalStoreService.activeCatalogIdsKey);
    final customHabits = habits.get(LocalStoreService.guestCustomHabitsKey);
    final tasks = settings.get(LocalStoreService.guestMatrixTasksKey);
    final dashboard = LocalStoreService.asStringMap(
      settings.get(LocalStoreService.guestDashboardKey),
    );

    return GuestSnapshot(
      habitCount: (catalogIds is List ? catalogIds.length : 0) +
          (customHabits is List ? customHabits.length : 0),
      // Days that actually record something, not every key ever touched:
      // an empty day map would otherwise inflate the number the person is
      // being asked to recognise.
      dayCount: daily.keys
          .where((k) => LocalStoreService.asStringMap(daily.get(k)).isNotEmpty)
          .length,
      level: (dashboard['level'] as num?)?.toInt() ?? 1,
      taskCount: tasks is List ? tasks.length : 0,
    );
  }

  // ── The move ────────────────────────────────────────────────────────

  /// Writes everything this device holds onto `users/[uid]`.
  ///
  /// Best-effort per section rather than all-or-nothing: one unreadable
  /// local record, or one section the server rejects, must not cost the
  /// other eight. [GuestMigrationResult.failed] reports whether any
  /// section failed so the caller can offer a retry, and the local data is
  /// left alone either way.
  static Future<GuestMigrationResult> migrate(String uid) async {
    var failed = false;
    var movedDays = 0;

    Future<void> section(Future<void> Function() run) async {
      try {
        await run();
      } catch (_) {
        failed = true;
      }
    }

    await section(() async => _migrateUserDoc(uid));
    await section(() async => movedDays = await _migrateDailyDocs(uid));
    await section(() async => _migrateCustomHabits(uid));
    await section(() async => _migrateCollection(
          uid,
          collection: 'matrix_tasks',
          box: await LocalStoreService.settingsBox(),
          key: LocalStoreService.guestMatrixTasksKey,
        ));
    await section(() async => _migrateCollection(
          uid,
          collection: 'custom_rewards',
          box: await LocalStoreService.settingsBox(),
          key: LocalStoreService.guestCustomRewardsKey,
        ));

    return GuestMigrationResult(movedDays: movedDays, failed: failed);
  }

  /// Everything that lives as a field on the profile document.
  ///
  /// One merge write, so the counters, the catalog, the character and the
  /// matrix quadrant settings either all land or none do. The field names
  /// on both sides are already identical - the guest maps were written to
  /// mirror the user document - with one deliberate exception handled
  /// below.
  static Future<void> _migrateUserDoc(String uid) async {
    final settings = await LocalStoreService.settingsBox();
    final habits = await LocalStoreService.habitsBox();

    final dashboard = LocalStoreService.asStringMap(
      settings.get(LocalStoreService.guestDashboardKey),
    );
    final character = LocalStoreService.asStringMap(
      settings.get(LocalStoreService.guestCharacterKey),
    );
    final prestige = LocalStoreService.asStringMap(
      settings.get(LocalStoreService.guestPrestigeKey),
    );
    final quadrants = LocalStoreService.asStringMap(
      settings.get(LocalStoreService.guestMatrixQuadrantsKey),
    );

    final payload = <String, dynamic>{
      ...dashboard,
      ...character,
      ...prestige,
      ...quadrants,
    };

    // displayName is dropped on purpose. _createUserDoc already seeded one
    // from the email local-part, and it is the single field that reaches a
    // Rooms leaderboard, where a guest's unscreened self-chosen name would
    // arrive having met none of setDisplayName's moderation.
    payload.remove('displayName');

    // The one field whose SHAPE differs between the two sides. A guest
    // stores an ISO string; the signed-in path stores a Timestamp, and
    // separately a 'lastActiveDay' date key that firestore.rules validates
    // (see userDayStampsOk). Writing the guest's string straight through
    // would leave a String where every reader expects a Timestamp.
    payload.remove('lastActiveDate');
    final lastActive =
        DateTime.tryParse(dashboard['lastActiveDate'] as String? ?? '');
    if (lastActive != null) {
      payload['lastActiveDate'] = Timestamp.fromDate(lastActive);
      payload['lastActiveDay'] = lastActive.toDateKey();
    }

    // The day stamps are rules-validated too: stampOk rejects anything
    // ahead of today, and one rejected field fails the whole write. A
    // device whose clock was wound forward during the guest session is
    // exactly how that happens, so drop rather than risk the write.
    final todayKey = DateTime.now().effectiveDay.toDateKey();
    for (final field in ['earnedDayKey', 'rewardedTasksDayKey']) {
      final value = payload[field];
      if (value is String && value.compareTo(todayKey) > 0) {
        payload.remove(field);
      }
    }

    void copy(Box source, String from, String to) {
      final value = source.get(from);
      if (_isNonEmpty(value)) payload[to] = value;
    }

    copy(settings, LocalStoreService.activeCatalogIdsKey, 'activeCatalogIds');
    copy(settings, LocalStoreService.activeCatalogActivatedAtKey,
        'activeCatalogActivatedAt');
    copy(settings, LocalStoreService.activeCatalogArchivedAtKey,
        'activeCatalogArchivedAt');
    copy(settings, LocalStoreService.activeCatalogStintHistoryKey,
        'activeCatalogStintHistory');
    copy(settings, LocalStoreService.catalogOverridesKey,
        LocalStoreService.catalogOverridesKey);
    copy(settings, LocalStoreService.habitOrderKey, 'habitOrder');
    copy(habits, LocalStoreService.guestCustomStintHistoryKey,
        'customHabitStintHistory');

    if (payload.isEmpty) return;
    await _userRef(uid).set(payload, SetOptions(merge: true));
  }

  /// Every stored day, into `users/{uid}/daily/{dateKey}`.
  ///
  /// Days ahead of today are skipped rather than written. firestore.rules
  /// refuses them (`notAhead(dateKey)`), and a rejected write fails its
  /// whole batch, so one bad day would otherwise cost every good day
  /// batched with it.
  static Future<int> _migrateDailyDocs(String uid) async {
    final daily = await LocalStoreService.dailyBox();
    final todayKey = DateTime.now().effectiveDay.toDateKey();
    final col = _userRef(uid).collection('daily');

    final writable = <String, Map<String, dynamic>>{};
    for (final key in daily.keys) {
      final dateKey = key.toString();
      if (dateKey.compareTo(todayKey) > 0) continue;
      final day = LocalStoreService.asStringMap(daily.get(key));
      if (day.isEmpty) continue;
      // Same String-versus-Timestamp difference as lastActiveDate above.
      final stamped = Map<String, dynamic>.from(day);
      final parsed = DateTime.tryParse(stamped['date'] as String? ?? '');
      stamped['date'] = parsed != null
          ? Timestamp.fromDate(parsed)
          : Timestamp.fromDate(DateTime.parse('${dateKey}T00:00:00'));
      writable[dateKey] = stamped;
    }

    final entries = writable.entries.toList();
    for (var i = 0; i < entries.length; i += _chunkSize) {
      final batch = _db.batch();
      for (final entry in entries.skip(i).take(_chunkSize)) {
        batch.set(col.doc(entry.key), entry.value, SetOptions(merge: true));
      }
      await batch.commit();
    }
    return entries.length;
  }

  /// Custom habits, active and archived, into one collection.
  ///
  /// Both lists land in `custom_habits`: an archived habit is not a
  /// separate place on the signed-in side, it is the same document
  /// carrying an archivedAt (see CustomHabitsNotifier._load, which splits
  /// one read into the two lists on exactly that field).
  static Future<void> _migrateCustomHabits(String uid) async {
    final habits = await LocalStoreService.habitsBox();
    final col = _userRef(uid).collection('custom_habits');
    final records = [
      ...LocalStoreService.asMapList(
          habits.get(LocalStoreService.guestCustomHabitsKey)),
      ...LocalStoreService.asMapList(
          habits.get(LocalStoreService.guestArchivedCustomHabitsKey)),
    ];
    await _writeRecords(col, records);
  }

  /// A guest list of `{id, ...}` maps into the matching subcollection.
  static Future<void> _migrateCollection(
    String uid, {
    required String collection,
    required Box box,
    required String key,
  }) async {
    await _writeRecords(
      _userRef(uid).collection(collection),
      LocalStoreService.asMapList(box.get(key)),
    );
  }

  /// Writes [records] keyed by their own `id`, chunked into batches.
  ///
  /// A record with no usable id is skipped rather than given a generated
  /// one: a fresh id every run would break this method's idempotency, and
  /// duplicating a person's habits on a retry is worse than dropping one
  /// malformed record.
  static Future<void> _writeRecords(
    CollectionReference<Map<String, dynamic>> col,
    List<Map<String, dynamic>> records,
  ) async {
    final usable =
        records.where((r) => (r['id'] as String?)?.isNotEmpty == true).toList();
    for (var i = 0; i < usable.length; i += _chunkSize) {
      final batch = _db.batch();
      for (final record in usable.skip(i).take(_chunkSize)) {
        final payload = Map<String, dynamic>.from(record)..remove('id');
        batch.set(
          col.doc(record['id'] as String),
          payload,
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    }
  }

  static bool _isNonEmpty(Object? value) {
    if (value is Map) return value.isNotEmpty;
    if (value is List) return value.isNotEmpty;
    return false;
  }
}
