import 'package:flutter/foundation.dart';

import 'local_store_service.dart';

/// A local copy of everything [habitListProvider] needs to draw the board,
/// so the habits are on screen in the first frame instead of after a server
/// round trip.
///
/// ── Why this is not just "read Firestore's cache" ──────────────────────────
///
/// Firestore already holds this data on the device and would serve it to a
/// Source.cache read. The reason for keeping our own copy is not storage, it
/// is WHO IS ALLOWED TO BELIEVE IT. Painting rows early is harmless; deciding
/// anything from an early answer is not. An empty habit list is
/// indistinguishable from "this person has no habits", and the reminder sweep
/// acts on that: it reconciles the AlarmKit window and reaps the near bands
/// against the list it is handed, so a short list taken as final cancels real
/// alarms. That is why this mirror feeds [habitsHydratedProvider] (pixels)
/// and never [habitsStillLoadingProvider] (correctness). The sweep, the
/// queued widget and notification taps, auto-resume and room grading all keep
/// waiting for the server exactly as before.
///
/// ── What is stored ─────────────────────────────────────────────────────────
///
/// The five slices habitListProvider actually composes: the custom habits,
/// which presets are on, when each preset was activated (a habit's birth date
/// decides which days it owed), the per-preset overrides, and the manual
/// order. Not the archive or the stint histories: nothing that paints reads
/// them, and the surfaces that do already wait for the server.
///
/// Keyed per uid, so signing in as somebody else cannot show their board, and
/// written whole so a half-updated set of slices can never be stored.
class HabitMirror {
  HabitMirror._();

  /// Bumped when the shape below changes. An envelope written by an older
  /// build is ignored rather than migrated: it costs one ordinary launch to
  /// rebuild, and guessing at an old shape is how a wrong board gets drawn.
  static const int _schemaVersion = 1;

  static const String _prefix = 'habit_mirror_v1_';

  /// How many accounts' envelopes to keep. Shared devices and test accounts
  /// exist; unbounded growth in a settings box does not need to.
  static const int _keepEnvelopes = 3;

  static String _keyFor(String uid) => '$_prefix$uid';

  static HabitSnapshot? _snapshot;

  /// The envelope for the uid passed to [load], or null if there was none,
  /// it was written by another build, or it could not be parsed.
  ///
  /// Synchronous on purpose: the notifiers read this in their constructors,
  /// before their first build, which is the only moment early enough to put
  /// rows in the first frame.
  static HabitSnapshot? get snapshot => _snapshot;

  /// Reads this uid's envelope into memory. Call once, awaited, during
  /// start-up before the first frame; it is a single get on an already-open
  /// box. A null [uid] (guest) clears it: the guest path has its own Hive
  /// storage and must never see a signed-in board.
  static Future<void> load(String? uid) async {
    _snapshot = null;
    if (kIsWeb || uid == null) return;
    try {
      final raw = await LocalStoreService.getSettingsMap(_keyFor(uid));
      if (raw.isEmpty) return;
      if (raw['schemaVersion'] != _schemaVersion) return;
      // Belt and braces against a key collision or a copied box: the
      // envelope names its own owner and is refused if it is not this one.
      if (raw['uid'] != uid) return;
      _snapshot = HabitSnapshot._from(raw);
    } catch (_) {
      _snapshot = null;
    }
  }

  /// Replaces this uid's envelope. Callers must have checked that what they
  /// are handing over came from a real server answer, not a failed read: see
  /// the loadFailed flags on the three notifiers.
  static Future<void> save({
    required String uid,
    required List<Map<String, dynamic>> customHabits,
    required List<String> activeCatalogIds,
    required Map<String, String> activatedAt,
    required Map<String, dynamic> catalogOverrides,
    required Map<String, double> habitOrder,
  }) async {
    if (kIsWeb) return;
    try {
      await LocalStoreService.putSettingsMap(_keyFor(uid), {
        'schemaVersion': _schemaVersion,
        'uid': uid,
        'savedAt': DateTime.now().toIso8601String(),
        'customHabits': customHabits,
        'activeCatalogIds': activeCatalogIds,
        'activatedAt': activatedAt,
        'catalogOverrides': catalogOverrides,
        'habitOrder': habitOrder,
      });
      await _prune(keep: uid);
    } catch (_) {
      // A mirror that cannot be written is a slow launch, never a broken
      // one. The board still loads from the server as it always did.
    }
  }

  /// Forgets this uid's envelope. For account deletion: the habits should not
  /// outlive the account on the device.
  static Future<void> drop(String uid) async {
    if (kIsWeb) return;
    try {
      final box = await LocalStoreService.settingsBox();
      await box.delete(_keyFor(uid));
      if (_snapshot?.uid == uid) _snapshot = null;
    } catch (_) {}
  }

  static Future<void> _prune({required String keep}) async {
    try {
      final box = await LocalStoreService.settingsBox();
      final keys = box.keys
          .whereType<String>()
          .where((k) => k.startsWith(_prefix) && k != _keyFor(keep))
          .toList();
      if (keys.length < _keepEnvelopes) return;
      // Oldest first by the stamp each envelope carries; anything unreadable
      // or unstamped sorts oldest and goes first, which is the right way
      // round for a cache.
      String stamp(String k) {
        final v = box.get(k);
        return v is Map && v['savedAt'] is String ? v['savedAt'] as String : '';
      }

      keys.sort((a, b) => stamp(a).compareTo(stamp(b)));
      for (final k in keys.take(keys.length - (_keepEnvelopes - 1))) {
        await box.delete(k);
      }
    } catch (_) {}
  }
}

/// One account's mirrored board, already parsed.
class HabitSnapshot {
  const HabitSnapshot({
    required this.uid,
    required this.customHabits,
    required this.activeCatalogIds,
    required this.activatedAt,
    required this.catalogOverrides,
    required this.habitOrder,
  });

  final String uid;

  /// Raw habit maps in the same shape `IslamicHabitTemplate.toFirestore()`
  /// emits, which is already Hive-safe: that method writes ISO strings rather
  /// than Timestamps precisely because guests store the same maps locally.
  final List<Map<String, dynamic>> customHabits;
  final Set<String> activeCatalogIds;
  final Map<String, String> activatedAt;
  final Map<String, dynamic> catalogOverrides;
  final Map<String, double> habitOrder;

  static HabitSnapshot _from(Map<String, dynamic> raw) => HabitSnapshot(
        uid: raw['uid'] as String,
        customHabits: [
          for (final h in (raw['customHabits'] as List? ?? const []))
            if (h is Map) Map<String, dynamic>.from(h),
        ],
        activeCatalogIds: {
          for (final id in (raw['activeCatalogIds'] as List? ?? const []))
            if (id is String) id,
        },
        activatedAt: {
          for (final e in (raw['activatedAt'] as Map? ?? const {}).entries)
            if (e.key is String && e.value is String)
              e.key as String: e.value as String,
        },
        catalogOverrides: raw['catalogOverrides'] is Map
            ? Map<String, dynamic>.from(raw['catalogOverrides'] as Map)
            : const {},
        habitOrder: {
          for (final e in (raw['habitOrder'] as Map? ?? const {}).entries)
            if (e.key is String && e.value is num)
              e.key as String: (e.value as num).toDouble(),
        },
      );
}
