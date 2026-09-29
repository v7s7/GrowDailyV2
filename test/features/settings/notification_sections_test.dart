// Settings › Notifications in sections (Aziz, 2026-09-28: "make it sections
// also").
//
// It was one card of six switches under «ما الذي تريد إشعاري به», with the
// daily reminder's time alone at the very bottom under «التوقيت», below the
// two switches that only ever add lines to that one note. Now each switch
// sits with what it feeds:
//   «العادات»          habit reminders, bundling
//   «التذكير اليومي»   the time, then streak and urgent tasks (they add to it)
//   «الغرف والأسبوع»   room activity (+ its delivery line), the Saturday note
//   «ساعات الهدوء»     unchanged
// And the picked time can be cleared with a visible ×, where it used to take
// a long press nothing on screen hinted at.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/constants/game_constants.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/habits/catalog/habit_plans.dart'
    show ReminderTimeNotifier, reminderTimeProvider;
import 'package:grow_daily_v2/features/settings/screens/notification_settings_screen.dart';
import 'package:grow_daily_v2/features/settings/widgets/notification_summary.dart';
import 'package:hive/hive.dart';

/// The reminder time without the store, Firestore or the scheduler: clear()
/// is what the × must reach, so it is counted instead of run.
class _FakeReminderTime extends ReminderTimeNotifier {
  _FakeReminderTime(TimeOfDay? time) {
    state = time;
  }

  int clears = 0;

  @override
  Future<void> clear() async {
    clears++;
    state = null;
  }
}

void main() {
  // Opened before any test body: real disk I/O started inside testWidgets
  // never finishes (see LandingHarness).
  setUp(() async {
    final tmp = await Directory.systemTemp.createTemp('notif_sections_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>(GameConstants.boxSettings);
  });

  Future<_FakeReminderTime> pump(
    WidgetTester tester, {
    TimeOfDay? time = const TimeOfDay(hour: 20, minute: 0),
    bool? phoneAllows = true,
    Locale locale = const Locale('en'),
  }) async {
    // Tall enough that every section is laid out, not lazily skipped.
    await tester.binding.setSurfaceSize(const Size(402, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final reminder = _FakeReminderTime(time);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          systemNotificationPermissionProvider
              .overrideWithValue(() async => phoneAllows),
          reminderTimeProvider.overrideWith((ref) => reminder),
        ],
        child: MaterialApp(
          locale: locale,
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: GameTheme.light,
          home: const NotificationSettingsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return reminder;
  }

  double y(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;

  testWidgets('the sections come in order, each switch under its own',
      (tester) async {
    await pump(tester);
    // 'Quiet hours' is both the heading and the switch: the heading is the
    // first one, and both must be there or .first lands on the switch.
    expect(find.text('Quiet hours'), findsNWidgets(2));
    final habits = y(tester, find.text('Habits'));
    final daily = y(tester, find.text('Daily reminder'));
    final rooms = y(tester, find.text('Rooms and the week'));
    final quiet = y(tester, find.text('Quiet hours').first);
    expect([habits, daily, rooms, quiet], orderedEquals([
      habits, daily, rooms, quiet,
    ]..sort()));

    bool between(String row, double from, double to) {
      final at = y(tester, find.text(row));
      return at > from && at < to;
    }

    expect(between('Habit reminders', habits, daily), isTrue);
    expect(between('Bundle close-together reminders', habits, daily), isTrue);
    // The two that add to the one daily note sit with its time, after it.
    expect(between('Daily Reminder', daily, rooms), isTrue);
    expect(between('Streak protection', daily, rooms), isTrue);
    expect(between('Mention urgent tasks', daily, rooms), isTrue);
    expect(y(tester, find.text('Streak protection')),
        greaterThan(y(tester, find.text('Daily Reminder'))));
    expect(between('Room activity', rooms, quiet), isTrue);
    expect(between('Weekly digest', rooms, quiet), isTrue);
    // The old headings are gone.
    expect(find.text('WHAT TO NOTIFY ME ABOUT'), findsNothing);
    expect(find.text('TIMING'), findsNothing);
  });

  testWidgets('the Arabic headings read whole: no letter spacing',
      (tester) async {
    await pump(tester, locale: const Locale('ar'));
    for (final heading in ['العادات', 'التذكير اليومي', 'الغرف والأسبوع']) {
      final text = tester.widget<Text>(find.text(heading));
      expect(text.style?.letterSpacing ?? 0, 0, reason: heading);
      expect(text.style?.fontSize, greaterThanOrEqualTo(13), reason: heading);
    }
    // Heading and switch share the words; the heading must still be there.
    expect(find.text('ساعات الهدوء'), findsNWidgets(2));
    expect(find.text('ما الذي تريد إشعاري به'), findsNothing);
  });

  testWidgets('the daily reminder row can show its ripple', (tester) async {
    // The card must be a Material with a colour and a clip, or the row's
    // ink paints on the Scaffold under the card's opaque fill.
    await pump(tester);
    final inkWell = find
        .ancestor(of: find.text('Daily Reminder'), matching: find.byType(InkWell))
        .first;
    final nearest = tester.widget<Material>(
        find.ancestor(of: inkWell, matching: find.byType(Material)).first);
    expect(nearest.color, isNotNull);
    expect(nearest.clipBehavior, isNot(Clip.none));
  });

  group('the daily reminder row', () {
    testWidgets('shows the picked time and a × that clears it',
        (tester) async {
      final reminder = await pump(tester);
      expect(find.text('8:00 PM'), findsOneWidget);
      expect(find.text('One notification a day, at the time you pick.'),
          findsOneWidget);

      await tester.tap(find.byTooltip('Clear the time'));
      await tester.pump();
      expect(reminder.clears, 1);
      expect(find.text('8:00 PM'), findsNothing);
      expect(find.byTooltip('Clear the time'), findsNothing);
      expect(find.text('Tap to set reminder time'), findsOneWidget);
    });

    testWidgets('with no time picked: no ×, the line asks for one',
        (tester) async {
      await pump(tester, time: null);
      expect(find.byTooltip('Clear the time'), findsNothing);
      expect(find.text('Tap to set reminder time'), findsOneWidget);
    });

    testWidgets('the × is a comfortable target', (tester) async {
      await pump(tester);
      final size = tester.getSize(find.byTooltip('Clear the time'));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });
  });

  // systemNotificationPermissionProvider is also what Settings' «الإشعارات»
  // line reads, so the page and the line cannot disagree.
  testWidgets('the phone-blocked banner shows when the phone blocks',
      (tester) async {
    await pump(tester, phoneAllows: false);
    expect(
        find.textContaining('turned off in system Settings'), findsOneWidget);
  });

  testWidgets('... and not when it allows', (tester) async {
    await pump(tester, phoneAllows: true);
    expect(find.textContaining('turned off in system Settings'), findsNothing);
  });

  testWidgets('... or cannot say', (tester) async {
    await pump(tester, phoneAllows: null);
    expect(find.textContaining('turned off in system Settings'), findsNothing);
  });
}
