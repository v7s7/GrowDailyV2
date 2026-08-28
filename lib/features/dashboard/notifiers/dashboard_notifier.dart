import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/game_constants.dart';
import '../../../core/extensions/datetime_ext.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/services/local_store_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/utils/text_moderation.dart';
import '../../../core/utils/xp_calculator.dart';
import '../../../features/achievements/models/achievement_model.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../models/undone_completion.dart';
import '../../milestones/models/milestone_event.dart';
import '../../habits/catalog/islamic_habit_catalog.dart';
import '../../grid/models/square_state.dart';
import '../../milestones/reports/habit_day_marks.dart';
import 'package:flutter/foundation.dart' show debugPrint;

part 'dashboard_notifier_loading.dart';
part 'dashboard_notifier_complete_habit.dart';
part 'dashboard_notifier_uncomplete_habit.dart';
part 'dashboard_notifier_grid_rewards.dart';


/// Streak-day thresholds that trigger a milestone celebration, derived from
/// [GameConstants.streakBonuses] so the thresholds and their XP payouts
/// can't drift apart into two different lists.
final List<int> kStreakMilestones = GameConstants.streakBonuses.keys.toList();

/// One-time XP bonus for reaching [milestone] days — delegates to
/// [XpCalculator.streakMilestoneBonus] (backed by [GameConstants]) so this
/// isn't a second, independently-editable copy of the same numbers.
int milestoneXpBonus(int milestone) =>
    XpCalculator.streakMilestoneBonus(milestone);

/// Every `catch (_) {}` below a Firestore batch/set write in this file
/// calls this instead of silently discarding the error. Firestore's own
/// offline queue already covers a plain connectivity gap transparently —
/// the write sits in the local cache and syncs once the device is back
/// online, no app-level retry needed (see BUILD_LESSONS.md) — so this
/// isn't standing in for that. What it catches is a *real* rejection (a
/// rules change, an expired/invalid auth token, a quota limit, a malformed
/// field) that used to vanish with zero trace anywhere. Deliberately still
/// non-fatal and still swallowed from the caller's point of view after
/// this runs: every call site already applied its optimistic local
/// [state] update before attempting the write (see e.g. [completeHabit]'s
/// own doc comment), and reverting that on a write failure would yank
/// away XP/gold/streak progress someone already saw and reacted to —
/// worse, for a rare failure, than a stray write that silently doesn't
/// reach Firestore this one time. Logging is strictly additive: it makes
/// that rare failure visible in Crashlytics without changing what the
/// user sees.
Future<void> _recordWriteFailure(
  String where,
  Object error,
  StackTrace stackTrace,
) {
  return FirebaseCrashlytics.instance.recordError(
    error,
    stackTrace,
    reason: 'dashboard_notifier.$where: Firestore write failed',
  );
}

/// The minimum fraction of today's scheduled habits that must be done for
/// the day to earn its streak point — see [willCompleteAllHabitsToday].
/// Deliberately not 1.0 (literal 100%): staying perfect every single day
/// of a long streak is unrealistic, and losing real progress over one
/// missed habit on an otherwise full day felt like a punishment for
/// nearly succeeding rather than a fair rule. 0.8 means "one slip on an
/// otherwise full day still counts," while a day that's mostly undone
/// still doesn't (1 of 6 done is 17% — nowhere near qualifying).
const double kStreakDayCompletionThreshold = 0.8;

/// The most a single day can PAY OUT from sources a user can repeat at will:
/// habit completions, grid squares, and every lump sum that comes through
/// [DashboardNotifier.awardBonus].
///
/// This is an anti-farming ceiling, not a difficulty knob. It is set well
/// clear of any honest day: a typical five-habit board pays about 170 XP and
/// 67 gold, and the heaviest realistic day measured (fifteen room-boosted
/// habits at the top reward tier, twenty tasks, every surprise bonus landing)
/// is about 2,200 XP and 835 gold. The floor below sits above that, so a
/// person who simply had a very good day never meets it.
///
/// It scales with the roster because habit count is the one honest way a day
/// gets bigger, and a flat ceiling would tax exactly the users doing the most
/// work. The floor protects the small board: nobody is capped below
/// [kDailyXpCapFloor] however few habits they run.
///
/// What it deliberately does NOT cover: achievements, both streak milestone
/// ladders, the comeback bonus, room claims and undo restores. Every one of
/// those is structurally once-per-lifetime or once-per-episode, so capping
/// them buys no safety, and swallowing one is unrecoverable in a way a capped
/// habit reward is not: an achievement id is written with arrayUnion into a
/// set that only grows, and the catalog filters out anything already in it,
/// so a payout lost to a cap can never be reclaimed by a later sweep.
const int kDailyXpCapFloor = 3000;
const int kDailyGoldCapFloor = 1000;
const int kDailyXpCapPerHabit = 150;
const int kDailyGoldCapPerHabit = 50;

/// How many Matrix tasks may PAY OUT in one day.
///
/// A tighter, separate bound because a task is the cheapest thing in the app
/// to manufacture: a line of text, ticked the same second, paying the same 20
/// XP and 8 gold as a habit somebody has kept for weeks. The paid-already
/// flag lives on the task itself, so deleting the task discards the flag and
/// the same reward can be collected again from a new one.
///
/// Fifteen is far past any real to-do list day and turns that lap from
/// unbounded into a rounding error. It is deliberately NOT a limit on how
/// many tasks may be created or completed: past the fifteenth, tasks still
/// tick and still count, they just stop paying.
const int kDailyRewardedTaskCap = 15;

/// Today's XP ceiling for a board of [habitCount] scheduled habits.
///
/// [habitCount] is today's scheduled roster, the same list that feeds
/// [willCompleteAllHabitsToday]. Callers that cannot cheaply produce it pass
/// nothing and get the floor, which is the safe direction to be wrong in: a
/// cap that is too generous costs a farmer some extra minutes, while a cap
/// that is too tight silently withholds a reward someone earned.
int dailyXpCapFor(int habitCount) {
  final scaled = kDailyXpCapPerHabit * habitCount;
  return scaled > kDailyXpCapFloor ? scaled : kDailyXpCapFloor;
}

/// Today's gold ceiling, on the same rule as [dailyXpCapFor].
int dailyGoldCapFor(int habitCount) {
  final scaled = kDailyGoldCapPerHabit * habitCount;
  return scaled > kDailyGoldCapFloor ? scaled : kDailyGoldCapFloor;
}

/// Whether completing [habitId] (today, toward [frequencyTarget]) leaves
/// today's scheduled habits at or above [kStreakDayCompletionThreshold] —
/// the completion-ratio moment that earns the day's streak point (see
/// [DashboardState.streakEarnedToday] and [DashboardNotifier.completeHabit]).
/// Name kept as-is (matching [DashboardNotifier.completeHabit]'s
/// `allHabitsDoneAfter` parameter, which every call site already spells
/// out by that name) rather than renamed for the threshold change — the
/// rule this answers is now "at or above the threshold," not literally
/// every habit.
///
/// [halfDoneHabitIds] are today's habits sitting on a جزئي square. They
/// count HALF, because half the work is worth half the credit everywhere
/// else in this app.
///
/// It is opt-in with an empty default on purpose. Only callers that actually
/// hold today's Grid squares can answer it, and a caller that cannot simply
/// gets exactly the behaviour it had before. This deliberately does NOT
/// create a new way to EARN a streak: a جزئي square never calls completeHabit,
/// so this predicate only ever runs when a real completion is landing anyway.
/// A day made entirely of half-done squares still earns nothing at all, which
/// is the property that keeps the streak honest.
///
/// [todayHabits] is today's scheduled habit list reduced to just the two
/// fields this needs (id + weekly target), passed in as records so this
/// stays free of any dependency on the habit catalog type — every caller
/// (DashboardScreen, the Grid screen, the notification action handler)
/// already has the real habit list in scope and can map it down to this
/// shape in one line.
bool willCompleteAllHabitsToday({
  required DashboardState state,
  required Iterable<({String id, int frequencyTarget})> todayHabits,
  required String habitId,
  required int frequencyTarget,
  Set<String> halfDoneHabitIds = const {},
}) {
  var sawTarget = false;
  var total = 0;
  var credited = 0.0;
  for (final h in todayHabits) {
    total++;
    final isTarget = h.id == habitId;
    if (isTarget) sawTarget = true;
    final done = isTarget
        ? (state.completions[h.id] ?? 0) + 1 >= frequencyTarget
        : state.isCompleted(h.id, h.frequencyTarget);
    if (done) {
      credited += 1;
    } else if (halfDoneHabitIds.contains(h.id)) {
      // A جزئي square is half a habit, the same 0.5 it is worth everywhere
      // else in this app. Three of four habits done plus one half done is
      // 87.5% rather than 75%, which crosses the threshold: exactly the
      // "nearly succeeded" case kStreakDayCompletionThreshold's own comment
      // says it exists to be kind to.
      credited += 0.5;
    }
  }
  // An empty (or habitId-missing) list never earns a streak point — a day
  // with nothing scheduled isn't a completed day, it's a day off.
  if (total == 0 || !sawTarget) return false;
  return credited / total >= kStreakDayCompletionThreshold;
}

/// How long an [UndoneCompletion] receipt stays redeemable.
///
/// Bounded so the map cannot grow forever on an account that undoes a lot and
/// never corrects any of it, and generous because the whole point is the
/// person who notices the mistake late. A year covers everything the yearly
/// strip can even show them.
const int kUndoneCompletionRetentionDays = 365;

/// Whole calendar days from [from] to [to], counted on the calendar rather
/// than in elapsed hours.
///
/// Via UTC on purpose: two local midnights 24 hours apart are 23 or 25 hours
/// apart across a DST change, and `.difference().inDays` truncates that to 0
/// or 1 accordingly. Every date in this file is a calendar day, so an hour of
/// wall clock must never be able to move one.
int daysBetweenDates(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;

/// This habit's streak once a completion lands today, given [gapDays] whole
/// days since its previous completion (null when it has never been completed)
/// and [previousStreak], the streak that previous completion ended on.
///
/// A gap of ZERO is the case worth naming. It means the stored last-completed
/// date already reads today, which happens exactly one way: an undo that found
/// no same-session snapshot leaves the per-habit streak fields alone rather
/// than guessing at them (see [DashboardNotifier.uncompleteHabit]), so they go
/// on describing today's completion after the completion itself is gone.
/// Re-ticking the habit then measures a gap of 0. Treating that like any other
/// non-1 gap restarted the streak at 1, which turned a long streak into a 1
/// for nothing but a mis-tap and an app restart in between. Today is already
/// counted inside [previousStreak], so the answer is [previousStreak] itself.
///
/// Pure so the rule is unit-testable without Firebase — see
/// test/features/dashboard/undo_restore_test.dart.
int nextHabitStreak({required int? gapDays, required int previousStreak}) =>
    switch (gapDays) {
      1 => previousStreak + 1,
      0 => previousStreak < 1 ? 1 : previousStreak,
      _ => 1,
    };

/// Whether a completion landing today with [gapDays] since the previous one
/// actually MOVED this habit's streak, and so whether it can pay a per-habit
/// milestone bonus.
///
/// False only for the gap-of-zero case above: that day's milestone was already
/// paid by the completion being put back and, with no snapshot, was never
/// refunded, so paying it again would pay twice for one day.
bool habitStreakAdvanced(int? gapDays) => gapDays != 0;

/// Whether the tap taking a habit from [doneBefore] to [doneBefore] + 1
/// should announce itself with the reward banner.
///
/// Only the tap that finishes the day does. The banner is an event — "this is
/// done, here is what it paid" — and a habit counted N times a day would fire
/// N of them otherwise.
///
/// The reason it is silence rather than a gentler cheer is that the app does
/// not know what the habit IS. Counted habits split cleanly into two kinds
/// that want opposite treatment: drinking water eight times is something a
/// person may well want encouraged, and taking medicine four times is
/// something no one should be congratulated for. One habit model cannot tell
/// them apart, and encouragement aimed at the second kind does not read as
/// neutral — it reads as the app misunderstanding what it is looking at.
/// A count going up is a statement of fact, and a fact is the only thing that
/// is right in both cases.
///
/// The cheerful case loses nothing: the finishing tap still fires exactly the
/// banner the habit fired when it was once a day. And at a [target] of 1 this
/// is always true, so nothing that predates counting is affected.
bool completionAnnouncesItself({
  required int doneBefore,
  required int target,
}) =>
    doneBefore + 1 >= target;

/// What a habit's streak fields should become once a completion that was
/// undone on [restoredDay] is put back, or null when they should be left
/// exactly as they are.
///
/// Restoring a past day is the one moment the incremental streak counter can
/// be re-linked without reading a single day of history, because the receipt
/// already carries the missing half. [streakAtCompletion] says the restored
/// day ended a run of that many days. [currentStreak] and
/// [currentLastCompleted] describe the run built since. The two runs join if
/// and only if the newer one starts the very next day, and then the habit's
/// real streak is simply their sum.
///
/// Three outcomes, and the conservative one is the default:
///  - nothing newer exists (or the restored day IS the newest): the receipt's
///    own numbers are the truth, and the restored day becomes the last
///    completed day;
///  - the newer run starts the day after the restored one: the hole the undo
///    punched is exactly what was keeping them apart, so they merge;
///  - anything else: there is another gap in between that this function has
///    no business guessing about, so it changes nothing. A streak that stays
///    honestly short is recoverable; one invented from a guess is not.
///
/// Pure so the rule is unit-testable without Firebase — see
/// test/features/dashboard/undo_restore_test.dart.
({int streak, DateTime lastCompleted})? restoredHabitStreak({
  required DateTime restoredDay,
  required int streakAtCompletion,
  required int currentStreak,
  required DateTime? currentLastCompleted,
}) {
  if (streakAtCompletion <= 0) return null;
  final restored = DateTime(restoredDay.year, restoredDay.month, restoredDay.day);
  final last = currentLastCompleted == null
      ? null
      : DateTime(currentLastCompleted.year, currentLastCompleted.month,
          currentLastCompleted.day);

  if (last == null || restored.isAfter(last)) {
    return (streak: streakAtCompletion, lastCompleted: restored);
  }
  // The counters already describe a run ending on the very day being
  // restored, which is what an undo with no same-session snapshot leaves
  // behind (it declines to guess at the streak, so it never rolled it back).
  // Nothing to re-link.
  if (!restored.isBefore(last)) return null;
  if (currentStreak <= 0) return null;

  final chainStart = DateTime(last.year, last.month, last.day - (currentStreak - 1));
  if (daysBetweenDates(restored, chainStart) != 1) return null;
  return (
    streak: streakAtCompletion + currentStreak,
    lastCompleted: last,
  );
}

// Milestone flavor titles ("3-Day Starter", "بداية النشامى", ...) live in
// S.milestoneTitle (app_strings.dart) since they're locale-dependent —
// keeping them here would mean an English-only title bleeding into the
// Arabic UI.

/// A per-habit streak milestone just reached — carries enough context (which
/// habit, by name) for the celebration dialog to reference it by name,
/// unlike the app-wide [DashboardState.milestoneCelebration] which only
/// needs the day count since there's only one app-wide streak to talk about.
class HabitMilestoneEvent {
  final String habitId;
  final String habitName;
  final int milestone;
  final int bonusXp;

  const HabitMilestoneEvent({
    required this.habitId,
    required this.habitName,
    required this.milestone,
    required this.bonusXp,
  });
}

/// Exactly what a single habit's per-habit streak fields (and any bonus
/// tied to that one completion) looked like the instant *before*
/// [DashboardNotifier.completeHabit] changed them — kept around just long
/// enough for a same-session [DashboardNotifier.uncompleteHabit] call to
/// reverse them precisely instead of guessing.
///
/// Guessing is the thing this exists to avoid: [prevStreak] can't be
/// recovered from the post-completion state once it's been overwritten
/// (the streak-continuation rule needs to know the date/streak as they
/// were *before* today's bump, and after the bump `habitLastCompletedDate`
/// already reads as "today" either way). Without this snapshot, an undo
/// has no way to tell "this habit was on a 6-day streak" apart from "this
/// habit has never been completed before" — both look identical once
/// `completeHabit` has already run.
class _HabitCompletionSnapshot {
  /// False when this habit had never been completed before today's tap —
  /// [prevStreak]/[prevLongest]/[prevTotal] are meaningless zeros in that
  /// case, and reversing means removing the map entries entirely rather
  /// than restoring them to 0 (keeps a never-completed habit's maps free
  /// of stray zero entries, same as they'd look if it were never tapped).
  final bool hadPrior;
  final int prevStreak;
  final int prevLongest;
  final int prevTotal;
  final String? prevLastCompletedDate;

  /// Surprise-bonus + per-habit-milestone XP/Gold this one completion
  /// awarded on top of the habit's base xpReward/goldReward — deliberately
  /// excludes any app-wide streak-milestone bonus, which stays
  /// undo-proof by design (see [DashboardNotifier.uncompleteHabit]'s doc
  /// comment).
  final int bonusXp;
  final int bonusGold;

  const _HabitCompletionSnapshot({
    required this.hadPrior,
    required this.prevStreak,
    required this.prevLongest,
    required this.prevTotal,
    required this.prevLastCompletedDate,
    required this.bonusXp,
    required this.bonusGold,
  });

  /// The same snapshot with another tap's bonus folded in.
  ///
  /// Only the day's FIRST tap writes a snapshot, because only that tap
  /// changes the prev* fields an undo restores. The surprise bonus does not
  /// work that way — it rolls on every tap — so a habit counted several
  /// times a day accumulates bonuses that the one first-tap snapshot never
  /// heard about, and clearing the day then refunded less than it paid.
  _HabitCompletionSnapshot copyWithAddedBonus({
    required int xp,
    required int gold,
  }) =>
      _HabitCompletionSnapshot(
        hadPrior: hadPrior,
        prevStreak: prevStreak,
        prevLongest: prevLongest,
        prevTotal: prevTotal,
        prevLastCompletedDate: prevLastCompletedDate,
        bonusXp: bonusXp + xp,
        bonusGold: bonusGold + gold,
      );
}

class DashboardState {
  /// User-chosen display name, stored on the 'displayName' Firestore field
  /// that account creation already writes (defaulting to the email prefix —
  /// see AuthNotifier._createUserDoc). Empty until loaded or for a guest who
  /// hasn't set one yet; callers should fall back to something else (email
  /// prefix, 'Warrior') when this is blank rather than showing nothing.
  final String displayName;
  final int level;
  final int currentLevelXp;
  final int cumulativeXp;
  final int gold;
  final int streak;
  final int longestStreak;
  final int totalCompletions;
  final int streakFreezes;
  final Map<String, int> completions;

  /// Habits whose day-counters (totalCompletions, categoryCompletions,
  /// totalGreenSquares, dailyGreenCounts) have already been banked TODAY.
  ///
  /// The finishing tap banks them, an undo that takes a finished day back
  /// un-banks them, and completeHabit refuses to bank twice for the same
  /// habit-day. Without this receipt the check was `current >=
  /// frequencyTarget`, which forgets the day ever finished the moment its
  /// times-per-day target is raised: finish at 4/4, edit the target to 6,
  /// and the tap reaching 6 counted the SAME habit-day a second time in
  /// every lifetime stat and achievement threshold. Persisted on the daily
  /// doc as 'dayCounted' beside habitCompletions, so it scopes to today by
  /// construction and needs no sweeping.
  final Set<String> dayCountedHabitIds;
  final List<String> unlockedAchievements;
  final List<AchievementModel> newlyUnlocked;
  final bool didJustLevelUp;
  final bool didUseStreakFreeze;

  /// One-shot "every habit scheduled today is now done" event — set by
  /// [DashboardNotifier.completeHabit] on exactly the completion that
  /// finishes the day (the same justReachedAllDone moment that earns the
  /// streak point, so it can fire at most once per day and never from a
  /// backfilled past square). Same reset-by-default copyWith semantics as
  /// [didJustLevelUp]: any other state change clears it, so it can't stick
  /// and replay. Consumed by registerDashboardReactions' perfect-day
  /// celebration.
  final bool perfectDayCelebration;
  final String? lastCompletedId;
  final bool isLoading;

  /// True when [_loadToday] threw and this state is therefore
  /// [DashboardState.initial()]'s zeros rather than anything the server
  /// actually said.
  ///
  /// This exists because every field above is written back to Firestore as an
  /// ABSOLUTE value (see completeHabit's batch), not as an increment. A
  /// failed load that silently presents as "level 1, 0 XP, 0 gold, no streak"
  /// is therefore not merely a cosmetic wrong number on Profile — the next
  /// habit completion would persist those zeros over the real document and
  /// destroy the account's actual progress. Reward writes MUST refuse to run
  /// while this is set; there is nothing trustworthy to base them on.
  final bool loadFailed;

  /// Whether the progression numbers in this state actually came from
  /// somewhere, and may therefore be shown to the person they belong to.
  ///
  /// [loadFailed]'s own comment above explains why a failed load must never
  /// be WRITTEN back, and the reward writers have always honoured that. What
  /// nothing honoured was the other half: those same zeros were still being
  /// DRAWN, at full confidence, as "level 1, 0 XP, 0 gold, no streak". A
  /// twelfth-level account with 7,564 XP and a 10-day best therefore renders
  /// as a brand new one, indistinguishable from the real thing, for the
  /// whole cold-start window and permanently if the load failed. Someone
  /// who opens Profile in that window has no way to know they are looking at
  /// a placeholder, and the obvious conclusion, that their account has been
  /// wiped, is exactly the wrong one.
  ///
  /// [isLoading] is included and not merely [loadFailed] because the two are
  /// indistinguishable to a reader: an in-flight load and a failed one both
  /// show the same zeros, and only one of them will ever resolve itself.
  /// Any widget rendering a progression number should show a placeholder
  /// rather than a figure when this is false.
  bool get statsAreReal => !isLoading && !loadFailed;

  /// A streak gap the loader spotted but deliberately did NOT judge: the
  /// last day that earned a streak point, when more than one calendar day
  /// has passed since.
  ///
  /// The judgement needs the habit SCHEDULE and the loader does not have
  /// it. A day with nothing scheduled can never earn a streak point -
  /// willCompleteAllHabitsToday returns false on an empty list, by design,
  /// because "a day with nothing scheduled isn't a completed day, it's a
  /// day off" - so lastActiveDate simply does not advance across rest
  /// days. Counting raw calendar days therefore read every rest day as a
  /// miss: a Sat/Mon/Wed schedule burned a freeze on its first Sunday and
  /// lost the streak on the next one, and a 3x-a-week habit could never
  /// hold a streak at all.
  ///
  /// So the loader records the gap here and [DashboardNotifier.
  /// resolveStreakGap] decides once the habit list is actually available.
  /// Null means there is nothing outstanding to judge.
  final DateTime? pendingStreakGapFrom;

  /// The streak that was just lost to a missed day, still recoverable via
  /// [DashboardNotifier.useStreakFreeze] — 0 when there's nothing pending.
  /// Persisted (Firestore's 'previousStreak' field / the guest settings
  /// map), unlike the old design where this was recomputed fresh on every
  /// load and only "worked" for a single in-memory session: since
  /// `refresh()` re-runs on every app resume, a value that could only ever
  /// be derived once meant backgrounding the app before acting on the
  /// comeback card silently and permanently lost the offer. Cleared (set
  /// back to 0, both locally and in storage) by whichever comes first:
  /// [DashboardNotifier.useStreakFreeze], [DashboardNotifier.acknowledgeComeback],
  /// or simply earning a fresh streak day for real — see
  /// [DashboardNotifier.completeHabit]'s `clearsPendingComeback`.
  final int previousStreak;

  /// Whether the "you lost your streak" card should show — always exactly
  /// [previousStreak] > 0, so this can never drift out of sync with the
  /// value it's describing the way a separately-tracked bool could.
  bool get showComebackBonus => previousStreak > 0;

  final int? milestoneCelebration;
  final bool intentionsSetToday;

  /// Lifetime count of green (complete/bonus) squares ever colored on the
  /// Victory Grid — the "100 green squares completed" style achievements.
  final int totalGreenSquares;

  /// Whether *today* has already earned its once-per-day streak point.
  /// Streak means a day at or above [kStreakDayCompletionThreshold] of
  /// today's scheduled habits done (see [willCompleteAllHabitsToday]) —
  /// not just "did something today", so this is only ever set the instant
  /// that threshold is first reached. It's the single explicit gate
  /// [completeHabit] checks before bumping the streak, replacing what used
  /// to be three separate places each re-guessing "did today already
  /// count" from [completions]/grid state; one persisted boolean can't be
  /// fooled by reload timing the way an inferred guess could, and —
  /// because it can only flip false→true once per calendar day — it's
  /// also what guarantees the streak can never climb by more than 1 per
  /// day (so, e.g., 7 real days can never produce more than a 7-day
  /// streak). Deliberately sticky: once true, adding a *new* habit later
  /// today (which lowers today's completion percentage back below the
  /// threshold) does not revoke it — see [completeHabit]'s doc comment for
  /// why that's the intended behavior, not a bug.
  final bool streakEarnedToday;

  /// dateKey ('YYYY-MM-DD') → green squares colored that day, across all
  /// history. Kept as a flat rollup on the user doc so the monthly heatmap
  /// loads instantly regardless of how many years of data exist.
  final Map<String, int> dailyGreenCounts;

  /// What today has already PAID OUT from repeatable sources, against
  /// [dailyXpCapFor]. Stamped with the day it belongs to rather than kept as
  /// a dateKey map, because unlike [dailyGreenCounts] nothing ever reads a
  /// past day's figure: the cap only asks about now. A map would grow for the
  /// life of the account to answer a question no one asks.
  ///
  /// [earnedDayKey] is what makes the reset free. Read the pair through
  /// [earnedXpOn] and a new day reports zero on its own, on exactly the same
  /// cutoff boundary every other daily number already uses, with no scheduled reset
  /// to run and nothing to go stale when the app is left open overnight.
  final String earnedDayKey;
  final int earnedXpToday;
  final int earnedGoldToday;

  /// Matrix task payouts already made today, against [kDailyRewardedTaskCap].
  /// Stamped and read exactly like the earn counter above.
  final String rewardedTasksDayKey;
  final int rewardedTasksToday;

  /// How many streak freezes this account may BANK at once.
  ///
  /// Was a flat constant. It is per-user now because capacity above the
  /// starting three is purchasable, which is one of the few repeatable gold
  /// sinks the app has.
  ///
  /// Never read this directly: read [freezeCapacityOrDefault], which floors
  /// it at [DashboardNotifier.maxStreakFreezes]. A stored 0 is what every
  /// account written before this field existed looks like, and an account
  /// that silently lost two freeze slots on upgrade would be the exact
  /// "nothing may be taken from an existing user" failure this economy work
  /// has been avoiding all along.
  final int freezeCapacity;

  /// The highest level whose grant has already been paid.
  ///
  /// A monotone high-water mark, not a counter, which is what makes the
  /// grant impossible to pay twice: every payment covers the span
  /// (levelGrantPaidThrough, newLevel] and then moves the mark to newLevel.
  /// A multi-level jump pays each crossed level once, and a reload pays
  /// nothing because the mark is persisted in the same write map as `level`
  /// and so cannot land apart from it.
  ///
  /// SEEDED TO THE ACCOUNT'S CURRENT LEVEL on a document that has no such
  /// field, never to 1. Seeding to 1 would hand a level-60 account all
  /// twelve grants retroactively, which is the one way this design could
  /// take the economy somewhere nobody earned.
  final int levelGrantPaidThrough;

  /// Lifetime completions per habit category (e.g. 'quran' → 42), used to
  /// evaluate [AchievementTrigger.habitMastery] achievements.
  final Map<String, int> categoryCompletions;

  // ── Per-habit streaks ────────────────────────────────────────
  //
  // habitId → streak count as of habitLastCompletedDate[habitId]. This is
  // the *raw* persisted value — it only ever changes when that habit is
  // completed, so a habit that's gone stale (missed a day since) would keep
  // showing its old streak forever if read directly. Always read
  // [habitStreak] instead, which corrects for that.
  final Map<String, int> habitStreakCounts;
  final Map<String, int> habitLongestStreaks;
  final Map<String, int> habitTotalCompletions;
  // habitId → 'YYYY-MM-DD' of that habit's most recent completion.
  final Map<String, String> habitLastCompletedDate;

  /// Outstanding receipts for completions that were undone and could still be
  /// put back, keyed by [UndoneCompletion.keyFor] — see that class for what
  /// they are for and why they cannot be farmed. Written by
  /// [DashboardNotifier.uncompleteHabit], consumed by the next completion of
  /// the same habit-day, whether that lands on today through [completeHabit]
  /// or on an already-past square through
  /// [DashboardNotifier.restoreUndoneCompletion].
  final Map<String, UndoneCompletion> undoneCompletions;

  /// The receipt still owed for [habitId] on [dateKey], if any.
  UndoneCompletion? undoneFor(String habitId, String dateKey) =>
      undoneCompletions[UndoneCompletion.keyFor(habitId, dateKey)];

  /// What [dayKey] has already been paid from repeatable sources.
  ///
  /// Answers zero for any day that is not the stamped one, which is the whole
  /// reset mechanism: yesterday's total is not cleared, it simply stops being
  /// readable the moment [earnedDayKey] no longer matches. A stale stamp left
  /// by an app open across the cutoff boundary therefore reads as a fresh
  /// allowance rather than as yesterday's spent one.
  int earnedXpOn(String dayKey) => earnedDayKey == dayKey ? earnedXpToday : 0;

  int earnedGoldOn(String dayKey) => earnedDayKey == dayKey ? earnedGoldToday : 0;

  int rewardedTasksOn(String dayKey) =>
      rewardedTasksDayKey == dayKey ? rewardedTasksToday : 0;

  /// The bank cap, floored so it can never be smaller than it has always
  /// been. Covers every stored input a legacy or corrupt document can
  /// produce: absent, null, zero and negative all read as the original three.
  int get freezeCapacityOrDefault {
    if (freezeCapacity < DashboardNotifier.maxStreakFreezes) {
      return DashboardNotifier.maxStreakFreezes;
    }
    // Capped as well as floored: without this a hand-edited or corrupt
    // document storing 99 would be honoured as ninety-nine slots.
    if (freezeCapacity > DashboardNotifier.maxFreezeCapacity) {
      return DashboardNotifier.maxFreezeCapacity;
    }
    return freezeCapacity;
  }

  /// Set the instant a per-habit streak crosses a milestone (see
  /// [GameConstants.habitStreakBonuses]); cleared once the celebration
  /// dialog is dismissed. Not persisted — this is a one-shot UI cue, not
  /// data worth remembering across app restarts.
  final HabitMilestoneEvent? habitMilestoneCelebration;

  /// Bonus XP/Gold from the most recent completion's surprise-bonus roll
  /// (see [GameConstants.surpriseBonusChance]) — 0 when that completion
  /// didn't roll a bonus. Transient, like [lastCompletedId]: read once by
  /// the completion toast, then irrelevant until the next completion.
  final int lastCompletionBonusXp;
  final int lastCompletionBonusGold;

  /// When this account was created (Firestore's 'createdAt' field, set once
  /// by AuthNotifier._createUserDoc at sign-up) — the "day one" anchor
  /// JourneyPage renders as a synthetic first entry ahead of the real
  /// MilestoneEvent log, and the "member since" line on the Profile Legacy
  /// Shelf. Null while loading, and permanently null for a guest: local
  /// (Hive) storage never stamps a creation date today, so there's nothing
  /// to read — both surfaces above just omit their "since" framing rather
  /// than showing a wrong or made-up date.
  final DateTime? accountCreatedAt;

  const DashboardState({
    this.displayName = '',
    required this.level,
    required this.currentLevelXp,
    required this.cumulativeXp,
    required this.gold,
    required this.streak,
    this.longestStreak = 0,
    this.totalCompletions = 0,
    this.streakFreezes = 1,
    required this.completions,
    this.dayCountedHabitIds = const {},
    this.unlockedAchievements = const [],
    this.newlyUnlocked = const [],
    this.didJustLevelUp = false,
    this.didUseStreakFreeze = false,
    this.perfectDayCelebration = false,
    this.lastCompletedId,
    this.isLoading = false,
    this.loadFailed = false,
    this.pendingStreakGapFrom,
    this.previousStreak = 0,
    this.milestoneCelebration,
    this.intentionsSetToday = false,
    this.totalGreenSquares = 0,
    this.streakEarnedToday = false,
    this.dailyGreenCounts = const {},
    this.earnedDayKey = '',
    this.earnedXpToday = 0,
    this.earnedGoldToday = 0,
    this.rewardedTasksDayKey = '',
    this.rewardedTasksToday = 0,
    this.freezeCapacity = 0,
    this.levelGrantPaidThrough = 0,
    this.categoryCompletions = const {},
    this.habitStreakCounts = const {},
    this.habitLongestStreaks = const {},
    this.habitTotalCompletions = const {},
    this.habitLastCompletedDate = const {},
    this.undoneCompletions = const {},
    this.habitMilestoneCelebration,
    this.lastCompletionBonusXp = 0,
    this.lastCompletionBonusGold = 0,
    this.accountCreatedAt,
  });

  factory DashboardState.initial() => const DashboardState(
        level: 1,
        currentLevelXp: 0,
        cumulativeXp: 0,
        gold: 0,
        streak: 0,
        longestStreak: 0,
        totalCompletions: 0,
        streakFreezes: 1,
        completions: {},
        unlockedAchievements: [],
        newlyUnlocked: [],
        isLoading: true,
      );

  double get levelProgress =>
      XpCalculator.levelProgressRatio(currentLevelXp, level);
  int get xpToNext => XpCalculator.xpToNextLevel(level);

  /// This account's numbers in the shape every achievement trigger is
  /// measured against — see [AchievementStats]. Every achievement surface
  /// (the full screen, Profile's preview strip) reads progress through
  /// this, so none of them can drift into its own private version of
  /// "how far along is this one".
  AchievementStats get achievementStats => AchievementStats(
        streak: streak,
        level: level,
        totalCompletions: totalCompletions,
        greenSquares: totalGreenSquares,
        categoryCompletions: categoryCompletions,
      );
  bool isCompleted(String habitId, int target) =>
      (completions[habitId] ?? 0) >= target;

  /// The live current streak for a single habit — unlike reading
  /// [habitStreakCounts] directly, this returns 0 once more than a day has
  /// passed since [habitLastCompletedDate], so a habit that's actually been
  /// abandoned never keeps showing an inflated, stale streak.
  int habitStreak(String habitId) {
    final lastKey = habitLastCompletedDate[habitId];
    if (lastKey == null) return 0;
    final last = DateTime.tryParse(lastKey);
    if (last == null) return 0;
    final gap = DateTime.now()
        .effectiveDay
        .difference(DateTime(last.year, last.month, last.day))
        .inDays;
    return gap <= 1 ? (habitStreakCounts[habitId] ?? 0) : 0;
  }

  DashboardState copyWith({
    String? displayName,
    int? level,
    int? currentLevelXp,
    int? cumulativeXp,
    int? gold,
    int? streak,
    int? longestStreak,
    int? totalCompletions,
    int? streakFreezes,
    Map<String, int>? completions,
    Set<String>? dayCountedHabitIds,
    List<String>? unlockedAchievements,
    List<AchievementModel>? newlyUnlocked,
    bool didJustLevelUp = false,
    bool didUseStreakFreeze = false,
    bool perfectDayCelebration = false,
    String? lastCompletedId,
    bool? isLoading,
    bool? loadFailed,
    DateTime? pendingStreakGapFrom,
    bool clearPendingStreakGap = false,
    int? previousStreak,
    int? setMilestone,
    bool clearMilestone = false,
    bool? intentionsSetToday,
    int? totalGreenSquares,
    bool? streakEarnedToday,
    Map<String, int>? dailyGreenCounts,
    String? earnedDayKey,
    int? earnedXpToday,
    int? earnedGoldToday,
    String? rewardedTasksDayKey,
    int? rewardedTasksToday,
    int? freezeCapacity,
    int? levelGrantPaidThrough,
    Map<String, int>? categoryCompletions,
    Map<String, int>? habitStreakCounts,
    Map<String, int>? habitLongestStreaks,
    Map<String, int>? habitTotalCompletions,
    Map<String, String>? habitLastCompletedDate,
    Map<String, UndoneCompletion>? undoneCompletions,
    HabitMilestoneEvent? setHabitMilestone,
    bool clearHabitMilestone = false,
    int? lastCompletionBonusXp,
    int? lastCompletionBonusGold,
    DateTime? accountCreatedAt,
  }) =>
      DashboardState(
        displayName: displayName ?? this.displayName,
        level: level ?? this.level,
        currentLevelXp: currentLevelXp ?? this.currentLevelXp,
        cumulativeXp: cumulativeXp ?? this.cumulativeXp,
        gold: gold ?? this.gold,
        streak: streak ?? this.streak,
        longestStreak: longestStreak ?? this.longestStreak,
        totalCompletions: totalCompletions ?? this.totalCompletions,
        streakFreezes: streakFreezes ?? this.streakFreezes,
        completions: completions ?? this.completions,
        dayCountedHabitIds: dayCountedHabitIds ?? this.dayCountedHabitIds,
        unlockedAchievements:
            unlockedAchievements ?? this.unlockedAchievements,
        newlyUnlocked: newlyUnlocked ?? this.newlyUnlocked,
        didJustLevelUp: didJustLevelUp,
        didUseStreakFreeze: didUseStreakFreeze,
        perfectDayCelebration: perfectDayCelebration,
        lastCompletedId: lastCompletedId ?? this.lastCompletedId,
        isLoading: isLoading ?? this.isLoading,
        pendingStreakGapFrom: clearPendingStreakGap
            ? null
            : (pendingStreakGapFrom ?? this.pendingStreakGapFrom),
        loadFailed: loadFailed ?? this.loadFailed,
        previousStreak: previousStreak ?? this.previousStreak,
        milestoneCelebration:
            clearMilestone ? null : (setMilestone ?? this.milestoneCelebration),
        intentionsSetToday: intentionsSetToday ?? this.intentionsSetToday,
        totalGreenSquares: totalGreenSquares ?? this.totalGreenSquares,
        streakEarnedToday: streakEarnedToday ?? this.streakEarnedToday,
        dailyGreenCounts: dailyGreenCounts ?? this.dailyGreenCounts,
        earnedDayKey: earnedDayKey ?? this.earnedDayKey,
        earnedXpToday: earnedXpToday ?? this.earnedXpToday,
        earnedGoldToday: earnedGoldToday ?? this.earnedGoldToday,
        rewardedTasksDayKey: rewardedTasksDayKey ?? this.rewardedTasksDayKey,
        rewardedTasksToday: rewardedTasksToday ?? this.rewardedTasksToday,
        freezeCapacity: freezeCapacity ?? this.freezeCapacity,
        levelGrantPaidThrough:
            levelGrantPaidThrough ?? this.levelGrantPaidThrough,
        categoryCompletions: categoryCompletions ?? this.categoryCompletions,
        habitStreakCounts: habitStreakCounts ?? this.habitStreakCounts,
        habitLongestStreaks: habitLongestStreaks ?? this.habitLongestStreaks,
        habitTotalCompletions:
            habitTotalCompletions ?? this.habitTotalCompletions,
        habitLastCompletedDate:
            habitLastCompletedDate ?? this.habitLastCompletedDate,
        undoneCompletions: undoneCompletions ?? this.undoneCompletions,
        habitMilestoneCelebration: clearHabitMilestone
            ? null
            : (setHabitMilestone ?? this.habitMilestoneCelebration),
        lastCompletionBonusXp:
            lastCompletionBonusXp ?? this.lastCompletionBonusXp,
        lastCompletionBonusGold:
            lastCompletionBonusGold ?? this.lastCompletionBonusGold,
        accountCreatedAt: accountCreatedAt ?? this.accountCreatedAt,
      );
}

class DashboardNotifier extends StateNotifier<DashboardState> {
  static const int streakFreezeCost = 100;
  static const int maxStreakFreezes = 3;

  /// Serializes every gold spend across ALL sinks — spendGold (closet,
  /// custom rewards), buyStreakFreeze, buyFreezeSlot. The per-sink guards
  /// (CustomRewardsState.claimingId, CharacterNotifier._buyingId) stop
  /// double-taps within one shop, but each spend rolls back a failed write
  /// by restoring an ABSOLUTE gold snapshot taken before its own deduction,
  /// so two overlapping spends from different sinks could silently refund
  /// each other when the first one's write eventually failed. One shared
  /// flag makes the overlap impossible; a spend attempted while another is
  /// in flight simply reports failure, same as an unaffordable one.
  bool _goldSpendInFlight = false;

  /// The ceiling on purchased bank capacity. [maxStreakFreezes] is the FLOOR
  /// every account starts at; this is where buying stops.
  static const int maxFreezeCapacity = 5;

  /// Gold paid on reaching a level that opens nothing else.
  ///
  /// These twelve are the exact complement, inside levels 2 to 25, of every
  /// level that already awards something: characters at 8, 10, 12, 14, 16,
  /// 18, 20, 21, 23, 24, 25; accessories at 5, 8, 10, 20; prestige ranks at
  /// 1, 5, 10, 20; level medals at 10 and 25. What was left was twelve
  /// level-ups that arrived with nothing attached, which is the drought this
  /// fills.
  ///
  /// 390 gold over an account's life, and modest on purpose: gold is the
  /// oversupplied currency, and the largest single grant sits below the 50
  /// that the level_10 medal already pays so a grant never outshines a medal.
  static const Map<int, int> levelUpGoldGrants = {
    2: 20, 3: 20, 4: 20,
    6: 30, 7: 30, 9: 30,
    11: 40, 13: 40, 15: 40, 17: 40, 19: 40, 22: 40,
  };

  /// Price and level gate of each purchasable slot, in ONE map so the two can
  /// never disagree. As two parallel maps an unmapped slot's level gate
  /// returned 0, so `state.level < 0` was false for every account and the
  /// gate failed OPEN, stopped only incidentally by the cost lookup.
  ///
  /// Escalating on purpose. A flat 100 a slot absorbs 200 gold total, which
  /// is under one percent of a year's income and would not have justified a
  /// persisted field. 400 plus 800 is about a third of the 3,710-gold
  /// accessory catalogue, the app's other one-time sink.
  ///
  /// Levels 10 and 25 are rungs the ladder already marks rather than two new
  /// numbers, and neither slot exists today, so no gate rises on anything
  /// anyone can currently see unlocked.
  static const Map<int, ({int cost, int level})> freezeSlots = {
    4: (cost: 400, level: 10),
    5: (cost: 800, level: 25),
  };
  static const int comebackBonusXp = 50;
  /// Max length for a user-chosen display name — generous enough for most
  /// real names while keeping the Profile hero header from wrapping.
  static const int maxDisplayNameLength = 24;

  final String? _uid;
  // Injectable for tests; defaults to a real Random in production — same
  // pattern QuickWinsNotifier already uses for its own randomized picks.
  final Random _random;

  /// habitId → snapshot of that habit's per-habit fields from the instant
  /// before its most recent [completeHabit] call touched them — see
  /// [_HabitCompletionSnapshot]. Deliberately in-memory only, never
  /// persisted: it exists purely so a same-session [uncompleteHabit] can
  /// reverse a completion precisely, and survives a plain app
  /// background/resume (this notifier instance isn't recreated for that —
  /// only a full app restart clears it), which is exactly the window a
  /// mis-tap correction actually happens in.
  final Map<String, _HabitCompletionSnapshot> _lastHabitCompletion = {};

  /// The initial load, kept so a caller can wait for ALL of it.
  ///
  /// `isLoading` is not that signal, and the difference is not academic.
  /// _loadGuestToday/_loadToday flip `isLoading: false` as soon as the saved
  /// state is in hand, then go on to `await _reconcileAchievements()`
  /// (dashboard_notifier_loading.dart:111 then :130), which can still award
  /// XP and gold for medals the account already qualified for. Anything that
  /// samples state the moment isLoading clears is therefore reading a
  /// baseline that is still moving.
  ///
  /// That window is why undo_restore_guest_test failed under load with a
  /// receipt of 15 XP where 10 was expected: the completion raced a
  /// reconciliation that had not finished, unlocked an achievement that
  /// should already have been unlocked, and both payouts landed on the same
  /// receipt.
  ///
  /// Test-only, like [LocalStoreService.settleDailyWrites] and
  /// [ActiveCatalogNotifier.settled]; the app never waits on this, because
  /// the UI is happy to render a loaded board while medals settle behind it.
  Future<void>? _initialLoad;

  /// Completes when the initial load AND its achievement reconciliation are
  /// both done. Never null-hostile: a notifier constructed and immediately
  /// awaited resolves as soon as its load does.
  Future<void> get ready => _initialLoad ?? Future<void>.value();

  DashboardNotifier(this._uid, {Random? random})
      : _random = random ?? Random(),
        super(DashboardState.initial()) {
    _initialLoad = _uid != null ? _loadToday() : _loadGuestToday();
  }

  // ── Helpers ─────────────────────────────────────────────────

  static String get _todayKey => DateTime.now().effectiveDay.toDateKey();

  /// How much of a REPEATABLE award today can still pay.
  ///
  /// [xp] and [gold] are what the action wants to pay; the return is what it
  /// is allowed to. Both are floored at zero and never exceed the room left
  /// under [dailyXpCapFor] / [dailyGoldCapFor], so a caller can hand over a
  /// full reward and pay out whatever comes back without checking anything.
  ///
  /// [habitCount] is today's scheduled roster. Callers that cannot cheaply
  /// produce it pass 0 and get the floor, which is the safe direction: a cap
  /// that is too generous costs a farmer time, a cap that is too tight
  /// silently withholds a reward someone earned.
  ///
  /// One-time awards must NOT be routed through here. Achievements, both
  /// streak milestone ladders, the comeback bonus and room claims are all
  /// once-per-lifetime or once-per-episode, so capping them buys no safety,
  /// and an achievement swallowed by a cap is gone for good: its id goes into
  /// a set that only grows and the catalog never re-offers it.
  /// Returns both what may be paid now and the running totals to store, so
  /// the caller never has to touch `state` for either. That is not only
  /// tidier: `state` is protected and visible-for-testing, and every read of
  /// it from one of this class's `part` extensions raises a pair of analyzer
  /// warnings, so keeping the arithmetic here keeps the call sites clean.
  ({int xp, int gold, int newXpToday, int newGoldToday}) _allowedToday({
    required int xp,
    required int gold,
    required int habitCount,
  }) {
    final dayKey = _todayKey;
    final spentXp = state.earnedXpOn(dayKey);
    final spentGold = state.earnedGoldOn(dayKey);
    final xpRoom = dailyXpCapFor(habitCount) - spentXp;
    final goldRoom = dailyGoldCapFor(habitCount) - spentGold;
    final grantedXp = xp <= 0 || xpRoom <= 0 ? 0 : (xp < xpRoom ? xp : xpRoom);
    final grantedGold =
        gold <= 0 || goldRoom <= 0 ? 0 : (gold < goldRoom ? gold : goldRoom);
    return (
      xp: grantedXp,
      gold: grantedGold,
      newXpToday: spentXp + grantedXp,
      newGoldToday: spentGold + grantedGold,
    );
  }

  static String get _weekKey {
    final today = DateTime.now().effectiveDay;
    final monday = today.subtract(Duration(days: today.weekday - DateTime.monday));
    return '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Resolves every achievement the given numbers now earn, together with
  /// the level/XP/gold those achievements' own rewards produce.
  ///
  /// Shared by all three writers that can cross a threshold — completeHabit,
  /// applyGridSquareChange, and the post-load reconciliation sweep — so the
  /// rule can't drift between them again (it already had: the grid path only
  /// ever tested two of the five triggers).
  ///
  /// Iterates to a fixed point rather than checking once, because an
  /// achievement's `xpReward` can itself raise the level and so put a
  /// *level* achievement in reach in the same action. Every round removes at
  /// least one achievement from the locked pool and the catalog is finite,
  /// so this can't spin: at most `AchievementCatalog.all.length` rounds, in
  /// practice one (or two when a reward cascades).
  ///
  /// Returns absolute values, not deltas — callers write them straight into
  /// state the same way they already write level/XP.
  ({
    List<AchievementModel> newly,
    List<String> unlockedIds,
    int level,
    int currentLevelXp,
    int cumulativeXp,
    int bonusGold,
    int levelGrantPaidThrough,
  }) _resolveUnlocks({
    required List<String> unlockedIds,
    required int level,
    required int currentLevelXp,
    required int cumulativeXp,
    required int streak,
    required int totalCompletions,
    required int greenSquares,
    required Map<String, int> categoryCompletions,
    required int levelGrantPaidThrough,
  }) {
    final newly = <AchievementModel>[];
    final ids = [...unlockedIds];
    var lvl = level;
    var levelXp = currentLevelXp;
    var cumXp = cumulativeXp;
    var gold = 0;

    while (true) {
      final round = AchievementCatalog.newlyUnlocked(
        AchievementStats(
          streak: streak,
          level: lvl,
          totalCompletions: totalCompletions,
          greenSquares: greenSquares,
          categoryCompletions: categoryCompletions,
        ),
        ids,
      );
      if (round.isEmpty) break;
      newly.addAll(round);
      ids.addAll(round.map((a) => a.id));
      gold += round.fold(0, (s, a) => s + a.goldReward);
      final roundXp = round.fold(0, (s, a) => s + a.xpReward);
      if (roundXp == 0) continue;
      final r = XpCalculator.applyXpGain(
        currentLevel: lvl,
        currentLevelXp: levelXp,
        cumulativeXp: cumXp,
        xpGained: roundXp,
      );
      lvl = r.newLevel;
      levelXp = r.newCurrentLevelXp;
      cumXp = r.newCumulativeXp;
    }

    // AFTER the fixed point, not inside it. A cascade where a medal's own XP
    // raises the level a second time still pays each crossed level exactly
    // once, because this runs once against the final `lvl`. Grants are gold
    // only and never XP, so they cannot re-enter the loop above and its
    // termination argument stands unchanged.
    //
    // `bonusGold` below is the TOTAL and already includes this. It must
    // never be added to gold a second time by a caller.
    var paidThrough = levelGrantPaidThrough;
    if (lvl > paidThrough) {
      for (var l = paidThrough + 1; l <= lvl; l++) {
        gold += DashboardNotifier.levelUpGoldGrants[l] ?? 0;
      }
      paidThrough = lvl;
    }

    return (
      newly: newly,
      unlockedIds: ids,
      level: lvl,
      currentLevelXp: levelXp,
      cumulativeXp: cumXp,
      bonusGold: gold,
      levelGrantPaidThrough: paidThrough,
    );
  }

  DocumentReference<Map<String, dynamic>> get _userRef =>
      FirebaseFirestore.instance.collection('users').doc(_uid);

  DocumentReference<Map<String, dynamic>> get _dailyRef =>
      _userRef.collection('daily').doc(_todayKey);

  /// The shared, append-only history behind Journey Page / Monthly Story /
  /// Legacy Shelf — see MilestoneEvent's own doc comment. completeHabit is
  /// the only writer today; it appends directly to the same batch as the
  /// reward write below rather than going through the standalone
  /// logMilestoneEvent() helper (milestone_notifier.dart), so a level-up
  /// and its milestone entry either both land or both don't.
  CollectionReference<Map<String, dynamic>> get _milestonesRef =>
      _userRef.collection('milestones');

  /// One mirror doc per habit — `{days: {dateKey: 1}}`, presence = done
  /// that day. See habit_history_notifier.dart for the full contract and
  /// the list of the three writers that keep it true.
  DocumentReference<Map<String, dynamic>> habitHistoryRef(String habitId) =>
      _userRef.collection('habit_history').doc(habitId);
}

final dashboardProvider =
    StateNotifierProvider<DashboardNotifier, DashboardState>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  return DashboardNotifier(uid);
});
