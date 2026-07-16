import 'package:hive_flutter/hive_flutter.dart';

import '../constants/game_constants.dart';

class LocalStoreService {
  LocalStoreService._();

  static const String guestDashboardKey = 'guest_dashboard_state';
  static const String guestFocusPrefix = 'guest_focus_plan_';
  static const String guestCustomHabitsKey = 'guest_custom_habits';
  static const String guestMatrixTasksKey = 'guest_matrix_tasks';
  static const String guestMatrixQuadrantsKey = 'guest_matrix_quadrants';
  static const String guestCharacterKey = 'guest_character_state';

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

  static Future<void> putDailyMap(String dateKey, Map<String, dynamic> value) async =>
      (await dailyBox()).put(dateKey, value);
}
