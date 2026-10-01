// Editing a habit that came from a Plan, in Arabic.
//
// Reported from a device: "editing a habit that is from a plan, now it stuck,
// and also the name is in english". The English name was real and it was not
// cosmetic. AddHabitSheet's initState seeds the name box from
// `IslamicHabitTemplate.name`, which is the *English* field, while _submit
// decides whether the typed name is a genuine override by comparing it
// against `catalogDefault.localName(isAr)`. In Arabic those two strings can
// never be equal, so opening a preset and pressing Save with nothing changed
// silently stored the English name as a permanent per-user override —
// renaming the person's habit into a language they did not pick, and doing it
// as a side effect of *looking* at the edit screen.
//
// The invariant these lock down: opening a preset shows the name in the
// user's own language, and saving an untouched preset writes no override at
// all.
//
// Since the three-step page (canvas v8, 2026-10-01) an edit opens on an
// overview of its three answers rather than on the name box, so the name is
// checked twice: in the overview's first row, and in the box that row opens
// (support/add_habit_flow.dart's openEditStep).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/widgets/add_habit_sheet.dart';

import 'support/add_habit_flow.dart';

void main() {
  late Directory tmp;
  late ProviderContainer container;

  setUp(() async {
    NotificationService.instance.celebrationsEnabled = false;
    GoogleFonts.config.allowRuntimeFetching = false;
    tmp = await Directory.systemTemp.createTemp('edit_preset_test_');
    Hive.init(tmp.path);
    // All three, exactly as main() opens them — opening a subset makes these
    // fail intermittently depending on which notifier touches which box first.
    await Hive.openBox<dynamic>('box_settings');
    await Hive.openBox<dynamic>('box_daily_logs');
    await Hive.openBox<dynamic>('box_habits');
    container = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
    ]);
    await container.read(authStateProvider.future);
  });

  tearDown(() => container.dispose());

  /// A catalog preset that genuinely has an Arabic name, so "shows the Arabic
  /// one" is a meaningful assertion rather than a fallback to English.
  IslamicHabitTemplate presetWithArabicName() {
    final t = IslamicHabitCatalog.templates
        .firstWhere((t) => (t.nameAr ?? '').trim().isNotEmpty);
    return t;
  }

  Widget app(Locale locale, IslamicHabitTemplate existing) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: locale,
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: GameTheme.light,
          home: Scaffold(body: AddHabitSheet(existing: existing)),
        ),
      );

  /// The name box's text, read from its controller.
  String typedName(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField).first).controller!.text;

  testWidgets('opening a plan habit in Arabic shows its Arabic name',
      (tester) async {
    const s = S(Locale('ar'));
    final preset = presetWithArabicName();
    await tester.pumpWidget(app(const Locale('ar'), preset));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: choice(s.addHabitStepWhat),
        matching: find.text(preset.nameAr!),
      ),
      findsOneWidget,
      reason: 'the overview\'s habit row must show localName(isAr), not the '
          'English catalog name',
    );
    expect(find.text(preset.name), findsNothing);

    await openEditStep(tester, s, 0);
    expect(typedName(tester), preset.nameAr,
        reason: 'the name box showed the English catalog name to an Arabic '
            'user; it must show localName(isAr), the one _submit compares '
            'against');
    expect(typedName(tester), isNot(preset.name),
        reason: 'guard: this preset must actually differ between languages, '
            'or the assertion above proves nothing');
    await _teardown(tester);
  });

  testWidgets('opening a plan habit in English still shows its English name',
      (tester) async {
    const s = S(Locale('en'));
    final preset = presetWithArabicName();
    await tester.pumpWidget(app(const Locale('en'), preset));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: choice(s.addHabitStepWhat),
        matching: find.text(preset.name),
      ),
      findsOneWidget,
      reason: 'the English path must be untouched by the Arabic fix',
    );

    await openEditStep(tester, s, 0);
    expect(typedName(tester), preset.name);
    await _teardown(tester);
  });

  group('on a real phone, where the sheet is height-constrained', () {
    setUp(() {
      const dpr = 3.0;
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
      view.physicalSize = const Size(402 * dpr, 874 * dpr);
      view.devicePixelRatio = dpr;
    });

    tearDown(() {
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });

    testWidgets('the edit sheet lays out without overflowing', (tester) async {
      // The reported "stuck": editing a plan habit painted Flutter's
      // yellow-and-black stripe across the footer and clipped the red "Remove
      // habit" button underneath it. Cause was the standalone sheet's outer
      // Column handing `content` an unbounded height, so the
      // Flexible(SingleChildScrollView) inside it had nothing to shrink
      // against. It reproduces only when the sheet is actually
      // height-constrained AND the extra edit-only Remove button is present —
      // which is why the default 800x600 test surface never caught it.
      //
      // A RenderFlex overflow raises a FlutterError, which the binding records
      // as a test exception, so simply laying this out is the assertion.
      //
      // Every page an edit has, not one of them: the reported screenshot was
      // the frequency page, markedly taller than the name page, and testing
      // the name page alone is why an earlier version of this passed with the
      // bug fully present. Now the Remove button sits under the overview's
      // footer, and each step page («تم» under it) is checked too.
      const s = S(Locale('ar'));
      final preset = presetWithArabicName();
      await tester.pumpWidget(app(const Locale('ar'), preset));
      await tester.pumpAndSettle();

      expect(find.text(s.saveChanges), findsOneWidget,
          reason: 'sanity: on the overview');
      expect(find.text(s.removeHabit), findsOneWidget);
      expect(tester.takeException(), isNull,
          reason: 'the edit overview overflowed its own constraints — the '
              'footer and the Remove button paint outside the sheet');

      for (final step in const [0, 1, 2]) {
        await openEditStep(tester, s, step);
        expect(find.text(s.habitEditStepDone), findsOneWidget,
            reason: 'sanity: on step $step\'s page');
        expect(tester.takeException(), isNull,
            reason: 'step $step\'s page overflowed the sheet');
        await editStepDone(tester, s);
        expect(find.text(s.saveChanges), findsOneWidget,
            reason: '«تم» comes back to the overview');
      }
      await _teardown(tester);
    });
  });

  // There is deliberately NO third test asserting "saving an untouched preset
  // writes no override". One was written and removed: CatalogOverridesNotifier
  // .setOverride persists before it publishes, so nothing observable lands
  // inside a widget test's pump window, and the test stayed green with the fix
  // reverted — a guard that cannot fail. The override behaviour follows
  // directly from the two assertions above anyway: _submit stores a name only
  // when the typed text differs from `catalogDefault.localName(isAr)`, so
  // seeding the box with that exact string is what makes "I changed nothing"
  // compare equal. Worth a real integration test one day; not worth a fake one.
}

/// Replaces the tree so every flutter_animate controller is disposed. Without
/// this the binding fails each test with "A Timer is still pending even after
/// the widget tree was disposed", which masks the real assertion.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}
