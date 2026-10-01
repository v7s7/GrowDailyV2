// The board's entrance fades draw exactly what flutter_animate drew, frame
// for frame, now that they are the board's own once-only fade (_OnceFade in
// grid_screen_table.dart), and they no longer leave a CurvedAnimation behind
// on every rebuild.
//
// Each row fades in on entrance (`.animate(delay: i * 45ms).fadeIn(320ms)`)
// and each marked square that is not green fades from 0.6
// (`.animate(key: ValueKey(square)).fadeIn(180ms, begin: 0.6)`).
// flutter_animate builds a new CurvedAnimation for each of them on EVERY
// build, and each one adds a status listener to the fade's controller that is
// never removed, so a week left on screen piled up one per row and per marked
// square with every tap.
//
// The trace below was recorded from the board as it was, with the library's
// chain, and frozen: every FadeTransition of every board, its opacity and
// whether it is a repaint boundary, on every 8ms frame of a run that removes
// and re-adds a row while the rows are still staggering in, rebuilds the
// board, changes marked squares mid-fade, mutes the tickers and lets them go
// again, and unmounts the board before its later rows have started.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/habits/notifiers/newly_added_habit_provider.dart';

import '../../helpers/landing_harness.dart';
import 'board_parity_fixture.dart';

/// The trace's digest, frozen from the board before the change and never
/// regenerated. Keyed by the zone's offsets like
/// grid_week_facts_parity_test.dart: a zone not listed still runs every other
/// check, only without the frozen trace.
const Map<String, String> _frozen = {
  // Asia/Riyadh and Asia/Bahrain: no daylight saving.
  '180/180':
      'e7e58ab1e429caeb6e6101aa1e685034a51339d1069efa90cc220dcff1de8a50',
};

String _zoneFingerprint() => [
      DateTime(2026, 3, 7),
      DateTime(2026, 3, 13),
    ].map((d) => d.timeZoneOffset.inMinutes).join('/');

/// Lets a test mute every ticker under the app, the way an opaque route
/// does, and let them go again.
class _Gate extends StatefulWidget {
  const _Gate({super.key, required this.child});
  final Widget child;
  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  bool on = true;
  void set(bool value) => setState(() => on = value);
  @override
  Widget build(BuildContext context) =>
      TickerMode(enabled: on, child: widget.child);
}

/// The habits the board is drawing, which the run edits mid-entrance.
final _habitsNow = StateProvider<List<IslamicHabitTemplate>>((ref) => []);

/// Every board's fades, in tree order: "opacity|repaintBoundary".
String _frame() => [
      for (final table in find
          .byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_GridTable',
            skipOffstage: false,
          )
          .evaluate())
        [
          for (final fade in find
              .descendant(
                of: find.byElementPredicate((e) => e == table),
                matching: find.byType(FadeTransition, skipOffstage: false),
              )
              .evaluate())
            () {
              final box = fade.renderObject! as RenderAnimatedOpacity;
              return '${box.opacity.value}|${box.isRepaintBoundary}';
            }(),
        ].join(','),
    ].join('#');

/// [fixture]'s squares, with [edits] ((habit, day index) → mark, null for
/// none) laid over them.
WeeklyGridState _stateWith(
  BoardFixture fixture,
  Map<(String, int), SquareState?> edits,
) {
  final base = fixture.state();
  final days = fixture.days;
  final states = {
    for (final e in base.states.entries) e.key: {...e.value},
  };
  edits.forEach((cell, mark) {
    final key = days[cell.$2].toDateKey();
    final day = states[key] ??= {};
    if (mark == null) {
      day.remove(cell.$1);
    } else {
      day[cell.$1] = mark;
    }
  });
  return WeeklyGridState(
    weekStart: base.weekStart,
    states: states,
    notes: base.notes,
  );
}

void main() {
  late LandingHarness h;
  late BoardFixture fixture;

  Future<void> prepare(WeeklyGridState Function() state) async {
    h = LandingHarness();
    await h.prepare(extraOverrides: [
      _habitsNow.overrideWith((ref) => fixture.habits),
      habitListProvider.overrideWith((ref) => ref.watch(_habitsNow)),
      habitsArchivedTodayProvider.overrideWith((ref) => const []),
      weeklyGridProvider.overrideWith((ref) => PinnedGrid(ref, state())),
      dashboardProvider
          .overrideWith((ref) => PinnedDashboard(fixture.dashboard())),
    ]);
  }

  PinnedGrid grid() => h.container.read(weeklyGridProvider.notifier) as PinnedGrid;

  group('the entrance, frame by frame', () {
    setUp(() async {
      fixture = BoardFixture(DateTime(2026, 3, 7), now: DateTime.now());
      await prepare(fixture.state);
    });
    tearDown(() => h.dispose());

    testWidgets('matches the frozen trace of flutter_animate\'s fades',
        (tester) async {
      final gate = GlobalKey<_GateState>();
      await tester.pumpWidget(_Gate(key: gate, child: h.app()));
      final frames = <String>[_frame()];
      final daily = fixture.habits.first;
      var rebuilds = 0;
      for (var ms = 8; ms <= 1400; ms += 8) {
        switch (ms) {
          // A row leaves while the rows are still staggering in: every row
          // below it moves up a slot, keeping its fade, and the last slot's
          // fade goes with the tree.
          case 48:
            h.container.read(_habitsNow.notifier).state =
                fixture.habits.skip(1).toList();
          // The board alone rebuilds, mid-fade.
          case 104:
          case 136:
            h.container.read(newlyAddedHabitIdProvider.notifier).state =
                'nobody-${rebuilds++}';
          // Marked squares change mid-fade: one marked to another (its fade
          // starts again), one emptied (its fade goes), one newly marked.
          case 160:
            grid().repin(_stateWith(fixture, {
              ('h_monthu', 5): SquareState.failed,
              ('h_quota', 4): null,
              ('h_steps', 3): SquareState.skipped,
            }));
          case 240:
            gate.currentState!.set(false);
          // The row comes back, at the top, while the tickers are muted.
          case 300:
            h.container.read(_habitsNow.notifier).state = [
              daily,
              ...fixture.habits.skip(1),
            ];
          case 400:
            gate.currentState!.set(true);
          // The whole screen rebuilds with the same week.
          case 520:
            grid().repin(_stateWith(fixture, {
              ('h_monthu', 5): SquareState.failed,
              ('h_quota', 4): null,
              ('h_steps', 3): SquareState.skipped,
            }));
          case 600:
            grid().repin(_stateWith(fixture, {
              ('h_monthu', 5): SquareState.failed,
              ('h_quota', 4): null,
              ('h_steps', 3): SquareState.skipped,
              ('h_daily', 1): SquareState.failed,
            }));
        }
        await tester.pump(const Duration(milliseconds: 8));
        frames.add(_frame());
      }
      // Unmounted before the later rows have started: nothing throws, and
      // the fades that never ran leave nothing behind.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_Gate(child: h.app()));
      await tester.pump(const Duration(milliseconds: 20));
      frames.add(_frame());
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));

      // The run reaches what it is for.
      final values = {
        for (final f in frames)
          for (final t in f.split('#'))
            for (final e in t.split(','))
              if (e.isNotEmpty) double.parse(e.split('|').first),
      };
      expect(values, contains(0.0), reason: 'a row before its fade');
      expect(values, contains(0.6), reason: 'a square before its fade');
      expect(values, contains(1.0));
      expect(values.where((v) => v > 0 && v < 0.6), isNotEmpty);
      expect(values.where((v) => v > 0.6 && v < 1), isNotEmpty);

      final digest =
          sha256.convert(utf8.encode(frames.join('\n'))).toString();
      final key = _zoneFingerprint();
      final frozen = _frozen[key];
      if (frozen == null) {
        // ignore: avoid_print
        print('no frozen trace for "$key": $digest');
        return;
      }
      expect(digest, frozen);
    });
  });

  group('rebuilds', () {
    setUp(() async {
      fixture = BoardFixture(DateTime(2026, 3, 7), now: DateTime.now());
      // No green square (its shimmer has CurvedAnimations of its own), no
      // room (the 2x flame) and no new habit (its highlight).
      await prepare(() {
        final all = fixture.state();
        return WeeklyGridState(
          weekStart: all.weekStart,
          states: {
            for (final e in all.states.entries)
              e.key: {
                for (final s in e.value.entries)
                  if (!s.value.isGreen) s.key: s.value,
              },
          },
          notes: all.notes,
        );
      });
    });
    tearDown(() => h.dispose());

    testWidgets('leave no CurvedAnimation behind, and the fades are disposed '
        'with the board', (tester) async {
      await h.pumpApp(tester);
      // The fades' own curves: a controller of 320ms (a row) or 180ms (a
      // marked square). Nothing else on the board runs for either.
      bool isFade(Object o) {
        if (o is! CurvedAnimation) return false;
        final parent = o.parent;
        return parent is AnimationController &&
            (parent.duration == const Duration(milliseconds: 320) ||
                parent.duration == const Duration(milliseconds: 180));
      }

      var created = 0;
      var disposed = 0;
      void listen(ObjectEvent event) {
        if (!isFade(event.object)) return;
        if (event is ObjectCreated) created++;
        if (event is ObjectDisposed) disposed++;
      }

      FlutterMemoryAllocations.instance.addListener(listen);
      addTearDown(
          () => FlutterMemoryAllocations.instance.removeListener(listen));
      for (var i = 0; i < 10; i++) {
        h.container.read(newlyAddedHabitIdProvider.notifier).state =
            'nobody-$i';
        await tester.pump();
      }
      // ignore: avoid_print
      print('fade curves made by 10 board rebuilds: $created');
      expect(created, 0);

      // Mounted again from nothing and taken away: every fade made is gone.
      await tester.pumpWidget(const SizedBox());
      created = 0;
      disposed = 0;
      await h.pumpApp(tester);
      final made = created;
      await tester.pumpWidget(const SizedBox());
      expect(made, greaterThan(0));
      expect(disposed, made);
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
