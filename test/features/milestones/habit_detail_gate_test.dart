// The per-habit detail sheet's premium floor.
//
// ── Why this file exists ──────────────────────────────────────────────────
// The sheet used to have no premium check of any kind. It is opened by
// tapping a habit's name on the أسبوعي tab, which is deliberately ungated
// (see reportPeriodUnlocked's doc comment), and its month stepper had no
// backward bound. So a free account reached every month it had ever
// recorded, one back-tap at a time, while the شهري tab beside it refused
// anything older than kFreeHistoryMonths. Same habit, same days, two
// prices, and the cheaper one was one tap away.
//
// The year strip underneath had the same hole from the other direction: it
// was handed `lockedBefore: null` outright, so it painted a full year of
// day-level history in full colour for everyone.
//
// What has to stay true is the whole point of these tests: this sheet
// refuses exactly where the reports hub refuses, using the same floor, and
// the back chevron stays alive across that floor so the refusal can sell.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/core/utils/western_digits.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/milestones/notifiers/habit_history_notifier.dart';
import 'package:grow_daily_v2/features/milestones/reports/habit_detail_sheet.dart';
import 'package:grow_daily_v2/features/milestones/reports/report_period.dart';
import 'package:grow_daily_v2/features/milestones/reports/year_strip.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';

/// Premium as a plain, settable bool.
///
/// Subclassing rather than faking the provider wholesale so the real
/// [PremiumNotifier] type still satisfies the provider's signature. Its
/// constructor is safe here: it subscribes to a plain broadcast controller
/// and calls refresh(), which returns early because PurchaseService is
/// never configured in tests (see PurchaseService.getCustomerInfo).
class _Premium extends PremiumNotifier {
  _Premium(bool value) {
    state = value;
  }
}

const _habitId = 'h1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── Pure: the floor itself ─────────────────────────────────────────────
  //
  // These need no Riverpod and no widget tree. They pin the arithmetic that
  // both the sheet and the reports hub now read through, which is the whole
  // reason freeHistoryFloor was lifted out of period_report_section.

  group('freeHistoryFloor', () {
    test('is the first day of the oldest month a free account may open', () {
      expect(
        freeHistoryFloor(DateTime(2026, 8, 21)),
        DateTime(2026, 8 - (kFreeHistoryMonths - 1)),
      );
    });

    test('lands on day 1, never carrying the day of the month across', () {
      for (final day in [1, 15, 28, 31]) {
        expect(freeHistoryFloor(DateTime(2026, 12, day)).day, 1,
            reason: 'day $day of the month must not survive into the floor');
      }
    });

    test('rolls back across a year boundary', () {
      // January with a 3-month window reaches into the previous November.
      expect(freeHistoryFloor(DateTime(2026, 1, 15)), DateTime(2025, 11));
      expect(freeHistoryFloor(DateTime(2026, 2, 1)), DateTime(2025, 12));
    });

    // The invariant that actually matters: the floor and the entitlement
    // predicate have to agree on the boundary, or one screen locks a month
    // the other opens. Swept across four years of months so a February or a
    // year edge cannot hide a mistake.
    test('the floor month is browsable and the month before it is not', () {
      for (var y = 2025; y <= 2028; y++) {
        for (var m = 1; m <= 12; m++) {
          final today = DateTime(y, m, 15);
          final floor = freeHistoryFloor(today);
          expect(
            canBrowseHistoryMonth(
                monthStart: floor, now: today, isPremium: false),
            isTrue,
            reason: 'the floor month itself must be free ($y-$m)',
          );
          expect(
            canBrowseHistoryMonth(
              monthStart: DateTime(floor.year, floor.month - 1),
              now: today,
              isPremium: false,
            ),
            isFalse,
            reason: 'the month before the floor must be walled ($y-$m)',
          );
        }
      }
    });

    test('premium is never floored', () {
      final today = DateTime(2026, 8, 21);
      expect(
        canBrowseHistoryMonth(
          monthStart: DateTime(2019),
          now: today,
          isPremium: true,
        ),
        isTrue,
      );
    });
  });

  // ── Pure: which windows get lock styling at all ────────────────────────
  //
  // The widget tests below run against whatever "today" the suite happens
  // to run on, and a year strip has nothing to mute for the first stretch
  // of every year. That asymmetry is the easiest thing in this change to
  // get wrong in a month nobody is testing in, so it is pinned here across
  // every month of several years rather than left to the calendar.

  group('historyFloorFor', () {
    test('premium is never given a floor, however far back the window', () {
      expect(
        historyFloorFor(
          windowStart: DateTime(2001),
          today: DateTime(2026, 8, 21),
          isPremium: true,
        ),
        isNull,
      );
    });

    test('a window inside the free window gets no floor', () {
      final today = DateTime(2026, 8, 21); // floor: 2026-06-01
      expect(
        historyFloorFor(
            windowStart: DateTime(2026, 7), today: today, isPremium: false),
        isNull,
        reason: 'July is inside the window, so nothing may be drawn locked',
      );
    });

    test('a window reaching past the floor gets exactly that floor', () {
      final today = DateTime(2026, 8, 21);
      expect(
        historyFloorFor(
            windowStart: DateTime(2026, 5), today: today, isPremium: false),
        DateTime(2026, 6),
      );
    });

    test('the floor month itself is not treated as reaching past the floor',
        () {
      final today = DateTime(2026, 8, 21);
      expect(
        historyFloorFor(
            windowStart: DateTime(2026, 6), today: today, isPremium: false),
        isNull,
        reason: 'the floor month is free, so it must not be muted',
      );
    });

    // A YEAR strip specifically: from January until the month the floor
    // lands in, the whole visible year is free and must not be muted.
    test('a year strip is unmuted early in the year and muted later', () {
      for (var y = 2025; y <= 2028; y++) {
        for (var m = 1; m <= 12; m++) {
          final today = DateTime(y, m, 15);
          final floor = freeHistoryFloor(today);
          final result = historyFloorFor(
            windowStart: DateTime(y),
            today: today,
            isPremium: false,
          );
          // January of the viewed year is before the floor only once the
          // floor has moved past January of that same year.
          final januaryIsWalled = DateTime(y).isBefore(floor);
          expect(result, januaryIsWalled ? floor : isNull,
              reason: 'year $y viewed in month $m');
        }
      }
    });

    test('the first three months of a year mute nothing on that year strip',
        () {
      // kFreeHistoryMonths is 3, so in January, February and March the free
      // window still covers back to at least January of the viewed year.
      for (final m in [1, 2, 3]) {
        expect(
          historyFloorFor(
            windowStart: DateTime(2026),
            today: DateTime(2026, m, 15),
            isPremium: false,
          ),
          isNull,
          reason: 'month $m of 2026 still covers all of 2026 so far',
        );
      }
      expect(
        historyFloorFor(
          windowStart: DateTime(2026),
          today: DateTime(2026, 4, 15),
          isPremium: false,
        ),
        DateTime(2026, 2),
        reason: 'April is the first month that walls part of its own year',
      );
    });
  });

  // ── Widget: the sheet's real behaviour ─────────────────────────────────

  group('habit detail sheet', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('habit_detail_gate_');
      Hive.init(tmp.path);
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await tmp.delete(recursive: true);
    });

    final today = DateTime.now().effectiveDay;
    final thisMonth = DateTime(today.year, today.month);

    IslamicHabitTemplate habit() => IslamicHabitTemplate(
          id: _habitId,
          name: 'Fajr',
          description: '',
          category: HabitCategory.faith,
          frequencyType: HabitFrequencyType.daily,
          frequencyTarget: 1,
          scheduledWeekdays: const [],
          hasTimer: false,
          xpReward: 10,
          goldReward: 1,
        );

    /// One completed day in the middle of each of the last [months] months,
    /// so the stepper always has real data behind it and `earliestData`
    /// sits far outside the free window.
    Map<String, SquareState> marksBack(int months) => {
          for (var i = 0; i < months; i++)
            DateTime(today.year, today.month - i, 15).toDateKey():
                SquareState.complete,
        };

    Future<void> open(
      WidgetTester tester, {
      required bool premium,
      Map<String, SquareState>? marks,
      String locale = 'en',
    }) async {
      // Tall enough that the month header and the year strip are both laid
      // out, so neither assertion depends on scrolling the sheet.
      tester.view.physicalSize = const Size(400 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
          premiumProvider.overrideWith((ref) => _Premium(premium)),
          habitYearHistoryProvider.overrideWith(
            (ref) async => {_habitId: marks ?? marksBack(24)},
          ),
        ],
        child: MaterialApp(
          locale: Locale(locale),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: GameTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showHabitDetailSheet(context, habit()),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    String label(DateTime month, [String locale = 'en']) =>
        westernDate(month, 'MMMM yyyy', locale);

    Finder back() => find.byIcon(Icons.chevron_left_rounded);

    /// The demo sheet, identified by its example stamp rather than its CTA:
    /// the CTA string is shared with the heatmap's own upgrade card.
    Finder demoGate(String locale) =>
        find.text(S(Locale(locale)).demoGateExample);

    testWidgets('opens on the current month', (tester) async {
      await open(tester, premium: false);
      expect(find.text(label(thisMonth)), findsOneWidget);
    });

    testWidgets('a free account steps freely inside the free window',
        (tester) async {
      await open(tester, premium: false);

      // kFreeHistoryMonths covers this month plus the two behind it, so the
      // first two back-taps must simply move.
      for (var i = 1; i < kFreeHistoryMonths; i++) {
        await tester.tap(back());
        await tester.pumpAndSettle();
        expect(find.text(label(DateTime(today.year, today.month - i))),
            findsOneWidget,
            reason: 'step $i is inside the free window and must move');
        expect(demoGate('en'), findsNothing,
            reason: 'no refusal inside the free window');
      }
    });

    testWidgets('the step past the floor raises the demo sheet and does NOT '
        'move the month', (tester) async {
      await open(tester, premium: false);
      for (var i = 1; i < kFreeHistoryMonths; i++) {
        await tester.tap(back());
        await tester.pumpAndSettle();
      }
      final floorMonth =
          DateTime(today.year, today.month - (kFreeHistoryMonths - 1));
      expect(find.text(label(floorMonth)), findsOneWidget);

      await tester.tap(back());
      await tester.pumpAndSettle();

      expect(demoGate('en'), findsOneWidget,
          reason: 'the refusal has to sell, not just say no');
      // The month must not have moved underneath the sheet: a gate that
      // shows the upsell AND hands over the data gates nothing.
      expect(find.text(label(floorMonth)), findsOneWidget);
      expect(
        find.text(label(DateTime(floorMonth.year, floorMonth.month - 1))),
        findsNothing,
        reason: 'the walled month must never be rendered',
      );
    });

    testWidgets('premium walks straight past the floor', (tester) async {
      await open(tester, premium: true);
      for (var i = 1; i <= kFreeHistoryMonths + 3; i++) {
        await tester.tap(back());
        await tester.pumpAndSettle();
        expect(demoGate('en'), findsNothing,
            reason: 'premium is never refused');
      }
      expect(
        find.text(
            label(DateTime(today.year, today.month - (kFreeHistoryMonths + 3)))),
        findsOneWidget,
      );
    });

    testWidgets('the back chevron stays LIVE across the floor', (tester) async {
      // A dead arrow reads as broken; a live one that answers with the demo
      // sheet is the upgrade pitch. This is the behaviour the reports hub
      // documents on its own stepper, and the sheet has to match it.
      await open(tester, premium: false);
      for (var i = 1; i < kFreeHistoryMonths; i++) {
        await tester.tap(back());
        await tester.pumpAndSettle();
      }
      final button = tester.widget<IconButton>(
        find.ancestor(of: back(), matching: find.byType(IconButton)),
      );
      expect(button.onPressed, isNotNull,
          reason: 'sitting on the floor with data behind it, the arrow lives');
    });

    testWidgets('the back chevron dies at the DATA floor, not the paywall',
        (tester) async {
      // Only this month recorded anything, so there is genuinely nothing
      // behind it, for a free account or a paid one.
      await open(
        tester,
        premium: true,
        marks: {
          DateTime(today.year, today.month, 1).toDateKey():
              SquareState.complete,
        },
      );
      final button = tester.widget<IconButton>(
        find.ancestor(of: back(), matching: find.byType(IconButton)),
      );
      expect(button.onPressed, isNull,
          reason: 'nothing recorded earlier, so the arrow must not march '
              'into blank pre-account months forever');
    });

    testWidgets('a habit with no history at all cannot step back',
        (tester) async {
      await open(tester, premium: true, marks: const {});
      final button = tester.widget<IconButton>(
        find.ancestor(of: back(), matching: find.byType(IconButton)),
      );
      expect(button.onPressed, isNull);
    });

    // ── The year strip ───────────────────────────────────────────────────

    YearStripPainter strip(WidgetTester tester) {
      final painters = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint, skipOffstage: false))
          .map((c) => c.painter)
          .whereType<YearStripPainter>()
          .toList();
      expect(painters, hasLength(1),
          reason: 'exactly one year strip is expected in this sheet');
      return painters.single;
    }

    /// What the strip SHOULD be muting on the day this suite happens to run.
    /// Computed rather than hardcoded because a year strip correctly mutes
    /// nothing early in a year; the exhaustive month-by-month matrix for
    /// that rule lives in the historyFloorFor group above.
    DateTime? expectedFloor({required bool isPremium}) => historyFloorFor(
          windowStart: DateTime(today.year),
          today: today,
          isPremium: isPremium,
        );

    testWidgets('free: the year strip draws the same floor the stepper '
        'enforces', (tester) async {
      await open(tester, premium: false);
      expect(strip(tester).lockedBefore, expectedFloor(isPremium: false),
          reason: 'the strip and the stepper must not disagree about which '
              'days are walled');
    });

    testWidgets('premium: the year strip mutes nothing', (tester) async {
      await open(tester, premium: true);
      expect(strip(tester).lockedBefore, isNull);
    });

    /// The detector wrapping the year strip specifically. Deliberately not a
    /// count of every tappable GestureDetector in the sheet: the calendar's
    /// own day cells are tappable too, so a tree-wide count passed happily
    /// against the ungated code and proved nothing.
    GestureDetector stripTapper(WidgetTester tester) {
      final painter = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is YearStripPainter,
        skipOffstage: false,
      );
      expect(painter, findsOneWidget);
      final ancestors = find.ancestor(
        of: painter,
        matching: find.byType(GestureDetector, skipOffstage: false),
      );
      expect(ancestors, findsWidgets,
          reason: 'the year strip must be wrapped in its own detector');
      return tester.widget<GestureDetector>(ancestors.first);
    }

    testWidgets('free: the strip is tappable exactly when it mutes something',
        (tester) async {
      await open(tester, premium: false);
      expect(
        stripTapper(tester).onTapUp,
        expectedFloor(isPremium: false) == null ? isNull : isNotNull,
        reason: 'an unmuted strip must stay inert rather than swallow taps',
      );
    });

    testWidgets('premium: the strip is inert and swallows no taps',
        (tester) async {
      await open(tester, premium: true);
      expect(stripTapper(tester).onTapUp, isNull,
          reason: 'nothing is muted, so the strip must not intercept taps');
    });

    testWidgets('free: tapping a muted day actually opens the demo sheet',
        (tester) async {
      final floor = expectedFloor(isPremium: false);
      await open(tester, premium: false);
      final painter = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is YearStripPainter,
        skipOffstage: false,
      );
      final box = tester.getRect(painter);

      // The strip's first column starts on the Saturday of the week holding
      // 1 January, so its top cells usually belong to the PREVIOUS year and
      // are deliberately ignored by the tap handler. Hunting for a cell that
      // is genuinely in-year and genuinely muted, instead of assuming the
      // leading edge is both.
      final columns = yearStripColumnCount(today.year);
      Offset? target;
      for (var col = 0; col < columns && target == null; col++) {
        for (var row = 0; row < 7; row++) {
          final dxFraction = (col + 0.5) / columns;
          final day = yearStripDayAt(
            year: today.year,
            dxFraction: dxFraction,
            row: row,
            isRtl: false,
          );
          if (day.year == today.year &&
              floor != null &&
              day.isBefore(floor)) {
            target = Offset(
              box.left + dxFraction * box.width,
              box.top + (row + 0.5) * (box.height / 7),
            );
            break;
          }
        }
      }

      if (floor == null) {
        expect(target, isNull,
            reason: 'nothing is walled this early in the year');
        return;
      }
      expect(target, isNotNull,
          reason: 'a walled year must contain at least one muted in-year day');

      await tester.tapAt(target!);
      await tester.pumpAndSettle();
      expect(demoGate('en'), findsOneWidget,
          reason: 'the muted region has to sell, the same as the stepper');
    });

    testWidgets('free: tapping an UNLOCKED day on the strip sells nothing',
        (tester) async {
      // The other half of the contract. A gate that fired anywhere on the
      // strip would interrupt people looking at days they have paid for, or
      // that were free all along.
      final floor = expectedFloor(isPremium: false);
      if (floor == null) return;
      await open(tester, premium: false);
      final painter = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is YearStripPainter,
        skipOffstage: false,
      );
      final box = tester.getRect(painter);
      final columns = yearStripColumnCount(today.year);
      Offset? target;
      for (var col = columns - 1; col >= 0 && target == null; col--) {
        for (var row = 0; row < 7; row++) {
          final dxFraction = (col + 0.5) / columns;
          final day = yearStripDayAt(
            year: today.year,
            dxFraction: dxFraction,
            row: row,
            isRtl: false,
          );
          if (day.year == today.year && !day.isBefore(floor)) {
            target = Offset(
              box.left + dxFraction * box.width,
              box.top + (row + 0.5) * (box.height / 7),
            );
            break;
          }
        }
      }
      expect(target, isNotNull);
      await tester.tapAt(target!);
      await tester.pumpAndSettle();
      expect(demoGate('en'), findsNothing,
          reason: 'days inside the free window must never raise the paywall');
    });

    // ── Arabic / RTL ─────────────────────────────────────────────────────

    testWidgets('refuses identically in Arabic', (tester) async {
      await open(tester, premium: false, locale: 'ar');
      for (var i = 1; i < kFreeHistoryMonths; i++) {
        await tester.tap(back());
        await tester.pumpAndSettle();
      }
      await tester.tap(back());
      await tester.pumpAndSettle();
      expect(demoGate('ar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the strip is built RTL in Arabic', (tester) async {
      await open(tester, premium: false, locale: 'ar');
      expect(strip(tester).isRtl, isTrue,
          reason: 'the year strip reads right to left in Arabic');
    });
  });
}
