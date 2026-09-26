import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/weekly_note_offer_provider.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/push_notification_service.dart';
import '../../../core/theme/game_theme.dart';
import '../../habits/catalog/habit_plans.dart' show reminderTimeProvider;
import '../models/notification_settings.dart';
import '../notifiers/notification_settings_notifier.dart';
import '../../../shared/widgets/app_snackbar.dart';

/// Everything the app can notify someone about, and every knob to tune or
/// turn off each category — the "all in settings, and the user can turn it
/// off" surface. Pushed from Profile's "Notifications" row, which replaces
/// the old inline Daily Reminder row (that setting now lives inside here
/// instead, alongside everything else notification-related).
///
/// The place prayer times are worked out from is not here any more. It was
/// the first row of a prayer-reminder section until 2026-09-25, when it moved
/// to its own page, Settings › موقع الصلاة (PrayerLocationScreen), with the
/// read-only calculation method beside it: the place feeds the prayer widget
/// and prayer habits too, and Aziz wanted a plainer way to pick it.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final settings = ref.watch(notificationSettingsProvider);
    final notifier = ref.read(notificationSettingsProvider.notifier);

    void update(NotificationSettings Function(NotificationSettings) f) =>
        notifier.update(f);

    return Scaffold(
      backgroundColor: gp.bg,
      appBar: AppBar(
        backgroundColor: gp.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(
          s.notificationsTitle,
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800, color: gp.textPrimary),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          // Renders ONLY when the OS itself is blocking this app's
          // notifications — the one failure mode every toggle below is
          // powerless against, and the one this screen used to be silent
          // about (see NotificationService.checkSystemPermission).
          const _SystemPermissionBanner(),
          _Card(children: [
            _SwitchRow(
              icon: Icons.notifications_rounded,
              label: s.notifMasterTitle,
              subtitle: s.notifMasterDesc,
              value: settings.masterEnabled,
              onChanged: (v) => update((c) => c.copyWith(masterEnabled: v)),
            ),
          ]),
          const SizedBox(height: 20),
          AnimatedOpacity(
            opacity: settings.masterEnabled ? 1 : 0.4,
            duration: GameMotion.standard,
            child: IgnorePointer(
              ignoring: !settings.masterEnabled,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionLabel(s.notifWhatSection),
                  _Card(children: [
                    _SwitchRow(
                      icon: Icons.notifications_active_rounded,
                      label: s.notifHabitReminders,
                      subtitle: s.notifHabitRemindersDesc,
                      value: settings.habitRemindersEnabled,
                      onChanged: (v) =>
                          update((c) => c.copyWith(habitRemindersEnabled: v)),
                    ),
                    const _RowDivider(),
                    _SwitchRow(
                      icon: Icons.local_fire_department_rounded,
                      label: s.notifStreakRisk,
                      subtitle: s.notifStreakRiskDesc,
                      value: settings.streakRiskEnabled,
                      onChanged: (v) =>
                          update((c) => c.copyWith(streakRiskEnabled: v)),
                    ),
                    const _RowDivider(),
                    _SwitchRow(
                      icon: Icons.grid_view_rounded,
                      label: s.notifMatrixNudge,
                      subtitle: s.notifMatrixNudgeDesc,
                      value: settings.matrixNudgeEnabled,
                      onChanged: (v) =>
                          update((c) => c.copyWith(matrixNudgeEnabled: v)),
                    ),
                    const _RowDivider(),
                    _SwitchRow(
                      icon: Icons.layers_rounded,
                      label: s.notifBundle,
                      subtitle: s.notifBundleDesc,
                      value: settings.bundleEnabled,
                      onChanged: (v) =>
                          update((c) => c.copyWith(bundleEnabled: v)),
                    ),
                    const _RowDivider(),
                    _SwitchRow(
                      icon: Icons.calendar_view_week_rounded,
                      label: s.notifWeeklyDigest,
                      subtitle: s.notifWeeklyDigestDesc,
                      value: settings.weeklyNoteOn,
                      // Either way this is the person's answer, so the
                      // recap card stops asking (weekly_note_offer_provider).
                      onChanged: (v) {
                        update((c) => c.copyWith(weeklyNoteOn: v));
                        markWeeklyNoteOfferAnswered(ref);
                      },
                    ),
                    const _RowDivider(),
                    // The one push category this app sends from a server
                    // rather than scheduling locally - see
                    // NotificationSettings.roomActivityEnabled's own doc
                    // comment. A specific room can also be muted on its own
                    // (the room's app-bar bell) without touching this
                    // master switch for every room at once.
                    _SwitchRow(
                      icon: Icons.groups_rounded,
                      label: s.notifRoomActivity,
                      subtitle: s.notifRoomActivityDesc,
                      value: settings.roomActivityEnabled,
                      onChanged: (v) =>
                          update((c) => c.copyWith(roomActivityEnabled: v)),
                    ),
                    // Directly under the switch it explains, because the
                    // switch alone was the lie: it read "on" while nothing
                    // could arrive.
                    _RoomPushStatus(
                      roomActivityEnabled: settings.roomActivityEnabled,
                    ),
                  ]),
                  const SizedBox(height: 20),
                  // The prayer place moved to its own page on 2026-09-25
                  // (Settings › موقع الصلاة, PrayerLocationScreen): it feeds
                  // the prayer widget and prayer habits, not only reminders.
                  _SectionLabel(s.notifQuietHoursSection),
                  _Card(children: [
                    _SwitchRow(
                      icon: Icons.bedtime_rounded,
                      label: s.notifQuietHours,
                      subtitle: s.notifQuietHoursDesc,
                      value: settings.quietHoursEnabled,
                      onChanged: (v) =>
                          update((c) => c.copyWith(quietHoursEnabled: v)),
                    ),
                    if (settings.quietHoursEnabled) ...[
                      const _RowDivider(),
                      _TimeRow(
                        icon: Icons.nightlight_round,
                        label: s.notifQuietStart,
                        time: settings.quietHoursStart,
                        onTap: () async {
                          final picked = await showTimePicker(
                              context: context,
                              initialTime: settings.quietHoursStart,
                              // Force 12-hour AM/PM regardless of the
                              // device's 24-hour system setting, so the
                              // picker looks the same on every phone.
                              builder: (context, child) => MediaQuery(
                                    data: MediaQuery.of(context)
                                        .copyWith(alwaysUse24HourFormat: false),
                                    child: child!,
                                  ));
                          if (picked != null) {
                            update((c) => c.copyWith(quietHoursStart: picked));
                          }
                        },
                      ),
                      const _RowDivider(),
                      _TimeRow(
                        icon: Icons.wb_sunny_rounded,
                        label: s.notifQuietEnd,
                        time: settings.quietHoursEnd,
                        onTap: () async {
                          final picked = await showTimePicker(
                              context: context,
                              initialTime: settings.quietHoursEnd,
                              builder: (context, child) => MediaQuery(
                                    data: MediaQuery.of(context)
                                        .copyWith(alwaysUse24HourFormat: false),
                                    child: child!,
                                  ));
                          if (picked != null) {
                            update((c) => c.copyWith(quietHoursEnd: picked));
                          }
                        },
                      ),
                      const _RowDivider(),
                      _SwitchRow(
                        icon: Icons.mosque_rounded,
                        label: s.notifQuietAppliesToPrayer,
                        subtitle: s.notifQuietAppliesToPrayerDesc,
                        value: settings.quietHoursAppliesToPrayer,
                        onChanged: (v) => update(
                            (c) => c.copyWith(quietHoursAppliesToPrayer: v)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 20),
                  _SectionLabel(s.notifTimingSection),
                  // The daily reminder's time is the evening note's only
                  // clock. The "streak check time" row beside it was a
                  // fallback clock used when no time was picked; nothing is
                  // sent without one now (Aziz, 2026-09-24), so it had
                  // nothing left to set.
                  const _Card(children: [
                    _DailyReminderRow(),
                  ]),
                ],
              ),
            ),
          ),
          // OUTSIDE the masterEnabled IgnorePointer, deliberately.
          //
          // This is the diagnostic that deliberately bypasses every in-app
          // gate to ask the OS "would a notification actually appear right
          // now" — so putting it inside the block that dims and disables
          // everything when notifications are off made it unreachable in
          // precisely the situation it was built for. Someone whose
          // reminders had stopped could not run the one check that explains
          // why.
          const SizedBox(height: 28),
          Center(
            child: TextButton.icon(
              onPressed: () => _sendTestNotification(context),
              icon: const Icon(Icons.send_rounded, size: 16),
              label: Text(s.notifSendTest),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _sendTestNotification(BuildContext context) async {
  final s = S.of(context);
  await NotificationService.instance.showTest(isAr: s.isAr);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showOne(
    SnackBar(
        content: Text(s.notifTestSent), duration: const Duration(seconds: 3)),
  );
}

/// The original Daily Reminder row, moved here from Profile unchanged in
/// behavior (same reminderTimeProvider, same permission-denied snackbar) —
/// just relocated so every notification-related setting lives in one place.
class _DailyReminderRow extends ConsumerWidget {
  const _DailyReminderRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final reminderTime = ref.watch(reminderTimeProvider);
    return InkWell(
      onTap: () async {
        HapticFeedback.selectionClick();
        final picked = await showTimePicker(
          context: context,
          initialTime: reminderTime ?? const TimeOfDay(hour: 20, minute: 0),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
            child: child!,
          ),
        );
        if (picked != null) {
          final granted =
              await ref.read(reminderTimeProvider.notifier).set(picked);
          if (!granted && context.mounted) {
            ScaffoldMessenger.of(context).showOne(
              SnackBar(
                content: Text(s.reminderPermissionDenied),
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      },
      onLongPress: reminderTime == null
          ? null
          : () async {
              HapticFeedback.mediumImpact();
              await ref.read(reminderTimeProvider.notifier).clear();
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.notifications_rounded, size: 20, color: gp.textSec),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(s.dailyReminder,
                      style: TextStyle(
                          fontSize: 15,
                          color: gp.textPrimary,
                          fontWeight: FontWeight.w500)),
                  Text(
                    reminderTime == null
                        ? s.tapToSetReminder
                        : reminderTime.format(context),
                    style: TextStyle(fontSize: 12, color: gp.textTert),
                  ),
                ],
              ),
            ),
            if (reminderTime != null)
              Icon(Icons.chevron_right_rounded, size: 18, color: gp.textTert),
          ],
        ),
      ),
    );
  }
}

/// The "iOS/Android has this app's notifications switched off" warning —
/// rendered at the very top of Notification Settings, and only when the OS

/// The delivery chain behind the room-activity switch, in plain words.
///
/// This exists because of a specific complaint that could not be answered:
/// "I never get a room notification." Every in-app switch read on, the Cloud
/// Function ran hourly and logged success, and nothing arrived. The missing
/// link was a device token that had never been registered, and NOTHING
/// anywhere said so. A switch that reads "on" while delivery is impossible is
/// worse than no switch, because it ends the investigation.
///
/// Three facts, in delivery order, and it names the FIRST one that is false
/// rather than listing everything: permission, then a registered device, then
/// the category switch. Re-checked on resume, like [_SystemPermissionBanner]
/// above, since the fix for the first two happens outside the app.
///
/// Deliberately quiet when everything is fine: one green line, no card, no
/// icon competing with the switch it sits under. A diagnosis screen that
/// shouts when there is nothing wrong is just more noise.
class _RoomPushStatus extends ConsumerStatefulWidget {
  final bool roomActivityEnabled;
  const _RoomPushStatus({required this.roomActivityEnabled});

  @override
  ConsumerState<_RoomPushStatus> createState() => _RoomPushStatusState();
}

class _RoomPushStatusState extends ConsumerState<_RoomPushStatus>
    with WidgetsBindingObserver {
  PushDeliveryStatus? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void didUpdateWidget(_RoomPushStatus old) {
    super.didUpdateWidget(old);
    if (old.roomActivityEnabled != widget.roomActivityEnabled) _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final status = await PushNotificationService.instance.deliveryStatus(
      roomActivityEnabled: widget.roomActivityEnabled,
    );
    if (mounted) setState(() => _status = status);
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    // Unknown renders nothing: a wrong diagnosis is worse than none, the
    // same rule _SystemPermissionBanner follows.
    if (status == null) return const SizedBox.shrink();
    final gp = context.gp;
    final s = S.of(context);

    if (status.canDeliver) {
      return Padding(
        padding: const EdgeInsetsDirectional.only(
            start: 52, end: 16, bottom: 12),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded,
                size: 14, color: context.gp.emeraldInk),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                s.notifRoomPushReady,
                style: TextStyle(fontSize: 11.5, color: gp.textSec),
              ),
            ),
          ],
        ),
      );
    }

    // First broken link only. Listing all three would make somebody fix the
    // wrong one.
    final needsSystemSettings = !status.permissionGranted;
    final message = !status.permissionGranted
        ? s.notifRoomPushNoPermission
        : !status.tokenRegistered
            ? s.notifRoomPushNoToken
            : s.notifRoomPushCategoryOff;

    return Padding(
      padding:
          const EdgeInsetsDirectional.only(start: 52, end: 16, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 14, color: context.gp.warningInk),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                      fontSize: 11.5, color: gp.textSec, height: 1.35),
                ),
              ),
            ],
          ),
          if (needsSystemSettings) ...[
            const SizedBox(height: 6),
            GestureDetector(
              // Not launchUrl('app-settings:'): that scheme is iOS-only and
              // silently did nothing on Android, so this link was dead on
              // exactly the platform the surrounding warning is about. See
              // NotificationService.openSystemNotificationSettings.
              onTap: () =>
                  NotificationService.instance.openSystemNotificationSettings(),
              child: Text(
                s.notifOpenSystemSettings,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: context.gp.goldInk,
                  decoration: TextDecoration.underline,
                  decorationColor: context.gp.goldInk,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// itself is blocking delivery (see NotificationService.checkSystemPermission,
/// and the real incident described there: every in-app toggle read "on",
/// every schedule call "succeeded", and the system silently dropped all of
/// it, test button included). Re-checks on every app resume, because the fix
/// this banner sends someone to make happens in system Settings — the moment
/// they come back is exactly the moment it should disappear.
class _SystemPermissionBanner extends StatefulWidget {
  const _SystemPermissionBanner();

  @override
  State<_SystemPermissionBanner> createState() =>
      _SystemPermissionBannerState();
}

class _SystemPermissionBannerState extends State<_SystemPermissionBanner>
    with WidgetsBindingObserver {
  // null = unknown/not-yet-checked, which renders nothing: a wrong warning
  // is worse than a missing one, so only an explicit "false" shows it.
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final enabled = await NotificationService.instance.checkSystemPermission();
    if (mounted) setState(() => _enabled = enabled);
  }

  @override
  Widget build(BuildContext context) {
    if (_enabled != false) return const SizedBox.shrink();
    final s = S.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: GameColors.error.withOpacity(0.1),
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          border: Border.all(color: GameColors.error.withOpacity(0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notifications_off_rounded,
                    size: 18, color: context.gp.errorInk),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.notifSystemPermissionOff,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                      color: context.gp.errorInk,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () async {
                  HapticFeedback.selectionClick();
                  // Prompt first, Settings only as a fallback - see
                  // NotificationService.ensureSystemPermission. On Android
                  // 13+ this banner's state is simply the default for a
                  // fresh install, so the fix is usually one system dialog.
                  //
                  // This used to call launchUrl('app-settings:') directly,
                  // an iOS-only scheme that silently did nothing on Android.
                  await NotificationService.instance.ensureSystemPermission();
                  if (mounted) _check();
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  s.notifSystemPermissionOffAction,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: context.gp.errorInk,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: context.gp.textSec,
            letterSpacing: 1.5,
          ),
        ),
      );
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Column(children: children),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) =>
      Container(height: 0.5, color: context.gp.divider);
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: gp.textSec),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 15,
                        color: gp.textPrimary,
                        fontWeight: FontWeight.w500)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      style: TextStyle(
                          fontSize: 12, color: gp.textTert, height: 1.3)),
                ],
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeTrackColor: GameColors.emerald,
            onChanged: (v) {
              HapticFeedback.selectionClick();
              onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final TimeOfDay time;
  final VoidCallback onTap;

  const _TimeRow({
    required this.icon,
    required this.label,
    required this.time,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: gp.textSec),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 15,
                      color: gp.textPrimary,
                      fontWeight: FontWeight.w500)),
            ),
            Text(time.format(context),
                style: TextStyle(
                    fontSize: 13,
                    color: gp.textSec,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, size: 18, color: gp.textTert),
          ],
        ),
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String valueLabel;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;

  const _StepperRow({
    required this.icon,
    required this.label,
    required this.valueLabel,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        children: [
          const SizedBox(width: 6),
          Icon(icon, size: 20, color: gp.textSec),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 15,
                    color: gp.textPrimary,
                    fontWeight: FontWeight.w500)),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onDecrement,
            icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
          ),
          SizedBox(
            width: 88,
            child: Text(
              valueLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: gp.textSec),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onIncrement,
            icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}
