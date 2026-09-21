/// Achievement text edited from the admin tool after a build shipped.
///
/// ── Why this exists ─────────────────────────────────────────────────────
/// Every achievement's name and description live as plain Dart literals in
/// [AchievementCatalog.all] (achievement_model.dart) — 24 entries, each in
/// English and Arabic, 6 family titles besides. Changing one of them meant a
/// build and an App Store review, same problem
/// [lib/core/l10n/wording_edits.dart] solved for the rest of the app's text
/// (Aziz, 2026-09-18: "we need to store them somewhere, where I have admin
/// side, where I can edit them and they auto change"). This is that same
/// idea, sized for 30 short records instead of the whole app's wording.
///
/// The built-in text stays exactly where it is and stays the source of every
/// name a player has never had edited. This is a thin layer of EDITS laid
/// over it: [AchievementModel.localName]/[localDescription] and
/// [AchievementFamily.localTitle] check it first and fall back to the
/// built-in string, so no edit can ever leave a reader with nothing to show.
///
/// ── Where the edits live ────────────────────────────────────────────────
/// One Firestore document, [kAchievementOverridesDocPath]:
///
///   achievements  {id: {name?, nameAr?, description?, descriptionAr?}}
///   families      {id: {title?, titleAr?}}
///   version       int, bumped by every save
///
/// Anyone may read it (guests have no Firebase account, and every word in it
/// ships inside the app anyway); nobody may write it from a client. The only
/// writer is the admin tool's Achievements page (scripts/admin_lookup),
/// through the Admin SDK.
///
/// ── How this differs from the Wording system ────────────────────────────
/// No `{parts}`/interpolation (achievement text never fills a value), no
/// daily-rotation-style list, and no live, mid-screen repaint: reading
/// [AchievementOverridesStore.current] is a plain static lookup rather than
/// something threaded through an `InheritedWidget`, so an edit saved while
/// the Achievements screen is already open shows the next time that screen
/// is opened, not instantly. Wording earned that extra machinery because it
/// covers text on screen almost all the time; achievements are visited
/// occasionally, and 30 records did not justify rewiring every screen that
/// shows one just to watch a provider.
library;

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';

import '../../../core/services/local_store_service.dart';

/// The one document the admin tool writes and every device reads.
const String kAchievementOverridesDocPath = 'achievement_overrides/live';

/// One achievement's or family's edited fields. Any field left null means
/// "show the built-in text for it" — this is a sparse patch, not a full
/// replacement of the record.
@immutable
class AchievementTextOverride {
  const AchievementTextOverride({this.a, this.b});

  /// name (for an achievement) or title (for a family), English.
  final String? a;

  /// nameAr / titleAr, Arabic.
  final String? b;

  bool get isEmpty => a == null && b == null;
}

/// The edits in force at one moment. Immutable: a change is a new instance.
@immutable
class AchievementOverrides {
  const AchievementOverrides({
    this.names = const {},
    this.descriptions = const {},
    this.familyTitles = const {},
    this.version = 0,
  });

  static const empty = AchievementOverrides();

  /// Achievement id → {a: edited name, b: edited nameAr}.
  final Map<String, AchievementTextOverride> names;

  /// Achievement id → {a: edited description, b: edited descriptionAr}.
  final Map<String, AchievementTextOverride> descriptions;

  /// Family id → {a: edited title, b: edited titleAr}.
  final Map<String, AchievementTextOverride> familyTitles;

  final int version;

  bool get isEmpty =>
      names.isEmpty && descriptions.isEmpty && familyTitles.isEmpty;

  String? name(String id, bool isAr) =>
      _pick(names[id], isAr);

  String? description(String id, bool isAr) =>
      _pick(descriptions[id], isAr);

  String? familyTitle(String id, bool isAr) =>
      _pick(familyTitles[id], isAr);

  static String? _pick(AchievementTextOverride? o, bool isAr) {
    if (o == null) return null;
    final text = isAr ? o.b : o.a;
    return text == null || text.trim().isEmpty ? null : text;
  }

  /// Parsed entry by entry, never trusted whole — the same rule every
  /// account loader in this app follows since one malformed map field once
  /// bricked a whole read. A malformed entry costs that entry, never the
  /// rest. Anything unreadable parses to [empty].
  factory AchievementOverrides.fromData(Object? data) {
    if (data is! Map) return empty;
    final achievements = data['achievements'];
    final families = data['families'];
    final version = data['version'];
    return AchievementOverrides(
      names: _fieldMap(achievements, 'name', 'nameAr'),
      descriptions: _fieldMap(achievements, 'description', 'descriptionAr'),
      familyTitles: _fieldMap(families, 'title', 'titleAr'),
      version: version is num ? version.toInt() : 0,
    );
  }

  static Map<String, AchievementTextOverride> _fieldMap(
    Object? raw,
    String enKey,
    String arKey,
  ) {
    if (raw is! Map) return const {};
    final out = <String, AchievementTextOverride>{};
    raw.forEach((id, value) {
      if (id is! String || value is! Map) return;
      final a = value[enKey];
      final b = value[arKey];
      final override = AchievementTextOverride(
        a: a is String && a.trim().isNotEmpty ? a : null,
        b: b is String && b.trim().isNotEmpty ? b : null,
      );
      if (!override.isEmpty) out[id] = override;
    });
    return Map.unmodifiable(out);
  }

  /// The shape [AchievementOverrides.fromData] reads back, for this
  /// device's cache.
  Map<String, Object?> toJson() => {
        'achievements': {
          for (final id in {...names.keys, ...descriptions.keys})
            id: {
              if (names[id]?.a != null) 'name': names[id]!.a,
              if (names[id]?.b != null) 'nameAr': names[id]!.b,
              if (descriptions[id]?.a != null)
                'description': descriptions[id]!.a,
              if (descriptions[id]?.b != null)
                'descriptionAr': descriptions[id]!.b,
            },
        },
        'families': {
          for (final entry in familyTitles.entries)
            entry.key: {
              if (entry.value.a != null) 'title': entry.value.a,
              if (entry.value.b != null) 'titleAr': entry.value.b,
            },
        },
        'version': version,
      };
}

/// Holds the edits in force and keeps them current. Same shape as
/// WordingEditsStore (wording_edits.dart), minus the InheritedWidget half —
/// see this file's own doc comment for why.
class AchievementOverridesStore {
  AchievementOverridesStore._();

  static const String cacheKey = 'achievement_overrides_v1';

  static final ValueNotifier<AchievementOverrides> live =
      ValueNotifier(AchievementOverrides.empty);

  static AchievementOverrides get current => live.value;

  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  static AppLifecycleListener? _resumeRetry;
  static String _currentJson = jsonEncode(AchievementOverrides.empty.toJson());

  /// Seeds [live] from this device's last-known copy, before the first
  /// frame — see WordingEditsStore.loadCached for why this has to run
  /// before runApp rather than after.
  static Future<void> loadCached([Box<dynamic>? box]) async {
    try {
      final settings = box ?? await LocalStoreService.settingsBox();
      final raw = settings.get(cacheKey);
      if (raw is String) {
        _publish(AchievementOverrides.fromData(jsonDecode(raw)));
      }
    } catch (e) {
      debugPrint('[achievements] cached overrides unreadable, using '
          'built-in: $e');
    }
  }

  /// Follows [kAchievementOverridesDocPath] for as long as the app runs.
  /// Re-attaches on foreground the same way WordingEditsStore.listen does,
  /// for the same reason (a permission-denied stream never restarts on its
  /// own).
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
    _sub = db.doc(kAchievementOverridesDocPath).snapshots().listen(
      (snap) {
        if (!snap.exists && snap.metadata.isFromCache) return;
        unawaited(_receive(
          snap.exists
              ? AchievementOverrides.fromData(snap.data())
              : AchievementOverrides.empty,
          box,
        ));
      },
      onError: (Object e) {
        debugPrint('[achievements] listener stopped, built-in or cached '
            'text stays: $e');
        _sub = null;
      },
    );
  }

  static Future<void> _receive(
    AchievementOverrides overrides,
    Box<dynamic>? box,
  ) async {
    if (!_publish(overrides)) return;
    try {
      final settings = box ?? await LocalStoreService.settingsBox();
      if (live.value.isEmpty) {
        await settings.delete(cacheKey);
      } else {
        await settings.put(cacheKey, _currentJson);
      }
    } catch (e) {
      debugPrint('[achievements] could not keep a copy of the overrides: $e');
    }
  }

  static bool _publish(AchievementOverrides overrides) {
    final json = jsonEncode(overrides.toJson());
    if (json == _currentJson) return false;
    _currentJson = json;
    live.value = overrides;
    return true;
  }

  @visibleForTesting
  static void debugPublish(AchievementOverrides overrides) =>
      _publish(overrides);

  @visibleForTesting
  static Future<void> reset() async {
    await _sub?.cancel();
    _sub = null;
    _resumeRetry?.dispose();
    _resumeRetry = null;
    _publish(AchievementOverrides.empty);
  }
}
