/// How one habit's day is stored in the `habit_history` mirror, and how it is
/// read back.
///
/// ── Why the mirror grew from a flag to a mark ──────────────────────────
/// The mirror used to store `{dateKey: 1}`: presence only, written exactly
/// when a square landed on complete or bonus. That answered the one question
/// the year strip asked ("was this day green"), and it made every other state
/// invisible to every report. A day someone deliberately marked تخطّي and a
/// day they never opened the app were the same absence, so a rest day counted
/// against them exactly like a miss.
///
/// Storing the state instead costs nothing: still one document per habit,
/// still roughly one read for a whole account. It is the same [SquareState]
/// the Grid paints and Rooms scores, so the four surfaces cannot drift into
/// four different vocabularies for the same square.
library;

import '../../grid/models/square_state.dart';

/// Reads a stored mirror value.
///
/// Legacy values are plain numbers: every account backfilled before marks
/// existed holds `1` on its done days, and `SquareState.fromJson` would parse
/// that to [SquareState.none] and silently erase every one of them. That is
/// the bug this function exists to make impossible, so it is the ONLY way
/// mirror values are read.
SquareState markFromStored(Object? raw) {
  if (raw is num) return raw > 0 ? SquareState.complete : SquareState.none;
  final text = raw?.toString();
  if (text == null || text.isEmpty) return SquareState.none;
  // '1' also arrives as a string key value in the guest store.
  final asNumber = num.tryParse(text);
  if (asNumber != null) {
    return asNumber > 0 ? SquareState.complete : SquareState.none;
  }
  return SquareState.fromJson(text);
}

/// What gets written back.
String markToStored(SquareState state) => state.toJson();

/// The mark for one habit on one day, derived from a raw daily document.
///
/// One precedence rule, in one place, so the mirror and anything reading day
/// documents directly can never disagree:
///
///  1. A green square wins. complete and bonus are recorded as painted, so
///     bonus keeps its flavour rather than flattening to complete.
///  2. Otherwise a positive completion count means complete. This is the arm
///     that covers habits finished from Today, which never paint a square.
///  3. Otherwise the painted square stands, which is how partial, failed and
///     skipped survive at all.
///  4. Otherwise nothing was recorded.
///
/// Rule 2 sitting above rule 3 is deliberate: a habit actually completed is
/// complete even if some earlier tap left the square on skipped, because a
/// completion is a fact and a square is a label.
SquareState dayMark(Map<String, dynamic> dailyDoc, String habitId) {
  // 'habitCompletions' is the field daily docs actually store. The STATE
  // field is called completions, the DOC field is not, and reading the wrong
  // one leaves this whole arm dead against production data.
  final completions =
      (dailyDoc['habitCompletions'] as Map?)?.cast<String, dynamic>();
  final count = completions?[habitId];
  final squares = (dailyDoc['squareStates'] as Map?)?.cast<String, dynamic>();
  final painted = SquareState.fromJson(squares?[habitId]?.toString());

  if (painted.isGreen) return painted;
  if (count is num && count > 0) return SquareState.complete;
  return painted;
}

/// Whether [mark] counts toward what was actually achieved.
///
/// Exactly [SquareState.isGreen], named here so report code reads as report
/// code. complete and bonus only: partial earns credit through
/// [markCredit], not by being called done.
bool markIsDone(SquareState mark) => mark.isGreen;

/// Whether [mark] means "this day should not be counted against anyone".
///
/// Only تخطّي. A skipped day leaves the denominator entirely, which is the
/// whole point of having the state: the app's position is that a rest day is
/// not a missed day, and until now the arithmetic disagreed with the slogan.
bool markIsRest(SquareState mark) => mark == SquareState.skipped;

/// How much of a day's obligation [mark] discharges.
///
/// The 0.5 for partial is not invented here: the Grid's own daily completion
/// ratio has scored partial at 0.5 since before these reports existed (see
/// WeeklyGridState.todayCompletionRatio). Using a different weight would have
/// made the same day worth two different amounts on two screens.
double markCredit(SquareState mark) => switch (mark) {
      SquareState.complete || SquareState.bonus => 1,
      SquareState.partial => 0.5,
      SquareState.none || SquareState.failed || SquareState.skipped => 0,
    };


/// Overlays TODAY's live truth onto history read from the mirror.
///
/// The mirror is a cache of the daily documents, written by three writers,
/// one of them fire-and-forget. For settled days it is authoritative. For
/// today it can lag or miss a write, and the reports then contradict the Grid
/// about a day the user is looking at on both screens.
///
/// [squareToday] and [completionsToday] are the same two records the mirror is
/// built from, passed as callbacks so this stays free of any dependency on the
/// Grid's state type and can be tested with plain maps.
///
/// [gridKnowsToday] is the guard that makes this safe, and it is not optional.
/// WeeklyGridState.squareFor returns none for any day outside the week it has
/// loaded, and paging the Grid back a week clears its states entirely. Without
/// the guard, browsing to last week and opening the reports would DELETE
/// today's تخطّي, جزئي and فشل from the day sheet, because "the Grid says
/// none" and "the Grid has not loaded today" are indistinguishable from here.
/// A habit with a completion behind it would survive, which is exactly why the
/// bug would have been invisible on the habits anyone tests with.
///
/// So: an assertion is always safe to apply, a CLEARANCE only when the Grid
/// can actually speak for today.
Map<String, Map<String, SquareState>> withLiveToday({
  required Map<String, Map<String, SquareState>> mirrored,
  required Iterable<String> habitIds,
  required SquareState Function(String habitId) squareToday,
  required int Function(String habitId) completionsToday,
  required String todayKey,
  required bool gridKnowsToday,
}) {
  final out = <String, Map<String, SquareState>>{
    for (final entry in mirrored.entries) entry.key: {...entry.value},
  };
  for (final id in habitIds) {
    // The same precedence [dayMark] documents, on live data: a green square
    // wins, then a positive completion count, then whatever the square says.
    final square = squareToday(id);
    final live = square.isGreen
        ? square
        : completionsToday(id) > 0
            ? SquareState.complete
            : square;
    if (live == SquareState.none) {
      if (gridKnowsToday) (out[id] ??= <String, SquareState>{}).remove(todayKey);
    } else {
      (out[id] ??= <String, SquareState>{})[todayKey] = live;
    }
  }
  return out;
}
