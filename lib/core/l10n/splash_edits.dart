import 'package:flutter/foundation.dart';

/// The launch splash's settings as edited on the admin tool's «الشاشة
/// الافتتاحية» page: the `splash` field of wording/live, beside Doum's
/// `pet` field and the string edits.
///
/// Aziz, 2026-10-01: "make it controlled by admin page, he can control when
/// each appear and etc". Which scene Doum plays on the launch curtain was all
/// code (lib/features/launch/launch_scene.dart); this is the part the admin
/// may change: which scenes are on, the hours and months each plays in, the
/// order they take precedence in, the coin between the two ordinary scenes,
/// the curtain's timing, and one scene played for everyone over a stretch of
/// days.
///
/// Only what was changed is stored, and every value absent here is the
/// app's own. What the names and numbers mean, and the range each may take,
/// is lib/features/launch/launch_settings.dart's to say (it lays these over
/// the built-in values and drops any it cannot use); this layer only reads
/// the document's shape, entry by entry like the rest of wording/live, so one
/// bad entry costs that entry and nothing else.
///
///   <a number>  int                  minShowMs, maxShowMs, replayAfterMinutes,
///                                    awayDays, firstOpenDays, updateDays,
///                                    newFirst, noRepeat, walkerFromHour,
///                                    walkerToHour
///   order       [scene name]         the precedence, first wins
///   off         [scene name]         scenes switched off
///   hours       {scene: [from, to]}  the hours a scene plays in; from > to
///                                    wraps past midnight, 24 is midnight
///   months      {scene: [1..12]}     the months a scene plays in
///   pool        {scene: share}       the anytime list's shares, 0 for out
///   onceADay    {scene: 0 or 1}      an every-open moment played once a day
///   chance      {scene: 0..100}      the percent of days a moment plays
///   lines       {scene: text}        the line under Doum, rewritten
///   slowLine    text                 the slow load's line, rewritten
///   force       {scene, from?, to?}  one scene for everyone, between two
///                                    local dates (yyyy-mm-dd), both ends
///                                    included; no dates = until removed
@immutable
class SplashEdits {
  const SplashEdits({
    this.numbers = const {},
    this.order,
    this.off = const [],
    this.hours = const {},
    this.months = const {},
    this.forceScene,
    this.forceFrom,
    this.forceTo,
    this.pool = const {},
    this.onceADay = const {},
    this.chance = const {},
    this.lines = const {},
    this.slowLine,
  });

  /// Every whole number stored, by name. Which names mean something, and the
  /// range each may take, is launch_settings.dart's to say.
  final Map<String, int> numbers;

  /// The scenes in the order they take precedence, or null for the app's.
  final List<String>? order;

  /// Scenes switched off.
  final List<String> off;

  /// A scene's hours, by scene name: [from, to].
  final Map<String, List<int>> hours;

  /// A scene's months, by scene name: 1 (January) to 12.
  final Map<String, List<int>> months;

  /// The scene played for everyone, with the first and last local day (as
  /// yyyy-mm-dd) it plays on; either end may be null for open.
  final String? forceScene;
  final String? forceFrom;
  final String? forceTo;

  /// The anytime list's shares, by scene name.
  final Map<String, int> pool;

  /// Once a day (1) or every open (0), by scene name.
  final Map<String, int> onceADay;

  /// The percent of days a moment plays, by scene name.
  final Map<String, int> chance;

  /// Rewritten lines under Doum, by scene name.
  final Map<String, String> lines;

  /// The slow load's line, rewritten.
  final String? slowLine;

  static const _named = {
    'order',
    'off',
    'hours',
    'months',
    'force',
    'pool',
    'onceADay',
    'chance',
    'lines',
    'slowLine',
  };

  bool get isEmpty =>
      numbers.isEmpty &&
      order == null &&
      off.isEmpty &&
      hours.isEmpty &&
      months.isEmpty &&
      forceScene == null &&
      pool.isEmpty &&
      onceADay.isEmpty &&
      chance.isEmpty &&
      lines.isEmpty &&
      slowLine == null;

  /// The stored field, or null when it holds nothing this build can read.
  static SplashEdits? fromData(Object? data) {
    if (data is! Map) return null;
    final numbers = <String, int>{};
    data.forEach((key, value) {
      if (key is String &&
          !_named.contains(key) &&
          value is num &&
          value.isFinite &&
          value == value.roundToDouble()) {
        numbers[key] = value.toInt();
      }
    });
    final force = data['force'];
    final forceScene = force is Map && force['scene'] is String
        ? force['scene'] as String
        : null;
    final pool = _intMap(data['pool']);
    final onceADay = _intMap(data['onceADay']);
    final chance = _intMap(data['chance']);
    final lines = <String, String>{};
    final rawLines = data['lines'];
    if (rawLines is Map) {
      rawLines.forEach((key, value) {
        if (key is String && value is String) lines[key] = value;
      });
    }
    final slowLine = data['slowLine'];
    final edits = SplashEdits(
      pool: pool,
      onceADay: onceADay,
      chance: chance,
      lines: Map.unmodifiable(lines),
      slowLine: slowLine is String ? slowLine : null,
      numbers: Map.unmodifiable(numbers),
      order: _names(data['order']),
      off: _names(data['off']) ?? const [],
      hours: _intLists(data['hours'], length: 2),
      months: _intLists(data['months']),
      forceScene: forceScene,
      forceFrom: forceScene != null && force is Map && force['from'] is String
          ? force['from'] as String
          : null,
      forceTo: forceScene != null && force is Map && force['to'] is String
          ? force['to'] as String
          : null,
    );
    return edits.isEmpty ? null : edits;
  }

  static Map<String, int> _intMap(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, int>{};
    raw.forEach((key, value) {
      if (key is String &&
          value is num &&
          value.isFinite &&
          value == value.roundToDouble()) {
        out[key] = value.toInt();
      }
    });
    return Map.unmodifiable(out);
  }

  static List<String>? _names(Object? raw) {
    if (raw is! List) return null;
    return List.unmodifiable([
      for (final v in raw)
        if (v is String) v,
    ]);
  }

  static Map<String, List<int>> _intLists(Object? raw, {int? length}) {
    if (raw is! Map) return const {};
    final out = <String, List<int>>{};
    raw.forEach((key, value) {
      if (key is! String || value is! List) return;
      final ints = <int>[
        for (final v in value)
          if (v is num && v.isFinite && v == v.roundToDouble()) v.toInt(),
      ];
      if (ints.length != value.length) return;
      if (length != null && ints.length != length) return;
      out[key] = List.unmodifiable(ints);
    });
    return Map.unmodifiable(out);
  }

  /// The field as wording/live holds it, for this device's cached copy.
  Map<String, dynamic> toJson() => {
        ...numbers,
        if (order != null) 'order': order,
        if (off.isNotEmpty) 'off': off,
        if (hours.isNotEmpty) 'hours': hours,
        if (months.isNotEmpty) 'months': months,
        if (pool.isNotEmpty) 'pool': pool,
        if (onceADay.isNotEmpty) 'onceADay': onceADay,
        if (chance.isNotEmpty) 'chance': chance,
        if (lines.isNotEmpty) 'lines': lines,
        if (slowLine != null) 'slowLine': slowLine,
        if (forceScene != null)
          'force': {
            'scene': forceScene,
            if (forceFrom != null) 'from': forceFrom,
            if (forceTo != null) 'to': forceTo,
          },
      };
}
