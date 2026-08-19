// The today/tomorrow boundary of the prayer anchor chips.
//
// The rule under test: a chip resolves to TODAY's prayer time when it is
// still ahead, and to TOMORROW's OWN computed time once it has passed —
// never today's time plus 24 hours, because prayer times drift daily and
// the entire value of anchoring is landing on the real moment.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/services/prayer_times_service.dart';
import 'package:grow_daily_v2/features/matrix/widgets/prayer_anchor_chips.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Bahrain'));
  });

  tz.TZDateTime at(DateTime day, int h, int m) =>
      tz.TZDateTime(tz.local, day.year, day.month, day.day, h, m);

  PrayerDayTimes timesFor(DateTime day) => PrayerDayTimes(
        fajr: at(day, 3, 49),
        sunrise: at(day, 5, 11),
        dhuhr: at(day, 11, 43),
        // Drifts by a minute across the boundary, so the "tomorrow is not
        // today plus 24h" assertion below has something real to bite on.
        asr: at(day, 15, day.day.isEven ? 12 : 11),
        maghrib: at(day, 18, 12),
        isha: at(day, 19, 32),
      );

  test('a prayer still ahead today anchors today', () {
    final now = DateTime(2026, 8, 19, 10, 0);
    final anchor = resolvePrayerAnchor(
      prayerKey: 'maghrib',
      now: now,
      timesFor: timesFor,
    );
    expect(anchor.day, 19);
    expect(anchor.hour, 18);
    expect(anchor.minute, 12);
  });

  test('a prayer already passed anchors tomorrow, recomputed for tomorrow',
      () {
    final now = DateTime(2026, 8, 19, 20, 0); // after isha? no: isha 19:32
    final anchor = resolvePrayerAnchor(
      prayerKey: 'asr',
      now: now,
      timesFor: timesFor,
    );
    expect(anchor.day, 20);
    expect(anchor.minute, 12, reason: "the 20th is even: tomorrow's OWN asr");
    final today = timesFor(now).asr;
    expect(anchor.difference(today).inMinutes, isNot(24 * 60),
        reason: 'must not be today plus a flat 24h');
  });

  test('exactly-now counts as passed — an anchor must be schedulable', () {
    final now = DateTime(2026, 8, 19, 18, 12);
    final anchor = resolvePrayerAnchor(
      prayerKey: 'maghrib',
      now: now,
      timesFor: timesFor,
    );
    expect(anchor.day, 20);
  });

  test('fajr after midnight but before its time anchors the same day', () {
    final now = DateTime(2026, 8, 19, 1, 30);
    final anchor = resolvePrayerAnchor(
      prayerKey: 'fajr',
      now: now,
      timesFor: timesFor,
    );
    expect(anchor.day, 19);
    expect(anchor.hour, 3);
  });

  test('an unknown key degrades to an hour ahead, never a crash', () {
    final now = DateTime(2026, 8, 19, 10, 0);
    final anchor = resolvePrayerAnchor(
      prayerKey: 'sunset',
      now: now,
      timesFor: timesFor,
    );
    expect(anchor, now.add(const Duration(hours: 1)));
  });
}
