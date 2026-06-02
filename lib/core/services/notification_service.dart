import 'package:flutter/foundation.dart';

/// Stub notification service — works as in-app banners now.
/// To enable push notifications on mobile:
///   1. Add: flutter_local_notifications: ^18.0.1
///   2. Configure AndroidManifest.xml and AppDelegate.swift per pub.dev docs
///   3. Replace stub body with real FlutterLocalNotificationsPlugin calls
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  Future<void> init() async {
    if (kIsWeb) return;
    debugPrint('[NotificationService] Ready');
  }

  Future<void> scheduleDailyReminder({int hour = 20, int minute = 0}) async {
    if (kIsWeb) return;
    debugPrint('[NotificationService] Daily reminder set — $hour:${minute.toString().padLeft(2, '0')}');
  }

  Future<void> showHabitCompleted({
    required String habitName,
    required int xpEarned,
    required int goldEarned,
  }) async {
    if (kIsWeb) return;
    debugPrint('[Notification] $habitName — +$xpEarned XP, +$goldEarned G');
  }

  Future<void> showLevelUp(int newLevel) async {
    if (kIsWeb) return;
    debugPrint('[Notification] Level up → LVL $newLevel');
  }
}
