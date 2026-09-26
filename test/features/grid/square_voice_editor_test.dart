// The square's editor records voice notes, as a task's sheets do (Premium),
// and a square someone only spoke about gets the same folded corner as a
// written one (square_voice_notes.dart).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/features/grid/notifiers/square_voice_notes.dart';
import 'package:grow_daily_v2/features/grid/widgets/note_corner.dart';
import 'package:grow_daily_v2/features/matrix/widgets/voice_note_player.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';

import '../../helpers/landing_harness.dart';

/// A store whose index never answers: an offline first start, or a load
/// that failed. The square's own recordings still read.
class _IndexNeverLoads extends SquareVoiceStore {
  @override
  Future<Map<String, int>> loadCounts(String? uid) =>
      Completer<Map<String, int>>().future;
}

void main() {
  const s = S(Locale('en'));
  final today = DateTime.now().effectiveDay;
  final key = squareVoiceKey('inbox_zero', today);

  Finder todaySquare() {
    final date = DateFormat('EEEE d MMMM', 'en').format(today);
    return find.bySemanticsLabel(RegExp('^Inbox Zero, ${RegExp.escape(date)}'));
  }

  Iterable<NoteCornerPainter> marks(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((c) => c.painter)
      .whereType<NoteCornerPainter>();

  Future<void> openEditor(WidgetTester tester, LandingHarness h) async {
    await h.pumpApp(tester);
    await tester.ensureVisible(todaySquare());
    await h.settle(tester);
    await tester.longPress(todaySquare());
    await h.settle(tester);
    expect(find.text(s.gridSave), findsOneWidget,
        reason: 'the long-press editor did not open');
  }

  Finder recordRow() => find.byType(VoiceNoteRecordRow);

  group('a free account', () {
    late LandingHarness h;

    setUp(() async {
      h = LandingHarness();
      await h.prepare(activeCatalogIds: const ['inbox_zero']);
      (await LocalStoreService.dailyBox()).clear();
      (await LocalStoreService.settingsBox()).delete(kGuestSquareVoiceKey);
    });
    tearDown(() => h.dispose());

    testWidgets('sees the mic with its lock, and the tap is the pitch',
        (tester) async {
      await openEditor(tester, h);
      expect(recordRow(), findsOneWidget);
      expect(tester.widget<VoiceNoteRecordRow>(recordRow()).locked, isTrue);

      await tester.ensureVisible(recordRow());
      await tester.tap(recordRow());
      await h.settle(tester);
      expect(find.text(s.voiceNoteGateTitle), findsOneWidget);
      expect(find.text(s.voiceNoteGateBody), findsOneWidget);
    });
  });

  group('recordings on a square', () {
    late LandingHarness h;

    setUp(() async {
      h = LandingHarness();
      await h.prepare(
        activeCatalogIds: const ['inbox_zero'],
        extraOverrides: [premiumAccessProvider.overrideWith((ref) => true)],
      );
      (await LocalStoreService.dailyBox()).clear();
      // Seeded in setUp, outside the widget test's fake clock, where Hive's
      // own I/O can finish (see widget-tests notes on fake async).
      await (await LocalStoreService.settingsBox()).put(kGuestSquareVoiceKey, {
        key: [
          {
            'id': 'v1',
            'path': '',
            'name': '',
            'durationSeconds': 9,
            'createdAt': today.toIso8601String(),
          },
        ],
      });
    });
    tearDown(() => h.dispose());

    testWidgets('a square with only a recording carries the corner',
        (tester) async {
      await h.pumpApp(tester);
      expect(marks(tester), hasLength(1),
          reason: 'a day someone spoke about is as findable as a written one');
    });

    testWidgets('Premium: the recording is listed, the mic is open',
        (tester) async {
      await openEditor(tester, h);
      expect(find.text(s.voiceNoteDefaultName(1)), findsOneWidget);
      expect(tester.widget<VoiceNoteRecordRow>(recordRow()).locked, isFalse);
    });

    testWidgets('deleting it clears the list, the corner and the store',
        (tester) async {
      await openEditor(tester, h);
      final delete = find.descendant(
        of: find.byType(VoiceNoteRow),
        matching: find.byIcon(Icons.close_rounded),
      );
      await tester.ensureVisible(delete);
      // On the real clock: the delete writes the guest's list to Hive, and a
      // disk write started on the test's fake clock never finishes, which
      // then stalls every later write to the same box, the next test's
      // setUp included (the widget-tests-and-Hive trap).
      await tester.runAsync(() async {
        await tester.tap(delete);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await h.settle(tester);

      expect(find.byType(VoiceNoteRow), findsNothing);
      expect(h.container.read(squareVoiceIndexProvider), isEmpty);
      final stored = (await LocalStoreService.settingsBox())
          .get(kGuestSquareVoiceKey) as Map?;
      expect(stored?.containsKey(key) ?? false, isFalse);
    });
  });

  // The safety net for the one way recordings could have been lost: an
  // editor that trusted an index which never loaded would have believed the
  // square empty, and a rewrite from it would have replaced what is saved.
  group('when the index never loads', () {
    late LandingHarness h;

    setUp(() async {
      h = LandingHarness();
      await h.prepare(
        activeCatalogIds: const ['inbox_zero'],
        extraOverrides: [
          premiumAccessProvider.overrideWith((ref) => true),
          squareVoiceStoreProvider.overrideWithValue(_IndexNeverLoads()),
        ],
      );
      (await LocalStoreService.dailyBox()).clear();
      await (await LocalStoreService.settingsBox()).put(kGuestSquareVoiceKey, {
        key: [
          {
            'id': 'v1',
            'path': '',
            'name': 'kept',
            'durationSeconds': 9,
            'createdAt': today.toIso8601String(),
          },
        ],
      });
    });
    tearDown(() => h.dispose());

    testWidgets('the editor reads the square itself and shows what is saved',
        (tester) async {
      await openEditor(tester, h);
      expect(h.container.read(squareVoiceIndexProvider.notifier).loaded,
          isFalse);
      expect(find.text('kept'), findsOneWidget,
          reason: 'an unloaded index says nothing about this square, so the '
              'editor must read it rather than show it empty');
    });
  });
}
