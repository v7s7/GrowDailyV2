// The apex medal has to actually be reachable.
//
// prestige_mark.dart draws Legacy as a struck medal — a raised rim and
// thirteen squares engraved in a diamond — but only when TWO conditions hold
// at the call site: the mark is at least 48pt, and nobody has passed it a
// flat colour. Miss either one and it falls back to a plain gold circle, with
// no error, no warning and nothing in the analyzer.
//
// Both were missed here. The picker sheet — by its own doc comment "the one
// place to browse every Level Prestige tier" — drew every rung at 22pt in a
// single tinted ink, so the medal existed but had exactly one surface it
// could appear on: the rank-up celebration, which fires once, at level 100.
//
// These lock the CALL SITE, not the painter. prestige_mark_test.dart already
// covers the figure itself, including that it stays a plain disc below 48pt,
// which is what the leaderboard and the Profile chip still want.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;

import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/character/screens/prestige_picker_sheet.dart';
import 'package:grow_daily_v2/features/character/widgets/prestige_mark.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    tmp = await Directory.systemTemp.createTemp('prestige_picker_test_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings');
    await Hive.openBox<dynamic>('box_daily_logs');
    await Hive.openBox<dynamic>('box_habits');
  });

  tearDown(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  /// A signed-out container, which is all this needs: the sheet lists every
  /// rung whatever the level is, dimming the locked ones. Level 1 therefore
  /// renders the same marks a level 100 account sees.
  Future<ProviderContainer> guest() async {
    final c = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
    ]);
    await c.read(authStateProvider.future);
    return c;
  }

  Widget app(ProviderContainer container, Locale locale, ThemeData theme) =>
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
          theme: theme,
          home: const Scaffold(body: PrestigePickerSheet()),
        ),
      );

  /// Every mark the sheet can show, keyed by rung.
  ///
  /// Gathered by scrolling rather than read off one frame, because a ListView
  /// only builds the rows it can display and Legacy is the LAST rung. Reading
  /// a single frame finds the first three and silently "passes" a summit that
  /// was never built — which is how this test failed the first time it was
  /// written, on the summit it exists to check.
  Future<Map<int, PrestigeMark>> ladder(WidgetTester t) async {
    final seen = <int, PrestigeMark>{};
    final list = find.byType(ListView);
    for (var pass = 0; pass < 20; pass++) {
      for (final m in t.widgetList<PrestigeMark>(find.byType(PrestigeMark))) {
        seen[m.spec.rank] = m;
      }
      if (seen.length == kPrestigeMarks.length) return seen;
      await t.drag(list, const Offset(0, -180));
      await t.pumpAndSettle();
    }
    return seen;
  }

  for (final locale in const [Locale('ar'), Locale('en')]) {
    final tag = locale.languageCode;

    for (final mode in const ['dark', 'light']) {
      testWidgets('[$tag/$mode] the summit is a medal here, not a gold circle',
          (t) async {
        final container = await guest();
        addTearDown(container.dispose);
        await t.pumpWidget(app(container, locale,
            mode == 'dark' ? GameTheme.dark : GameTheme.light));
        await t.pumpAndSettle();

        final rungs = await ladder(t);
        final apex = rungs.values.where((m) => m.spec.solid).toList();
        expect(apex, hasLength(1),
            reason: 'exactly one rung on the ladder is the filled summit');
        expect(apex.single.engraves, isTrue,
            reason: 'Legacy is drawing as a plain disc in the one sheet '
                'built for looking at the ladder');
      });
    }
  }

  testWidgets('every rung is browsable, not just the summit', (t) async {
    final container = await guest();
    addTearDown(container.dispose);
    await t.pumpWidget(app(container, const Locale('en'), GameTheme.dark));
    await t.pumpAndSettle();

    final rungs = await ladder(t);
    expect(rungs, hasLength(kPrestigeMarks.length),
        reason: 'the sheet lists the whole ladder, locked rungs included');

    for (final entry in rungs.entries) {
      // 22pt was small for every rung, not only the apex. The metal gradient
      // has its own 16pt floor, so a flattened mark here loses the highlight
      // and shadow that make the thing read as struck rather than printed.
      expect(entry.value.size, greaterThanOrEqualTo(48.0),
          reason: 'rung ${entry.key} is too small to browse');
      expect(entry.value.color, isNull,
          reason: 'rung ${entry.key} is flattened to one ink, which turns '
              'the metal off');
    }
  });

  testWidgets('the taller rows still lay out on a small phone in Arabic',
      (t) async {
    // The medal costs 18pt a row, nine rows deep, inside a sheet capped at
    // 80% of the screen. It scrolled at the old size too; it has to keep
    // scrolling rather than start overflowing.
    await t.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final container = await guest();
    addTearDown(container.dispose);
    await t.pumpWidget(app(container, const Locale('ar'), GameTheme.dark));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull, reason: 'the picker overflows at 320x568');
    expect(find.byType(PrestigePickerSheet), findsOneWidget);

    // And the ladder is still reachable by scrolling on that screen.
    final rungs = await ladder(t);
    expect(rungs, hasLength(kPrestigeMarks.length));
    expect(t.takeException(), isNull,
        reason: 'scrolling the picker overflows at 320x568');
  });
}
