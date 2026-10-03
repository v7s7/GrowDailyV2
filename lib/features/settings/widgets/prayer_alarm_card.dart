import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/alarm_choice_provider.dart';
import '../../../core/services/alarm_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/theme/game_theme.dart';
import '../../habits/models/habit_cue.dart';
import '../models/notification_settings.dart';
import '../notifiers/notification_settings_notifier.dart';
import 'prayer_today_card.dart' show prayerMomentIcon;

/// What the adhan alarm switches can do on this phone right now.
enum PrayerAlarmReadiness {
  /// A switch that is on rings.
  ready,

  /// iOS 26 or newer, and nobody has been asked for the alarm permission
  /// yet: turning a switch on asks, then turns it on if allowed.
  askFirst,

  /// Android with notifications off, which is how a fresh install starts on
  /// Android 13: turning a switch on asks (or opens their settings once
  /// refused), then turns it on if they come on.
  needsNotifications,

  /// Grey: an iPhone below iOS 26, where no app can ring an alarm.
  needsNewerIos,

  /// Grey: the alarm permission was refused, on the system sheet or later
  /// in Settings.
  alarmsDenied,

  /// Grey: Android 12 with «المنبّهات والتذكيرات» off for the app, where an
  /// alarm could ring up to an hour late.
  exactAlarmsOff,

  /// No card at all: the web, or an iPhone whose alarm bridge did not
  /// answer, where nothing true can be offered or said.
  unavailable;

  /// Drawn, but no switch can be turned on, and the card says why.
  bool get isGrey =>
      this == needsNewerIos || this == alarmsDenied || this == exactAlarmsOff;
}

/// Which [PrayerAlarmReadiness] holds now. Asked again every time the app
/// comes back to the front, since every answer here can change in the
/// phone's Settings while it is away: a permission allowed there brings the
/// switches back without a restart.
final prayerAlarmReadinessProvider =
    FutureProvider<PrayerAlarmReadiness>((ref) async {
  if (kIsWeb) return PrayerAlarmReadiness.unavailable;
  final lifecycle = AppLifecycleListener(onResume: ref.invalidateSelf);
  ref.onDispose(lifecycle.dispose);
  try {
    return await _readiness();
  } catch (e) {
    debugPrint('[PrayerAlarmCard] readiness unknown: $e');
    return PrayerAlarmReadiness.unavailable;
  }
});

Future<PrayerAlarmReadiness> _readiness() async {
  if (defaultTargetPlatform == TargetPlatform.android) {
    if (await NotificationService.instance.canScheduleExactAlarms() == false) {
      return PrayerAlarmReadiness.exactAlarmsOff;
    }
    return await NotificationService.instance.checkSystemPermission() == false
        ? PrayerAlarmReadiness.needsNotifications
        : PrayerAlarmReadiness.ready;
  }
  if (defaultTargetPlatform != TargetPlatform.iOS) {
    return PrayerAlarmReadiness.unavailable;
  }
  if (await AlarmService.instance.isSupported()) {
    return switch (await AlarmService.instance.authorizationState()) {
      'authorized' => PrayerAlarmReadiness.ready,
      'denied' => PrayerAlarmReadiness.alarmsDenied,
      'notDetermined' => PrayerAlarmReadiness.askFirst,
      _ => PrayerAlarmReadiness.unavailable,
    };
  }
  // Only a real iPhone's version means anything (see alarmChoiceProvider).
  if (!Platform.isIOS) return PrayerAlarmReadiness.unavailable;
  final choice = alarmChoiceWithoutAlarmKit(
    iosMajorVersion(Platform.operatingSystemVersion),
  );
  return choice == AlarmChoice.needsNewerIos
      ? PrayerAlarmReadiness.needsNewerIos
      : PrayerAlarmReadiness.unavailable;
}

/// «منبّه الأذان» on Settings › موقع الصلاة: one switch per prayer, all off
/// until the person turns one on, each ringing a real alarm at that
/// prayer's adhan for the saved place (NotificationService's
/// _syncPrayerAlarms arms them, two weeks ahead, topped up on every open).
///
/// Aziz, 2026-10-03: "a choice where user can toggle it on, by default its
/// off, where user can enable alarm for each prayer, the 5 prayer, and it
/// should only be toggled if it will work". He picked a card of its own on
/// this page, under the two ways to choose a place, free for everyone. So a
/// switch reads on only while its alarm will really ring on this phone, and
/// turns on only once it can ([PrayerAlarmReadiness]):
///  - iOS 26 or newer: AlarmKit. The first switch turned on asks for the
///    alarm permission, at the moment it is wanted. Refused, the switches
///    go grey and say so, in the words «منبّه» uses under a habit reminder.
///  - An iPhone below iOS 26: grey, «المنبّه يحتاج iOS 26 أو أحدث.».
///  - Android: the alarm reaches the phone as a notification on the alarm
///    channel, so turning one on asks for notifications first, and it stays
///    off if they stay off. Android 12 with «المنبّهات والتذكيرات» off is grey.
/// A choice saved while it cannot ring (a permission taken back in
/// Settings, or a choice restored from the account on a new phone) is kept,
/// shown off, and comes back on by itself once the phone allows it.
///
/// Carries its own space above it, so a phone that cannot be offered alarms
/// at all leaves no gap on the page.
class PrayerAlarmCard extends ConsumerStatefulWidget {
  const PrayerAlarmCard({super.key});

  @override
  ConsumerState<PrayerAlarmCard> createState() => _PrayerAlarmCardState();
}

class _PrayerAlarmCardState extends ConsumerState<PrayerAlarmCard> {
  /// Waiting on the phone's own answer (its permission sheet), so a second
  /// tap meanwhile does not ask again.
  bool _asking = false;

  /// Android: turning one on found notifications off, and neither the
  /// prompt nor their settings turned them back on.
  bool _notificationsRefused = false;

  Future<void> _set(
    String key,
    bool on,
    PrayerAlarmReadiness readiness,
  ) async {
    final settings = ref.read(notificationSettingsProvider.notifier);
    if (!on) {
      await settings.update(
        (c) => c.copyWith(prayerAlarms: {...c.prayerAlarms}..remove(key)),
      );
      return;
    }
    if (_asking) return;
    if (readiness == PrayerAlarmReadiness.askFirst ||
        readiness == PrayerAlarmReadiness.needsNotifications) {
      setState(() => _asking = true);
      final allowed = readiness == PrayerAlarmReadiness.askFirst
          ? await AlarmService.instance.requestPermission()
          : await NotificationService.instance.ensureSystemPermission();
      if (!mounted) return;
      setState(() {
        _asking = false;
        _notificationsRefused =
            readiness == PrayerAlarmReadiness.needsNotifications && !allowed;
      });
      ref.invalidate(prayerAlarmReadinessProvider);
      // The habit and task sheets' «منبّه» reads the same permission.
      ref.invalidate(alarmChoiceProvider);
      if (!allowed) return;
    }
    await settings.update(
      (c) => c.copyWith(prayerAlarms: {...c.prayerAlarms, key}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final readiness = ref.watch(prayerAlarmReadinessProvider).value;
    if (readiness == null || readiness == PrayerAlarmReadiness.unavailable) {
      return const SizedBox.shrink();
    }
    final gp = context.gp;
    final s = S.of(context);
    final chosen = ref.watch(
      notificationSettingsProvider.select((st) => st.prayerAlarms),
    );
    final grey = readiness.isGrey;
    final rings = readiness == PrayerAlarmReadiness.ready;
    // In place of the hint, which promises a ring this phone cannot give.
    final note = switch (readiness) {
      PrayerAlarmReadiness.needsNewerIos => s.alarmNeedsNewerIos,
      PrayerAlarmReadiness.alarmsDenied => s.alarmPermissionDenied,
      PrayerAlarmReadiness.exactAlarmsOff => s.prayerAlarmNeedsExactAlarms,
      PrayerAlarmReadiness.needsNotifications when _notificationsRefused =>
        s.prayerAlarmNeedsNotifications,
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Material(
        color: gp.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          side: BorderSide(color: gp.border, width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.alarm_rounded,
                    size: 20,
                    color: grey ? gp.textSec : gp.goldInk,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.prayerAlarmTitle,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: gp.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          note ?? s.prayerAlarmHint,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: gp.textSec,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 0.5, thickness: 0.5, color: gp.divider),
            const SizedBox(height: 4),
            for (final key in kPrayerAlarmKeys)
              _PrayerSwitchRow(
                prayerKey: key,
                value: rings && chosen.contains(key),
                enabled: !grey,
                onChanged: (on) => _set(key, on, readiness),
              ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

/// One prayer and its switch, read out together.
class _PrayerSwitchRow extends StatelessWidget {
  const _PrayerSwitchRow({
    required this.prayerKey,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String prayerKey;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        child: Row(
          children: [
            Icon(
              prayerMomentIcon(prayerKey),
              size: 18,
              color: enabled ? gp.textSec : gp.textTert,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                HabitCue.preset(prayerKey).labelForLocale(s.isAr),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: enabled ? gp.textPrimary : gp.textTert,
                ),
              ),
            ),
            Switch.adaptive(
              value: value,
              activeTrackColor: GameColors.emerald,
              onChanged: enabled
                  ? (v) {
                      HapticFeedback.selectionClick();
                      onChanged(v);
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
