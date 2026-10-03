import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../shared/widgets/overlay_notice.dart';
import '../../habits/models/habit_cue.dart';
import '../../habits/widgets/habit_offset_sheet.dart';
import '../../settings/notifiers/notification_settings_notifier.dart';
import '../../settings/widgets/city_search_sheet.dart';
import '../task_prayer.dart';

/// A task's reminder set by a prayer, the habit way (Aziz, 2026-10-03:
/// "he can choose, like 15 before, it should be well designed and easy to
/// use, same as habit reminder"): the prayer sheet Add Habit uses
/// (showPrayerSlotSheet), with the five prayers and their times on [day],
/// «قبل | بعد», and the amounts «في الوقت · 5 · 10 · 15 · 30 · ساعة» or a
/// typed one. A tap on an amount sets it, so «بعد العصر بـ15 دقيقة» is the
/// prayer, the side and 15.
///
/// Opens on [current] when the task already has one, else on the next
/// prayer of the day (nextTaskPrayer), on «بعد»: a task "after Asr" is the
/// usual case. A pair whose moment has already gone is refused inside the
/// sheet with «اختر وقتًا في المستقبل», the wheel's own words, so a task
/// can never be given a past time this way either.
///
/// Returns the pair and the moment it lands on, or null when the sheet is
/// closed, or no prayer place could be found.
Future<({PrayerSlot prayer, DateTime at})?> pickTaskPrayerReminder(
  BuildContext context,
  WidgetRef ref, {
  required DateTime day,
  PrayerSlot? current,
}) async {
  if (!await ensurePrayerPlace(context, ref) || !context.mounted) return null;
  final settings = ref.read(notificationSettingsProvider);
  final s = S.of(context);
  final options = <PrayerSlotOption>[
    for (final key in kTaskPrayers)
      (
        key: key,
        label: HabitCue.preset(key).labelForLocale(s.isAr),
        at: switch (prayerMomentOn(key, day, settings)) {
          final at? => TimeOfDay.fromDateTime(at),
          null => null,
        },
      ),
  ];
  final picked = await showPrayerSlotSheet(
    context,
    title: s.reminderWithPrayer,
    prayers: options,
    prayer: current?.prayer ?? nextTaskPrayer(day, settings, DateTime.now()),
    current: current?.offset,
    refuse: (prayer, offset) {
      final at = taskPrayerMoment((prayer: prayer, offset: offset), day, settings);
      return at == null || at.isAfter(DateTime.now())
          ? null
          : s.matrixReminderPast;
    },
  );
  final slot = picked?.slot;
  if (slot == null) return null;
  final at = taskPrayerMoment(slot, day, settings);
  // The clock can cross the moment while the sheet is open.
  if (at == null || !at.isAfter(DateTime.now())) {
    if (context.mounted) {
      showOverlayNotice(
        context,
        s.matrixReminderPast,
        icon: Icons.history_toggle_off_rounded,
      );
    }
    return null;
  }
  return (prayer: slot, at: at);
}

/// The reminder row's words for [prayer]: «في وقت العصر», «بعد العصر بـ15
/// دقيقة», «قبل الفجر بساعة». The sentence Add Habit's rows say
/// (habitReminderSentence), so a habit and a task word a prayer alike.
String taskPrayerSentence(PrayerSlot prayer, S s) => habitReminderSentence(
      prayer.offset,
      s,
      prayer: HabitCue.preset(prayer.prayer).labelForLocale(s.isAr),
    );

/// True when a prayer place is saved, finding one first when it is not:
/// the phone's own location, else the city search, the way Add Habit asks
/// when a prayer is picked with no place (_ensureLocationForPrayerCue).
/// Overlay notices, not SnackBars: both callers are modal sheets, and a
/// SnackBar draws behind them.
Future<bool> ensurePrayerPlace(BuildContext context, WidgetRef ref) async {
  if (ref.read(notificationSettingsProvider).location != null) return true;
  final s = S.of(context);
  showOverlayNotice(
    context,
    s.notifLocationResolving,
    icon: Icons.my_location_rounded,
  );
  final outcome = await detectAndSaveLocation(
    ref,
    isAr: s.isAr,
    resolvingLabel: s.notifLocationResolving,
    genericLabel: s.notifLocationSetGeneric,
    isMounted: () => context.mounted,
  );
  if (!context.mounted) return false;
  if (outcome.isSuccess) return true;
  showOverlayNotice(
    context,
    s.notifLocationDetectFailed,
    icon: Icons.location_off_rounded,
  );
  final picked = await showCitySearchSheet(context);
  if (!context.mounted || picked == null) return false;
  await ref
      .read(notificationSettingsProvider.notifier)
      .update((c) => c.copyWith(location: picked));
  return true;
}
