import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One alarm of the month armed ahead for an alarm reminder, see
/// [AlarmService.syncWindow].
typedef WindowAlarm = ({
  int id,
  DateTime fireAt,
  String title,
  String? subtitle,
  String kind,
  String targetId,
  String stopLabel,
});

/// Real alarms, as opposed to notifications, for the reminders a person
/// asks to be woken by.
///
/// On iOS 26 and newer this is Apple's AlarmKit: the alarm rings through
/// Silent mode and every Focus, shows the full-screen stop screen the Clock
/// app uses, survives restarts, and appears on a paired Apple Watch. Older
/// iOS versions have no such thing for third-party apps, and Android's
/// equivalent is a notification on an alarm-audio channel, which
/// NotificationService builds itself. So this class is iOS only, and every
/// caller treats a false from [schedule] as "use the notification instead".
///
/// The native half is ios/Runner/AlarmKitBridge.swift, reached over one
/// small MethodChannel, the same shape as AppBadgeService. A habit's alarm
/// carries Stop and nothing else: it wakes the person, often well before the
/// habit itself, and the habit is recorded in the app as usual (Aziz,
/// 2026-09-11), so stopping one never marks anything done and the next alarm
/// still rings. A task's alarm has a second button, «خلّصت المهمة» (the
/// doneLabel of [schedule]), which stops it and queues the task's completion
/// the way the Home Screen widget's checkmark does; main.dart ticks the task
/// at the next open.
///
/// Alarm ids are the same integers the notification schedule uses for the
/// same slot (NotificationService._habitReminderId / _taskReminderId), so
/// the two systems can never both hold a reminder for one moment: whichever
/// one a slot is scheduled through cancels the other.
class AlarmService {
  AlarmService._() {
    _channel.setMethodCallHandler(_onNativeCall);
  }
  static final instance = AlarmService._();

  static const _channel = MethodChannel('com.growdaily.v2/alarm');

  /// Called with the slot id of an alarm that started ringing while the
  /// app was in front. iOS shows no alarm over its own app, so the native
  /// side stops it and hands the moment here; NotificationService answers
  /// by showing the same reminder as a banner, see its init. Set once, by
  /// that service.
  void Function(int slotId)? onForegroundAlarm;

  Future<Object?> _onNativeCall(MethodCall call) async {
    if (call.method != 'alarmAlertingInForeground') return null;
    final args = call.arguments;
    final id = args is Map ? args['id'] : null;
    if (id is int) {
      debugPrint('[AlarmService] alarm $id rang with the app in front');
      onForegroundAlarm?.call(id);
    }
    return null;
  }

  /// Cached for the process: the OS version does not change under us, and
  /// the sheets ask on every rebuild.
  bool? _supported;

  /// What each slot was scheduled with, so a foreground ring can be shown
  /// as the notification it would otherwise have been. Only this process's
  /// schedules are known; an alarm scheduled by an earlier launch that
  /// rings with the app open shows its title alone.
  final _scheduled =
      <int, ({String title, String? subtitle, String kind, String targetId})>{};

  /// The words and target of a slot this process scheduled, if any.
  ({String title, String? subtitle, String kind, String targetId})? scheduledFor(
          int id) =>
      _scheduled[id];

  static bool get _isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Whether this device can ring a real alarm at all (iOS 26 or newer).
  /// Says nothing about permission; see [isAuthorized].
  Future<bool> isSupported() async {
    if (!_isIOS) return false;
    final cached = _supported;
    if (cached != null) return cached;
    try {
      return _supported =
          await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (e) {
      debugPrint('[AlarmService] support check skipped: $e');
      return _supported = false;
    }
  }

  /// Supported and granted, which is the only state [schedule] can succeed
  /// in. The person can withdraw the grant in Settings at any time, so this
  /// is asked again on every schedule rather than cached.
  Future<bool> isAuthorized() async {
    if (!await isSupported()) return false;
    try {
      return await _channel.invokeMethod<String>('authorizationState') ==
          'authorized';
    } catch (_) {
      return false;
    }
  }

  /// Shows the system alarm permission sheet the first time, and answers
  /// the stored decision after that. True when alarms may be scheduled.
  ///
  /// Android has no such permission for the alarm-style channel, so it is
  /// true there: the chooser that calls this must not stall on it.
  Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    if (defaultTargetPlatform == TargetPlatform.android) return true;
    if (!await isSupported()) return false;
    try {
      return await _channel.invokeMethod<bool>('requestAuthorization') ??
          false;
    } catch (e) {
      debugPrint('[AlarmService] permission request failed: $e');
      return false;
    }
  }

  /// Schedules one alarm under [id] at [fireAt], replacing any alarm already
  /// under that id. [title] is the ringing screen's headline (the habit or
  /// task name), [subtitle] the line under it. [kind] is 'habit' or 'task'
  /// and [targetId] the habit or task id the alarm is about. [stopLabel] is
  /// the Stop button's text in the app's language (iOS 26.1 and later draw
  /// their own Stop and ignore it). [doneLabel] adds the second button,
  /// which records the task as done, and is for tasks only: without it the
  /// alarm carries Stop alone, as every habit alarm does.
  ///
  /// False whenever the alarm could not be made: unsupported, permission
  /// missing, a moment already past, or a native failure. The caller then
  /// schedules its notification for the slot instead, so the reminder is
  /// never silently lost.
  Future<bool> schedule({
    required int id,
    required DateTime fireAt,
    required String title,
    String? subtitle,
    required String kind,
    required String targetId,
    String? doneLabel,
    required String stopLabel,
  }) async {
    if (!await isSupported()) return false;
    _scheduled[id] = (
      title: title,
      subtitle: subtitle,
      kind: kind,
      targetId: targetId,
    );
    try {
      return await _channel.invokeMethod<bool>('schedule', {
            'id': id,
            'fireAtMs': fireAt.millisecondsSinceEpoch,
            'title': title,
            if (subtitle != null) 'subtitle': subtitle,
            'kind': kind,
            'targetId': targetId,
            if (doneLabel != null) 'doneLabel': doneLabel,
            'stopLabel': stopLabel,
          }) ??
          false;
    } catch (e) {
      debugPrint('[AlarmService] schedule $id failed: $e');
      return false;
    }
  }

  /// Makes every alarm with an id in [lowId]..[highId] exactly [alarms], in
  /// one native call: anything that range holds and [alarms] does not name
  /// is cancelled, and an alarm already armed at the same moment with the
  /// same words is left alone. This is the far end of an alarm reminder's
  /// window (NotificationService.kAlarmWindowDays), which is too many ids to
  /// schedule and cancel one call at a time on every resume.
  ///
  /// Returns the bridge's counts (scheduled, kept, cancelled, failed), or
  /// null where there are no real alarms or the call failed. An alarm that
  /// fails here has no notification fallback on purpose: the near days of
  /// the same reminder already have one, and a month of notifications would
  /// not fit in iOS's 64-request budget.
  Future<Map<String, int>?> syncWindow({
    required int lowId,
    required int highId,
    required List<WindowAlarm> alarms,
  }) async {
    if (!await isSupported()) return null;
    _scheduled.removeWhere((id, _) => id >= lowId && id <= highId);
    for (final a in alarms) {
      _scheduled[a.id] = (
        title: a.title,
        subtitle: a.subtitle,
        kind: a.kind,
        targetId: a.targetId,
      );
    }
    try {
      return await _channel.invokeMapMethod<String, int>('syncWindow', {
        'lowId': lowId,
        'highId': highId,
        'alarms': [
          for (final a in alarms)
            {
              'id': a.id,
              'fireAtMs': a.fireAt.millisecondsSinceEpoch,
              'title': a.title,
              if (a.subtitle != null) 'subtitle': a.subtitle,
              'kind': a.kind,
              'targetId': a.targetId,
              'stopLabel': a.stopLabel,
            },
        ],
      });
    } catch (e) {
      debugPrint('[AlarmService] window sync skipped: $e');
      return null;
    }
  }

  /// Removes the alarm under [id], if any. Safe to call for a slot that
  /// never held one, which is the common case: every notification schedule
  /// clears its slot's alarm so a reminder switched back from alarm to
  /// notification does not ring twice.
  Future<void> cancel(int id) async {
    _scheduled.remove(id);
    if (!await isSupported()) return;
    try {
      await _channel.invokeMethod<void>('cancel', {'id': id});
    } catch (e) {
      debugPrint('[AlarmService] cancel $id skipped: $e');
    }
  }
}
