/// Character and accessory text edited from the admin tool after a build
/// shipped — the same idea as achievement_overrides.dart (see its own doc
/// comment for the full "why"), sized for the closet instead of the medal
/// case: 16 characters (name only) and 12 accessories (name + description),
/// plus the 6 accessory-category labels shown as section headers in the
/// closet.
///
/// One Firestore document, [kCosmeticOverridesDocPath]:
///
///   characters   {id: {name?, nameAr?}}
///   accessories  {id: {name?, nameAr?, description?, descriptionAr?}}
///   categories   {id: {label?, labelAr?}}
///   version      int, bumped by every save
///
/// Read by anyone, written only by the admin tool's Achievements page
/// (scripts/admin_lookup), through the Admin SDK. Same read-anywhere,
/// no-live-rebuild trade-off as achievement_overrides.dart: an edit shows
/// the next time the closet is opened, not while it is already on screen.
library;

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';

import '../../../core/services/local_store_service.dart';
import '../../achievements/models/achievement_overrides.dart'
    show AchievementTextOverride;

const String kCosmeticOverridesDocPath = 'cosmetic_overrides/live';

@immutable
class CosmeticOverrides {
  const CosmeticOverrides({
    this.characterNames = const {},
    this.accessoryNames = const {},
    this.accessoryDescriptions = const {},
    this.categoryLabels = const {},
    this.prestigeTitles = const {},
    this.version = 0,
  });

  static const empty = CosmeticOverrides();

  final Map<String, AchievementTextOverride> characterNames;
  final Map<String, AchievementTextOverride> accessoryNames;
  final Map<String, AchievementTextOverride> accessoryDescriptions;
  final Map<String, AchievementTextOverride> categoryLabels;
  final Map<String, AchievementTextOverride> prestigeTitles;

  final int version;

  bool get isEmpty =>
      characterNames.isEmpty &&
      accessoryNames.isEmpty &&
      accessoryDescriptions.isEmpty &&
      categoryLabels.isEmpty &&
      prestigeTitles.isEmpty;

  String? characterName(String id, bool isAr) => _pick(characterNames[id], isAr);
  String? accessoryName(String id, bool isAr) => _pick(accessoryNames[id], isAr);
  String? accessoryDescription(String id, bool isAr) =>
      _pick(accessoryDescriptions[id], isAr);
  String? categoryLabel(String id, bool isAr) => _pick(categoryLabels[id], isAr);
  String? prestigeTitle(String id, bool isAr) => _pick(prestigeTitles[id], isAr);

  static String? _pick(AchievementTextOverride? o, bool isAr) {
    if (o == null) return null;
    final text = isAr ? o.b : o.a;
    return text == null || text.trim().isEmpty ? null : text;
  }

  /// Parsed entry by entry, never trusted whole — see
  /// achievement_overrides.dart's identical factory for why.
  factory CosmeticOverrides.fromData(Object? data) {
    if (data is! Map) return empty;
    final version = data['version'];
    return CosmeticOverrides(
      characterNames: _fieldMap(data['characters'], 'name', 'nameAr'),
      accessoryNames: _fieldMap(data['accessories'], 'name', 'nameAr'),
      accessoryDescriptions:
          _fieldMap(data['accessories'], 'description', 'descriptionAr'),
      categoryLabels: _fieldMap(data['categories'], 'label', 'labelAr'),
      prestigeTitles: _fieldMap(data['prestige'], 'title', 'titleAr'),
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

  Map<String, Object?> toJson() => {
        'characters': {
          for (final entry in characterNames.entries)
            entry.key: {
              if (entry.value.a != null) 'name': entry.value.a,
              if (entry.value.b != null) 'nameAr': entry.value.b,
            },
        },
        'accessories': {
          for (final id in {...accessoryNames.keys, ...accessoryDescriptions.keys})
            id: {
              if (accessoryNames[id]?.a != null) 'name': accessoryNames[id]!.a,
              if (accessoryNames[id]?.b != null) 'nameAr': accessoryNames[id]!.b,
              if (accessoryDescriptions[id]?.a != null)
                'description': accessoryDescriptions[id]!.a,
              if (accessoryDescriptions[id]?.b != null)
                'descriptionAr': accessoryDescriptions[id]!.b,
            },
        },
        'categories': {
          for (final entry in categoryLabels.entries)
            entry.key: {
              if (entry.value.a != null) 'label': entry.value.a,
              if (entry.value.b != null) 'labelAr': entry.value.b,
            },
        },
        'prestige': {
          for (final entry in prestigeTitles.entries)
            entry.key: {
              if (entry.value.a != null) 'title': entry.value.a,
              if (entry.value.b != null) 'titleAr': entry.value.b,
            },
        },
        'version': version,
      };
}

/// Holds the edits in force and keeps them current. Same shape as
/// AchievementOverridesStore, one per document.
class CosmeticOverridesStore {
  CosmeticOverridesStore._();

  static const String cacheKey = 'cosmetic_overrides_v1';

  static final ValueNotifier<CosmeticOverrides> live =
      ValueNotifier(CosmeticOverrides.empty);

  static CosmeticOverrides get current => live.value;

  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  static AppLifecycleListener? _resumeRetry;
  static String _currentJson = jsonEncode(CosmeticOverrides.empty.toJson());

  static Future<void> loadCached([Box<dynamic>? box]) async {
    try {
      final settings = box ?? await LocalStoreService.settingsBox();
      final raw = settings.get(cacheKey);
      if (raw is String) _publish(CosmeticOverrides.fromData(jsonDecode(raw)));
    } catch (e) {
      debugPrint('[cosmetics] cached overrides unreadable, using built-in: $e');
    }
  }

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
    _sub = db.doc(kCosmeticOverridesDocPath).snapshots().listen(
      (snap) {
        if (!snap.exists && snap.metadata.isFromCache) return;
        unawaited(_receive(
          snap.exists
              ? CosmeticOverrides.fromData(snap.data())
              : CosmeticOverrides.empty,
          box,
        ));
      },
      onError: (Object e) {
        debugPrint('[cosmetics] listener stopped, built-in or cached text '
            'stays: $e');
        _sub = null;
      },
    );
  }

  static Future<void> _receive(
    CosmeticOverrides overrides,
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
      debugPrint('[cosmetics] could not keep a copy of the overrides: $e');
    }
  }

  static bool _publish(CosmeticOverrides overrides) {
    final json = jsonEncode(overrides.toJson());
    if (json == _currentJson) return false;
    _currentJson = json;
    live.value = overrides;
    return true;
  }

  @visibleForTesting
  static void debugPublish(CosmeticOverrides overrides) => _publish(overrides);

  @visibleForTesting
  static Future<void> reset() async {
    await _sub?.cancel();
    _sub = null;
    _resumeRetry?.dispose();
    _resumeRetry = null;
    _publish(CosmeticOverrides.empty);
  }
}
