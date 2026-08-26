import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/matrix/models/matrix_task.dart';
import 'package:grow_daily_v2/features/matrix/widgets/task_detail_sheet.dart';
import 'package:grow_daily_v2/features/matrix/widgets/voice_note_player.dart';
import 'package:hive/hive.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Two reports against the task-edit sheet, both about the sheet as a
/// surface rather than about what it saves:
///
///  1. There was no Done. Title and description only ever wrote in
///     dispose(), so the sole way out was a swipe-dismiss — which reads as
///     "cancel", and left anyone who had just retyped a title with no
///     signal their edit had been kept.
///  2. The voice-notes block was the only part of the sheet that wasn't a
///     card: an 11px section label at one edge, the mic pill floating at
///     the other, and "tap to record" stranded on its own line under the
///     label, a sheet's width away from the button it describes.
///
/// Arabic/RTL throughout, because that's the app's default locale and both
/// defects are about where things land horizontally.
void main() {
  const dpr = 3.0;
  const ar = S(Locale('ar'));

  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  // Same setup reminder_layout_test.dart documents: date formatting for
  // 'ar', and a real settings box for MatrixNotifier's guest load, which
  // this sheet reaches through matrixProvider for its quadrant colour.
  // Opened out here in the real async zone so it's resolved before
  // pumpWidget's fake-async zone builds the tree.
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ar');
    tmp = await Directory.systemTemp.createTemp('task_detail_sheet_test_');
    Hive.init(tmp.path);
    if (!Hive.isBoxOpen('box_settings')) {
      await Hive.openBox<dynamic>('box_settings');
    }
  });

  tearDownAll(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    // iPhone 15 Pro logical size.
    view.physicalSize = const Size(402 * dpr, 874 * dpr);
    view.devicePixelRatio = dpr;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
    view.resetViewInsets();
  });

  MatrixTask taskWith({List<VoiceNote> notes = const []}) => MatrixTask(
        id: 't1',
        title: 'اقرأ وردك',
        quadrant: MatrixQuadrant.doFirst,
        isDone: false,
        createdAt: DateTime(2026, 8, 26, 9),
        voiceNotes: notes,
        order: 1,
      );

  /// Presented the way matrix_screen.dart's _openTaskDetails presents it —
  /// a real showModalBottomSheet with the same arguments. Rendered straight
  /// into a Scaffold body instead, the sheet would sit at the top of the
  /// screen under different constraints, and any assertion about where its
  /// footer lands would be measuring the harness rather than the sheet.
  Widget harness({
    required MatrixTask task,
    void Function(String id, String title)? onRename,
  }) {
    return ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
      ],
      child: MaterialApp(
        theme: GameTheme.dark,
        // The locale scope goes in `builder`, not around `home`: a sheet is
        // pushed onto the Navigator, so it's a sibling of `home` and would
        // never see an override nested inside it.
        builder: (context, child) => Localizations(
          locale: const Locale('ar'),
          delegates: _AnyLocale.delegates,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  useSafeArea: true,
                  builder: (_) => TaskDetailSheet(
                    task: task,
                    onRename: onRename ?? (_, __) {},
                    onUpdateDetails: (_, {description, clearDescription}) {},
                    onAddVoiceNote: (_, __) {},
                    onRenameVoiceNote: (_, __, ___) {},
                    onRemoveVoiceNote: (_, __) {},
                    onSetReminders: (_, __, {reminderAnchorAt}) {},
                    onDelete: () {},
                    onMove: (_) {},
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> open(WidgetTester tester, Widget app) async {
    await tester.pumpWidget(app);
    await tester.tap(find.text('open'));
    await tester.pump();
    // The sheet route animates in AND the card runs its own flutter_animate
    // slide, so a fixed pump can land mid-slide and measure the card
    // 40-odd points lower than where it settles.
    await tester.pumpAndSettle();
  }

  group('the way out of the sheet', () {
    testWidgets('Done is on screen without scrolling, and is not in the scroll',
        (tester) async {
      await open(tester, harness(task: taskWith()));

      final done = find.widgetWithText(FilledButton, ar.matrixDone);
      expect(done, findsOneWidget, reason: 'the sheet has no Done button');

      // Pinned, not scrolled. Delete and the whole move-to-quadrant list sit
      // below the fold on this screen, so a Done that lived inside the
      // scroll view would be exactly as hard to find as no Done at all.
      expect(
        find.ancestor(of: done, matching: find.byType(Scrollable)),
        findsNothing,
        reason: 'Done is inside the scroll view, so reaching it means '
            'scrolling past Delete first',
      );

      final rect = tester.getRect(done);
      final screen =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(
        rect.bottom,
        lessThanOrEqualTo(screen),
        reason: 'Done renders below the bottom of the screen',
      );
      expect(
        rect.width,
        greaterThan(200),
        reason: 'Done should span the sheet the way ADD TASK does',
      );
    });

    testWidgets('Done clears the Arabic keyboard', (tester) async {
      // The reported state, reproduced: the sheet open with the keyboard up,
      // which is how it looks the whole time anyone is editing a title. A
      // footer that lands under the keyboard is no better than no footer,
      // and this sheet's max height is computed from the full screen when
      // the keyboard is down — so the keyboard case needs its own check.
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
      // ~335pt of Arabic keyboard including the QuickType candidate bar.
      view.viewInsets = const FakeViewPadding(bottom: 335 * dpr);

      await open(tester, harness(task: taskWith()));

      expect(
        tester.takeException(),
        isNull,
        reason: 'the sheet overflowed with the keyboard up',
      );

      final rect =
          tester.getRect(find.widgetWithText(FilledButton, ar.matrixDone));
      expect(
        rect.bottom,
        lessThanOrEqualTo(874.0 - 335.0),
        reason: 'Done is under the keyboard, where it cannot be tapped',
      );
    });

    testWidgets('tapping Done closes the sheet and keeps the retyped title',
        (tester) async {
      String? renamedTo;
      await open(
        tester,
        harness(
          task: taskWith(),
          onRename: (_, title) => renamedTo = title,
        ),
      );

      await tester.enterText(find.byType(TextField).first, 'عاداتك تبنيك');
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, ar.matrixDone));
      await tester.pumpAndSettle();

      expect(
        find.byType(TaskDetailSheet),
        findsNothing,
        reason: 'Done did not close the sheet',
      );
      // The save still happens in dispose() — Done is an affordance for the
      // exit that already existed, not a second write path. This asserts the
      // two are actually wired to each other.
      expect(renamedTo, 'عاداتك تبنيك');
    });
  });

  group('the voice notes section', () {
    testWidgets('label, hint and mic sit together in one card', (tester) async {
      await open(tester, harness(task: taskWith()));

      final row = find.byType(VoiceNoteRecordRow);
      expect(row, findsOneWidget);

      // Both lines belong to the row now. They used to be a section label
      // and a stray hint stacked outside any container.
      expect(
        find.descendant(of: row, matching: find.text(ar.voiceNotesTitle)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.text(ar.voiceNoteTapToRecord),
        ),
        findsOneWidget,
      );

      // The reported defect, measured: the mic and the sentence telling you
      // to tap it were at opposite edges of a ~330pt-wide sheet. They're one
      // gutter apart now.
      final mic = tester.getRect(
        find.descendant(of: row, matching: find.byIcon(Icons.mic_rounded)),
      );
      final hint = tester.getRect(
        find.descendant(of: row, matching: find.text(ar.voiceNoteTapToRecord)),
      );
      final gap =
          mic.left > hint.right ? mic.left - hint.right : hint.left - mic.right;
      expect(
        gap,
        lessThan(24),
        reason: 'the mic is $gap pt from its own "tap to record" line; they '
            'are meant to be one row',
      );
    });

    testWidgets('recording turns the row red and puts the clock on it',
        (tester) async {
      // Driven directly rather than through the sheet: starting a real take
      // needs VoiceNoteService and a microphone permission, neither of which
      // a widget test (or a simulator I should be granting system
      // permissions on) can supply. The row is a dumb display, so handing it
      // the recording state is the whole of what the sheet does anyway.
      await tester.pumpWidget(
        MaterialApp(
          theme: GameTheme.dark,
          home: Localizations(
            locale: const Locale('ar'),
            delegates: _AnyLocale.delegates,
            // Not const: GameColors.gold is a mutable static (the theme
            // preset rewrites it), so nothing holding it can be.
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 330,
                    child: VoiceNoteRecordRow(
                      recording: true,
                      elapsed: const Duration(seconds: 67),
                      color: GameColors.gold,
                      onTap: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // The state has to be unmistakable while it's live: what it's doing,
      // how to stop it, and how long it's been going.
      expect(find.text(ar.voiceNoteRecording), findsOneWidget);
      expect(find.text(ar.voiceNoteTapToStop), findsOneWidget);
      expect(find.text('01:07'), findsOneWidget);
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
      expect(
        find.byIcon(Icons.mic_rounded),
        findsNothing,
        reason: 'a mic icon mid-recording reads as "not started yet"',
      );

      // The clock goes at the far end, opposite the stop control, so it
      // never pushes the label around as the digits change.
      final clock = tester.getRect(find.text('01:07'));
      final stop = tester.getRect(find.byIcon(Icons.stop_rounded));
      expect(
        clock.center.dx,
        lessThan(stop.center.dx),
        reason: 'RTL: the stop control is at the start (right), the clock at '
            'the end (left)',
      );
    });

    testWidgets('the record row and a recording form one column',
        (tester) async {
      await open(
        tester,
        harness(
          task: taskWith(
            notes: [
              VoiceNote(
                id: 'n1',
                path: '${tmp.path}/n1.m4a',
                name: 'الخطوة ١',
                durationSeconds: 12,
                createdAt: DateTime(2026, 8, 26, 9, 30),
              ),
            ],
          ),
        ),
      );

      final record = tester.getRect(find.byType(VoiceNoteRecordRow));
      final note = tester.getRect(find.byType(VoiceNoteRow));

      expect(record.left, moreOrLessEquals(note.left, epsilon: 0.5));
      expect(record.right, moreOrLessEquals(note.right, epsilon: 0.5));
      expect(
        note.top,
        greaterThan(record.bottom),
        reason: 'recordings should stack below the record row, not beside it',
      );
      // Same geometry on purpose (see VoiceNoteRecordRow's doc comment), so
      // the section reads as one column rather than a control and a list.
      expect(record.height, moreOrLessEquals(note.height, epsilon: 1.5));
    });
  });
}

/// The app ships `ar` without flutter_localizations, so the stock
/// Default*Localizations delegates report `ar` unsupported and MaterialApp
/// raises. These serve the English defaults for any locale — the widgets
/// under test read their copy from `S`, so the Material-level strings are
/// irrelevant here; all these have to do is exist. Same shim
/// reminder_layout_test.dart carries, for the same reason.
class _AnyLocale {
  static const delegates = <LocalizationsDelegate<dynamic>>[
    _AnyLocaleMaterial(),
    _AnyLocaleWidgets(),
  ];
}

class _AnyLocaleMaterial extends LocalizationsDelegate<MaterialLocalizations> {
  const _AnyLocaleMaterial();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      DefaultMaterialLocalizations.load(locale);
  @override
  bool shouldReload(_) => false;
}

class _AnyLocaleWidgets extends LocalizationsDelegate<WidgetsLocalizations> {
  const _AnyLocaleWidgets();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      DefaultWidgetsLocalizations.load(locale);
  @override
  bool shouldReload(_) => false;
}
