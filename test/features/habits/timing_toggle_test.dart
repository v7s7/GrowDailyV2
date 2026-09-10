// The When step asks two questions now, and only one of them opens by
// default.
//
// Cadence (daily / weekly / specific days) is settled first. Whether the
// habit has a MOMENT at all is a separate question behind a switch, off for
// every new habit, and nothing under it is pre-selected: the mode a habit
// ends up with is one somebody chose.
//
// What this replaced is worth stating, because it is the bug being fixed
// rather than a style change. The picker used to open with a mode already
// selected — Prayer for anything that read as faith, Custom Text for a quit
// goal — and a line of small print under it explaining that you could skip
// this if it did not apply. So the honest, common answer ("no particular
// time") was reachable only by leaving a control alone and believing a
// sentence that asked you not to use it, while the guess sat there looking
// like an answer already given.
//
// The tests below drive it the way a person does: through the sheet, in
// both scripts, including the two paths where the switch has to arrive
// already ON (a habit that was saved with a cue) and where turning it OFF
// has to actually drop that cue.
//
// Since 2026-09-09 the switch itself waits for the Repeat chips: what it
// opens depends on the cadence above it (a daily habit counted three times
// can hold three clock times, a weekly one cannot), so step two is answered
// downward and every helper below picks a cadence before looking for the
// switch. `pickDaily: false` stops short of that, for the test that pins
// the state before any of it exists.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_cue.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/widgets/add_habit_sheet.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    NotificationService.instance.celebrationsEnabled = false;
    GoogleFonts.config.allowRuntimeFetching = false;
    tmp = await Directory.systemTemp.createTemp('timing_toggle_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings');
    await Hive.openBox<dynamic>('box_daily_logs');
    await Hive.openBox<dynamic>('box_habits');
  });

  tearDown(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  const ar = S(Locale('ar'));
  const en = S(Locale('en'));

  Future<ProviderContainer> boot() async {
    final c = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
    ]);
    await c.read(authStateProvider.future);
    return c;
  }

  Widget app(
    ProviderContainer container,
    Locale locale, {
    IslamicHabitTemplate? existing,
  }) =>
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
          theme: GameTheme.dark,
          home: Scaffold(body: AddHabitSheet(existing: existing)),
        ),
      );

  /// A habit as it lands on disk, with whatever cue the test needs.
  IslamicHabitTemplate saved({required String cue}) => IslamicHabitTemplate(
        id: 'h-quran',
        name: 'Read Quran',
        nameAr: 'قراءة القرآن',
        description: '',
        cueAfter: cue,
        category: HabitCategory.faith,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
        hasTimer: false,
        xpReward: 20,
        goldReward: 5,
      );

  /// The tappable cell of a chip rather than its label: a picked cadence is
  /// printed again by the preview card, so the label alone is ambiguous.
  Finder chip(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;

  /// Names the habit, advances to the When step, and answers the cadence
  /// question, which is what puts the timing switch on screen at all.
  Future<void> toWhen(
    WidgetTester tester,
    S s, {
    String name = 'قراءة',
    bool pickDaily = true,
  }) async {
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField).first, name);
    await tester.pump();
    await tester.tap(find.text(s.continueAction));
    await tester.pumpAndSettle();
    if (!pickDaily) return;
    await tester.tap(chip(s.daily));
    await tester.pumpAndSettle();
  }

  /// The three timing modes, as a set: they arrive together and leave
  /// together, so every assertion about them is about all three.
  void expectModes(S s, Matcher matcher) {
    expect(find.text(s.customTime), matcher);
    expect(find.text(s.cuePrayerOption), matcher);
    expect(find.text(s.customText), matcher);
  }

  testWidgets('the switch itself waits for the cadence', (tester) async {
    final c = await boot();
    addTearDown(c.dispose);
    await tester.pumpWidget(app(c, const Locale('ar')));
    await toWhen(tester, ar, pickDaily: false);

    expect(find.text(ar.repeat), findsOneWidget,
        reason: 'the one question the step opens with');
    expect(find.byType(Switch), findsNothing);
    expect(find.text(ar.timingToggle), findsNothing,
        reason: 'what this switch opens depends on the cadence above it, so '
            'it is not offered before there is one');
    expectModes(ar, findsNothing);

    await tester.tap(chip(ar.daily));
    await tester.pumpAndSettle();
    expect(find.byType(Switch), findsOneWidget,
        reason: 'answered, so the next question arrives');
    expect(find.text(ar.timingToggle), findsOneWidget);
    // And it arrives switched off, as always: no modes under it.
    expectModes(ar, findsNothing);
  });

  testWidgets('a new habit reaches the When step with the picker closed',
      (tester) async {
    final c = await boot();
    addTearDown(c.dispose);
    await tester.pumpWidget(app(c, const Locale('ar')));
    await toWhen(tester, ar);

    expect(find.text(ar.repeat), findsOneWidget,
        reason: 'cadence is still answered here, and first');
    expect(find.text(ar.timingToggle), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    expectModes(ar, findsNothing);
    expect(find.text(ar.pickATime), findsNothing,
        reason: 'nothing under the switch until somebody opens it');
  });

  testWidgets('turning it on offers the three modes, none of them chosen',
      (tester) async {
    final c = await boot();
    addTearDown(c.dispose);
    await tester.pumpWidget(app(c, const Locale('ar')));
    await toWhen(tester, ar);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expectModes(ar, findsOneWidget);
    // The chips are the question. Anything below them would be an answer,
    // and the whole point is that the form has not been given one yet.
    expect(find.text(ar.pickATime), findsNothing);
    expect(find.text(ar.pickAPrayer), findsNothing);
    expect(find.text(ar.remindMeSection), findsNothing);
  });

  testWidgets('a mode opens only once it is picked', (tester) async {
    final c = await boot();
    addTearDown(c.dispose);
    await tester.pumpWidget(app(c, const Locale('ar')));
    await toWhen(tester, ar);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ar.customTime));
    await tester.pumpAndSettle();
    expect(find.text(ar.pickATime), findsOneWidget);

    await tester.tap(find.text(ar.cuePrayerOption));
    await tester.pumpAndSettle();
    expect(find.text(ar.pickAPrayer), findsOneWidget,
        reason: 'the chips still switch between modes as they always did');
    expect(find.text(ar.pickATime), findsNothing);
  });

  testWidgets('turning it off again takes the whole section away',
      (tester) async {
    final c = await boot();
    addTearDown(c.dispose);
    await tester.pumpWidget(app(c, const Locale('ar')));
    await toWhen(tester, ar);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ar.customTime));
    await tester.pumpAndSettle();
    expect(find.text(ar.pickATime), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expectModes(ar, findsNothing);
    expect(find.text(ar.pickATime), findsNothing,
        reason: 'off means off: the mode goes with the section, so nothing '
            'is saved that nothing on screen still shows');
  });

  testWidgets('a faith habit is no longer handed a prayer nobody picked',
      (tester) async {
    // The old default: category faith opened the Prayer picker, and its five
    // chips were on screen at the When step whether or not the person ever
    // went near them.
    final c = await boot();
    addTearDown(c.dispose);
    await tester.pumpWidget(app(c, const Locale('ar')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text(HabitCategory.faith.localizedName(true)));
    await tester.pumpAndSettle();
    await toWhen(tester, ar);

    expectModes(ar, findsNothing);
    expect(find.text(ar.pickAPrayer), findsNothing);
    expect(find.text(HabitCue.preset('fajr').labelForLocale(true)),
        findsNothing);
  });

  testWidgets('a quit goal opens closed too, and says trigger', (tester) async {
    final c = await boot();
    addTearDown(c.dispose);
    await tester.pumpWidget(app(c, const Locale('ar')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text(ar.goalTypeQuitOption));
    await tester.pumpAndSettle();
    await toWhen(tester, ar, name: 'تقليل القهوة');
    // Picked inside toWhen: for a quit goal the chips are the same three.

    expect(find.text(ar.timingToggleQuit), findsOneWidget,
        reason: "a quit habit is watching for a moment, not scheduling one");
    expect(find.text(ar.timingToggle), findsNothing);
    expectModes(ar, findsNothing);
    expect(find.text(ar.customTriggerOptional), findsNothing,
        reason: 'the freeform trigger field used to be open by default');
  });

  testWidgets('a habit saved with a prayer cue reopens with it showing',
      (tester) async {
    final c = await boot();
    addTearDown(c.dispose);
    await tester.pumpWidget(app(c, const Locale('en'), existing: saved(cue: 'fajr')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.continueAction));
    await tester.pumpAndSettle();

    expectModes(en, findsOneWidget);
    expect(find.text(en.pickAPrayer), findsOneWidget,
        reason: 'editing is the one path where the switch starts on');
    expect(find.text(HabitCue.preset('fajr').labelForLocale(false)),
        findsOneWidget);
  });

  testWidgets('a habit saved without a cue reopens closed', (tester) async {
    final c = await boot();
    addTearDown(c.dispose);
    await tester.pumpWidget(app(c, const Locale('en'), existing: saved(cue: '')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.continueAction));
    await tester.pumpAndSettle();

    expectModes(en, findsNothing);
  });

  testWidgets('turning the switch off drops the cue the habit had',
      (tester) async {
    // The preview card's summary line is built by _currentCue(), the same
    // method _submit writes to storage, so a cue that has left the preview
    // is a cue that will not be saved.
    final c = await boot();
    addTearDown(c.dispose);
    await tester.pumpWidget(
        app(c, const Locale('en'), existing: saved(cue: 'custom_time:07:30')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.continueAction));
    await tester.pumpAndSettle();
    expect(find.textContaining('7:30'), findsWidgets,
        reason: 'the time is on the row and in the preview summary');

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.textContaining('7:30'), findsNothing);
    expect(find.text(en.daily), findsNWidgets(2),
        reason: 'the summary is bare cadence again: the Daily chip and the '
            'preview line, with no cue appended to either');

    // The one tap that can put the cue back behind the section's back. The
    // per-day stepper carries a single-moment mode onto the clock-time mode
    // when the count goes above one, and the picked time is deliberately
    // kept in memory while the switch is off, so without the guard on that
    // carry this tap resurrects «7:30» into a habit whose switch says it has
    // no time, with no control on screen to see it or undo it.
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    expect(find.textContaining('7:30'), findsNothing,
        reason: 'off has to stay off through the stepper');
    expectModes(en, findsNothing);
  });

  testWidgets('the mode chips are painted unpicked until one is tapped',
      (tester) async {
    // Same reasoning as the cadence chips: absence tests below the chips all
    // survive a chip that is drawn as chosen. _SmallPick puts its state in
    // the label's weight.
    final c = await boot();
    addTearDown(c.dispose);
    await tester.pumpWidget(app(c, const Locale('en')));
    await toWhen(tester, en, name: 'Walk');
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    FontWeight? weightOf(String label) => tester
        .widget<Text>(
            find.descendant(of: chip(label), matching: find.byType(Text)))
        .style
        ?.fontWeight;

    expect(weightOf(en.customTime), FontWeight.w600);
    expect(weightOf(en.cuePrayerOption), FontWeight.w600);
    expect(weightOf(en.customText), FontWeight.w600);

    await tester.tap(find.text(en.cuePrayerOption));
    await tester.pumpAndSettle();
    expect(weightOf(en.cuePrayerOption), FontWeight.w800);
    expect(weightOf(en.customTime), FontWeight.w600);
  });
}
