import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/services/country_lookup_service.dart';
import '../../../core/services/device_location_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/prayer_times_service.dart';
import '../../../core/theme/game_theme.dart';
import '../../habits/catalog/habit_plans.dart' show reminderTimeProvider;
import '../models/notification_settings.dart';
import '../notifiers/notification_settings_notifier.dart';
import '../widgets/city_search_sheet.dart';

/// Everything the app can notify someone about, and every knob to tune or
/// turn off each category — the "all in settings, and the user can turn it
/// off" surface. Pushed from Profile's "Notifications" row, which replaces
/// the old inline Daily Reminder row (that setting now lives inside here
/// instead, alongside everything else notification-related).
///
/// Location for prayer-time calculation is auto-detected via on-device GPS
/// (tapping the location row - see [_LocationRow]/DeviceLocationService),
/// with typed city search ([showCitySearchSheet]/GeocodingService) as the
/// fallback for denied permission, disabled location services, or simply
/// wanting a different city (long-press the row) — e.g. while traveling.
/// Either path resolves to one lat/lng pair cached in [NotificationSettings.
/// location] — no location permission or search needed again. A country
/// code for that same pair (`NotificationSettings.resolvedCountryCode`) is
/// resolved right alongside it via CountryLookupService, feeding
/// [PrayerTimesService.resolveRegion]'s global-coverage tier — see that
/// function's doc comment. [PrayerTimesService] then fetches the actual 5
/// daily times from a live prayer-times API for that pair (falling back to
/// an offline calculation with no connection), so no further location
/// prompts are ever needed, just a network call at scheduling time.
///
/// The calculation method itself is *not* user-editable — it used to be a
/// 12-option picker, but [PrayerTimesService.resolveRegion] now auto-selects
/// it from the saved location (a hand-verified recipe for each of the 6 GCC
/// countries, a documented-but-not-independently-verified one for roughly
/// 17 more, and a plain global default everywhere else — see that
/// function's doc comment), so there's nothing left for a picker to
/// meaningfully change.
/// [_InfoRow] below shows the resolved method read-only, next to
/// [NotificationSettings.madhab] (also currently display-only here — no
/// switch edits it yet, it's fixed at its Shafi default).
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final isAr = s.isAr;
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
            duration: const Duration(milliseconds: 200),
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
                      icon: Icons.celebration_rounded,
                      label: s.notifCelebrations,
                      subtitle: s.notifCelebrationsDesc,
                      value: settings.celebrationsEnabled,
                      onChanged: (v) =>
                          update((c) => c.copyWith(celebrationsEnabled: v)),
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
                  ]),
                  const SizedBox(height: 20),
                  _SectionLabel(s.notifPrayerSection),
                  _Card(children: [
                    _LocationRow(location: settings.location),
                    const _RowDivider(),
                    _InfoRow(
                      icon: Icons.explore_rounded,
                      label: s.notifCalcMethod,
                      value: settings.location == null
                          ? s.notifLocationNotSet
                          : '${PrayerTimesService.resolveRegion(settings.location!.lat, settings.location!.lng, countryCode: settings.resolvedCountryCode).method.label(isAr)} · ${settings.madhab.label(isAr)}',
                    ),
                    const _RowDivider(),
                    _StepperRow(
                      icon: Icons.timer_outlined,
                      label: s.notifPrayerOffset,
                      valueLabel: s.minutesAfterPrayer(settings.prayerOffsetMinutes),
                      onDecrement: settings.prayerOffsetMinutes > 0
                          ? () => update((c) => c.copyWith(
                              prayerOffsetMinutes:
                                  (c.prayerOffsetMinutes - 5).clamp(0, 60)))
                          : null,
                      onIncrement: settings.prayerOffsetMinutes < 60
                          ? () => update((c) => c.copyWith(
                              prayerOffsetMinutes:
                                  (c.prayerOffsetMinutes + 5).clamp(0, 60)))
                          : null,
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      settings.hasLocation
                          ? s.notifLocationManualHint
                          : s.notifLocationHint,
                      style: TextStyle(fontSize: 12, color: gp.textTert, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 20),
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
                              context: context, initialTime: settings.quietHoursStart);
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
                              context: context, initialTime: settings.quietHoursEnd);
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
                  _Card(children: [
                    _DailyReminderRow(),
                    const _RowDivider(),
                    _TimeRow(
                      icon: Icons.local_fire_department_outlined,
                      label: s.notifStreakRiskTime,
                      time: settings.streakRiskTime,
                      onTap: () async {
                        final picked = await showTimePicker(
                            context: context, initialTime: settings.streakRiskTime);
                        if (picked != null) {
                          update((c) => c.copyWith(streakRiskTime: picked));
                        }
                      },
                    ),
                  ]),
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
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(s.notifTestSent), duration: const Duration(seconds: 3)),
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
        );
        if (picked != null) {
          final granted = await ref.read(reminderTimeProvider.notifier).set(picked);
          if (!granted && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
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
                          fontSize: 15, color: gp.textPrimary, fontWeight: FontWeight.w500)),
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

/// Prayer location row — tap auto-detects via on-device GPS
/// ([DeviceLocationService]), long-press opens the manual city-search sheet
/// directly. On a failed/denied/timed-out detection, the tap path falls
/// back to that same manual sheet automatically (with a snackbar explaining
/// why) rather than just dead-ending on an error, so one tap always gets
/// somewhere usable. A location, once set either way, is just a lat/lng —
/// nothing downstream cares which path produced it.
///
/// No reverse-geocoding: a GPS fix is labeled with its own rounded
/// coordinates (see [DeviceLocationFix]'s doc comment) rather than a looked-
/// up city name, so this stays a single new permission/package instead of
/// two.
class _LocationRow extends ConsumerStatefulWidget {
  final NotificationLocation? location;
  const _LocationRow({required this.location});

  @override
  ConsumerState<_LocationRow> createState() => _LocationRowState();
}

class _LocationRowState extends ConsumerState<_LocationRow> {
  bool _detecting = false;

  Future<void> _openManualSearch() async {
    final picked = await showCitySearchSheet(context);
    if (!mounted || picked == null) return;
    ref
        .read(notificationSettingsProvider.notifier)
        .update((c) => c.copyWith(location: picked));
    _resolveCountryInBackground(picked.lat, picked.lng);
  }

  Future<void> _detect() async {
    HapticFeedback.selectionClick();
    setState(() => _detecting = true);
    final outcome = await DeviceLocationService.detect();
    if (!mounted) return;
    setState(() => _detecting = false);

    if (outcome.isSuccess) {
      final fix = outcome.fix!;
      // Coordinates are NEVER shown to the user — the label starts as a
      // localized "finding your location…" placeholder, becomes the real
      // «المنامة، البحرين» name the moment the reverse lookup resolves,
      // and degrades to a plain "Location set" if that lookup fails. The
      // raw lat/lng still power every calculation underneath; they just
      // never appear as text.
      ref.read(notificationSettingsProvider.notifier).update((c) => c.copyWith(
            location: NotificationLocation(
              lat: fix.latitude,
              lng: fix.longitude,
              label: S.of(context).notifLocationResolving,
            ),
          ));
      _resolveCountryInBackground(fix.latitude, fix.longitude,
          updateLabel: true);
      return;
    }

    final s = S.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(s.notifLocationDetectFailed),
        duration: const Duration(seconds: 3),
      ),
    );
    await _openManualSearch();
  }

  /// Fire-and-forget, deliberately not awaited by either call site above:
  /// the location itself is already set and on screen by the time this
  /// runs, so the country code (needed only for PrayerTimesService.
  /// resolveRegion's global fallback tier, not for this row's own display)
  /// resolves quietly in the background rather than making the user wait
  /// on a second network round-trip before the location row updates.
  ///
  /// Re-reads the settings' current location right before writing and
  /// discards the result if it no longer matches [lat]/[lng] — guards
  /// against a slower-to-resolve lookup from an earlier location
  /// overwriting a newer one that's since replaced it (e.g. GPS-detect
  /// immediately followed by a manual re-search, before the first lookup
  /// has returned). Silently a no-op on a failed lookup too — see
  /// CountryLookupService.lookup's doc comment.
  /// [updateLabel] is true only for the GPS-detect path, whose initial
  /// label is a raw-coordinates placeholder worth replacing with the
  /// resolved "City, Country" name; a manually-searched city keeps the
  /// exact label the user picked.
  Future<void> _resolveCountryInBackground(double lat, double lng,
      {bool updateLabel = false}) async {
    final s = S.of(context);
    final place = await CountryLookupService.lookupPlace(lat, lng,
        languageCode: s.isAr ? 'ar' : 'en');
    if (!mounted) return;
    final current = ref.read(notificationSettingsProvider).location;
    if (current == null || current.lat != lat || current.lng != lng) return;
    // Whatever happens, the "finding your location…" placeholder must not
    // survive: real place name when the lookup succeeded, a plain
    // "Location set" when it didn't — never raw coordinates.
    final newLabel = place.label ?? s.notifLocationSetGeneric;
    ref.read(notificationSettingsProvider.notifier).update((c) => c.copyWith(
          resolvedCountryCode: place.code ?? c.resolvedCountryCode,
          location: updateLabel
              ? NotificationLocation(lat: lat, lng: lng, label: newLabel)
              : c.location,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return InkWell(
      onTap: _detecting ? null : _detect,
      onLongPress: _detecting
          ? null
          : () {
              HapticFeedback.mediumImpact();
              _openManualSearch();
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.location_on_rounded, size: 20, color: gp.textSec),
            const SizedBox(width: 12),
            Expanded(
              child: Text(s.prayerLocationTitle,
                  style: TextStyle(
                      fontSize: 15, color: gp.textPrimary, fontWeight: FontWeight.w500)),
            ),
            if (_detecting) ...[
              SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: gp.textTert),
              ),
              const SizedBox(width: 6),
              Text(s.notifDetectingLocation,
                  style: TextStyle(
                      fontSize: 13, color: gp.textSec, fontWeight: FontWeight.w600)),
            ] else ...[
              Flexible(
                child: Text(
                  widget.location?.label ?? s.notifLocationNotSet,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13, color: gp.textSec, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.my_location_rounded, size: 16, color: gp.textTert),
            ],
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
                        fontSize: 15, color: gp.textPrimary, fontWeight: FontWeight.w500)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      style: TextStyle(fontSize: 12, color: gp.textTert, height: 1.3)),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
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

class _NavRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _NavRow({
    required this.icon,
    required this.label,
    required this.value,
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
                      fontSize: 15, color: gp.textPrimary, fontWeight: FontWeight.w500)),
            ),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: gp.textSec, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, size: 18, color: gp.textTert),
          ],
        ),
      ),
    );
  }
}

/// A [_NavRow] twin for a value that's shown but not tappable — the
/// calculation-method line, now that it's auto-resolved from location
/// rather than a picker (see NotificationSettingsScreen's doc comment and
/// [PrayerTimesService.resolveRegion]). Same layout minus the InkWell/
/// chevron, so it still reads as "part of this list" and not visually
/// demoted, just clearly not an action.
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 20, color: gp.textSec),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 15, color: gp.textPrimary, fontWeight: FontWeight.w500)),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: gp.textSec, fontWeight: FontWeight.w600),
            ),
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
                      fontSize: 15, color: gp.textPrimary, fontWeight: FontWeight.w500)),
            ),
            Text(time.format(context),
                style: TextStyle(fontSize: 13, color: gp.textSec, fontWeight: FontWeight.w600)),
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
                    fontSize: 15, color: gp.textPrimary, fontWeight: FontWeight.w500)),
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
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: gp.textSec),
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
