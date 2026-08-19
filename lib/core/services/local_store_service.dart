import 'package:hive_flutter/hive_flutter.dart';

import '../constants/game_constants.dart';

class LocalStoreService {
  LocalStoreService._();

  static const String guestDashboardKey = 'guest_dashboard_state';
  static const String guestFocusPrefix = 'guest_focus_plan_';
  static const String guestCustomHabitsKey = 'guest_custom_habits';
  static const String guestArchivedCustomHabitsKey =
      'guest_archived_custom_habits';
  static const String guestMatrixTasksKey = 'guest_matrix_tasks';
  static const String guestMatrixQuadrantsKey = 'guest_matrix_quadrants';
  static const String guestCharacterKey = 'guest_character_state';
  // Deliberately its own key, not folded into guestCharacterKey above:
  // putSettingsMap does a plain Hive .put() (a full overwrite at that key,
  // no auto-merge - see that method below), so sharing a key between two
  // independent notifiers (CharacterNotifier and PrestigeNotifier) would
  // have one silently clobber the other's guest data on every save.
  static const String guestPrestigeKey = 'guest_prestige_state';

  static Future<Box<dynamic>> settingsBox() => _open(GameConstants.boxSettings);
  static Future<Box<dynamic>> dailyBox() => _open(GameConstants.boxDailyLogs);
  static Future<Box<dynamic>> habitsBox() => _open(GameConstants.boxHabits);

  static Future<Box<dynamic>> _open(String name) =>
      Hive.isBoxOpen(name)
          ? Future.value(Hive.box<dynamic>(name))
          : Hive.openBox<dynamic>(name);

  static String dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Map<String, dynamic> asStringMap(Object? value) {
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return <String, dynamic>{};
  }

  static List<Map<String, dynamic>> asMapList(Object? value) {
    if (value is List) {
      return value
          .whereType<Map>()
          .map((item) => item.map((key, val) => MapEntry(key.toString(), val)))
          .toList();
    }
    return const [];
  }

  static Future<Map<String, dynamic>> getSettingsMap(String key) async =>
      asStringMap((await settingsBox()).get(key));

  static Future<void> putSettingsMap(String key, Map<String, dynamic> value) async =>
      (await settingsBox()).put(key, value);

  static Future<Map<String, dynamic>> getDailyMap(String dateKey) async =>
      asStringMap((await dailyBox()).get(dateKey));

  /// Every stored day at once, keyed by dateKey — what the guest side of
  /// the yearly strip aggregates from. The box is in memory, so unlike the
  /// Firestore daily collection there is no per-day read cost to avoid.
  static Future<Map<String, Map<String, dynamic>>> allDailyMaps() async {
    final box = await dailyBox();
    return {
      for (final key in box.keys) key.toString(): asStringMap(box.get(key)),
    };
  }

  static Future<void> putDailyMap(String dateKey, Map<String, dynamic> value) async =>
      (await dailyBox()).put(dateKey, value);
}
