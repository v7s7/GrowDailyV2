// Pause / resume / delete-forever on a habit.
//
// The behaviors that matter to a person: pausing must never lose a day,
// resuming must bring back the SAME habit (same id, so every streak,
// square and room link reattaches), and deleting forever must actually
// be forever. These run the real notifier against Hive in guest mode.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/habits/catalog/habit_plans.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/core/constants/game_constants.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('gd_pause_test');
    Hive.init(tmp.path);
    // The notifier's constructor loads guest state, which opens these
    // boxes; opening them up front keeps every test synchronous after
    // construction.
    await Hive.openBox<dynamic>(GameConstants.boxHabits);
    await Hive.openBox<dynamic>(GameConstants.boxSettings);
  });

  tearDown(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  IslamicHabitTemplate custom(String id, String name) => IslamicHabitTemplate(
        id: id,
        name: name,
        description: '',
        category: HabitCategory.custom,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
        hasTimer: false,
        xpReward: 10,
        goldReward: 5,
      );

  test('pausing a completed habit keeps it, resuming restores the same id',
      () {
    final n = CustomHabitsNotifier(null)
      ..state = [custom('h1', 'قيام الليل')];

    n.archive('h1', everCompleted: true);
    expect(n.state.any((h) => h.id == 'h1'), isFalse,
        reason: 'off the board immediately');
    expect(n.archived.map((h) => h.id), contains('h1'),
        reason: 'kept, not destroyed — this is the whole point of pause');
    expect(n.archived.first.archivedAt, isNotNull);

    n.unarchive('h1');
    expect(n.state.map((h) => h.id), contains('h1'));
    expect(n.archived, isEmpty);
    // Same id is what makes every square, streak and room link reattach
    // rather than the habit coming back as a stranger.
    expect(n.state.first.id, 'h1');
    expect(n.state.first.archivedAt, isNull);
    expect(n.state.first.name, 'قيام الليل');
  });

  test('REMOVE of a habit never once completed hard-deletes it', () {
    // Nothing to preserve, and a ghost row that lingers reads as "why
    // will this not delete". This is the multi-select remove path, whose
    // promise is that the habit goes away.
    final n = CustomHabitsNotifier(null)..state = [custom('h2', 'تجربة')];
    n.archive('h2', everCompleted: false);
    expect(n.state, isEmpty);
    expect(n.archived, isEmpty, reason: 'nothing to resume later');
  });

  test('PAUSE of a habit never once completed keeps it, because pause '
      'promises it comes back', () {
    // The opposite promise from remove, on the same underlying call. The
    // pause sheet says the record is kept and the habit returns whenever
    // you want; before eraseIfEmpty existed, pausing a habit you had not
    // completed yet destroyed it on the spot, and the destruction was
    // invisible precisely because there was no history to miss.
    final n = CustomHabitsNotifier(null)..state = [custom('h2b', 'تجربة')];
    n.archive('h2b', everCompleted: false, eraseIfEmpty: false);
    expect(n.state, isEmpty, reason: 'off the board');
    expect(n.archived.map((h) => h.id), contains('h2b'),
        reason: 'and still resumable, which is what pause promised');
    n.unarchive('h2b');
    expect(n.state.map((h) => h.id), contains('h2b'));
  });

  test('deleteForever removes an ACTIVE habit and leaves nothing to resume',
      () {
    final n = CustomHabitsNotifier(null)..state = [custom('h3', 'شيء')];
    n.deleteForever('h3');
    expect(n.state, isEmpty);
    expect(n.archived, isEmpty);
  });

  test('deleteForever also reaches a habit that is already paused', () {
    // The paused list is where someone sees an old habit and decides they
    // are truly done with it, so delete has to work from there too.
    final n = CustomHabitsNotifier(null)..state = [custom('h4', 'قديم')];
    n.archive('h4', everCompleted: true);
    expect(n.archived, hasLength(1));
    n.deleteForever('h4');
    expect(n.archived, isEmpty);
    expect(n.state, isEmpty);
  });

  test('unarchive is safe to call twice — Undo can be tapped twice', () {
    final n = CustomHabitsNotifier(null)..state = [custom('h5', 'ذكر')];
    n.archive('h5', everCompleted: true);
    n.unarchive('h5');
    n.unarchive('h5');
    expect(n.state.where((h) => h.id == 'h5'), hasLength(1),
        reason: 'no duplicate row from a double Undo');
  });

  test('deleteForever on an unknown id changes nothing', () {
    final n = CustomHabitsNotifier(null)..state = [custom('h6', 'باقٍ')];
    n.deleteForever('does-not-exist');
    expect(n.state, hasLength(1));
  });

  test('pausing a preset and resuming it the same day records no stint '
      'boundary at all', () async {
    // allHabitsEverProvider states the invariant out loud: real stints
    // never overlap, so at most one synthetic template claims any given
    // day. A same-day pause then resume used to close a window ending
    // today and open another starting today, and both claimed today, so
    // the Heatmap and Insights counted it twice. Now that Pause and
    // Resume are one tap apart this stopped being a rare sequence.
    final n = ActiveCatalogNotifier(null);
    const id = 'quran_daily_page';
    n.activatedAt = {id: DateTime.now().effectiveDay.subtract(
      const Duration(days: 30),
    )};
    n.state = {id};

    n.toggle(id, everCompleted: true, eraseIfEmpty: false);
    expect(n.state.contains(id), isFalse);
    expect(n.catalogArchivedAt[id], isNotNull);

    n.toggle(id);
    expect(n.state.contains(id), isTrue, reason: 'back on the board');
    expect(n.catalogStintHistory[id] ?? const [], isEmpty,
        reason: 'no closed stint: the day never actually ended');
    expect(n.catalogArchivedAt.containsKey(id), isFalse);
    // And the original start survives, so the habit reads as one
    // continuous run rather than as starting over today.
    expect(
      n.activatedAt[id]!.isSameDayAs(
        DateTime.now().effectiveDay.subtract(const Duration(days: 30)),
      ),
      isTrue,
    );
    // ActiveCatalogNotifier persists in the background; let those writes
    // land before tearDown closes the boxes underneath them.
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  test('Plans switching a preset off and back on the same day records no '
      'stint either', () async {
    // applyPlanSelection is the other door into the same data. Someone who
    // turns a plan off and back on in one sitting must not end up with two
    // windows both claiming today, for the same reason toggle must not.
    final n = ActiveCatalogNotifier(null);
    final plan = habitPlans.first;
    final id = plan.catalogIds.first;
    final start = DateTime.now().effectiveDay.subtract(
      const Duration(days: 12),
    );
    n.activatedAt = {id: start};
    n.catalogArchivedAt = {id: DateTime.now().effectiveDay};

    n.applyPlanSelection(plan, {id});
    expect(n.catalogStintHistory[id] ?? const [], isEmpty);
    expect(n.activatedAt[id]!.isSameDayAs(start), isTrue,
        reason: 'one uninterrupted window, still starting when it started');
    expect(n.catalogArchivedAt.containsKey(id), isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  test('pausing a preset and resuming on a LATER day does record the stint',
      () async {
    // The counterpart to the test above: a real gap is real history and
    // must still be preserved, or the Heatmap loses the old window.
    final n = ActiveCatalogNotifier(null);
    const id = 'quran_daily_page';
    final start = DateTime.now().effectiveDay.subtract(
      const Duration(days: 30),
    );
    final endedYesterday = DateTime.now().effectiveDay.subtract(
      const Duration(days: 1),
    );
    n.activatedAt = {id: start};
    n.catalogArchivedAt = {id: endedYesterday};

    n.toggle(id);
    expect(n.catalogStintHistory[id], hasLength(1));
    expect(n.catalogStintHistory[id]!.first.$1.isSameDayAs(start), isTrue);
    expect(n.catalogStintHistory[id]!.first.$2.isSameDayAs(endedYesterday),
        isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  test('a habit paused TODAY is still listed as paused, so Resume is '
      'reachable the same day', () {
    // The hole this closes: a habit paused today leaves the active list
    // at once, and the paused list used to skip anything paused today (on
    // the theory that Grid still shows its row). That left the whole rest
    // of the day with no way back once the six-second Undo expired. Grid
    // now paints that row as paused and this list still offers Resume.
    final container = ProviderContainer(
      overrides: [
        customHabitsProvider.overrideWith((ref) {
          return CustomHabitsNotifier(null)..state = [custom('h7', 'تمرين')];
        }),
      ],
    );
    addTearDown(container.dispose);

    container.read(customHabitsProvider.notifier)
        .archive('h7', everCompleted: true);

    final paused = container.read(pausedHabitsProvider);
    expect(paused.map((h) => h.id), contains('h7'),
        reason: 'paused today must still be resumable today');
    // And Grid keeps the row for the rest of the day, so today's earned
    // squares do not blank out mid-day.
    expect(container.read(habitsArchivedTodayProvider).map((h) => h.id),
        contains('h7'));
  });
}
