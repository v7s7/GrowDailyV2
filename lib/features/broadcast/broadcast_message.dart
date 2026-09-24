/// A message from the admin to everyone, shown once as a pop-up the next
/// time the app is opened.
///
/// ── Why this exists ─────────────────────────────────────────────────────
/// Aziz, 2026-09-22: "let me as an admin send a message to all users, I
/// choose if it's a pop up when they open the app, or a notification". The
/// notification half needs nothing from the app: the admin tool sends it
/// through FCM to the device tokens PushNotificationService already
/// registers. This is the pop-up half, which only the app itself can show.
///
/// ── Where it lives ──────────────────────────────────────────────────────
/// One Firestore document, [kBroadcastDocPath], written only by the admin
/// tool's Messages page (scripts/admin_lookup/lib/broadcast.js) through the
/// Admin SDK. Anyone may read it, guests included; nobody may write it from
/// a client (firestore.rules). Two slots:
///
///   everyone  {id, titleAr, bodyAr, titleEn, bodyEn, buttonAr, buttonEn,
///              startsAt, endsAt}
///   test      the same, plus testUidHashes: the SHA-256 of each test
///             account's uid, so the public document never carries a uid
///
/// A test never replaces what everyone is shown, which is the whole reason
/// for the second slot.
///
/// ── Once, and only when the app opens ─────────────────────────────────
/// Each pop-up has its own id and this device remembers the ids it showed
/// ([BroadcastStore.seen]), so a pop-up appears once per device however
/// many times the app opens while it is up. "When the app opens" is a cold
/// start or a return from the background, never the middle of a session:
/// see BroadcastAnnouncer (broadcast_announcer.dart) for how that is judged.
library;

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';

import '../../core/services/local_store_service.dart';

/// The one document the admin tool writes and every device reads.
const String kBroadcastDocPath = 'broadcast/live';

/// SHA-256 of [uid], lowercase hex: how the public document names a test
/// account without naming it. scripts/admin_lookup/lib/broadcast.js's
/// uidHash computes the same, and both sides' tests pin the same vector.
String broadcastUidHash(String uid) =>
    sha256.convert(utf8.encode(uid)).toString();

/// One pop-up as stored. Immutable: a change is a new instance.
@immutable
class BroadcastPopup {
  const BroadcastPopup({
    required this.id,
    required this.titleAr,
    required this.bodyAr,
    this.titleEn = '',
    this.bodyEn = '',
    this.buttonAr = '',
    this.buttonEn = '',
    this.startsAt,
    this.endsAt,
    this.testUidHashes = const {},
  });

  final String id;
  final String titleAr;
  final String bodyAr;
  final String titleEn;
  final String bodyEn;
  final String buttonAr;
  final String buttonEn;

  /// Null means "from whenever it was written" and "no end". The admin tool
  /// always writes both; the nulls only keep a hand-made document readable.
  final DateTime? startsAt;
  final DateTime? endsAt;

  /// Empty for everyone. Otherwise only these accounts see it.
  final Set<String> testUidHashes;

  bool get isTest => testUidHashes.isNotEmpty;

  bool _english(bool isAr) => !isAr && titleEn.isNotEmpty && bodyEn.isNotEmpty;

  /// Whether a reader in this language is shown the Arabic: an Arabic app,
  /// or an English one when the admin wrote no English. Decides the text
  /// direction as well as the words.
  bool showsArabic(bool isAr) => !_english(isAr);

  String title(bool isAr) => _english(isAr) ? titleEn : titleAr;

  String body(bool isAr) => _english(isAr) ? bodyEn : bodyAr;

  /// Null when the admin left it empty; the dialog then uses the platform's
  /// own OK.
  String? button(bool isAr) {
    final text = _english(isAr) ? buttonEn : buttonAr;
    return text.isEmpty ? null : text;
  }

  /// How far ahead of this phone's clock a start may be and still count as
  /// started. [startsAt] is the admin's Mac clock at the moment of sending;
  /// a phone running a few minutes slow would otherwise pass over a pop-up
  /// that arrived inside its open window, and not look again until the next
  /// open.
  static const Duration clockSkew = Duration(minutes: 10);

  bool isActiveAt(DateTime now) =>
      (startsAt == null || !now.isBefore(startsAt!.subtract(clockSkew))) &&
      (endsAt == null || now.isBefore(endsAt!));

  /// Everyone's pop-up is for everyone; a test is for the listed accounts
  /// only, so a guest (no uid) never sees one.
  bool isFor(String? uid) =>
      !isTest || (uid != null && testUidHashes.contains(broadcastUidHash(uid)));

  /// Null for anything that is not a usable pop-up: no id, or no Arabic
  /// title and body to show. Every field is read on its own, the rule every
  /// loader in this app follows since one malformed field once cost a whole
  /// read: a bad optional field costs that field, never the pop-up.
  static BroadcastPopup? fromData(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final titleAr = _text(raw['titleAr']);
    final bodyAr = _text(raw['bodyAr']);
    if (id is! String || id.isEmpty || titleAr.isEmpty || bodyAr.isEmpty) {
      return null;
    }
    final hashes = raw['testUidHashes'];
    return BroadcastPopup(
      id: id,
      titleAr: titleAr,
      bodyAr: bodyAr,
      titleEn: _text(raw['titleEn']),
      bodyEn: _text(raw['bodyEn']),
      buttonAr: _text(raw['buttonAr']),
      buttonEn: _text(raw['buttonEn']),
      startsAt: _date(raw['startsAt']),
      endsAt: _date(raw['endsAt']),
      testUidHashes: hashes is List
          ? Set.unmodifiable(hashes.whereType<String>())
          : const {},
    );
  }

  static String _text(Object? value) => value is String ? value.trim() : '';

  /// A Firestore Timestamp from the live document, epoch milliseconds from
  /// this device's own cached copy.
  static DateTime? _date(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    return null;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'titleAr': titleAr,
        'bodyAr': bodyAr,
        'titleEn': titleEn,
        'bodyEn': bodyEn,
        'buttonAr': buttonAr,
        'buttonEn': buttonEn,
        if (startsAt != null) 'startsAt': startsAt!.millisecondsSinceEpoch,
        if (endsAt != null) 'endsAt': endsAt!.millisecondsSinceEpoch,
        if (testUidHashes.isNotEmpty) 'testUidHashes': testUidHashes.toList(),
      };
}

/// The document's two slots at one moment.
@immutable
class BroadcastState {
  const BroadcastState({this.everyone, this.test, this.version = 0});

  static const empty = BroadcastState();

  final BroadcastPopup? everyone;
  final BroadcastPopup? test;
  final int version;

  bool get isEmpty => everyone == null && test == null;

  /// A slot that cannot be read is simply empty; the other slot is kept.
  /// A test slot that names no test account is empty too: read as it
  /// stands, it would be a pop-up for everyone, and checked first.
  factory BroadcastState.fromData(Object? data) {
    if (data is! Map) return empty;
    final version = data['version'];
    final test = BroadcastPopup.fromData(data['test']);
    return BroadcastState(
      everyone: BroadcastPopup.fromData(data['everyone']),
      test: test != null && test.isTest ? test : null,
      version: version is num ? version.toInt() : 0,
    );
  }

  Map<String, Object?> toJson() => {
        'everyone': everyone?.toJson(),
        'test': test?.toJson(),
        'version': version,
      };
}

/// The pop-up this reader should see now, if any: a test meant for them
/// first (the admin is looking at their own phone), then everyone's. One
/// that is not up at [now], not for [uid], or already in [seen] is passed
/// over. Pure, so the whole rule is pinned by unit tests.
BroadcastPopup? broadcastToShow(
  BroadcastState state, {
  required String? uid,
  required DateTime now,
  required Set<String> seen,
}) {
  for (final popup in [state.test, state.everyone]) {
    if (popup == null) continue;
    if (seen.contains(popup.id)) continue;
    if (!popup.isActiveAt(now)) continue;
    if (!popup.isFor(uid)) continue;
    return popup;
  }
  return null;
}

/// Where the pop-up document is read from in a debug build started with
/// `--dart-define=BROADCAST_EMULATOR=127.0.0.1:8080`: a local Firestore
/// emulator, through a second Firebase app, so ONLY this listener moves
/// there and every account read and write stays on the real project. The
/// same arrangement as wordingEmulatorFirestore (wording_edits.dart), and
/// how a pop-up can be tried on the simulator without putting one in front
/// of real phones. Null in every other build: a release compiles this away.
Future<FirebaseFirestore?> broadcastEmulatorFirestore() async {
  const target = String.fromEnvironment('BROADCAST_EMULATOR');
  if (!kDebugMode || target.isEmpty) return null;
  final hostAndPort = target.split(':');
  final app = await Firebase.initializeApp(
    name: 'broadcast-emulator',
    options: Firebase.app().options,
  );
  final db = FirebaseFirestore.instanceFor(app: app)
    ..useFirestoreEmulator(
      hostAndPort.first,
      int.parse(hostAndPort.length > 1 ? hostAndPort[1] : '8080'),
    );
  debugPrint('[broadcast] reading the pop-up from the emulator at $target');
  return db;
}

/// Holds the document in force, and which pop-ups this device has shown.
/// Same shape as AchievementOverridesStore: a copy in the settings box so
/// the first frame after a cold start already knows, then a live listener.
class BroadcastStore {
  BroadcastStore._();

  static const String cacheKey = 'broadcast_live_v1';
  static const String seenKey = 'broadcast_seen_v1';

  /// Ids remembered. A few a month at most are ever sent; forty is years.
  static const int seenLimit = 40;

  static final ValueNotifier<BroadcastState> live =
      ValueNotifier(BroadcastState.empty);

  static BroadcastState get current => live.value;

  /// Insertion-ordered, so the oldest id is the one dropped at the limit.
  static final Set<String> _seen = <String>{};

  static Set<String> get seen => Set.unmodifiable(_seen);

  static Box<dynamic>? _box;
  static FirebaseFirestore? _db;
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  static AppLifecycleListener? _resumeRetry;
  static String _currentJson = jsonEncode(BroadcastState.empty.toJson());

  /// Off in widget tests, where the settings box is never opened and
  /// awaiting Hive would hang the test (see the widget-test notes).
  @visibleForTesting
  static bool persistSeen = true;

  /// Stands in for [readFromServer] in widget tests, which have no
  /// Firestore to ask.
  @visibleForTesting
  static Future<BroadcastState?> Function()? debugServerRead;

  /// Seeds [live] and [seen] from this device's own copies, before the
  /// first frame.
  static Future<void> loadCached([Box<dynamic>? box]) async {
    try {
      final settings = box ?? await LocalStoreService.settingsBox();
      _box = settings;
      final raw = settings.get(cacheKey);
      if (raw is String) {
        _publish(BroadcastState.fromData(jsonDecode(raw)));
      }
      final ids = settings.get(seenKey);
      if (ids is List) {
        _seen
          ..clear()
          ..addAll(ids.whereType<String>());
      }
    } catch (e) {
      debugPrint('[broadcast] cached pop-up unreadable, starting empty: $e');
    }
  }

  /// Follows [kBroadcastDocPath] for as long as the app runs, re-attaching
  /// on foreground for the reason WordingEditsStore.listen gives (a stream
  /// that failed, say before the rule was deployed, never restarts itself).
  static void listen({
    FirebaseFirestore? firestore,
    Box<dynamic>? box,
    bool retryOnResume = true,
  }) {
    if (retryOnResume) {
      _resumeRetry ??= AppLifecycleListener(
        onResume: () => listen(firestore: firestore, box: box),
      );
    }
    if (_sub != null) return;
    final db = firestore ?? FirebaseFirestore.instance;
    _db = db;
    _sub = db.doc(kBroadcastDocPath).snapshots().listen(
      (snap) {
        // A cache miss says nothing about the server; wait for the answer.
        if (!snap.exists && snap.metadata.isFromCache) return;
        unawaited(
          _receive(
            snap.exists
                ? BroadcastState.fromData(snap.data())
                : BroadcastState.empty,
            box,
          ),
        );
      },
      onError: (Object e) {
        debugPrint('[broadcast] listener stopped, keeping the last copy: $e');
        _sub = null;
      },
    );
  }

  /// The document as the server has it at this moment, or null when that
  /// cannot be known in time: offline, slow, the rule not deployed yet, or
  /// [listen] never ran.
  ///
  /// Asked once, right before a pop-up goes up (BroadcastAnnouncer). The
  /// copy on this device can be out of date by the time the app opens: a
  /// pop-up that arrived while the app was open, then was stopped or
  /// replaced while the phone sat in a pocket, would otherwise show from
  /// that copy in the second or two before the listener reconnects. One
  /// read, and only when there is something to show.
  static Future<BroadcastState?> readFromServer({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final stand = debugServerRead;
    if (stand != null) return stand();
    final db = _db;
    if (db == null) return null;
    try {
      final snap = await db
          .doc(kBroadcastDocPath)
          .get(const GetOptions(source: Source.server))
          .timeout(timeout);
      final state = snap.exists
          ? BroadcastState.fromData(snap.data())
          : BroadcastState.empty;
      await _receive(state, null);
      return state;
    } catch (e) {
      debugPrint('[broadcast] could not confirm the pop-up with the '
          'server, not showing it yet: $e');
      return null;
    }
  }

  static Future<void> _receive(BroadcastState state, Box<dynamic>? box) async {
    if (!_publish(state)) return;
    try {
      final settings = box ?? _box ?? await LocalStoreService.settingsBox();
      if (state.isEmpty) {
        await settings.delete(cacheKey);
      } else {
        await settings.put(cacheKey, _currentJson);
      }
    } catch (e) {
      debugPrint('[broadcast] could not keep a copy of the pop-up: $e');
    }
  }

  static bool _publish(BroadcastState state) {
    final json = jsonEncode(state.toJson());
    if (json == _currentJson) return false;
    _currentJson = json;
    live.value = state;
    return true;
  }

  /// Remembers that [id] was shown on this device, for good. Called as the
  /// pop-up goes up, not when it is closed: an app killed with the pop-up
  /// on screen still showed it.
  static void markSeen(String id) {
    if (!_seen.add(id)) return;
    while (_seen.length > seenLimit) {
      _seen.remove(_seen.first);
    }
    if (!persistSeen) return;
    final ids = _seen.toList();
    unawaited(() async {
      try {
        final settings = _box ?? await LocalStoreService.settingsBox();
        await settings.put(seenKey, ids);
      } catch (e) {
        debugPrint('[broadcast] could not remember the pop-up as seen: $e');
      }
    }());
  }

  @visibleForTesting
  static void debugPublish(BroadcastState state) => _publish(state);

  @visibleForTesting
  static Future<void> reset() async {
    await _sub?.cancel();
    _sub = null;
    _resumeRetry?.dispose();
    _resumeRetry = null;
    _box = null;
    _db = null;
    _seen.clear();
    persistSeen = true;
    debugServerRead = null;
    _publish(BroadcastState.empty);
  }
}
