// A square someone only SPOKE about belongs in Habit Notes too, with its
// real colour, and a written note's entry carries its recordings' count
// (grid_journal_notifier.dart, square_voice_notes.dart).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/grid_journal_notifier.dart';
import 'package:grow_daily_v2/features/grid/notifiers/square_voice_notes.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tmp;
  // Days early in the current month, so the journal's first load reads them.
  final today = DateTime.now().effectiveDay;
  final monthStart = DateTime(today.year, today.month, 1);

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('square_voice_journal_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings');
    await Hive.openBox<dynamic>('box_daily_logs');
  });

  tearDown(() async {
    await LocalStoreService.settleDailyWrites();
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  Future<GridJournalNotifier> loaded(Map<String, int> counts) async {
    final journal = GridJournalNotifier(null, voiceCounts: () => counts);
    for (var i = 0; i < 200 && journal.state.isLoading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(journal.state.isLoading, isFalse);
    return journal;
  }

  test('a green square with only a recording is an entry, still green',
      () async {
    await LocalStoreService.updateDailyMap(monthStart.toDateKey(), (m) {
      m['squareStates'] = {'walk': SquareState.complete.name};
    });
    final journal =
        await loaded({squareVoiceKey('walk', monthStart): 2});

    final entry = journal.state.entries
        .singleWhere((e) => e.habitId == 'walk' && e.day == monthStart);
    expect(entry.voiceCount, 2);
    expect(entry.note, isEmpty);
    expect(entry.state, SquareState.complete,
        reason: 'filing it as «لم يكتمل» would contradict the board');
    journal.dispose();
  });

  test('a written note carries its recordings, one entry not two', () async {
    await LocalStoreService.updateDailyMap(monthStart.toDateKey(), (m) {
      m['squareNotes'] = {'walk': 'long walk by the sea'};
    });
    final journal =
        await loaded({squareVoiceKey('walk', monthStart): 1});

    final entries = journal.state.entries
        .where((e) => e.habitId == 'walk' && e.day == monthStart);
    expect(entries, hasLength(1));
    expect(entries.single.note, 'long walk by the sea');
    expect(entries.single.voiceCount, 1);
    journal.dispose();
  });

  test('recordings on a day nothing else was saved still show', () async {
    final journal =
        await loaded({squareVoiceKey('walk', monthStart): 1});
    final entry = journal.state.entries
        .singleWhere((e) => e.habitId == 'walk' && e.day == monthStart);
    expect(entry.state, SquareState.none);
    expect(entry.voiceCount, 1);
    journal.dispose();
  });

  test('voiceChanged adds, updates and removes, keeping the real state',
      () async {
    final journal = await loaded(const {});
    expect(journal.state.entries, isEmpty);

    journal.voiceChanged(monthStart, 'walk', 1,
        squareState: SquareState.complete);
    expect(journal.state.entries.single.voiceCount, 1);
    expect(journal.state.entries.single.state, SquareState.complete);

    journal.voiceChanged(monthStart, 'walk', 3,
        squareState: SquareState.complete);
    expect(journal.state.entries.single.voiceCount, 3);

    journal.voiceChanged(monthStart, 'walk', 0,
        squareState: SquareState.complete);
    expect(journal.state.entries, isEmpty,
        reason: 'a plain green square with nothing said is not an entry');
    journal.dispose();
  });

  test('clearing the written note keeps a square that still has recordings',
      () async {
    final journal = await loaded(const {});
    journal.voiceChanged(monthStart, 'walk', 1,
        squareState: SquareState.complete);
    journal.noteChanged(monthStart, 'walk', 'a note',
        squareState: SquareState.complete);
    journal.noteChanged(monthStart, 'walk', '',
        squareState: SquareState.complete);

    final entry = journal.state.entries.single;
    expect(entry.note, isEmpty);
    expect(entry.voiceCount, 1);
    journal.dispose();
  });
}
