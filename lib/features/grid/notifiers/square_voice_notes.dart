import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/services/local_store_service.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../../matrix/models/matrix_task.dart' show VoiceNote;

/// Voice notes on one habit's day, a Grid square (Premium; Aziz,
/// 2026-09-25: "do 3"). The recorder, the player, the 30-second cap and the
/// Premium gate are the task notes' own (VoiceNoteService,
/// VoiceNoteRecordRow, VoiceNoteRow, showVoiceNoteGate). What is new is
/// only where a square's recordings live.
///
/// NOT in the day's `daily` document beside the written note. That document
/// holds every habit of the day and is read by the week load, the journal's
/// month query, the heatmap, Rooms' sync and two whole-collection passes,
/// while one square's recordings may carry up to
/// VoiceNoteService.maxSyncedBytesPerTask of audio: two busy squares would
/// take a day past Firestore's 1 MiB document limit, and every one of those
/// readers would pay for audio it never plays. So:
///
///  * `users/{uid}/square_voice/{key}` (see [squareVoiceKey]): one document
///    per square that has recordings, `{dateKey, habitId, notes: [...]}`,
///    read only when that square's editor opens.
///  * `users/{uid}/meta/square_voice`: `{counts: {key: n}}`, ONE document
///    that tells the Grid which squares carry recordings (the folded corner)
///    without opening any of them.
///  * A guest keeps both in Hive, under [kGuestSquareVoiceKey]. The
///    recordings stay files on this phone with no base64 copy, since a guest
///    has no second device to carry them to (the task notes' own rule).
///    Known limit: a guest's recordings are not carried into an account
///    made later; they stay on the phone under the guest key.
///
/// Both collections sit one level under `users/{uid}`, which the owner-only
/// wildcard in firestore.rules already covers: no rules change, nothing to
/// deploy. Account deletion lists both (auth_notifier.dart's
/// _deleteAllUserData), because recordings of someone's voice are the last
/// thing a deleted account should leave behind.
const String kSquareVoiceCollection = 'square_voice';
const String kSquareVoiceIndexDoc = 'square_voice';
const String kGuestSquareVoiceKey = 'guest_square_voice_v1';

/// The id one square's recordings are filed under: its day, then its habit.
/// The day is always the 10 characters of 'YYYY-MM-DD', so the habit id can
/// hold underscores of its own and still come back out whole.
String squareVoiceKey(String habitId, DateTime day) =>
    '${day.toDateKey()}_$habitId';

/// The day and habit of a [squareVoiceKey], or null for anything else.
({DateTime day, String habitId})? parseSquareVoiceKey(String key) {
  if (key.length < 12 || key[10] != '_') return null;
  final day = DateTime.tryParse(key.substring(0, 10));
  if (day == null) return null;
  return (day: DateTime(day.year, day.month, day.day), habitId: key.substring(11));
}

/// The index document's `{key: count}`, without zero or malformed rows.
Map<String, int> parseSquareVoiceCounts(Map<String, dynamic>? data) {
  final raw = data?['counts'];
  if (raw is! Map) return const {};
  return {
    for (final e in raw.entries)
      if (e.value is num && (e.value as num) > 0)
        e.key.toString(): (e.value as num).toInt(),
  };
}

/// A square document's recordings, oldest first as they were saved.
List<VoiceNote> parseSquareVoiceNotes(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final m in raw)
      if (m is Map) VoiceNote.fromMap(m.cast<String, dynamic>()),
  ];
}

/// Reads and writes a square's recordings, for a signed-in account or a
/// guest ([uid] null). The Firestore instance is injectable for tests.
class SquareVoiceStore {
  SquareVoiceStore({FirebaseFirestore? firestore}) : _firestore = firestore;

  final FirebaseFirestore? _firestore;
  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      _db.collection('users').doc(uid);

  DocumentReference<Map<String, dynamic>> notesRef(String uid, String key) =>
      _userRef(uid).collection(kSquareVoiceCollection).doc(key);

  DocumentReference<Map<String, dynamic>> indexRef(String uid) =>
      _userRef(uid).collection('meta').doc(kSquareVoiceIndexDoc);

  Future<Map<String, List<VoiceNote>>> _guestAll() async {
    final box = await LocalStoreService.settingsBox();
    final raw = box.get(kGuestSquareVoiceKey);
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries) e.key.toString(): parseSquareVoiceNotes(e.value),
    };
  }

  /// Which squares carry recordings, and how many each.
  Future<Map<String, int>> loadCounts(String? uid) async {
    if (uid == null) {
      final all = await _guestAll();
      return {
        for (final e in all.entries)
          if (e.value.isNotEmpty) e.key: e.value.length,
      };
    }
    return parseSquareVoiceCounts((await indexRef(uid).get()).data());
  }

  /// One square's recordings.
  Future<List<VoiceNote>> load(String? uid, String key) async {
    if (uid == null) return (await _guestAll())[key] ?? const [];
    return parseSquareVoiceNotes((await notesRef(uid, key).get()).data()?['notes']);
  }

  /// Adds one recording WITHOUT reading the square's list first: an
  /// arrayUnion onto the square's document and an increment of its index
  /// row, in one batch.
  ///
  /// Never a rewrite of the list, and that is the point. The editor only
  /// reads a square's recordings when the index says it has some, and the
  /// index can be missing (an offline first start, a failed load): a
  /// rewrite from an editor that saw "none" would replace every recording
  /// already saved with the one just made. Appending cannot lose anything.
  /// Renaming and deleting still rewrite ([save]), and they can, because
  /// they only ever act on a list that is on the screen.
  Future<void> add(String? uid, String key, VoiceNote note) async {
    if (uid == null) {
      // A guest's list is this phone's own, so reading it is always
      // possible and always complete.
      await save(uid, key, [...await load(uid, key), note]);
      return;
    }
    final parsed = parseSquareVoiceKey(key);
    final batch = _db.batch()
      ..set(
        notesRef(uid, key),
        {
          'dateKey': parsed?.day.toDateKey() ?? key.substring(0, 10),
          'habitId': parsed?.habitId ?? '',
          'notes': FieldValue.arrayUnion([note.toMap()]),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      )
      ..set(
        indexRef(uid),
        {
          'counts': {key: FieldValue.increment(1)},
        },
        SetOptions(merge: true),
      );
    await batch.commit();
  }

  /// Makes [notes] the square's whole list, and its count in the index, in
  /// one batch, so the corner on the Grid can never claim recordings the
  /// square does not have, or miss ones it does. An empty list deletes the
  /// square's document and its index row. For a list that is on screen
  /// (renaming, deleting); a new recording goes through [add].
  ///
  /// Not awaited by the editor for the same reason the written note's save
  /// is not: with offline persistence on, a commit neither resolves nor
  /// rejects while the phone is offline. The caller uses the future only to
  /// report a real failure.
  Future<void> save(String? uid, String key, List<VoiceNote> notes) async {
    if (uid == null) {
      final box = await LocalStoreService.settingsBox();
      final raw = box.get(kGuestSquareVoiceKey);
      final all = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};
      if (notes.isEmpty) {
        all.remove(key);
      } else {
        all[key] = [
          for (final n in notes) Map<String, dynamic>.from(n.toMap())..remove('audioBase64'),
        ];
      }
      await box.put(kGuestSquareVoiceKey, all);
      return;
    }
    final parsed = parseSquareVoiceKey(key);
    final batch = _db.batch();
    if (notes.isEmpty) {
      batch.delete(notesRef(uid, key));
    } else {
      batch.set(notesRef(uid, key), {
        'dateKey': parsed?.day.toDateKey() ?? key.substring(0, 10),
        'habitId': parsed?.habitId ?? '',
        'notes': [for (final n in notes) n.toMap()],
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    batch.set(
      indexRef(uid),
      {
        'counts': {key: notes.isEmpty ? FieldValue.delete() : notes.length},
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }
}

final squareVoiceStoreProvider =
    Provider<SquareVoiceStore>((ref) => SquareVoiceStore());

/// Which squares carry recordings, `{squareVoiceKey: count}`: the folded
/// corner on the Grid, and whether the square's editor needs to read its
/// recordings at all. Loaded once per account (one document read), then
/// kept current by [setCount] as the editor records and deletes.
class SquareVoiceIndexNotifier extends StateNotifier<Map<String, int>> {
  SquareVoiceIndexNotifier(this._store, this._uid) : super(const {}) {
    _load();
  }

  final SquareVoiceStore _store;
  final String? _uid;

  /// Whether the index has been read. Until it has, "no recordings here"
  /// is not known, only unasked, and the editor reads the square itself.
  bool get loaded => _loaded;
  bool _loaded = false;

  /// Counts made exact on this device (a rename or a delete rewrote the
  /// square's list) before the load came back: newer than the load, so they
  /// win over it.
  final Map<String, int> _exact = {};

  /// Counts after recordings added on this device before the load came
  /// back. An add is an increment on the server, so the load may already
  /// include it: the larger of the two is kept, never the sum.
  final Map<String, int> _added = {};

  Future<void> _load() async {
    Map<String, int> loaded;
    try {
      loaded = await _store.loadCounts(_uid);
    } catch (_) {
      // Offline first run, or Firebase not set up (widget tests): no
      // corners until the next load, and nothing recorded is lost, since
      // the recordings live in their own documents.
      return;
    }
    if (!mounted) return;
    final merged = {...loaded};
    _added.forEach((key, n) {
      final was = merged[key] ?? 0;
      merged[key] = n > was ? n : was;
    });
    _exact.forEach((key, n) => n > 0 ? merged[key] = n : merged.remove(key));
    _loaded = true;
    state = merged;
  }

  /// Whether [habitId]'s square on [day] carries a recording.
  bool has(String habitId, DateTime day) =>
      (state[squareVoiceKey(habitId, day)] ?? 0) > 0;

  /// A recording was added to [key]'s square (SquareVoiceStore.add).
  void added(String key) {
    final count = (state[key] ?? 0) + 1;
    _added[key] = count;
    _exact.remove(key);
    state = {...state, key: count};
  }

  /// [key]'s square now holds exactly [count] (SquareVoiceStore.save).
  void setCount(String key, int count) {
    _exact[key] = count;
    _added.remove(key);
    final next = {...state};
    if (count > 0) {
      next[key] = count;
    } else {
      next.remove(key);
    }
    state = next;
  }
}

final squareVoiceIndexProvider =
    StateNotifierProvider<SquareVoiceIndexNotifier, Map<String, int>>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  return SquareVoiceIndexNotifier(ref.watch(squareVoiceStoreProvider), uid);
});
