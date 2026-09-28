import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../../core/extensions/datetime_ext.dart';

// ─── A room's short quota week ────────────────────────────────────────────
//
// A room grades a flexible weekly quota over the Grid's Saturday-to-Friday
// weeks, and a room rarely starts on a Saturday or ends on a Friday. A week
// the room only partly covers keeps the habit's whole target, cut down only
// when the week has fewer days than that. F8HQKE «بزنس مِن» (30 days, Sunday
// 27 September to Monday 26 October, تمرين 4x) asks 4 in its first six days
// and 3 in its last three: three workouts in a row on a habit that is four
// times a week, 19 sessions in 30 days where the habit's own pace is about 17.
//
// Aziz, 2026-09-27: a short week asks its share of the target instead, the
// days the room asks of it over seven, rounded, never less than one. That
// room's first week would ask 3 and its last 2. Waiting for a Saturday to
// start would not have fixed it (30 days is four weeks and two days, so the
// short week only moves to the end), and giving each room its own week would
// put one session in different weeks on the Grid and in the room again, the
// mismatch the Saturday weeks were introduced to end.
//
// BUILT AND SWITCHED OFF (2026-09-28). Each member's phone grades its own
// record, so the share only counts on phones that have it: a member on an
// older build keeps being asked the whole target in the same week, on a
// ranked board. The same reason kWeeklyShareEnabled is held off in
// rooms_notifier.dart. The start week is Aziz's call, a Saturday after the
// build that carries it is on members' phones; until then every week asks
// exactly what it did before.

/// The first Grid week, as its Saturday's date key, in which a short week
/// asks its share; null keeps the share off everywhere. Every earlier week
/// keeps the whole target, so no week that had already closed moves when it
/// is switched on: a member's phone regrades the last 45 days on every open
/// (kRoomSyncWindowDays), and closed short weeks sit inside that window
/// (BKWVN9's first week, 19 to 21 August, three days at 3 of 3).
const String? kRoomQuotaShareFromWeekKey = null;

/// Stands in for [kRoomQuotaShareFromWeekKey] in tests, which grade the
/// share while the app keeps it off. Null in the app.
@visibleForTesting
String? debugRoomQuotaShareFromWeekKey;

/// Whether the Grid week holding [day] is graded with the share: on or after
/// [kRoomQuotaShareFromWeekKey], never while that is null. Counted in
/// calendar days, not Durations (see RoomParticipant._saturdayOn).
bool roomQuotaWeekHasShare(DateTime day) {
  final from = debugRoomQuotaShareFromWeekKey ?? kRoomQuotaShareFromWeekKey;
  if (from == null) return false;
  final saturday = DateTime(
    day.year,
    day.month,
    day.day - (day.weekday - DateTime.saturday + 7) % 7,
  );
  return saturday.toDateKey().compareTo(from) >= 0;
}

/// What a flexible weekly quota of [target] asks of one room week: the Grid
/// week holding [day], counted over the days the room asks the habit of this
/// member, from [firstDay] (the later of the member's first counted day and
/// the day the habit joined their plan) through [lastDay] (the room's last
/// day, null for a room with no end).
///
/// The whole target for a week the room asks every day of. For a shorter
/// one, target x days / 7 rounded, at least one and never more than the days:
/// 4x over six days asks 3, over three days 2, over one day 1. A 4x week
/// cannot land on a half, nor can any target up to 6 over fewer than seven
/// days, so the rounding never has a tie to break. A week without the share
/// ([roomQuotaWeekHasShare]) keeps the whole target.
///
/// Only the room's own edges make a week short here: its start, its end, a
/// member joining late and a habit added to the plan mid-week. A pause, a
/// stand-down or a leader's removal does not; every caller still caps what
/// this returns at the days the habit was actually present for, as it always
/// has. That cap is also what keeps a week in progress from being handed rest
/// days early: the sync grades an open week over the days so far, so a share
/// taken of those would read a 4x week as met on its third day.
///
/// Known edge, left for when the share is switched on: a room's last week
/// met by its share and banked in quotaOkWeeks stays banked if the leader
/// then extends the room, so for a member who never opens the app again the
/// days the extension adds to that week read as rest
/// (RoomParticipant.recordedScheduledCountFor). The whole target had the same
/// gap for a last week shorter than the target; the share widens it.
int roomQuotaWeekTarget({
  required int target,
  required DateTime day,
  required DateTime firstDay,
  DateTime? lastDay,
}) {
  if (!roomQuotaWeekHasShare(day)) return target;
  final saturday = DateTime(
    day.year,
    day.month,
    day.day - (day.weekday - DateTime.saturday + 7) % 7,
  );
  final first = DateTime(firstDay.year, firstDay.month, firstDay.day);
  final last =
      lastDay == null ? null : DateTime(lastDay.year, lastDay.month, lastDay.day);
  var days = 0;
  for (var i = 0; i < 7; i++) {
    final d = DateTime(saturday.year, saturday.month, saturday.day + i);
    if (d.isBefore(first)) continue;
    if (last != null && d.isAfter(last)) continue;
    days++;
  }
  // A week the room asks nothing of has no share to take; the callers never
  // grade one, and the whole target keeps what they did before.
  if (days >= 7 || days == 0) return target;
  return (target * days / 7).round().clamp(1, days);
}
