import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/local_store_service.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../../grid/models/square_state.dart';

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
/// ── What counts as done ────────────────────────────────────────────────
/// A day is done for a habit when its completion count that day is
/// positive OR its grid square is in a done state (complete/bonus).
/// [dayIsDone] is the single spelling of that rule: the backfill, the
/// guest path, and the tests all call it, so the strip can never disagree
/// with itself between data sources.
bool dayIsDone(Map<String, dynamic> dailyDoc, String habitId) {
  // 'habitCompletions' is the field daily docs actually store —
  // completeHabit, uncompleteHabit, and the guest saver all write that
  // name (the STATE field is called completions, the DOC field is not).
  // The first draft of this function read 'completions', which no daily
  // doc has ever contained, so the completion arm of the union was dead
  // against production data and only square-painted days backfilled;
  // caught by the adversarial review, fixed before any external account
  // was stamped.
  final completions =
      (dailyDoc['habitCompletions'] as Map?)?.cast<String, dynamic>();
  final count = completions?[habitId];
  if (count is num && count > 0) return true;
  final squares =
      (dailyDoc['squareStates'] as Map?)?.cast<String, dynamic>();
  final state = SquareState.fromJson(squares?[habitId]?.toString());
  return state == SquareState.complete || state == SquareState.bonus;
}

/// Folds raw daily docs (dateKey -> doc map) into per-habit day sets —
/// pure, so the backfill and the guest reader share one tested behavior.
Map<String, Set<String>> aggregateHabitHistory(
  Map<String, Map<String, dynamic>> dailyDocs,
) {
  final out = <String, Set<String>>{};
  dailyDocs.forEach((dateKey, doc) {
    final ids = <String>{
      ...((doc['habitCompletions'] as Map?)?.keys.map((k) => k.toString()) ??
          const Iterable<String>.empty()),
      ...((doc['squareStates'] as Map?)?.keys.map((k) => k.toString()) ??
          const Iterable<String>.empty()),
    };
    for (final id in ids) {
      if (dayIsDone(doc, id)) (out[id] ??= <String>{}).add(dateKey);
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
    FutureProvider.autoDispose<Map<String, Set<String>>>((ref) async {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  if (uid == null) {
    return aggregateHabitHistory(await LocalStoreService.allDailyMaps());
  }

  final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
  final historyCol = userRef.collection('habit_history');

  final userSnap = await userRef.get();
  if (userSnap.data()?['habitHistoryBackfilledAt'] == null) {
    // Wait out any run already in flight, then re-check the stamp: the
    // earlier run may have finished the job while we waited.
    final inFlight = _backfillInFlight;
    if (inFlight != null) {
      await inFlight;
    }
    final fresh = await userRef.get();
    if (fresh.data()?['habitHistoryBackfilledAt'] != null) {
      final snap = await historyCol.get();
      return {
        for (final d in snap.docs)
          d.id: ((d.data()['days'] as Map?)
                      ?.keys
                      .map((k) => k.toString()) ??
                  const Iterable<String>.empty())
              .toSet(),
      };
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
      final todayKey = LocalStoreService.dateKey(DateTime.now());
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
            'days': {for (final day in entry.value) day: 1},
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
        {'habitHistoryBackfilledAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
      await batch.commit();
    }

    final running = run();
    _backfillInFlight = running;
    try {
      await running;
    } finally {
      _backfillInFlight = null;
    }
  }

  final snap = await historyCol.get();
  return {
    for (final d in snap.docs)
      d.id: ((d.data()['days'] as Map?)?.keys.map((k) => k.toString()) ??
              const Iterable<String>.empty())
          .toSet(),
  };
});
