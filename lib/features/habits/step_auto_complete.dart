import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/extensions/datetime_ext.dart';
import '../../core/services/health_steps_service.dart';
import '../dashboard/notifiers/dashboard_notifier.dart';
import '../grid/models/square_state.dart';
import '../grid/notifiers/weekly_grid_notifier.dart';
import '../rooms/notifiers/rooms_notifier.dart';
import 'catalog/islamic_habit_catalog.dart';
import 'notifiers/custom_habits_notifier.dart';

/// Today's step count as last read from the platform (null before the
/// first successful read). Written only by [runStepAutoComplete]; read by
/// any surface that wants to show the number without its own health call.
final stepsTodayProvider = StateProvider<int?>((ref) => null);

/// Why the last steps read produced nothing, or null when it produced a
/// number. Read by the surfaces that would otherwise show a zero the app
/// cannot stand behind (see S.stepsLinkBlocked and S.stepsNotArrivingHint).
///
/// Only ever non-null on Android, where Health Connect fails a query it will
/// not answer. iOS returns a zero-step success for a refused read because
/// HealthKit gives apps no way to tell that apart from a quiet morning.
final stepsFailureProvider = StateProvider<HealthStepsFailure?>((ref) => null);

DateTime? _lastRead;

/// The share of the goal from which a walk leaves a جزئي square. Half, in
/// Aziz's own words (2026-09-07): "if he walked the half, it marks and
/// saves the half at the end of the day". Below it the day stays empty, so
/// carrying the phone to the kitchen never colours a square.
const double kStepPartialShare = 0.5;

/// Twenty percent over the goal earns the blue إنجاز إضافي square, the same
/// one the long-press palette offers by hand.
const double kStepBonusShare = 1.2;

/// The square a day's step count has earned on its own: nothing, جزئي at
/// half the goal, the green square at the goal, the blue one at
/// [kStepBonusShare] of it. Pure, so the ladder is testable without health
/// data or a Grid.
SquareState stepSquareFor({required int steps, required int goal}) {
  if (goal <= 0 || steps <= 0) return SquareState.none;
  if (steps >= goal * kStepBonusShare) return SquareState.bonus;
  if (steps >= goal) return SquareState.complete;
  if (steps >= goal * kStepPartialShare) return SquareState.partial;
  return SquareState.none;
}

/// Where a square sits on the ladder the step count may climb: -1 for the
/// two marks that are the owner's own word about the day (فشل, تخطّي) and
/// must never be touched by a count.
int stepSquareRank(SquareState square) => switch (square) {
      SquareState.none => 0,
      SquareState.partial => 1,
      SquareState.complete => 2,
      SquareState.bonus => 3,
      SquareState.failed || SquareState.skipped => -1,
    };

/// Whether the count may move a square from [from] to [to]: only upwards,
/// and never off a mark the owner made. Steps only ever grow within a day,
/// so a downgrade can only mean a stale read, which must not undo anything.
bool stepCountMayLift(SquareState from, SquareState to) =>
    stepSquareRank(from) >= 0 && stepSquareRank(to) > stepSquareRank(from);

/// The effective day whose *previous* day has already been checked for a
/// walk the app was never open to see. One extra health read per day, not
/// one per trigger — see [_creditYesterdayWalks].
DateTime? _yesterdayCheckedFor;

/// Reads today's steps and writes what they have earned into every linked
/// habit's square: جزئي from half the goal, the green square at the goal,
/// the blue إنجاز إضافي at twenty percent over it, only ever upwards (see
/// [stepCountMayLift]). The green square is the one that pays; the other
/// two are marks, exactly as the palette would make them.
///
/// The completion goes through the exact same canonical path a lock-screen "Mark Done" takes
/// (main.dart's notification-action handler is the template): completeHabit
/// for the reward, then the Grid square, then the room sync. Safe to call
/// often — it throttles its own health reads to one per two minutes, does
/// nothing at all when no habit is linked (so accounts that never touched
/// the feature never wake HealthKit), and every guard failure is a silent
/// return, never an error surface: the person did not ask for anything,
/// so there is nothing to apologise for. Callers: HomeShell (first frame
/// and app-resume) and AddHabitSheet (right after saving a linked habit,
/// so a goal already met today completes on the spot).
///
/// Also looks back one day, once per day, for a walk nobody was here to see
/// — see [_creditYesterdayWalks]. And it publishes why a read failed
/// ([stepsFailureProvider]) instead of letting a refusal read as a zero: a
/// zero is a claim about somebody's day, and the app should only make it
/// when the platform actually said so.
Future<void> runStepAutoComplete(WidgetRef ref, {bool force = false}) async {
  // Every linked habit, not only today's: a habit scheduled for Mondays
  // still needs Monday's walk credited on Tuesday (see
  // [_creditYesterdayWalks]), and gating the whole function on "scheduled
  // today" used to return before the read that would have found it.
  final allLinked =
      ref.read(habitListProvider).where((h) => h.stepGoal != null).toList();
  if (allLinked.isEmpty) return;

  final now = DateTime.now();
  if (!force &&
      _lastRead != null &&
      now.difference(_lastRead!) < const Duration(minutes: 2)) {
    return;
  }
  _lastRead = now;

  // The app's effective day, NOT the calendar day: after midnight the
  // habit-day still in progress is yesterday's, and it must be judged
  // against yesterday's steps (see stepsForDay's doc comment).
  final effectiveDay = DateTime.now().effectiveDay;
  final linked =
      allLinked.where((h) => h.isScheduledFor(effectiveDay)).toList();
  final outcome = await HealthStepsService.instance.stepsForDay(effectiveDay);
  if (!ref.context.mounted) return;
  // Published even on the happy path, so a surface that showed a stall
  // clears it the moment the count comes back.
  ref.read(stepsFailureProvider.notifier).state = outcome.failure;
  final steps = outcome.steps;
  // A failed read leaves the last known count standing rather than
  // overwriting it with a zero: "you walked 0 today" is a claim about the
  // person's day, and a refused query is not evidence for it.
  if (steps == null) return;
  ref.read(stepsTodayProvider.notifier).state = steps;

  // completeHabit refuses while the account doc is still loading (writing
  // through would zero it — see its guards), and the Grid square write
  // below has its own cold-start race: markResultFromHabit's in-memory
  // write lands, then _loadWeek's read (already in flight) replaces the
  // state wholesale and the square vanishes until the next app start
  // reloads the persisted copy (observed live before the grid wait was
  // added). So wait for BOTH stores, then let the next trigger retry
  // rather than spinning here.
  for (var attempt = 0; attempt < 10; attempt++) {
    final dash = ref.read(dashboardProvider);
    if (dash.loadFailed) return;
    if (!dash.isLoading && !ref.read(weeklyGridProvider).isLoading) break;
    await Future<void>.delayed(const Duration(seconds: 1));
    if (!ref.context.mounted) return;
  }
  if (ref.read(dashboardProvider).isLoading ||
      ref.read(weeklyGridProvider).isLoading) {
    return;
  }

  await _creditYesterdayWalks(ref, allLinked, effectiveDay);
  if (!ref.context.mounted) return;

  for (final habit in linked) {
    final target = stepSquareFor(steps: steps, goal: habit.stepGoal!);
    final current =
        ref.read(weeklyGridProvider).squareFor(habit.id, effectiveDay);
    // Upwards only, and never off فشل or تخطّي: the count set this square
    // earlier today or the person did, and either way it only ever climbs.
    if (!stepCountMayLift(current, target)) continue;
    if (!stepHabitAcceptsAutoComplete(
      habit: habit,
      grid: ref.read(weeklyGridProvider),
      dash: ref.read(dashboardProvider),
      day: effectiveDay,
    )) {
      continue;
    }
    if (target == SquareState.partial) {
      // Half the goal: the square says so now, so the day keeps its mark
      // when it rolls over instead of reading as if nobody moved. A mark,
      // not a reward: the day is paid only when the goal is reached.
      await ref
          .read(weeklyGridProvider.notifier)
          .setSquareStateOnlyAsync(habit.id, effectiveDay, target);
      if (!ref.context.mounted) return;
      syncRoomToday(ref, habit.id, effectiveDay);
      continue;
    }
    final done = ref.read(dashboardProvider).completions[habit.id] ?? 0;
    final perDay = habit.effectiveDailyTarget;
    if (done >= perDay) {
      // Already paid, from Today or by an earlier read. Only the blue
      // square can still be owed.
      if (target == SquareState.bonus && current != SquareState.bonus) {
        await ref
            .read(weeklyGridProvider.notifier)
            .setSquareStateOnlyAsync(habit.id, effectiveDay, target);
        if (!ref.context.mounted) return;
        syncRoomToday(ref, habit.id, effectiveDay);
      }
      continue;
    }

    // From here down this mirrors main.dart's Mark Done branch line for
    // line — same boost, same all-done predicate, same square mirroring —
    // so an auto-completion is indistinguishable from a tap.
    final dashState = ref.read(dashboardProvider);
    final todayHabits = ref
        .read(habitListProvider)
        .where((h) => h.isScheduledFor(effectiveDay))
        .map((h) => (id: h.id, frequencyTarget: h.effectiveDailyTarget));
    final mirroredBySingleTap =
        await ref.read(dashboardProvider.notifier).completeHabit(
              habitId: habit.id,
              scheduledWeekdays: habit.scheduledWeekdays.toSet(),
              xpReward: roomBoostedReward(ref, habit.id, habit.xpReward),
              goldReward: roomBoostedReward(ref, habit.id, habit.goldReward),
              frequencyTarget: perDay,
              allHabitsDoneAfter: willCompleteAllHabitsToday(
                state: dashState,
                todayHabits: todayHabits,
                habitId: habit.id,
                frequencyTarget: perDay,
              ),
              scheduledHabitCount: todayHabits.length,
              category: habit.category.name,
            );
    if (!ref.context.mounted) return;
    if (!mirroredBySingleTap) continue;
    // effectiveDay as captured at the top, not a fresh read. This function
    // can spend ten seconds waiting for two stores, and somebody who opens
    // the app in the last moments of a habit-day can cross the cutoff while
    // it waits: re-reading the clock here would credit the reward to one day
    // and paint the square on the next one.
    ref.read(weeklyGridProvider.notifier).markCompleteFromHabit(
          habit.id,
          effectiveDay,
        );
    if (target == SquareState.bonus) {
      // Twenty percent over the goal: the blue square, exactly what the
      // long-press palette gives by hand. A mark on top of the paid day,
      // not a second reward, same as picking it from the palette.
      await ref
          .read(weeklyGridProvider.notifier)
          .setSquareStateOnlyAsync(habit.id, effectiveDay, target);
      if (!ref.context.mounted) return;
    }
    syncRoomToday(ref, habit.id, effectiveDay);
  }
}

/// Credits a walk the app was never open to see.
///
/// Auto-completion only ever looked at the day in progress, so someone who
/// walked their goal and did not open the app before the cutoff lost it
/// outright: the next launch reads a fresh day and yesterday stays empty
/// forever. Steps are the one habit in this app that genuinely happen while
/// the app is closed, which is exactly why they are worth reading at all,
/// and the flex window after midnight only covers the person who happens to
/// open it in those few hours.
///
/// Marks the SQUARE only, never [DashboardNotifier.completeHabit]. That is
/// the same division of labour a person gets for tapping a past square: the
/// record is corrected, and nothing is paid, because setSquare's
/// anti-backdating guard has always refused to pay for a day that is over.
/// Room percentages do follow, through syncRoomToday's past-day branch,
/// which runs a full resync rather than the today-only fast path.
///
/// Yesterday only, and once per day: a longer lookback would mean a health
/// query per day per launch for a payoff that shrinks with every day (a
/// person who has not opened the app in a week has bigger problems than one
/// missing square), and a square already marked closes the gate anyway.
Future<void> _creditYesterdayWalks(
  WidgetRef ref,
  List<IslamicHabitTemplate> allLinked,
  DateTime effectiveDay,
) async {
  if (_yesterdayCheckedFor == effectiveDay) return;
  // Claimed BEFORE the await, so the two triggers that can overlap on a cold
  // start (HomeShell's post-frame call and the linked-habit listener's
  // forced one) cannot both spend a health read on the same question.
  _yesterdayCheckedFor = effectiveDay;

  // The calendar's previous day, not "24 hours earlier": on a DST shift a
  // day is 23 or 25 hours long, and effectiveDay is a local midnight, so
  // subtracting a fixed Duration lands at 01:00 or 23:00 rather than on
  // midnight. Same reason stepsForDay builds both of its ends this way.
  final yesterday = DateTime(
    effectiveDay.year,
    effectiveDay.month,
    effectiveDay.day - 1,
  );

  // Yesterday is usually in the visible week, and the in-memory row is the
  // better answer there: it includes a mark made seconds ago whose write to
  // the store may still be in flight. On the first day of a grid week it is
  // NOT in the visible week, and WeeklyGridState answers `none` for every day
  // it has not loaded — indistinguishable from an untouched day. Believing
  // that would have painted over a تخطّي once every seven days.
  final grid = ref.read(weeklyGridProvider);
  final marks = grid.days.any((d) => d.isSameDayAs(yesterday))
      ? grid.states[yesterday.toDateKey()] ?? const <String, SquareState>{}
      : await ref
          .read(weeklyGridProvider.notifier)
          .storedSquaresFor(yesterday);
  if (!ref.context.mounted) return;
  if (marks == null) {
    // The day could not be read at all. Deciding anything about a day the app
    // has not seen is exactly the mistake above, so leave it and let a later
    // trigger try again.
    _yesterdayCheckedFor = null;
    return;
  }

  final owed = stepHabitsOwedYesterday(
    linked: allLinked,
    marks: marks,
    yesterday: yesterday,
  );
  if (owed.isEmpty) return;

  final outcome = await HealthStepsService.instance.stepsForDay(yesterday);
  final steps = outcome.steps;
  if (steps == null) {
    // A transient platform-channel failure gets the day back: the first
    // launch of a day is exactly when the health plugin is most likely to
    // still be warming up, and losing yesterday to that would be the same
    // silent loss this whole function exists to stop. A refusal (permission
    // gone, no Health Connect) does not, because retrying it every two
    // minutes for the rest of the day would burn reads to be told no again.
    if (outcome.failure == HealthStepsFailure.unavailable) {
      _yesterdayCheckedFor = null;
    }
    return;
  }
  if (!ref.context.mounted) return;

  for (final habit in owed) {
    final current = marks[habit.id] ?? SquareState.none;
    final target = stepSquareFor(steps: steps, goal: habit.stepGoal!);
    // The day's final count, in the day's own square: half stays a جزئي,
    // the goal a green, twenty percent over a blue. Only ever upwards from
    // whatever the live reads left there yesterday.
    if (!stepCountMayLift(current, target)) continue;
    // Awaited, unlike today's equivalent, because the room sync that follows
    // reads a PAST day back out of the store (syncRoomToday's past-day branch
    // runs a full resync rather than the in-memory fast path). Firing the
    // write and the read together let the resync see the day as it was a
    // moment ago and publish a percentage that did not include the walk.
    await ref
        .read(weeklyGridProvider.notifier)
        .setSquareStateOnlyAsync(habit.id, yesterday, target);
    if (!ref.context.mounted) return;
    syncRoomToday(ref, habit.id, yesterday);
  }
}

/// Which linked habits still have an open question about [yesterday]: it was
/// one of their days, and nobody has said anything about it.
///
/// Split out of [_creditYesterdayWalks] because this is the whole risk in
/// back-filling a day. Writing a square the person never asked for is only
/// defensible while it is confined to days that are genuinely blank, and a
/// blank day is the one thing this decides.
///
/// Takes the day's marks rather than the whole grid state on purpose: the
/// caller has to source them differently depending on whether that day is in
/// the visible week, and this function must not be able to tell the
/// difference (see WeeklyGridNotifier.storedSquaresFor for why guessing is
/// not allowed here).
///
/// An explicit mark of any kind ends it. A green square means the walk is
/// already recorded; a تخطّي means the person stood the day down on purpose;
/// a red means they said it did not happen. A step count read a day late
/// does not get to overrule any of those, and neither does a جزئي, which is
/// somebody's own account of a part-done day.
List<IslamicHabitTemplate> stepHabitsOwedYesterday({
  required List<IslamicHabitTemplate> linked,
  required Map<String, SquareState> marks,
  required DateTime yesterday,
}) =>
    linked
        .where(
          (h) =>
              h.stepGoal != null &&
              h.isScheduledFor(yesterday) &&
              stepSquareRank(marks[h.id] ?? SquareState.none) >= 0 &&
              (marks[h.id] ?? SquareState.none) != SquareState.bonus,
        )
        .toList();

/// Whether the app is still allowed to complete [habit] on [day] by itself,
/// or whether the person has already said something about that day.
///
/// The step counter is evidence, not a verdict. Someone who marks the day
/// فشل or تخطّي has made a statement about it, and a pedometer does not get
/// to overrule a person about their own day; إنجاز إضافي is already the top
/// of the ladder. A جزئي is different since 2026-09-07: the count sets it
/// itself at half the goal, so it is a rung the count may climb from. Before
/// this, it did: marking a linked habit فشل and reopening the app turned the
/// square green again and paid the day's XP for a day its owner had just said
/// did not happen (seen live on 2026-09-02).
///
/// The cleared case needs the receipt rather than the square, because an
/// empty square is ambiguous in a way the others are not: it is both "nobody
/// has said anything yet" and "I took that back". [UndoneCompletion] is the
/// trace the undo leaves behind, so a person who clears an auto-completion is
/// left alone for the rest of the day instead of watching it reappear, while
/// a genuinely untouched square still completes itself the moment the walk
/// is done.
///
/// Says nothing about a square that is already [SquareState.complete]: the
/// caller's own `done >= perDay` guard covers that, and it covers it better,
/// because it reads the completion rather than its mirror.
bool stepHabitAcceptsAutoComplete({
  required IslamicHabitTemplate habit,
  required WeeklyGridState grid,
  required DashboardState dash,
  required DateTime day,
}) {
  final square = grid.squareFor(habit.id, day);
  // فشل and تخطّي are the owner's word about the day and stay theirs; the
  // blue square is already more than done. A جزئي is in play: the count
  // sets it itself at half the goal now, and a person who marked half by
  // hand and then walked the whole goal is still owed the green square.
  if (stepSquareRank(square) < 0 || square == SquareState.bonus) return false;
  return dash.undoneFor(habit.id, day.toDateKey()) == null;
}
