// A Grid board that reaches every drawing path of _GridTable, for the tests
// that pin the board's output while its build is made cheaper
// (grid_week_facts_parity_test.dart and the others that import this).
//
// Every cadence the board draws differently is here: daily, specific days, a
// flexible weekly quota, a habit counted three times a day, a step-linked
// walk, one born in the middle of the week, one archived in it, two whose
// schedule changed inside the week, a quit habit, a specific-days habit with
// a session moved onto an off day, and a quota week holding halves. The
// squares use every SquareState, and the week carries notes (one a blank
// tombstone), voice notes and step counts.
//
// The week and "today" are parameters, so the same board can be drawn on the
// current week (today's ring, yesterday's open count), on a fixed past week
// (a frozen golden), and on a daylight-saving week (run the file with
// TZ=America/New_York).
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/square_voice_notes.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_cadence.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';

/// A grid whose state is whatever the test pinned: the load the real
/// notifier starts would otherwise replace it the moment it resolves.
/// [repin] is the test's own write.
class PinnedGrid extends WeeklyGridNotifier {
  PinnedGrid(Ref ref, this.pinned) : super(null, ref) {
    super.state = pinned;
  }

  WeeklyGridState pinned;

  @override
  set state(WeeklyGridState value) => super.state = pinned;

  void repin(WeeklyGridState next) {
    pinned = next;
    super.state = next;
  }
}

/// A dashboard pinned the same way, so a counted habit's today and
/// yesterday counts are exactly what the test says.
class PinnedDashboard extends DashboardNotifier {
  PinnedDashboard(this.pinned) : super(null) {
    super.state = pinned;
  }

  DashboardState pinned;

  @override
  set state(DashboardState value) => super.state = pinned;

  void repin(DashboardState next) {
    pinned = next;
    super.state = next;
  }
}

IslamicHabitTemplate fixtureHabit(
  String id,
  String en,
  String ar, {
  HabitFrequencyType type = HabitFrequencyType.daily,
  int target = 1,
  List<int> weekdays = const [],
  GoalType goal = GoalType.build,
  DateTime? createdAt,
  DateTime? archivedAt,
  int? stepGoal,
  List<PastCadence> past = const [],
}) =>
    IslamicHabitTemplate(
      id: id,
      name: en,
      nameAr: ar,
      description: '',
      category: HabitCategory.custom,
      frequencyType: type,
      frequencyTarget: target,
      scheduledWeekdays: weekdays,
      goalType: goal,
      hasTimer: false,
      xpReward: 10,
      goldReward: 5,
      createdAt: createdAt,
      archivedAt: archivedAt,
      stepGoal: stepGoal,
      pastCadences: past,
    );

const _monThu = HabitCadence(
  frequencyType: HabitFrequencyType.weekly,
  frequencyTarget: 2,
  scheduledWeekdays: [DateTime.monday, DateTime.thursday],
);
const _daily = HabitCadence(
  frequencyType: HabitFrequencyType.daily,
  frequencyTarget: 1,
);

/// The board for the Saturday week starting at [weekStart] (local midnight),
/// with [today] deciding which habit was archived today.
class BoardFixture {
  BoardFixture(this.weekStart, {required DateTime now})
      : today = DateTime(now.year, now.month, now.day);

  final DateTime weekStart;
  final DateTime today;

  /// The week's days exactly as the notifier builds them, a daylight-saving
  /// week's repeated or shifted instants included.
  List<DateTime> get days =>
      WeeklyGridState(weekStart: weekStart, states: const {}, notes: const {})
          .days;

  DateTime _at(int dayOffset, int hour, [int minute = 0]) => DateTime(
      weekStart.year, weekStart.month, weekStart.day + dayOffset, hour, minute);

  bool get _holdsToday => days.any((d) => d.isSameDayAs(today));

  late final List<IslamicHabitTemplate> habits = [
    fixtureHabit('h_daily', 'Daily read', 'قراءة يومية',
        createdAt: _at(-30, 9, 30)),
    fixtureHabit('h_monthu', 'Mon Thu fast', 'صيام الاثنين والخميس',
        type: HabitFrequencyType.weekly,
        target: 2,
        weekdays: const [DateTime.monday, DateTime.thursday],
        createdAt: _at(-30, 9, 30)),
    fixtureHabit('h_quota', 'Gym four a week', 'نادي أربع مرات',
        type: HabitFrequencyType.weekly,
        target: 4,
        createdAt: _at(-30, 9, 30)),
    fixtureHabit('h_counted', 'Water three times', 'ماء ثلاث مرات',
        target: 3, createdAt: _at(-30, 9, 30)),
    fixtureHabit('h_steps', 'Walk', 'مشي',
        stepGoal: 8000, createdAt: _at(-30, 9, 30)),
    fixtureHabit('h_born', 'Born midweek', 'بدأت وسط الأسبوع',
        createdAt: _at(3, 9, 30)),
    fixtureHabit('h_archived', 'Paused one', 'عادة موقوفة',
        createdAt: _at(-30, 9, 30),
        archivedAt: _holdsToday
            ? DateTime(today.year, today.month, today.day, 8)
            : _at(4, 20)),
    fixtureHabit('h_changed', 'Now daily', 'صارت يومية',
        createdAt: _at(-30, 9, 30),
        past: [PastCadence(until: _at(2, 0), cadence: _monThu)]),
    fixtureHabit('h_changed_quota', 'Now three a week', 'صارت ثلاث مرات',
        type: HabitFrequencyType.weekly,
        target: 3,
        createdAt: _at(-30, 9, 30),
        past: [PastCadence(until: _at(3, 0), cadence: _daily)]),
    fixtureHabit('h_quit', 'No sugar', 'بدون سكر',
        goal: GoalType.quit),
    fixtureHabit('h_moved', 'Mon Thu swim', 'سباحة الاثنين والخميس',
        type: HabitFrequencyType.weekly,
        target: 2,
        weekdays: const [DateTime.monday, DateTime.thursday],
        createdAt: _at(-30, 9, 30)),
    fixtureHabit('h_quota_half', 'Run three a week', 'جري ثلاث مرات',
        type: HabitFrequencyType.weekly,
        target: 3,
        createdAt: _at(-30, 9, 30)),
  ];

  /// Saturday first: '.' none, p partial, c complete, f failed, b bonus,
  /// s skipped.
  static const Map<String, String> squareRows = {
    'h_daily': 'cpf.bs.',
    'h_monthu': '..c..p.',
    'h_quota': 'c.c.p..',
    'h_counted': 'p.c.f..',
    'h_steps': '.c...s.',
    'h_born': '....c..',
    'h_archived': 'c.c.c..',
    'h_changed': '...c...',
    'h_changed_quota': 'c...c..',
    'h_quit': 'c.f.cb.',
    'h_moved': '....c..',
    'h_quota_half': 'p.p.c..',
  };

  static const _marks = {
    'p': SquareState.partial,
    'c': SquareState.complete,
    'f': SquareState.failed,
    'b': SquareState.bonus,
    's': SquareState.skipped,
  };

  /// (habit, day index) → note. The blank one is a tombstone: an old clear
  /// stored '' or spaces rather than deleting the key.
  static const Map<(String, int), String> noteCells = {
    ('h_daily', 1): 'felt good',
    ('h_quota', 3): '   ',
    ('h_moved', 2): 'moved to Wednesday',
    ('h_archived', 0): 'last one',
  };

  /// (habit, day index) squares carrying a recording.
  static const List<(String, int)> voiceCells = [
    ('h_monthu', 3),
    ('h_steps', 0),
    ('h_quit', 6),
    ('h_counted', 1),
  ];

  /// The walk's count per day; a null day has no read.
  static const List<int?> stepCounts = [9120, 3210, 0, 5480, 12640, null, 7300];

  WeeklyGridState state() {
    final d = days;
    final states = <String, Map<String, SquareState>>{};
    final notes = <String, Map<String, String>>{};
    squareRows.forEach((id, row) {
      for (var i = 0; i < 7; i++) {
        final mark = _marks[row[i]];
        if (mark != null) (states[d[i].toDateKey()] ??= {})[id] = mark;
      }
    });
    noteCells.forEach((cell, text) {
      (notes[d[cell.$2].toDateKey()] ??= {})[cell.$1] = text;
    });
    return WeeklyGridState(weekStart: weekStart, states: states, notes: notes);
  }

  Map<String, int> steps() => {
        for (var i = 0; i < 7; i++)
          if (stepCounts[i] != null) days[i].toDateKey(): stepCounts[i]!,
      };

  List<String> voiceKeys() => [
        for (final (id, i) in voiceCells) squareVoiceKey(id, days[i]),
      ];

  /// Two of three done today, one of three yesterday.
  DashboardState dashboard() {
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    return DashboardState.initial().copyWith(
      isLoading: false,
      completions: const {'h_counted': 2},
      graceDayKey: yesterday.toDateKey(),
      graceCompletions: const {'h_counted': 1},
    );
  }
}
