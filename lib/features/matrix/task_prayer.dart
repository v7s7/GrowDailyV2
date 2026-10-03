import '../../core/services/prayer_times_service.dart';
import '../habits/models/habit_cue.dart' show PrayerSlot;
import '../settings/models/notification_settings.dart';

export '../habits/models/habit_cue.dart' show PrayerSlot;

/// The five prayers a task reminder can ride on, in the day's order.
const kTaskPrayers = ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'];

/// [prayer]'s moment on [day] where the person is ([settings]' prayer
/// place), on the phone's clock and to the minute; null with no place
/// saved. The offline table the habit pills and the prayer page read
/// (Bahrain's official one in Bahrain), so a task says the same Asr as
/// everything else in the app, and it answers at once, with no network.
DateTime? prayerMomentOn(
  String prayer,
  DateTime day,
  NotificationSettings settings,
) {
  final loc = settings.location;
  if (loc == null) return null;
  final at = PrayerTimesService.calculateOfflineCorrected(
    latitude: loc.lat,
    longitude: loc.lng,
    date: DateTime(day.year, day.month, day.day),
    countryCode: settings.resolvedCountryCode,
  ).forKey(prayer)?.toLocal();
  if (at == null) return null;
  return DateTime(at.year, at.month, at.day, at.hour, at.minute);
}

/// The moment a task reminder set by [prayer] lands on [day]: the prayer's
/// time there plus its signed minutes. Null with no place saved.
DateTime? taskPrayerMoment(
  PrayerSlot prayer,
  DateTime day,
  NotificationSettings settings,
) =>
    prayerMomentOn(prayer.prayer, day, settings)
        ?.add(Duration(minutes: prayer.offset));

/// The prayer the prayer sheet opens on for [day]: the first whose time of
/// day is still ahead of [now]'s, so at 5 PM it is Maghrib or Isha, on any
/// day; Fajr once Isha has gone. What someone adding a task in the
/// afternoon most likely means by "after the prayer".
String nextTaskPrayer(
  DateTime day,
  NotificationSettings settings,
  DateTime now,
) {
  final minuteOfDay = now.hour * 60 + now.minute;
  for (final p in kTaskPrayers) {
    final at = prayerMomentOn(p, day, settings);
    if (at != null && at.hour * 60 + at.minute > minuteOfDay) return p;
  }
  return kTaskPrayers.first;
}
