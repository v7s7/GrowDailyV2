import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/local_store_service.dart';
import '../../auth/notifiers/auth_notifier.dart';

/// A day-level index of "which days carry writing", at `users/{uid}/meta/notes`:
///
/// ```json
/// { "months": { "2026-09": [4, 8, 14], "2026-08": [2, 19] } }
/// ```
///
/// It exists because the fact it holds is otherwise unanswerable. A note
/// lives only as a map key inside a day document
/// (`daily/{dateKey}.squareNotes[habitId]`), Firestore cannot filter on
/// map-key presence, and the one lifetime aggregate the app already keeps
/// (`habit_history/{habitId}.days`) stores a bare SquareState written by a
/// path notes never travel. So "which days did I write on" costs one
/// document read per day of range, roughly 365 a year, and the monthly
/// heatmap builds every month section eagerly. One document answers it
/// instead.
///
/// THE INDEX MAY ONLY ROUTE, NEVER ASSERT. It decides which heatmap cells
/// get a corner mark and which month chips get a dot. It never renders note
/// text, never claims in a list that a note exists, and never gates reading.
/// That single rule is what makes both failure directions survivable: a
/// false positive sends the user to a day sheet that honestly shows nothing
/// and heals itself in the same breath, and a false negative costs a
/// decoration on a control that is still tappable. Words on screen always
/// come from the day document.
///
/// It stays honest three ways: it is written in the same [WriteBatch] as the
/// note itself, so it cannot diverge from a save that succeeded; it is
/// backfilled once per account; and every read of ground truth (a journal
/// month, a day sheet) reconciles what it just saw. See [diffNoteDays].
const String kNoteIndexCollection = 'meta';
const String kNoteIndexDoc = 'notes';

/// The month key ('YYYY-MM') a 'YYYY-MM-DD' dateKey belongs to.
String monthKeyOf(String dateKey) => dateKey.substring(0, 7);

/// The first day of the month a 'YYYY-MM' key names, or null if it is not one.
///
/// The index is the only place that knows which months hold writing, so this
/// is what turns it into something the pickers and the all-months search can
/// navigate by.
DateTime? monthFromKey(String monthKey) {
  if (monthKey.length != 7) return null;
  final year = int.tryParse(monthKey.substring(0, 4));
  final month = int.tryParse(monthKey.substring(5, 7));
  if (year == null || month == null || month < 1 || month > 12) return null;
  return DateTime(year, month);
}

/// Whether a stored `squareNotes` row still carries real writing.
///
/// Every consumer must test the VALUE, not key presence. Clearing a note
/// used to write `''` rather than deleting the key (fixed in
/// [WeeklyGridNotifier._persistNote], but old tombstones stay forever), so
/// a row can name a dozen habits and hold nothing.
bool notesRowHasWriting(Map<String, dynamic>? row) =>
    row != null &&
    row.values.any((v) => v is String && v.trim().isNotEmpty);

/// Does [dayNotes] still carry writing once [habitId] is set to [text]?
///
/// Pure, so the batch that writes the index is unit-testable with no
/// Firestore involved. Exact rather than heuristic: the cell editor is
/// reachable only from the Grid, and `WeeklyGridState.notes[dateKey]` holds
/// every habit's note for that day, so clearing one of two notes correctly
/// leaves the day in the index.
bool dayStillHasWriting(
  Map<String, String> dayNotes,
  String habitId,
  String text,
) {
  if (text.trim().isNotEmpty) return true;
  return dayNotes.entries.any(
    (e) => e.key != habitId && e.value.trim().isNotEmpty,
  );
}

/// Folds raw day documents (dateKey to document) into the index shape.
///
/// Used by the backfill, by the guest path (where `allDailyMaps()` is free)
/// and by the tests that pin the two against each other.
Map<String, Set<int>> noteMonthIndexFrom(
  Map<String, Map<String, dynamic>> days,
) {
  final months = <String, Set<int>>{};
  for (final entry in days.entries) {
    final dateKey = entry.key;
    if (dateKey.length < 10) continue;
    final row = (entry.value['squareNotes'] as Map?)?.cast<String, dynamic>();
    if (!notesRowHasWriting(row)) continue;
    final day = int.tryParse(dateKey.substring(8, 10));
    if (day == null) continue;
    (months[monthKeyOf(dateKey)] ??= <int>{}).add(day);
  }
  return months;
}

/// Reads the stored index document into the in-memory shape.
Map<String, Set<int>> parseNoteIndex(Map<String, dynamic>? doc) {
  final raw = (doc?['months'] as Map?)?.cast<String, dynamic>() ?? const {};
  final out = <String, Set<int>>{};
  for (final e in raw.entries) {
    final days = (e.value as List?)
            ?.map((d) => d is int ? d : int.tryParse('$d'))
            .whereType<int>()
            .toSet() ??
        <int>{};
    if (days.isNotEmpty) out[e.key] = days;
  }
  return out;
}

/// What a reconciliation should write for one month, having seen the truth.
///
/// Deliberately a diff and not a wholesale `set` on `months.{key}`: a `set`
/// would clobber a concurrent arrayUnion from a second device. Empty on
/// agreement, so a healer riding an existing read writes nothing in the
/// common case.
class NoteIndexDiff {
  final List<int> add;
  final List<int> remove;
  const NoteIndexDiff({required this.add, required this.remove});

  bool get isEmpty => add.isEmpty && remove.isEmpty;
}

/// [truth] is what a full read of the month actually found.
///
/// [trustRemovals] must be false whenever the read could have come from the
/// offline cache. Nothing in this app configures Firestore `Settings`, so
/// persistence is on and an offline month resolves happily with every
/// document missing. Reconciling deletes on that would erase a year of true
/// entries, which is the one bug in this file that destroys data.
NoteIndexDiff diffNoteDays({
  required Set<int> indexed,
  required Set<int> truth,
  required bool trustRemovals,
}) =>
    NoteIndexDiff(
      add: truth.difference(indexed).toList()..sort(),
      remove:
          trustRemovals ? (indexed.difference(truth).toList()..sort()) : const [],
    );

DocumentReference<Map<String, dynamic>> noteIndexRef(String uid) =>
    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection(kNoteIndexCollection)
        .doc(kNoteIndexDoc);

/// Applies a reconciliation for one month. Fire and forget by design: the
/// caller is a screen load, and a failed heal simply leaves the index as it
/// was for the next visit to fix.
void healNoteIndexMonth({
  required String? uid,
  required String monthKey,
  required NoteIndexDiff diff,
}) {
  if (uid == null || diff.isEmpty) return;
  final ref = noteIndexRef(uid);
  void write(FieldValue transform) => ref.set(
        {
          'months': {monthKey: transform},
        },
        SetOptions(merge: true),
      ).ignore();
  // Two field transforms cannot target the same field in one write, so a
  // month needing both directions is split into two.
  if (diff.add.isNotEmpty) write(FieldValue.arrayUnion(diff.add));
  if (diff.remove.isNotEmpty) write(FieldValue.arrayRemove(diff.remove));
}

/// The index, read once per screen that needs it.
///
/// Deliberately a one-shot read and not a `snapshots()` listener: this app
/// has zero listeners on day data by design, and cross-device freshness
/// here is worth exactly one document read per screen open.
final noteIndexProvider =
    FutureProvider.autoDispose<Map<String, Set<int>>>((ref) async {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  if (uid == null) {
    // The guest box is in memory, so the guest never needs the index doc at
    // all: the fold over every stored day is free and always exact.
    return noteMonthIndexFrom(await LocalStoreService.allDailyMaps());
  }
  try {
    final snap = await noteIndexRef(uid).get();
    return parseNoteIndex(snap.data());
  } catch (_) {
    // An unreadable index is a missing decoration, never a broken screen.
    return const {};
  }
});
