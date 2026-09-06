import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/alarm_service.dart';

/// Whether the reminder editors should offer "alarm" next to
/// "notification" at all.
///
/// True on Android, where the alarm is a notification on the alarm-audio
/// channel and needs no permission, and on iOS 26 or newer, where it is a
/// real AlarmKit alarm. Anywhere else the choice is hidden rather than shown
/// and refused: an option that can never work is worse than none.
///
/// Availability only. Permission is asked the moment someone picks alarm,
/// so a refusal is answered where it was made; see AddHabitSheet and the
/// task sheets' reminder pickers.
final alarmChoiceAvailableProvider = FutureProvider<bool>((ref) async {
  if (kIsWeb) return false;
  if (defaultTargetPlatform == TargetPlatform.android) return true;
  return AlarmService.instance.isSupported();
});
