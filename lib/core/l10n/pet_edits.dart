import 'package:flutter/foundation.dart';

/// Doum's settings as edited on the admin tool's «دوم» page: the `pet`
/// field of wording/live, beside the string edits that hold his words.
///
/// Aziz, 2026-09-28: "make everything changeable in the admin page", then
/// "add the confetti sizes too". His words were already editable there; this
/// is the rest: how often he talks, when he sleeps, which praise list each
/// habit hears, and the confetti of the day's three moments.
///
/// Only what was changed is stored, and every value absent here is the app's
/// own. The numbers and names are checked where they are used
/// (lib/features/mascot/pet_settings.dart, which lays these over the
/// built-in values and drops any it cannot use); this layer only reads the
/// document's shape, entry by entry like the rest of wording/live, so one bad
/// entry costs that entry and nothing else.
///
///   <a number>  int               praiseEverySeconds, streakConfettiPieces
///                                 and the rest of pet_settings.dart's kPet
///                                 numbers, by name
///   presets     {habit id: list}  a ready-made habit's list, '' for its
///                                 category's
///   categories  {category: list}  a category's list
///   alsoHears   {list: list}      the list a list also draws on, '' for none
///   quit        list              every quit habit's list
@immutable
class PetEdits {
  const PetEdits({
    this.numbers = const {},
    this.presets = const {},
    this.categories = const {},
    this.alsoHears = const {},
    this.quit,
  });

  /// Every whole number stored, by name. Which names mean something, and the
  /// range each may take, is pet_settings.dart's to say.
  final Map<String, int> numbers;

  /// A ready-made habit's list, by its catalog id; empty for "follow its
  /// category".
  final Map<String, String> presets;

  /// A category's list, by HabitCategory name.
  final Map<String, String> categories;

  /// The list a list also draws on, by list name. An empty value is "none".
  final Map<String, String> alsoHears;

  /// The list every quit habit hears.
  final String? quit;

  static const _named = {'presets', 'categories', 'alsoHears', 'quit'};

  bool get isEmpty =>
      numbers.isEmpty &&
      presets.isEmpty &&
      categories.isEmpty &&
      alsoHears.isEmpty &&
      quit == null;

  /// The stored field, or null when it holds nothing this build can read.
  static PetEdits? fromData(Object? data) {
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
    final quit = data['quit'];
    final edits = PetEdits(
      numbers: Map.unmodifiable(numbers),
      presets: _names(data['presets']),
      categories: _names(data['categories']),
      alsoHears: _names(data['alsoHears']),
      quit: quit is String ? quit : null,
    );
    return edits.isEmpty ? null : edits;
  }

  static Map<String, String> _names(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    };
  }

  /// The field as wording/live holds it, for this device's cached copy.
  Map<String, dynamic> toJson() => {
        ...numbers,
        if (presets.isNotEmpty) 'presets': presets,
        if (categories.isNotEmpty) 'categories': categories,
        if (alsoHears.isNotEmpty) 'alsoHears': alsoHears,
        if (quit != null) 'quit': quit,
      };
}
