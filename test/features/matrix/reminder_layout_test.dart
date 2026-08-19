import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/matrix/models/matrix_task.dart';
import 'package:grow_daily_v2/features/matrix/widgets/add_task_sheet.dart';
import 'package:grow_daily_v2/features/matrix/widgets/custom_offset_sheet.dart';
import 'package:grow_daily_v2/features/matrix/widgets/reminder_picker.dart';
import 'package:grow_daily_v2/shared/widgets/choice_chip_grid.dart';
import 'package:hive/hive.dart';
import 'package:intl/date_symbol_data_local.dart';

/// The reported "stuck": with the Arabic keyboard up and a reminder set,
/// AddTaskSheet painted its multi-add hint half-cut and its ADD TASK button
/// underneath the keyboard — present, but unreachable and unscrollable.
///
/// Cause was a `maxHeight: size.height * 0.85` computed from the FULL screen
/// while the keyboard was subtracted only in the sibling AnimatedPadding, over
/// a body that was a bare non-scrollable Column. ConstrainedBox clamped the
/// card to the post-keyboard height, the Column still demanded the
/// pre-keyboard one, and because Flex.clipBehavior defaults to Clip.none the
/// overflow was *painted* outside the card rather than clipped.
///
/// A RenderFlex overflow raises a FlutterError that the binding records as a
/// test exception, so laying these out is itself the assertion.
void main() {
  const dpr = 3.0;

  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  // formatReminderMoment goes through DateFormat, which throws for 'ar'
  // until the locale data is loaded. Hive is for MatrixNotifier's guest
  // load, which AddTaskSheet reaches through matrixProvider for its
  // quadrant colour — opened here, in the real async zone, so it's already
  // resolved by the time pumpWidget's fake-async zone builds the tree (the
  // same reason matrix_add_task_test.dart does it this way).
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ar');
    tmp = await Directory.systemTemp.createTemp('reminder_layout_test_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings');
  });

  tearDownAll(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  group('the reminder section on a height-constrained phone', () {
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

    /// The picker with a full stack, in the height a keyboard actually
    /// leaves. 440pt is roughly what an iPhone 15 Pro has above the Arabic
    /// keyboard once the sheet's own padding is taken out — and the picker
    /// alone wants more than that at eight reminders, which is exactly why
    /// its host has to be able to scroll.
    Widget harness({
      required Locale locale,
      required Set<int> offsets,
      required double height,
      bool scrollable = true,
    }) {
      final picker = ReminderPicker(
        anchorAt: DateTime.now().add(const Duration(days: 1)),
        offsets: offsets,
        color: GameColors.error,
        isAr: locale.languageCode == 'ar',
        canStack: true,
        onPickAnchor: () {},
        onClear: () {},
        onToggleOffset: (_) {},
        onLocked: () {},
      );
      // The locale is overridden *inside* the app rather than on MaterialApp
      // itself: this project ships `ar` without flutter_localizations, so a
      // MaterialApp declaring ar as its locale trips the framework's
      // "not supported by all of its localization delegates" warning, which
      // a widget test records as a failure. S.of reads
      // Localizations.localeOf, so an inner scope is all the widgets need.
      return MaterialApp(
        theme: GameTheme.dark,
        home: Localizations(
          locale: locale,
          delegates: GlobalMaterialLocalizationsCompat.delegates,
          child: Directionality(
            textDirection: locale.languageCode == 'ar'
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320,
                  height: height,
                  child: scrollable
                      ? SingleChildScrollView(child: picker)
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [picker],
                        ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    for (final locale in const [Locale('en'), Locale('ar')]) {
      testWidgets(
          'a full 8-reminder stack fits a keyboard-sized box (${locale.languageCode})',
          (tester) async {
        // Seven offsets plus the anchor is kMaxTaskReminderSlots. Every one
        // of them adds a chip to the grid AND a row to the list, which is
        // the growth the old fixed-height Column could not survive.
        //
        // 300, not the 440 this test originally used: the box must be
        // SHORTER than the rendered section or the overflow protection is
        // never exercised. 440 was calibrated against the flutter_test
        // placeholder font; once the app's real families were bundled as
        // assets (see pubspec's google_fonts entry), tests render genuine
        // IBM Plex metrics and the same 8-slot stack measures ~375pt (en)
        // / ~341pt (ar) — comfortably inside 440, which silently turned
        // the assertion below into a no-op. The guard after it exists to
        // catch exactly this, and did.
        const boxHeight = 300.0;
        await tester.pumpWidget(
          harness(
            locale: locale,
            offsets: const {-120, -60, -30, -15, -10, 15, 45},
            height: boxHeight,
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          tester.takeException(),
          isNull,
          reason: 'the reminder section overflowed the room a keyboard '
              'leaves — its host sheet must be able to scroll it',
        );

        // The self-check that keeps the assertion above honest: the content
        // must exceed the box, or "no overflow" proves nothing. Tied to the
        // same constant so the two numbers can never drift apart again.
        expect(
          tester.getSize(find.byType(ReminderPicker)).height,
          greaterThan(boxHeight),
          reason: 'if this section ever gets short enough to fit unscrolled, '
              'the assertion above stops proving anything',
        );
      });
    }

    testWidgets('AddTaskSheet survives the Arabic keyboard with details open',
        (tester) async {
      // The reported screenshot, reproduced: the sheet is open, the title
      // field has focus (it requests it in initState, so this is the normal
      // state, not an edge case), and the Arabic keyboard is up.
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
      // ~335pt of Arabic keyboard including the QuickType candidate bar.
      view.viewInsets = const FakeViewPadding(bottom: 335 * dpr);

      // Presented exactly the way matrix_screen.dart's _showAdd presents it
      // — a real showModalBottomSheet with the same arguments. Rendering the
      // sheet straight into a Scaffold body instead would put it at the top
      // of the screen with different constraints, and then any assertion
      // about where its footer lands is measuring the harness, not the bug.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
          ],
          child: MaterialApp(
            theme: GameTheme.dark,
            // The locale scope goes in `builder`, not around `home`:
            // showModalBottomSheet pushes onto the Navigator, so a sheet is a
            // sibling of `home` and would never see an override nested inside
            // it. MaterialApp's builder wraps the Navigator itself, so routes
            // inherit it too.
            builder: (context, child) => Localizations(
              locale: const Locale('ar'),
              delegates: GlobalMaterialLocalizationsCompat.delegates,
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
                      builder: (_) => AddTaskSheet(
                        quadrant: MatrixQuadrant.doFirst,
                        onAdd: (
                          _, {
                          description,
                          voiceNotes,
                          reminderAts,
                          reminderAnchorAt,
                        }) {},
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester.takeException(),
        isNull,
        reason: 'AddTaskSheet overflowed with the keyboard up',
      );

      const ar = S(Locale('ar'));

      // Set an anchor, which is what makes the section grow at all: until
      // one exists the picker is a single row and nothing can overflow.
      // Two native dialogs, each accepted at its default (the time picker
      // starts an hour out, so it's comfortably in the future).
      await tester.tap(find.text(ar.matrixReminderLabel));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('OK'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('OK'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.text(ar.matrixExtraRemindersSection),
        findsOneWidget,
        reason: 'the anchor was not set, so the rest of this test would '
            'be measuring a sheet that never grows',
      );

      // Now stack offsets onto it. Every chip adds a grid cell AND a list
      // row — the growth the old fixed Column could not survive.
      for (final label in [-60, -30, -15, -10, -5]) {
        final chip = find.text(formatOffsetCompact(label, true, ar));
        if (chip.evaluate().isEmpty) continue;
        await tester.tap(chip.first, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 250));
      }
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        tester.takeException(),
        isNull,
        reason: 'AddTaskSheet overflowed once the reminder stack grew, '
            'with the keyboard up — the exact reported state',
      );

      // And the structural half of the fix: the sheet's growable body is
      // inside a Scrollable, so content that outgrows the room the keyboard
      // leaves can be reached instead of being painted past the card's edge.
      // Before the fix there was no Scrollable above the footer at all —
      // which is why nothing could be scrolled back into view.
      expect(
        find.descendant(
          of: find.byType(AddTaskSheet),
          matching: find.byType(Scrollable),
        ),
        findsWidgets,
        reason: 'AddTaskSheet has no scrollable body; anything taller than '
            'the keyboard leaves room for is unreachable',
      );
      final button = find.byType(FilledButton);
      expect(button, findsWidgets, reason: 'the ADD TASK button vanished');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('an after-ladder reopens on the After tab, not Before',
        (tester) async {
      // The second half of the anchor bug, and the half that only shows up
      // once the first is fixed. `_isAfter` used to be hardcoded false, so a
      // task built entirely out of "after" offsets reopened on Before with
      // an empty-looking grid — every chip it actually had was in the other
      // tab. It went unnoticed because the anchor was being re-guessed as
      // the last reminder, which forced every reconstructed offset negative;
      // now that an after-ladder comes back as an after-ladder, the tab has
      // to follow the data.
      await tester.pumpWidget(
        harness(
          locale: const Locale('en'),
          offsets: const {15, 30},
          height: 600,
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      PlainChoiceChip chipFor(String label) => tester.widget<PlainChoiceChip>(
            find
                .ancestor(
                  of: find.text(label),
                  matching: find.byType(PlainChoiceChip),
                )
                .first,
          );

      expect(
        chipFor('After').selected,
        isTrue,
        reason: 'a task whose offsets are all "after" opened on Before',
      );
      expect(chipFor('Before').selected, isFalse);
      // And its chips read as selected on that tab, rather than the grid
      // looking empty.
      expect(chipFor('15').selected, isTrue);
      expect(chipFor('30').selected, isTrue);
    });

    testWidgets('a before-ladder still opens on Before', (tester) async {
      await tester.pumpWidget(
        harness(
          locale: const Locale('en'),
          offsets: const {-15, -30},
          height: 600,
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      final before = tester.widget<PlainChoiceChip>(
        find
            .ancestor(
              of: find.text('Before'),
              matching: find.byType(PlainChoiceChip),
            )
            .first,
      );
      expect(before.selected, isTrue);
    });

    testWidgets('a mixed ladder defaults to Before', (tester) async {
      // Ties go to "before": a reminder about a thing almost always wants
      // to arrive ahead of it.
      await tester.pumpWidget(
        harness(
          locale: const Locale('en'),
          offsets: const {-15, 30},
          height: 600,
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      final before = tester.widget<PlainChoiceChip>(
        find
            .ancestor(
              of: find.text('Before'),
              matching: find.byType(PlainChoiceChip),
            )
            .first,
      );
      expect(before.selected, isTrue);
    });

    testWidgets('a chip label never ellipsizes at 320pt', (tester) async {
      // The narrowest device this ships to, in Arabic, with the longest
      // preset label. Self-labelling chips are only an improvement if they
      // are actually readable.
      await tester.pumpWidget(
        harness(
          locale: const Locale('ar'),
          offsets: const {},
          height: 600,
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        final data = text.data;
        if (data == null || !data.contains('قبل') && !data.contains('بعد')) {
          continue;
        }
        final painter = TextPainter(
          text: TextSpan(text: data, style: text.style),
          textDirection: TextDirection.rtl,
          maxLines: 1,
        )..layout();
        expect(
          painter.didExceedMaxLines,
          isFalse,
          reason: '"$data" wraps or ellipsizes in a chip',
        );
      }
    });
  });
}

/// The app ships `ar` without pulling in flutter_localizations, so the stock
/// Default*Localizations delegates report `ar` unsupported and MaterialApp
/// raises. These serve the English defaults for any locale — the widgets
/// under test take their own `isAr` flag and read copy from `S`, so the
/// Material-level strings are irrelevant here; all these have to do is exist.
class GlobalMaterialLocalizationsCompat {
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
