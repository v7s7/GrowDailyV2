// Runs the real RoomsController against a fake Firestore, for one member of
// one room, at a chosen moment.
//
// Not a test file itself. Everything the grader reads is supplied here: the
// participant document, the member's daily documents, and the habit lists it
// resolves links against. The controller's injected clock is what makes a
// scenario deterministic, so each step of one runs at a fixed calendar moment
// whatever day the suite happens to run on.
//
// Several members of one room share one [FakeFirebaseFirestore] (pass the
// first harness's [db] to the next), each signed in as themselves, the way
// each member's own phone grades only their own document.
//
// Adapted from the 2026-09-11 back-painting harness. Squares are written the
// way WeeklyGridNotifier._persistSquare stores them (squareStates keyed by
// habit id), with `lastUpdated` set to the moment the store would have
// stamped, because that stamp is what the grader reads
// (roomDayMarkedWhileOpen).
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/character/notifiers/character_notifier.dart';
import 'package:grow_daily_v2/features/character/notifiers/prestige_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';
import 'package:hive/hive.dart';

/// The participant write's profile fields read the guest dashboard,
/// character and prestige notifiers, which keep their state in Hive. Once per
/// test file, from setUpAll.
void initHarnessHive() {
  Hive.init(Directory.systemTemp.createTempSync('room_sync_harness_').path);
}

class _Member implements User {
  _Member(this.uid);

  @override
  final String uid;

  @override
  String? get email => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The fake Firestore with update() doing what Firestore does.
///
/// FakeFirebaseFirestore merges a map handed to update() into the stored
/// map, key by key. Firestore replaces the named field whole, and
/// syncLinkedHabitsProgress depends on that: its update() is the only way a
/// key leaves a sparse map (see the "update(), NOT set(merge: true)" note at
/// that call). Without this a day's stale scheduled count survives every
/// resync here, and a scenario reads numbers no phone could have stored.
class _ReplacingFirestore implements FirebaseFirestore {
  _ReplacingFirestore(this._fake);
  final FakeFirebaseFirestore _fake;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(_fake.collection(path));

  /// The plan edits (removeSharedHabit / restoreSharedHabit) read and write
  /// the room document in one transaction. The fake supports transactions,
  /// but only over its OWN references, so every reference the handler passes
  /// back is unwrapped first.
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) =>
      _fake.runTransaction<T>(
        (txn) => handler(_Txn(txn)),
        timeout: timeout,
        maxAttempts: maxAttempts,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Txn implements Transaction {
  _Txn(this._inner);
  final Transaction _inner;

  // Through Object, so the check promotes: _Doc implements the Map-typed
  // reference, and a generic DocumentReference<T> never promotes to it.
  DocumentReference<T> _raw<T extends Object?>(DocumentReference<T> ref) {
    final Object candidate = ref;
    if (candidate is _Doc) return candidate._inner as DocumentReference<T>;
    return ref;
  }

  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
          DocumentReference<T> documentReference) =>
      _inner.get(_raw(documentReference));

  @override
  Transaction set<T extends Object?>(
    DocumentReference<T> documentReference,
    T data, [
    SetOptions? options,
  ]) =>
      _inner.set(_raw(documentReference), data, options);

  @override
  Transaction update(
    DocumentReference<Object?> documentReference,
    Map<String, Object?> data,
  ) =>
      _inner.update(_raw(documentReference), data);

  @override
  Transaction delete(DocumentReference<Object?> documentReference) =>
      _inner.delete(_raw(documentReference));
}

// The @sealed hints are about subclassing the plugin's references in app
// code; this only forwards to the fake's own, in a test.
// ignore: subtype_of_sealed_class
class _Collection implements CollectionReference<Map<String, dynamic>> {
  _Collection(this._inner);
  final CollectionReference<Map<String, dynamic>> _inner;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _Doc(_inner.doc(path));

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) =>
      _inner.get(options);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _Doc implements DocumentReference<Map<String, dynamic>> {
  _Doc(this._inner);
  final DocumentReference<Map<String, dynamic>> _inner;

  @override
  String get id => _inner.id;

  @override
  String get path => _inner.path;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(_inner.collection(path));

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) =>
      _inner.get(options);

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) =>
      _inner.set(data, options);

  @override
  Future<void> update(Map<Object, Object?> data) async {
    final current = (await _inner.get()).data();
    // Not found: let the fake raise it, as Firestore would.
    if (current == null) return _inner.update(data);
    await _inner.set({
      ...current,
      for (final e in data.entries) e.key as String: e.value,
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class RoomSyncHarness {
  RoomSyncHarness({
    required this.room,
    required List<IslamicHabitTemplate> habits,
    this.uid = 'member',
    FakeFirebaseFirestore? db,
    /// Habits the member has PAUSED: resolvable, so the grader can tell a
    /// stood-down day from a deleted link, but not active.
    List<IslamicHabitTemplate> paused = const [],
    /// The windows each habit was really active for (habitStintsProvider),
    /// for a habit paused and resumed in the past. None by default.
    Map<String, List<(DateTime?, DateTime?)>> stints = const {},
  }) : db = db ?? FakeFirebaseFirestore() {
    container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(_Member(uid))),
        dashboardProvider.overrideWith((ref) => DashboardNotifier(null)),
        characterProvider.overrideWith((ref) => CharacterNotifier(ref, null)),
        prestigeProvider.overrideWith((ref) => PrestigeNotifier(null)),
        habitListProvider.overrideWithValue(habits),
        pausedHabitsProvider.overrideWithValue(paused),
        habitStintsProvider.overrideWithValue(stints),
        habitsStillLoadingProvider.overrideWithValue(false),
        roomsControllerProvider.overrideWith(
          (ref) => RoomsController(
            ref,
            firestore: _ReplacingFirestore(this.db),
            clock: () => _now,
          ),
        ),
      ],
    );
  }

  /// The room as this member's phone last saw it. A plan edit is only graded
  /// once the phone has the edited room, so a scenario swaps it in with
  /// [seeRoom] exactly when a real phone's room stream would deliver it.
  RoomModel room;
  final String uid;
  final FakeFirebaseFirestore db;
  late final ProviderContainer container;
  DateTime _now = DateTime(2000);

  RoomsController get controller => container.read(roomsControllerProvider);

  DocumentReference<Map<String, dynamic>> get roomDoc =>
      db.collection('rooms').doc(room.code);

  DocumentReference<Map<String, dynamic>> get memberDoc =>
      roomDoc.collection('participants').doc(uid);

  DocumentReference<Map<String, dynamic>> dayDoc(String dateKey) =>
      db.collection('users').doc(uid).collection('daily').doc(dateKey);

  /// Writes the room document itself, as its leader created it.
  Future<void> createRoom() => roomDoc.set(room.toFirestore());

  /// Re-reads the room document, the way this member's room stream would
  /// deliver a leader's edit.
  Future<RoomModel> seeRoom() async {
    room = RoomModel.fromFirestore(await roomDoc.get());
    return room;
  }

  Future<void> join(RoomParticipant member) async {
    await container.read(authStateProvider.future);
    await memberDoc.set(member.toFirestore());
  }

  /// A square set while its day was still open (a Grid tap, a Today
  /// completion), stored at [storedAt].
  Future<void> mark(
    String dateKey,
    String habitId,
    SquareState value,
    DateTime storedAt,
  ) =>
      dayDoc(dateKey).set(
        {
          'squareStates': {habitId: value.toJson()},
          'lastUpdated': Timestamp.fromDate(storedAt),
        },
        SetOptions(merge: true),
      );

  /// Moves this member's clock without grading anything.
  void setClock(DateTime at) => _now = at;

  /// One full resync, graded at [at].
  Future<void> syncAt(DateTime at) async {
    _now = at;
    await container.read(authStateProvider.future);
    await controller.syncLinkedHabitsProgress(room);
  }

  Future<RoomParticipant> member() async =>
      RoomParticipant.fromFirestore(await memberDoc.get());

  void dispose() => container.dispose();
}
