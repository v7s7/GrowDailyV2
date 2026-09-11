import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../extensions/datetime_ext.dart';

/// The next instant at which any day's settled state can change: the moment
/// yesterday closes (DateTimeGameExt.closesAt) when that is still ahead of
/// [now], otherwise the coming midnight.
///
/// A day's answers change only when it starts, at its own midnight, and
/// when it closes. Every day before yesterday has already closed, and today
/// closes after the coming midnight, so those two instants are the only
/// ones DateTimeGameExt.isOpenDayAt, isSettledAt and effectiveDay can move
/// at, and a clock re-read at each of them answers every "is this day still
/// open" question exactly as reading DateTime.now() on every build would.
///
/// Read off closesAt rather than a wall-clock [kDayCutoffHour]. The two are
/// the same instant on every ordinary day; on a day a daylight-saving change
/// runs through, yesterday closes an hour either side of 10:00, and a timer
/// armed for 10:00 would fire an hour early and find nothing changed, or an
/// hour late.
DateTime nextDayBoundaryAfter(DateTime now) {
  final midnight = DateTime(now.year, now.month, now.day + 1);
  final yesterdayCloses =
      DateTime(now.year, now.month, now.day - 1).closesAt;
  return yesterdayCloses.isAfter(now) && yesterdayCloses.isBefore(midnight)
      ? yesterdayCloses
      : midnight;
}

/// Whether a day clock read at [seen] may now answer some day question
/// differently from the wall clock at [now]: a day boundary
/// (nextDayBoundaryAfter) has been reached since, or the clock has moved
/// backwards.
///
/// What main.dart asks on resume before re-reading [dayClockProvider]. A
/// re-read always hands out a new instant, and a DateTime never equals a
/// later one, so re-reading on every resume rebuilt every watcher, and the
/// Insights screen and the Progress tab's preview start their 56-document
/// read inside build. Between two boundaries nothing any watcher derives
/// from the clock can differ (see nextDayBoundaryAfter), so skipping the
/// re-read then changes no number on screen.
///
/// Not seen: a time zone the phone travelled into while suspended. A
/// DateTime keeps only its instant, so [seen] cannot say which zone it was
/// read in, and such a screen keeps the old zone's day answers until the
/// provider's own timer fires, at most one boundary later. Before the day
/// clock existed no report noticed a new zone at all.
bool dayClockIsStale({required DateTime seen, required DateTime now}) =>
    now.isBefore(seen) || !now.isBefore(nextDayBoundaryAfter(seen));

/// Where [dayClockProvider] reads the time: DateTime.now, and only a test
/// overrides it, so the boundary timer can be driven under a fake clock
/// (test/core/providers/day_clock_provider_test.dart).
final dayClockSourceProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);

/// The wall clock every surface that asks "is this day still open" reads,
/// re-read by itself at each day boundary (midnight, and the moment
/// yesterday closes at [kDayCutoffHour]; see nextDayBoundaryAfter).
///
/// Aziz, 2026-09-11: a report must not count a day that is still open as
/// missed, and must count it once it closes. A screen that only reads
/// DateTime.now() when something else rebuilds it would keep showing the
/// pre-10:00 number to someone who left the report open across 10:00, so
/// the clock itself triggers the rebuild. Same self-refreshing timer
/// premiumAccessProvider uses for the end of a trial.
///
/// Only the DAY answers derived from this value are exact between
/// boundaries; the instant itself is as old as the last boundary, so never
/// print it as a time. A suspended app's timer can fire late, which is why
/// main.dart also re-reads this on resume once dayClockIsStale says a
/// boundary has passed.
final dayClockProvider = Provider<DateTime>((ref) {
  final now = ref.watch(dayClockSourceProvider)();
  final wait = nextDayBoundaryAfter(now).difference(now);
  final timer = Timer(wait + const Duration(seconds: 1), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return now;
});

/// What main.dart runs when the app resumes: re-reads [dayClockProvider] in
/// [container] once dayClockIsStale says a day boundary has passed since it
/// was last read, and leaves it untouched otherwise. Returns whether it
/// re-read.
///
/// The provider's own timer does not run while the app is suspended, so a
/// phone put away at 09:00 and opened at 11:00 would still hold yesterday
/// open. Only on a boundary, because a fresh instant never equals the old
/// one: an unconditional re-read rebuilt every watcher on every resume, and
/// the Insights screen and the Progress tab's preview re-fetched their 56
/// daily documents for answers that had not changed.
///
/// Here rather than inline in main.dart so the condition can be tested
/// (test/core/providers/day_clock_provider_test.dart).
bool refreshDayClockIfStale(ProviderContainer container) {
  final stale = dayClockIsStale(
    seen: container.read(dayClockProvider),
    now: container.read(dayClockSourceProvider)(),
  );
  if (stale) container.invalidate(dayClockProvider);
  return stale;
}
