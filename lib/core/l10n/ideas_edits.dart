import 'package:flutter/foundation.dart';

/// The habit ideas and ready-made plans as edited on the admin tool's
/// «Habit ideas» page: the `ideas` and `plans` fields of wording/live,
/// beside `splash`, `pet` and the string edits (Aziz, 2026-10-01: "all
/// plans, and all habits in the list, and the admin can easily change it").
///
/// The built-in ideas are assets/data/habit_ideas.json and the built-in
/// plans are habit_plans.dart; this layer only reads the document's shape,
/// entry by entry like the rest of wording/live, so one bad entry costs that
/// entry and nothing else. What the fields mean and how they combine with the
/// built-ins is habit_ideas.dart's [resolveIdeas] / [resolvePlans], held to
/// the same cases as the admin tool's wording/ideas_rules.js
/// (scripts/admin_lookup/test/fixtures/ideas_cases.json).
///
///   ideas  order?     [id]                  the list's order, built-in and added
///          hidden?    [id]                  built-in ideas taken off
///          featured?  {id: bool}            «مختارة لك», over the idea's own
///          text?      {id: {field: value}}  edited fields of a built-in idea
///          added?     {id: idea}            ideas made on the admin tool
///   plans  order?     [planId]
///          hidden?    [planId]
///          text?      {planId: {nameAr?, nameEn?, descAr?, descEn?}}
@immutable
class IdeasEdits {
  const IdeasEdits({
    this.order,
    this.hidden = const [],
    this.featured = const {},
    this.text = const {},
    this.added = const {},
  });

  final List<String>? order;
  final List<String> hidden;
  final Map<String, bool> featured;

  /// Raw field maps; each field is checked where it is applied.
  final Map<String, Map<String, Object?>> text;

  /// Raw idea maps; each is checked whole where it is read.
  final Map<String, Map<String, Object?>> added;

  static IdeasEdits? fromData(Object? data) {
    if (data is! Map) return null;
    return IdeasEdits(
      order: _ids(data['order']),
      hidden: _ids(data['hidden']) ?? const [],
      featured: {
        if (data['featured'] case final Map m)
          for (final e in m.entries)
            if (e.key is String && e.value is bool) e.key as String: e.value as bool,
      },
      text: _maps(data['text']),
      added: _maps(data['added']),
    );
  }

  Map<String, Object?> toJson() => {
        if (order != null) 'order': order,
        if (hidden.isNotEmpty) 'hidden': hidden,
        if (featured.isNotEmpty) 'featured': featured,
        if (text.isNotEmpty) 'text': text,
        if (added.isNotEmpty) 'added': added,
      };
}

@immutable
class PlansEdits {
  const PlansEdits({this.order, this.hidden = const [], this.text = const {}});

  final List<String>? order;
  final List<String> hidden;

  /// {planId: {nameAr?, nameEn?, descAr?, descEn?}}, strings only.
  final Map<String, Map<String, String>> text;

  static PlansEdits? fromData(Object? data) {
    if (data is! Map) return null;
    return PlansEdits(
      order: _ids(data['order']),
      hidden: _ids(data['hidden']) ?? const [],
      text: {
        for (final e in _maps(data['text']).entries)
          e.key: {
            for (final f in const ['nameAr', 'nameEn', 'descAr', 'descEn'])
              if (e.value[f] case final String v when v.trim().isNotEmpty)
                f: v.trim(),
          },
      },
    );
  }

  Map<String, Object?> toJson() => {
        if (order != null) 'order': order,
        if (hidden.isNotEmpty) 'hidden': hidden,
        if (text.isNotEmpty) 'text': text,
      };
}

const int _maxIdLength = 64;

List<String>? _ids(Object? raw) {
  if (raw is! List) return null;
  return [
    for (final v in raw)
      if (v is String && v.isNotEmpty && v.length <= _maxIdLength) v,
  ];
}

Map<String, Map<String, Object?>> _maps(Object? raw) {
  if (raw is! Map) return const {};
  return {
    for (final e in raw.entries)
      if (e.key is String &&
          (e.key as String).length <= _maxIdLength &&
          e.value is Map)
        e.key as String: Map<String, Object?>.from(e.value as Map),
  };
}
