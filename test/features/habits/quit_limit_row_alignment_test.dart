// The limit row sits under the avoid / limit picks, so it has to line up
// with them.
//
// Reported from the device: «الحد الأقصى» and its unit dropdown did not sit
// on one line, and neither column matched the row of picks above. Two
// causes, both in _quitStyleSection:
//
//  1. The amount field carries a helperText («مطلوب رقم أكبر من صفر»)
//     whenever the number is missing, which is the state the row OPENS in.
//     That makes the field taller than the dropdown, and a Row centres its
//     children by default, so the dropbox sank by half the helper's height
//     against a field whose box stayed put.
//  2. The gap was 10 where the picks above use 8, so the inner edges of the
//     two rows were 1pt off each other on each side.
//
// These lock both: same top, same box height, same left and right edges as
// the picks above.
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
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/habits/widgets/add_habit_sheet.dart';

void main() {
  const dpr = 3.0;
  late Directory tmp;

  setUp(() async {
    NotificationService.instance.celebrationsEnabled = false;
    GoogleFonts.config.allowRuntimeFetching = false;
    tmp = await Directory.systemTemp.createTemp('quit_limit_row_test_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings');
    await Hive.openBox<dynamic>('box_daily_logs');
    await Hive.openBox<dynamic>('box_habits');
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.physicalSize = const Size(390 * dpr, 844 * dpr);
    view.devicePixelRatio = dpr;
  });

  tearDown(() async {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  Future<ProviderContainer> container() async {
    final c = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
      habitListProvider
          .overrideWithValue([IslamicHabitCatalog.templates.first]),
    ],);
    await c.read(authStateProvider.future);
    return c;
  }

  Widget app(ProviderContainer c, Locale locale) => UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          locale: locale,
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: GameTheme.dark,
          home: const Scaffold(body: AddHabitSheet()),
        ),
      );

  /// The tappable cell of a _SmallPick, which is the pick's whole slot.
  Finder pick(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;

  for (final locale in const [Locale('ar'), Locale('en')]) {
    final tag = locale.languageCode;
    final s = S(locale);

    testWidgets('[$tag] the limit row lines up with the picks above it',
        (tester) async {
      final c = await container();
      addTearDown(c.dispose);
      await tester.pumpWidget(app(c, locale));
      await tester.pumpAndSettle();

      await tester.tap(find.text(s.goalTypeQuitOption));
      await tester.pumpAndSettle();
      await tester.tap(pick(s.setLimit));
      await tester.pumpAndSettle();

      // The taller state, where the drift showed up: the amount field with
      // its helper line under it.
      //
      // It is no longer on screen the moment the row opens (2026-09-09: a
      // required-field note that arrives before anybody has typed is
      // nagging, so both of this sheet's required notes now wait for a
      // refused press). A name and one tap on the primary button, with the
      // number still empty, puts it there: the same state this always
      // measured. The name is only here because the button is dead without
      // one, which is the sheet's single remaining greyed-out gate.
      await tester.enterText(find.byType(TextField).first, 'قهوة');
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.continueAction));
      await tester.pumpAndSettle();
      expect(find.text(s.limitAmountRequired), findsOneWidget,
          reason: 'refused, so the field says what it is owed');

      final amount = find
          .ancestor(of: find.text(s.maxAmount), matching: find.byType(TextField))
          .first;
      final unit = find.byType(DropdownButtonFormField<LimitUnit>).first;

      final amountRect = tester.getRect(amount);
      final unitRect = tester.getRect(unit);
      final avoidRect = tester.getRect(pick(s.avoidCompletely));
      final limitRect = tester.getRect(pick(s.setLimit));

      expect(unitRect.top, moreOrLessEquals(amountRect.top, epsilon: 0.5),
          reason: 'one row: both fields start on the same line',);

      // Columns: the amount field sits under the pick on its own side, the
      // unit under the other. Which side is which flips with the locale, so
      // pair them by position rather than by name.
      final amountPick =
          (amountRect.center.dx - avoidRect.center.dx).abs() < 1 ? avoidRect : limitRect;
      final unitPick = identical(amountPick, avoidRect) ? limitRect : avoidRect;

      expect(amountRect.left, moreOrLessEquals(amountPick.left, epsilon: 0.5),
          reason: 'the amount field is as wide as the pick above it',);
      expect(amountRect.right, moreOrLessEquals(amountPick.right, epsilon: 0.5));
      expect(unitRect.left, moreOrLessEquals(unitPick.left, epsilon: 0.5),
          reason: 'and so is the unit dropdown',);
      expect(unitRect.right, moreOrLessEquals(unitPick.right, epsilon: 0.5));

      // With a number typed the helper goes, and then the two boxes are the
      // same rectangle twice over: same top, same height.
      await tester.enterText(amount, '30');
      await tester.pumpAndSettle();
      expect(find.text(s.limitAmountRequired), findsNothing);

      final filled = tester.getRect(amount);
      final unitFilled = tester.getRect(unit);
      expect(unitFilled.top, moreOrLessEquals(filled.top, epsilon: 0.5));
      // Within a hairline rather than exactly: the dropdown's height comes
      // from its 24pt chevron and the field's from its text line, so the two
      // land a fraction of a point apart and the fraction moves with the
      // font. A point is invisible; the 11.5pt the row used to be off was not.
      expect(unitFilled.height, moreOrLessEquals(filled.height, epsilon: 1.5),
          reason: 'the same box height on both sides of the row',);
    });
  }
}
