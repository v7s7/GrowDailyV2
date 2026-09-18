import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/alarm_service.dart';

/// What the reminder editors offer under «طريقة التنبيه».
enum AlarmChoice {
  /// Notification or alarm, and either can be picked: on Android, where the
  /// alarm is a notification on the alarm-audio channel and needs no
  /// permission, and on iOS 26 or newer, where it is a real AlarmKit alarm.
  available,

  /// Drawn, but only notification can be picked: an iPhone still on an iOS
  /// older than 26, where no app can ring a real alarm. «منبّه» is grey,
  /// and tapping it says what it needs instead of switching, so the person
  /// learns that an update is the way to it. Hiding the choice here, as the
  /// app first did, read as broken: an iPhone 14 not yet updated to iOS 26
  /// showed neither cell, and nothing said why (reported 2026-09-18).
  needsNewerIos,

  /// Drawn, but only notification can be picked: iOS 26 or newer, and the
  /// alarm permission was refused, on the system sheet or later in
  /// Settings, so no alarm can ring. «منبّه» is grey, and tapping it says
  /// the permission is off and where to turn it back on. Grey for exactly
  /// these two reasons and nothing else (Aziz, 2026-09-18): before anyone
  /// has been asked, the cell is live and the tap asks.
  permissionDenied,

  /// Not drawn at all: the web, and an iOS 26 phone whose alarm bridge did
  /// not answer, where there is nothing to offer and nothing true to say
  /// about it.
  hidden,
}

/// Which [AlarmChoice] the reminder editors draw.
///
/// A permission nobody has been asked for yet counts as available: it is
/// asked the moment someone picks alarm, so a refusal is answered where it
/// was made (see AddHabitSheet and the task sheets' reminder pickers), and
/// from then on the cell is grey ([AlarmChoice.permissionDenied]).
final alarmChoiceProvider = FutureProvider<AlarmChoice>((ref) async {
  if (kIsWeb) return AlarmChoice.hidden;
  if (defaultTargetPlatform == TargetPlatform.android) {
    return AlarmChoice.available;
  }
  if (defaultTargetPlatform != TargetPlatform.iOS) return AlarmChoice.hidden;
  if (await AlarmService.instance.isSupported()) {
    // The permission changes outside the switch: on the system sheet, while
    // the app is inactive, and in Settings, while it is in the background.
    // Both end with the app coming back to the front, so it is asked again
    // then, and a cell greyed by a refusal comes back once it is allowed.
    final lifecycle = AppLifecycleListener(onResume: ref.invalidateSelf);
    ref.onDispose(lifecycle.dispose);
    return await AlarmService.instance.authorizationState() == 'denied'
        ? AlarmChoice.permissionDenied
        : AlarmChoice.available;
  }
  // Only a real iPhone's version means anything here: a test on a Mac with
  // the iOS look switched on would read the Mac's.
  if (!Platform.isIOS) return AlarmChoice.hidden;
  final version = Platform.operatingSystemVersion;
  final choice = alarmChoiceWithoutAlarmKit(iosMajorVersion(version));
  debugPrint('[AlarmChoice] no AlarmKit on "$version": ${choice.name}');
  return choice;
});

/// What an iPhone without AlarmKit offers. Below iOS 26: the choice, with
/// the alarm cell saying what it needs. Anything else: nothing, because
/// telling a phone already on iOS 26 to update would be false.
AlarmChoice alarmChoiceWithoutAlarmKit(int? iosMajor) =>
    iosMajor != null && iosMajor < 26
        ? AlarmChoice.needsNewerIos
        : AlarmChoice.hidden;

/// The major version out of dart:io's iOS version string, which reads
/// "Version 18.6 (Build 22G86)", or null when it holds no number.
int? iosMajorVersion(String operatingSystemVersion) {
  final digits = RegExp(r'\d+').firstMatch(operatingSystemVersion);
  return digits == null ? null : int.tryParse(digits.group(0)!);
}
