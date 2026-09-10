import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/extensions/datetime_ext.dart';
import '../../core/services/health_steps_service.dart';
import '../../core/services/local_store_service.dart';
import '../dashboard/notifiers/dashboard_notifier.dart';
import '../grid/models/square_state.dart';
import '../grid/notifiers/square_audit.dart';
import '../grid/notifiers/weekly_grid_notifier.dart';
import '../rooms/notifiers/rooms_notifier.dart';
import 'catalog/islamic_habit_catalog.dart';
import 'notifiers/custom_habits_notifier.dart';

/// Today's step count as last read from the platform (null before the
/// first successful read). Written only by [runStepAutoComplete]; read by
/// any surface that wants to show the number without its own health call.
final stepsTodayProvider = StateProvider<int?>((ref) => null);

/// Every day this session has a step count for, keyed by date key.
///
/// The board draws a linked habit's part-done walk as a proportional fill,
/// and that fill used to come from [stepsTodayProvider] alone. So it was
/// only ever drawn on TODAY, and at midnight a day that had been showing a
/// real walk all day went blank: nothing is written below half the goal (see
/// [kStepPartialShare]), so the record of the walk lived only in a variable
/// that now meant a different day. "It records correctly from the app, but
/// when it hits 00:00 it becomes zero, like the user never walked" — Aziz,
/// 2026-09-10.
///
/// Filled from three places: today's read, the once-a-day catch-up pass over
/// the last [kStepCatchUpDays] days ([_creditWalksOn]), and the day log on
/// disk ([_hydrateSteps]).
///
/// It IS persisted, which was the second half of the same complaint. An
/// in-memory map made HealthKit the sole record, and HealthKit is a record
/// the app cannot always get back: the catch-up reaches seven days, a
/// revoked permission answers a well-formed zero for all of them, and every
/// launch paid to re-learn what it already knew. "When the day finish it
/// saves the data, and start count to the next day, it should not go to 0,
/// even if its 3921 steps and the goal is 6000" - Aziz, 2026-09-10.
///
/// Disk and memory are merged the same way two reads are, by
/// [stepsMapWith]'s never-downward rule, so neither copy can talk the other
/// one down.
final stepsByDayProvider = StateProvider<Map<String, int>>((ref) => const {});

/// Why the last steps read produced nothing, or null when it produced a
/// number. Read by the surfaces that would otherwise show a zero the app
/// cannot stand behind (see S.stepsLinkBlocked and S.stepsNotArrivingHint).
///
/// Only ever non-null on Android, where Health Connect fails a query it will
/// not answer. iOS returns a zero-step success for a refused read because
/// HealthKit gives apps no way to tell that apart from a quiet morning.
final stepsFailureProvider = StateProvider<HealthStepsFailure?>((ref) => null);

DateTime? _lastRead;

/// Records [steps] against [day] for the board's fill.
///
/// Merge, never replace: the catch-up walks seven days and today's read
/// lands separately, and the map has to end up holding all of them.
///
/// And never DOWNWARD for a day it already knows, which is the whole
/// difference between a record and a rumour. Steps only grow within a day,
/// so a smaller number for a day already counted is not news, it is a bad
/// read — and iOS has a standing supply of those: a refused read there is
/// indistinguishable from a quiet morning and arrives as a perfectly
/// well-formed zero (see HealthStepsService.stepsForDay). One of those
/// landing on a day the app had already measured is exactly the "it saved
/// it, then overwrote it to zero" Aziz reported on 2026-09-10.
///
/// A new day is a different key, so midnight still resets what the board
/// shows without this ever having to allow a decrease.
void _publishSteps(WidgetRef ref, DateTime day, int steps) {
  final current = ref.read(stepsByDayProvider);
  final next = stepsMapWith(current, day.toDateKey(), steps);
  if (identical(next, current)) return;
  ref.read(stepsByDayProvider.notifier).state = next;
  unawaited(_persistSteps(next));
}

/// Writes the day log to disk, pruned to [kStepLogKeepDays].
///
/// Fire-and-forget on purpose: the number is already on screen by the time
/// this runs, and a Hive failure is not something to interrupt somebody's
/// walk over. The next publish rewrites the whole map anyway, so a dropped
/// write costs one day of durability and nothing else.
Future<void> _persistSteps(Map<String, int> log) async {
  try {
    await LocalStoreService.putSettingsMap(
      LocalStoreService.stepsByDayKey,
      prunedStepsLog(log, DateTime.now()),
    );
  } catch (_) {
    // No Hive (widget tests), a closed box, a full disk. All the same here.
  }
}

/// Whether the day log on disk has been merged into [stepsByDayProvider]
/// this session. Once per process: the provider is the newer copy from then
/// on, and every write goes through both.
bool _hydrated = false;

/// Test seam. Lets a test start from a cold process without a Hive box.
void resetStepHydrationForTest() => _hydrated = false;

/// Merges the stored day log into [stepsByDayProvider].
///
/// Runs before the first health read of the session, so a launch whose read
/// is refused, stalled or simply zero still shows what the phone measured
/// yesterday rather than an empty week. Merged, never assigned: a day the
/// provider already holds a bigger number for keeps it (see [stepsMapWith]).
Future<void> _hydrateSteps(WidgetRef ref) async {
  if (_hydrated) return;
  _hydrated = true;
  Map<String, dynamic> raw;
  try {
    raw = await LocalStoreService.getSettingsMap(LocalStoreService.stepsByDayKey);
  } catch (_) {
    return;
  }
  if (!ref.context.mounted) return;
  final stored = stepsLogFrom(raw);
  if (stored.isEmpty) return;
  var merged = ref.read(stepsByDayProvider);
  for (final entry in stored.entries) {
    merged = stepsMapWith(merged, entry.key, entry.value);
  }
  if (identical(merged, ref.read(stepsByDayProvider))) return;
  ref.read(stepsByDayProvider.notifier).state = merged;
}

/// How many days of step counts the log keeps.
///
/// Sixty: comfortably past [kStepCatchUpDays] and past the two months of
/// squares the Grid and the room strips can scroll back to, while keeping
/// the stored map small enough to rewrite on every read.
const int kStepLogKeepDays = 60;

/// The stored map, as counts. Anything that is not a positive int for a
/// plausible key is dropped rather than trusted: this comes off disk, where
/// an older build's shape may still be sitting.
Map<String, int> stepsLogFrom(Map<String, dynamic> raw) {
  final out = <String, int>{};
  for (final entry in raw.entries) {
    final value = entry.value;
    final steps = value is int ? value : (value is num ? value.toInt() : null);
    if (steps == null || steps <= 0) continue;
    if (DateTime.tryParse(entry.key) == null) continue;
    out[entry.key] = steps;
  }
  return out;
}

/// [log] with everything older than [kStepLogKeepDays] before [now] dropped,
/// and anything dated after today dropped with it: a future day cannot have
/// been walked, and one arriving from a device whose clock is wrong must not
/// be able to sit in the log forever.
Map<String, int> prunedStepsLog(
  Map<String, int> log,
  DateTime now, {
  int keepDays = kStepLogKeepDays,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final oldest = DateTime(now.year, now.month, now.day - keepDays);
  final out = <String, dynamic>{};
  for (final entry in log.entries) {
    final day = DateTime.tryParse(entry.key);
    if (day == null || day.isBefore(oldest) || day.isAfter(today)) continue;
    out[entry.key] = entry.value;
  }
  return out.cast<String, int>();
}

/// [_publishSteps]'s rule, as a value: the map that results from recording
/// [steps] against [key], or the same map back when there is nothing to
/// record. Pure so the never-downward invariant can be tested without a
/// health store, a Grid or a clock.
Map<String, int> stepsMapWith(Map<String, int> current, String key, int steps) {
  if (steps <= (current[key] ?? 0)) return current;
  return {...current, key: steps};
}

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

/// The share of the goal to draw as a FILL on a day's square, or null when
/// there is nothing to draw.
///
/// The sibling of [stepSquareFor]: that one decides what the count has
/// EARNED, this one what it should look like on a day it earned nothing.
/// Below half the goal no square is ever written, and until this was drawn
/// for past days too, such a day went blank at midnight and read as though
/// nobody had walked at all.
///
/// Null in four cases, each of them a day this must not speak about: nothing
/// walked, the goal already reached (the square is green by then and says so
/// itself), a day the habit does not run on, and a square that already
/// carries a mark — تخطّي, فشل, جزئي or the blue one are all statements that
/// outrank a measured count, exactly as _effectiveSquare ranks them over a
/// times-per-day tally.
///
/// Deliberately takes no date. Which day's count to hand in is the caller's
/// question, and making it this function's was the bug: the fill was drawn
/// only for `day.isToday`, so it could not survive the day it described.
double? stepFillFraction({
  required int? steps,
  required int? goal,
  required bool scheduled,
  required SquareState square,
}) {
  if (steps == null || goal == null || goal <= 0 || !scheduled) return null;
  if (steps <= 0 || steps >= goal) return null;
  if (square != SquareState.none) return null;
  return steps / goal;
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

/// How many days back the once-a-day catch-up looks for a walk the app was
/// never open to see.
///
/// Seven, Aziz's call on 2026-09-09, after testers came back with days that
/// had gone empty. It used to be one, on the argument that somebody who has
/// not opened the app in a week has bigger problems than a missing square.
/// That argument was wrong in the one case that matters: steps are the only
/// habit here that happens entirely while the app is closed, so the person
/// who walks every day and opens the app twice a week lost every day in
/// between, permanently, and nothing on screen ever said so.
///
/// Seven is the visible grid week, which makes the promise easy to state:
/// no day the board still shows is a day the count quietly gave up on.
///
/// It is also the recovery path for the days lost to build 66, where a walk
/// short of the goal wrote nothing at all: HealthKit still holds the counts,
/// so the first launch after updating fills back in whatever the week still
/// has. Days older than the window stay empty, because nothing was ever
/// written for them and nothing now will be.
const int kStepCatchUpDays = 7;

/// The effective day whose previous [kStepCatchUpDays] days have already
/// been checked for a walk the app was never open to see. One pass per day,
/// not one per trigger — see [_creditRecentWalks].
DateTime? _catchUpCheckedFor;

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

  // Before the throttle, and before the read: a launch whose health query is
  // refused or slow should still be showing yesterday's measured walk, not an
  // empty week that fills in two seconds later.
  await _hydrateSteps(ref);
  if (!ref.context.mounted) return;

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
  _publishSteps(ref, effectiveDay, steps);
  // Read back out of the map rather than from the read, so the same
  // never-downward rule protects the number every surface shows. A stalled
  // read that comes back as zero at 4pm must not tell somebody who walked
  // 9,000 steps this morning that they have walked none.
  ref.read(stepsTodayProvider.notifier).state =
      ref.read(stepsByDayProvider)[effectiveDay.toDateKey()] ?? steps;

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

  await _creditRecentWalks(ref, allLinked, effectiveDay);
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
          .setSquareStateOnlyAsync(habit.id, effectiveDay, target,
              source: kSquareSourceSteps);
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
            .setSquareStateOnlyAsync(habit.id, effectiveDay, target,
              source: kSquareSourceSteps);
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
          source: kSquareSourceSteps,
        );
    if (target == SquareState.bonus) {
      // Twenty percent over the goal: the blue square, exactly what the
      // long-press palette gives by hand. A mark on top of the paid day,
      // not a second reward, same as picking it from the palette.
      await ref
          .read(weeklyGridProvider.notifier)
          .setSquareStateOnlyAsync(habit.id, effectiveDay, target,
              source: kSquareSourceSteps);
      if (!ref.context.mounted) return;
    }
    syncRoomToday(ref, habit.id, effectiveDay);
  }
}

/// Credits walks the app was never open to see, over the last
/// [kStepCatchUpDays] days.
///
/// Auto-completion only ever looked at the day in progress, so someone who
/// walked their goal and did not open the app before the cutoff lost it
/// outright: the next launch reads a fresh day and the day before stays
/// empty forever. Steps are the one habit in this app that genuinely happen
/// while the app is closed, which is exactly why they are worth reading at
/// all, and the flex window after midnight only covers the person who
/// happens to open it in those few hours.
///
/// Marks the SQUARE only, never [DashboardNotifier.completeHabit]. That is
/// the same division of labour a person gets for tapping a past square: the
/// record is corrected, and nothing is paid, because setSquare's
/// anti-backdating guard has always refused to pay for a day that is over.
/// Room percentages do follow, through syncRoomToday's past-day branch,
/// which runs a full resync rather than the today-only fast path.
///
/// Once per day, newest day first, and a health read only for a day that
/// actually has an open question on it: a day already marked costs one
/// stored-squares read and nothing else. A day the store could not answer,
/// or a health read that failed for a reason that might not last, puts the
/// whole pass back for a later trigger rather than writing a guess.
Future<void> _creditRecentWalks(
  WidgetRef ref,
  List<IslamicHabitTemplate> allLinked,
  DateTime effectiveDay,
) async {
  if (_catchUpCheckedFor == effectiveDay) return;
  // Claimed BEFORE the await, so the two triggers that can overlap on a cold
  // start (HomeShell's post-frame call and the linked-habit listener's
  // forced one) cannot both spend a pass on the same question.
  _catchUpCheckedFor = effectiveDay;

  // Newest first. An interrupted pass then leaves the days nearest today
  // done, which are both the likeliest to matter and the ones still on
  // screen.
  var retryLater = false;
  for (var back = 1; back <= kStepCatchUpDays; back++) {
    // The calendar's day, not "N times 24 hours earlier": on a DST shift a
    // day is 23 or 25 hours long, and effectiveDay is a local midnight, so
    // subtracting a fixed Duration lands at 01:00 or 23:00 rather than on
    // midnight. Same reason stepsForDay builds both of its ends this way.
    final day = DateTime(
      effectiveDay.year,
      effectiveDay.month,
      effectiveDay.day - back,
    );
    if (await _creditWalksOn(ref, allLinked, day)) continue;
    if (!ref.context.mounted) return;
    retryLater = true;
  }
  // One failure anywhere in the window re-opens the whole pass. The days
  // that did land are marked by then, so the retry costs a stored read each
  // and no health read at all.
  if (retryLater) _catchUpCheckedFor = null;
}

/// One day of [_creditRecentWalks]. True when the day is settled (filled in,
/// or nothing was owed on it), false when it should be tried again later.
Future<bool> _creditWalksOn(
  WidgetRef ref,
  List<IslamicHabitTemplate> allLinked,
  DateTime day,
) async {
  // A day inside the visible week is better read from memory: the row there
  // includes a mark made seconds ago whose write to the store may still be
  // in flight. Outside it, WeeklyGridState answers `none` for every day it
  // has not loaded — indistinguishable from an untouched day, and believing
  // that would paint over a تخطّي.
  final grid = ref.read(weeklyGridProvider);
  final marks = grid.days.any((d) => d.isSameDayAs(day))
      ? grid.states[day.toDateKey()] ?? const <String, SquareState>{}
      : await ref.read(weeklyGridProvider.notifier).storedSquaresFor(day);
  if (!ref.context.mounted) return true;
  // The day could not be read at all. Deciding anything about a day the app
  // has not seen is exactly the mistake above, so leave it for a later try.
  if (marks == null) return false;

  final owed = stepHabitsOwedOn(
    linked: allLinked,
    marks: marks,
    day: day,
  );
  if (owed.isEmpty) return true;

  final outcome = await HealthStepsService.instance.stepsForDay(day);
  final steps = outcome.steps;
  if (steps == null) {
    // A transient platform-channel failure gets the day back: the first
    // launch of a day is exactly when the health plugin is most likely to
    // still be warming up, and losing a day to that would be the same
    // silent loss this whole function exists to stop. A refusal (permission
    // gone, no Health Connect) does not, because retrying it every two
    // minutes for the rest of the day would burn reads to be told no again.
    return outcome.failure != HealthStepsFailure.unavailable;
  }
  if (!ref.context.mounted) return true;
  // Published even when nothing below writes a square. A walk short of half
  // the goal earns no mark by design, and this is the whole point of
  // recording it anyway: the board can still draw what was actually walked
  // instead of an empty square.
  _publishSteps(ref, day, steps);

  for (final habit in owed) {
    final current = marks[habit.id] ?? SquareState.none;
    final target = stepSquareFor(steps: steps, goal: habit.stepGoal!);
    // The day's final count, in the day's own square: half stays a جزئي,
    // the goal a green, twenty percent over a blue. Only ever upwards from
    // whatever the live reads left there on the day itself.
    if (!stepCountMayLift(current, target)) continue;
    // Awaited, unlike today's equivalent, because the room sync that follows
    // reads a PAST day back out of the store (syncRoomToday's past-day branch
    // runs a full resync rather than the in-memory fast path). Firing the
    // write and the read together let the resync see the day as it was a
    // moment ago and publish a percentage that did not include the walk.
    await ref
        .read(weeklyGridProvider.notifier)
        .setSquareStateOnlyAsync(habit.id, day, target,
            source: kSquareSourceStepsCatchUp);
    if (!ref.context.mounted) return true;
    syncRoomToday(ref, habit.id, day);
  }
  return true;
}

/// Which linked habits still have an open question about [day]: it was one
/// of their days, and nobody has said anything about it.
///
/// Split out of [_creditRecentWalks] because this is the whole risk in
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
List<IslamicHabitTemplate> stepHabitsOwedOn({
  required List<IslamicHabitTemplate> linked,
  required Map<String, SquareState> marks,
  required DateTime day,
}) =>
    linked
        .where(
          (h) =>
              h.stepGoal != null &&
              h.isScheduledFor(day) &&
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
