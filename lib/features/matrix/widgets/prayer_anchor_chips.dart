import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/services/prayer_times_service.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/choice_chip_grid.dart';
import '../../settings/notifiers/notification_settings_notifier.dart';

/// One tap from prayer to anchor.
///
/// Task reminders are absolute clock moments, and in an app whose day is
/// organised around الصلاة that meant "ذكرني قبل المغرب بنصف ساعة" cost
/// about seven taps THROUGH two stock Material dialogs, plus knowing what
/// time Maghrib actually is today. These chips collapse that to one tap:
/// pick the prayer, and the anchor becomes its next occurrence — today if
/// it hasn't passed, tomorrow if it has — computed from the same
/// PrayerTimesService the habit cues use (which in Bahrain means the
/// Kingdom's own published timetable). The existing قبل/بعد offset grid
/// then does what it always did, so "half an hour before" is one more tap.
///
/// Deliberately FREE, per the roadmap: prayer anchoring is the mission,
/// not the upsell. The existing stacking gate (one reminder free) is what
/// monetizes wanting قبل الفجر AND بعد المغرب on the same task.
///
/// Renders nothing when no prayer location is configured — a chip that
/// answers "we don't know where you are" would be a dead end here; the
/// person sets location once in Settings and these appear everywhere.
class PrayerAnchorChips extends ConsumerWidget {
  /// Receives the resolved anchor moment.
  final void Function(DateTime anchor) onPicked;
  final Color color;

  const PrayerAnchorChips({
    super.key,
    required this.onPicked,
    required this.color,
  });

  static const _prayers = ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'];

  String _label(String key, bool isAr) => switch (key) {
        'fajr' => isAr ? 'الفجر' : 'Fajr',
        'dhuhr' => isAr ? 'الظهر' : 'Dhuhr',
        'asr' => isAr ? 'العصر' : 'Asr',
        'maghrib' => isAr ? 'المغرب' : 'Maghrib',
        _ => isAr ? 'العشاء' : 'Isha',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final settings = ref.watch(notificationSettingsProvider);
    final location = settings.location;
    if (location == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Text(
          s.matrixPrayerAnchorHint,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: gp.textTert,
          ),
        ),
        const SizedBox(height: 8),
        // 5 chips on a 3-column grid (3 + 2) — the same control and
        // geometry as the offset grid that will appear right here once an
        // anchor exists, so the two read as one flow.
        ChoiceChipGrid(
          columns: 3,
          items: [
            for (final key in _prayers)
              PlainChoiceChip(
                selected: false,
                label: _label(key, s.isAr),
                selectedColor: color,
                onTap: () {
                  HapticFeedback.selectionClick();
                  final anchor = resolvePrayerAnchor(
                    prayerKey: key,
                    now: DateTime.now(),
                    timesFor: (date) =>
                        PrayerTimesService.calculateOfflineCorrected(
                      latitude: location.lat,
                      longitude: location.lng,
                      date: date,
                      madhab: settings.madhab,
                      countryCode: settings.resolvedCountryCode,
                    ),
                  );
                  onPicked(anchor);
                },
              ),
          ],
        ),
      ],
    );
  }
}

/// The next occurrence of [prayerKey] as of [now]: today's time if it is
/// still ahead, otherwise tomorrow's — recomputed for tomorrow's own date,
/// never today's time plus 24h, because prayer times drift by a minute or
/// two per day and the whole point of anchoring is landing on the real
/// moment.
///
/// Top-level and pure ([timesFor] injected) so the today/tomorrow boundary
/// is testable without a real location or timezone database.
DateTime resolvePrayerAnchor({
  required String prayerKey,
  required DateTime now,
  required PrayerDayTimes Function(DateTime date) timesFor,
}) {
  final today = timesFor(now).forKey(prayerKey);
  if (today != null && today.isAfter(now)) return today;
  // The next CALENDAR day, not now+24h: across a DST spring-forward a
  // 24-hour hop can skip straight past a short day's early prayer. (No
  // DST in Bahrain, but the code shouldn't know that.)
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  return timesFor(tomorrow).forKey(prayerKey) ??
      // forKey only returns null for an unknown key, which callers here
      // never pass — but a wrong constant must degrade to "an hour from
      // now", not a crash inside a tap handler.
      now.add(const Duration(hours: 1));
}
