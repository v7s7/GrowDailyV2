import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/services/local_store_service.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../../grid/models/square_state.dart';
import '../reports/habit_day_marks.dart';

/// Per-habit day history: which habit was DONE on which day, across the
/// whole account — the data behind the yearly strip (YearRecordScreen).
///
/// ── Why a mirror exists at all ─────────────────────────────────────────
/// The truth already lives in `users/{uid}/daily/{date}` docs, but reading
/// a year of it costs ~365 document reads per open. So each habit gets one
/// mirror doc — `users/{uid}/habit_history/{habitId}` holding
/// `{days: {dateKey: 1}}` — kept current by the same three choke points
/// that write per-habit day truth anywhere in the app:
///  - completeHabit's batch (today, done),
///  - uncompleteHabit's batch (today, undone when the count hits zero),
///  - WeeklyGridNotifier._persistSquare (ANY visible day, done exactly when
///    the square lands on a done state).
/// Presence-based (a key exists or it doesn't), not counted, because the
/// strip asks one question per cell and presence can't drift negative.
///
/// ── What each day now records ──────────────────────────────────────────
/// A day used to store `1` and mean "green". It now stores the [SquareState]
/// itself, so تخطّي, فشل and جزئي survive into the reports instead of
/// collapsing into the same absence as a day nobody touched. See
/// habit_day_marks.dart for the precedence rule and for why legacy `1`
/// values must never go through SquareState.fromJson.
///
/// [dayIsDone] is kept as the single spelling of "did this count", so the
/// strip, the backfill, the guest path and the tests can never disagree
/// about it.
bool dayIsDone(Map<String, dynamic> dailyDoc, String habitId) =>
    markIsDone(dayMark(dailyDoc, habitId));

/// Folds raw daily docs (dateKey -> doc map) into per-habit day marks.
///
/// Pure, so the backfill and the guest reader share one tested behaviour.
/// Days that recorded nothing at all are left out rather than stored as
/// [SquareState.none]: absence already means that, and writing it would grow
/// every mirror doc by every day the account has existed.
Map<String, Map<String, SquareState>> aggregateHabitHistory(
  Map<String, Map<String, dynamic>> dailyDocs,
) {
  final out = <String, Map<String, SquareState>>{};
  dailyDocs.forEach((dateKey, doc) {
    // Per DOCUMENT, not per account. These documents have been written by
    // several features across several app versions, and this fold is the
    // one-time migration path for every existing account: one day with an
    // unexpected shape must cost that day, not the other nine hundred. The
    // field-level casts below already degrade a wrong type to null, so this
    // is the backstop for anything they cannot see coming.
    try {
      final ids = <String>{
        ...((doc['habitCompletions'] as Map?)?.keys.map((k) => k.toString()) ??
            const Iterable<String>.empty()),
        ...((doc['squareStates'] as Map?)?.keys.map((k) => k.toString()) ??
            const Iterable<String>.empty()),
      };
      for (final id in ids) {
        final mark = dayMark(doc, id);
        if (mark == SquareState.none) continue;
        (out[id] ??= <String, SquareState>{})[dateKey] = mark;
      }
    } catch (_) {
      // Skip the day, keep the account.
    }
  });
  return out;
}

/// Every habit's done-day set, account-wide.
///
/// Signed in: runs the one-time backfill if this account has never had one
/// (folds every existing daily doc into the mirror docs, then stamps
/// `habitHistoryBackfilledAt` on the user doc so it never repeats), then
/// reads the mirror collection — a handful of docs however long the
/// history. Guest: aggregates the local Hive daily box directly; it is
/// in-memory, so there is no read cost to mirror away and no mirror to
/// drift.
/// One backfill at a time per app session. The provider is autoDispose
/// and re-executes on auth re-emissions or screen reopen; Riverpod does
/// not cancel the in-flight future, and two concurrent backfills would
/// interleave their batches with each other and with the live writers.
Future<void>? _backfillInFlight;

final habitYearHistoryProvider =
    FutureProvider.autoDispose<Map<String, Map<String, SquareState>>>(
        (ref) async {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  if (uid == null) {
    return aggregateHabitHistory(await LocalStoreService.allDailyMaps());
  }

  final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
  final historyCol = userRef.collection('habit_history');

  final userSnap = await userRef.get();
  // ── Why there are three stamps ────────────────────────────────────────
  // Each one is a generation of this mirror, and the gate always reads the
  // NEWEST, so adding a generation is how a fix reaches accounts that were
  // already stamped by an older one.
  //
  //  habitHistoryBackfilledAt        presence only, green days
  //  habitHistoryMarksBackfilledAt   the six-state marks
  //  habitHistoryMarksV2BackfilledAt this one
  //
  // V2 exists because the marks generation could still miss history. The
  // mirror only gained non-green squares once the Grid's own writer started
  // recording them, so any تخطّي, فشل or جزئي painted before that moment was
  // DELETED from the mirror by the old writer rather than stored, and a
  // person opening their reports saw a blank square on a day they had
  // explicitly marked. The daily documents still hold the truth, so one more
  // pass over them recovers every one of those days.
  //
  // The pass is idempotent and merge-only, so an account that has nothing to
  // recover simply rewrites what it already had.
  if (userSnap.data()?['habitHistoryMarksV2BackfilledAt'] == null) {
    // Wait out any run already in flight, then re-check the stamp: the
    // earlier run may have finished the job while we waited.
    final inFlight = _backfillInFlight;
    if (inFlight != null) {
      // Its failure is its own: this caller re-checks the stamp below and
      // will simply run the backfill itself if the other one did not finish.
      await inFlight.catchError((_) {});
    }
    final fresh = await userRef.get();
    if (fresh.data()?['habitHistoryMarksV2BackfilledAt'] != null) {
      return _readMirror(historyCol);
    }
    // ── One-time backfill ────────────────────────────────────────────
    // Reads the full daily history once (~2 months ≈ 70 docs for the
    // oldest current accounts) and writes one mirror doc per habit.
    // Chunked well under the 500-op batch ceiling. The stamp is written
    // in the LAST batch, so a failure mid-way retries the whole thing
    // next open rather than half-backfilling forever.
    Future<void> run() async {
      final dailySnap = await userRef.collection('daily').get();
      // TODAY is excluded from the backfill on purpose: the live writers
      // own the current day, and a backfill whose aggregate was read
      // seconds ago would otherwise resurrect a completion the user
      // un-did while it was running. Yesterday and older are settled.
      //
      // effectiveDay, NOT DateTime.now(). Every writer that owns "today"
      // keys it by the app's 6am-cutoff day: DashboardNotifier._todayKey is
      // `DateTime.now().effectiveDay.toDateKey()`, and setSquare's
      // anti-backdating guard is `day.isToday`, which is cutoff-aware too.
      // This guard alone used the real calendar day, so between midnight and
      // 06:00 the two disagreed by one: the backfill excluded the calendar
      // day nobody was writing to and happily rebuilt the EFFECTIVE day the
      // live writers owned, which is precisely the resurrection this comment
      // says it exists to prevent.
      final todayKey = DateTime.now().effectiveDay.toDateKey();
      final aggregated = aggregateHabitHistory({
        for (final d in dailySnap.docs)
          if (d.id != todayKey) d.id: d.data(),
      });
      var batch = FirebaseFirestore.instance.batch();
      var ops = 0;
      for (final entry in aggregated.entries) {
        batch.set(
          historyCol.doc(entry.key),
          {
            'days': {
              for (final day in entry.value.entries)
                day.key: markToStored(day.value),
            },
          },
          SetOptions(merge: true),
        );
        if (++ops >= 400) {
          await batch.commit();
          batch = FirebaseFirestore.instance.batch();
          ops = 0;
        }
      }
      // The stamp rides the LAST batch: a failure anywhere above leaves
      // the account unstamped and the whole backfill retries next open.
      batch.set(
        userRef,
        {
          'habitHistoryBackfilledAt': FieldValue.serverTimestamp(),
          'habitHistoryMarksBackfilledAt': FieldValue.serverTimestamp(),
          'habitHistoryMarksV2BackfilledAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await batch.commit();
      // One line, once per account, so that running this against a real
      // second account produces evidence instead of silence.
      debugPrint(
        '[habitHistory] marks backfill wrote ${aggregated.length} habits, '
        '${aggregated.values.fold<int>(0, (n, m) => n + m.length)} day marks '
        'from ${dailySnap.docs.length} daily docs',
      );
    }

    final running = run();
    _backfillInFlight = running;
    try {
      await running;
    } catch (e) {
      // NON-FATAL, deliberately. This runs once per existing account on the
      // first open after the update, and letting it throw would turn a
      // migration hiccup (one bad document, a dropped connection mid-batch)
      // into a permanently broken reports screen for that account.
      //
      // Falling through to the mirror instead means the worst case is the
      // data they already had: every legacy green day still reads correctly
      // through markFromStored, and only the newly-recoverable rest and fail
      // days are missing. The stamp is written in the last batch, so an
      // unstamped account simply tries again next open.
      debugPrint('[habitHistory] marks backfill deferred: $e');
    } finally {
      _backfillInFlight = null;
    }
  }

  return _readMirror(historyCol);
});

/// Reads the mirror collection into per-habit day marks.
///
/// Every value goes through [markFromStored], which is what keeps a legacy
/// `1` reading as complete instead of parsing to none and wiping an
/// account's entire recorded history off its own report.
Future<Map<String, Map<String, SquareState>>> _readMirror(
  CollectionReference<Map<String, dynamic>> historyCol,
) async {
  final snap = await historyCol.get();
  return {
    for (final d in snap.docs)
      d.id: {
        for (final entry in
            ((d.data()['days'] as Map?) ?? const {}).entries)
          entry.key.toString(): markFromStored(entry.value),
      },
  };
}
