import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_icon_catalog.dart';

/// The Home Screen icon's channel to iOS (ios/Runner/AppIconBridge.swift).
///
/// Every call answers safely everywhere else: Android and the web report
/// no support and the shipped icon, and never reach the channel.
class AppIconService {
  const AppIconService();

  static const _channel = MethodChannel('com.growdaily.v2/app_icon');

  /// iPhone only; see app_icon_catalog.dart's [PlantShape] for why.
  static bool get onThisPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<bool> supported() async {
    if (!onThisPlatform) return false;
    try {
      return await _channel.invokeMethod<bool>('supported') ?? false;
    } catch (e) {
      debugPrint('[AppIconService] supported? $e');
      return false;
    }
  }

  /// What the phone shows right now. iOS is the record: the choice is never
  /// stored anywhere else, so it cannot disagree with the Home Screen.
  Future<AppIconChoice> current() async {
    if (!onThisPlatform) return AppIconChoice.shipped;
    try {
      return AppIconChoice.fromIosName(
        await _channel.invokeMethod<String>('current'),
      );
    } catch (e) {
      debugPrint('[AppIconService] current: $e');
      return AppIconChoice.shipped;
    }
  }

  /// Puts [choice] on the Home Screen. iOS answers with its own alert, so
  /// this must only ever run from something the person just tapped. True
  /// when the phone now shows [choice].
  Future<bool> set(AppIconChoice choice) async {
    if (!onThisPlatform) return false;
    try {
      await _channel.invokeMethod<bool>('set', {'name': choice.iosName});
      return true;
    } catch (e) {
      debugPrint('[AppIconService] set $choice: $e');
      return false;
    }
  }
}
