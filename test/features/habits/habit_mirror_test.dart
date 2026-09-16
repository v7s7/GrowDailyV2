// The device's copy of the habit board, and the one rule that keeps it safe.
//
// The mirror exists so the rows paint in the first frame instead of after a
// server round trip. The danger it carries is that a guess gets mistaken for
// an answer: an empty or short habit list is indistinguishable from "this
// person has no habits", and acting on that cancels real AlarmKit alarms (see
// main.dart's _runRecomputeNotifications guard). The cases below pin the
// separation that prevents it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/services/habit_mirror.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('habit_mirror_test');
    Hive.init(tmp.path);
    // Seeded here rather than inside a test body: awaiting real I/O inside a
    // testWidgets body hangs the file silently.
    await Hive.openBox<dynamic>('box_settings');
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await Hive.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> saveBoard(String uid, {List<String> habitIds = const []}) =>
      HabitMirror.save(
        uid: uid,
        customHabits: [
          for (final id in habitIds) {'id': id, 'name': id},
        ],
        activeCatalogIds: const ['morning_athkar'],
        activatedAt: const {'morning_athkar': '2026-09-01T00:00:00.000'},
        catalogOverrides: const {},
        habitOrder: const {'morning_athkar': 1.5},
      );

  test('a board saved for one account comes back for that account', () async {
    await saveBoard('uid-a', habitIds: ['h1', 'h2']);
    await HabitMirror.load('uid-a');

    final snap = HabitMirror.snapshot;
    expect(snap, isNotNull);
    expect(snap!.uid, 'uid-a');
    expect(snap.customHabits.map((h) => h['id']), ['h1', 'h2']);
    expect(snap.activeCatalogIds, {'morning_athkar'});
    expect(snap.activatedAt['morning_athkar'], '2026-09-01T00:00:00.000');
    expect(snap.habitOrder['morning_athkar'], 1.5);
  });

  test("another account's board is never handed over", () async {
    await saveBoard('uid-a', habitIds: ['h1']);
    await HabitMirror.load('uid-b');
    expect(HabitMirror.snapshot, isNull,
        reason: 'signing in as somebody else must not show their habits');
  });

  test('a guest is given nothing, whatever is stored', () async {
    await saveBoard('uid-a', habitIds: ['h1']);
    await HabitMirror.load(null);
    expect(HabitMirror.snapshot, isNull,
        reason: 'the signed-out path has its own store and its own board');
  });

  test('an envelope from another build is ignored, not guessed at', () async {
    final box = Hive.box<dynamic>('box_settings');
    await box.put('habit_mirror_v1_uid-a', {
      'schemaVersion': 999,
      'uid': 'uid-a',
      'customHabits': [
        {'id': 'h1'},
      ],
    });
    await HabitMirror.load('uid-a');
    expect(HabitMirror.snapshot, isNull,
        reason: 'one ordinary launch rebuilds it; a wrong board is forever');
  });

  test('a deleted account leaves no board behind on the device', () async {
    await saveBoard('uid-a', habitIds: ['h1']);
    await HabitMirror.drop('uid-a');
    await HabitMirror.load('uid-a');
    expect(HabitMirror.snapshot, isNull);
  });

  test(
      'an account that genuinely has no habits round-trips as empty, not as '
      'absent', () async {
    // The distinction the whole design rests on. "No envelope" means the app
    // knows nothing and must keep the spinner up; an envelope holding an
    // empty list is a real answer that happens to be empty. Only the second
    // one may paint, and NEITHER may tell the reminder sweep anything — the
    // sweep reads habitsStillLoadingProvider, which this never touches.
    await saveBoard('uid-a');
    await HabitMirror.load('uid-a');

    expect(HabitMirror.snapshot, isNotNull,
        reason: 'an answer was stored, so there is something to paint');
    expect(HabitMirror.snapshot!.customHabits, isEmpty);
  });

  test(
      'a real habit survives the round trip the app actually performs, id '
      'included', () async {
    // Deliberately built from the REAL template and serialised exactly the
    // way main.dart's writer does, rather than from a hand-written map.
    // The first version of this suite hand-wrote {'id': ..., 'name': ...},
    // a shape the writer never produced: toFirestore() omits the id (in
    // Firestore the DOCUMENT carries it), so every mirrored custom habit was
    // dropped on hydrate and the suite passed anyway. A fixture that does not
    // come from the production writer cannot catch a production writer bug.
    const habit = IslamicHabitTemplate(
      id: 'habit-real',
      name: 'تمرين',
      description: '',
      category: HabitCategory.health,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 20,
      goldReward: 8,
    );
    await HabitMirror.save(
      uid: 'uid-a',
      customHabits: [
        {'id': habit.id, ...habit.toFirestore()},
      ],
      activeCatalogIds: const [],
      activatedAt: const {},
      catalogOverrides: const {},
      habitOrder: const {},
    );
    await HabitMirror.load('uid-a');

    final stored = HabitMirror.snapshot!.customHabits;
    expect(stored, hasLength(1));
    expect(stored.single['id'], 'habit-real',
        reason: 'without the id the hydrator drops the habit entirely');

    // And the hydrator's own parse, not a paraphrase of it.
    final restored = [
      for (final raw in stored)
        if (raw['id'] is String)
          IslamicHabitTemplate.fromMap(raw['id'] as String, raw),
    ];
    expect(restored, hasLength(1),
        reason: 'every stored habit must come back, or the board is short '
            'rows while claiming it is complete');
    expect(restored.single.id, 'habit-real');
    expect(restored.single.name, 'تمرين');
  });

  test('old accounts are pruned, the current one is always kept', () async {
    for (final uid in ['old-1', 'old-2', 'old-3', 'old-4']) {
      await saveBoard(uid, habitIds: ['h']);
    }
    await saveBoard('current', habitIds: ['h']);

    final box = Hive.box<dynamic>('box_settings');
    final kept = box.keys
        .whereType<String>()
        .where((k) => k.startsWith('habit_mirror_v1_'))
        .toList();
    expect(kept, contains('habit_mirror_v1_current'),
        reason: 'the account being used is never the one pruned');
    expect(kept.length, lessThanOrEqualTo(3),
        reason: 'a shared device must not accumulate boards without bound');
  });
}
