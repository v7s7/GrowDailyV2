// How often is a question, and the sheet does not answer it itself.
//
// Two things this pins, both from 2026-09-09, both carried into the
// three-step sheet of 2026-10-01 (canvas v8).
//
// ONE. The cadence used to open with «يومياً» already lit and the per-day
// stepper under it, so a habit could be created with a cadence nobody
// picked. Cadence is not cosmetic: it decides which days the Grid asks about,
// what the streak counts and which days a room scores. So it is its own step
// now, «كم مرة», one row of «كل يوم | مرات بالأسبوع | أيام معيّنة» with none
// lit, and what a choice needs next (times a day, a number a week, the days)
// in a panel under it once it is picked. «متابعة» is pressable, and pressed
// with nothing picked it says «اختر كم مرة» in the error colour and stays on
// the step rather than saving a default on somebody's behalf. Editing is the
// exception: an existing habit already has an answer and opens showing it.
//
// The old Repeat chips («يومياً | أسبوعياً | أيام محددة») and the weekly
// dropdown are gone; a number a week is six pills, «1» to «6».
//
// TWO. Embedded in the hub, the form prints no heading of its own under the
// hub's «إضافة عادة». Standalone, its heading is the only one there is (the
// Grid's edit sheet, the room habit picker and Create Room all open it with
// no chrome of their own), and for a new habit it now says the hub's words,
// «إضافة عادة» or «ترك أو تقليل», where it used to say «إضافة هدف». The hub's
// Plans / Add Goal pills are hidden on Add Goal for everybody now, not only a
// first habit, so «إضافة هدف» is not on that screen at all.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/providers/app_guide_provider.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/habits/widgets/add_habit_hub_sheet.dart';
import 'package:grow_daily_v2/features/habits/widgets/add_habit_sheet.dart';

import 'support/add_habit_flow.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    NotificationService.instance.celebrationsEnabled = false;
    GoogleFonts.config.allowRuntimeFetching = false;
    tmp = await Directory.systemTemp.createTemp('repeat_choice_');
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

  Future<ProviderContainer> boot({
    List<IslamicHabitTemplate>? habits,
    bool guest = false,
    bool midLesson = false,
  }) async {
    final c = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
      if (habits != null) habitListProvider.overrideWithValue(habits),
    ]);
    await c.read(authStateProvider.future);
    // Signed out is not the same flag as guest: guestModeProvider is what
    // «المتابعة كضيف» sets and what the habit ceiling reads
    // (habitLimitFor's isGuest), so a test that only nulls the auth stream
    // is testing a signed-out account, not a guest.
    if (guest) c.read(guestModeProvider.notifier).state = true;
    if (midLesson) {
      c.read(activeAppGuideLessonProvider.notifier).state =
          AppGuideLesson.addHabit;
    }
    return c;
  }

  Widget wrap(ProviderContainer container, Locale locale, Widget child) =>
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
          home: Scaffold(body: child),
        ),
      );

  /// An existing habit as it lands on disk.
  IslamicHabitTemplate saved({
    HabitFrequencyType type = HabitFrequencyType.weekly,
    int target = 3,
  }) =>
      IslamicHabitTemplate(
        id: 'h-walk',
        name: 'Walk',
        nameAr: 'مشي',
        description: '',
        cueAfter: '',
        category: HabitCategory.health,
        frequencyType: type,
        frequencyTarget: target,
        hasTimer: false,
        xpReward: 20,
        goldReward: 5,
      );

  /// The footer's primary button, whose onPressed being null IS the gate.
  bool primaryEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed !=
      null;

  // ── What the row LOOKS like, not only what follows from it ─────────────
  //
  // Most tests here prove "unpicked" through absences (no stepper, no week
  // pills, no cadence in the strip). All of those survive a cell that is
  // painted as chosen while _freqType is still null, which is the exact shape
  // of the mistake someone makes when a person complains «متابعة» refuses for
  // no visible reason. _SegmentedRow carries its state in the label's weight
  // (w800 lit, w600 not), so read that.
  FontWeight? weight(WidgetTester tester, String label) => tester
      .widget<Text>(
          find.descendant(of: choice(label), matching: find.byType(Text)))
      .style
      ?.fontWeight;

  void expectNoneLit(WidgetTester tester, S s) {
    expect(weight(tester, s.oftenEveryDay), FontWeight.w600);
    expect(weight(tester, s.oftenTimesAWeek), FontWeight.w600);
    expect(weight(tester, s.oftenSetDays), FontWeight.w600);
  }

  /// Nothing under the row: none of the three panels.
  void expectNoPanel(S s) {
    expect(find.byIcon(Icons.add_rounded), findsNothing,
        reason: "every day's per-day stepper waits for every day");
    expect(find.text(s.timesPerDayLabel(1)), findsNothing);
    expect(find.text(s.oftenWeekQuestion), findsNothing,
        reason: 'a number a week waits for its own choice');
    expect(find.text(s.oftenDaysQuestion), findsNothing);
  }

  testWidgets('the row opens with none of it lit, and nothing under it',
      (tester) async {
    final c = await boot();
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(c, const Locale('ar'), const AddHabitSheet()));
    await toOften(tester, ar);

    expect(find.text(ar.howOftenQuestion), findsOneWidget);
    expect(find.text(ar.oftenEveryDay), findsOneWidget,
        reason: 'the cell and nothing else: with nothing picked, the strip '
            'has no cadence to print');
    expect(find.text(ar.oftenTimesAWeek), findsOneWidget);
    expect(find.text(ar.oftenSetDays), findsOneWidget);
    expectNoneLit(tester, ar);
    expectNoPanel(ar);
    expect(find.text(ar.reminderQuestion), findsNothing,
        reason: 'the reminder is the next step, not this one');
    // The old row's words are not on this sheet any more.
    expect(find.text(ar.repeat), findsNothing);
    expect(find.text(ar.daily), findsNothing);
    expect(find.text(ar.weekly), findsNothing);
    expect(find.text(ar.specificDays), findsNothing);
    expect(find.text(ar.timesPerWeek), findsNothing);
  });

  testWidgets('«متابعة» refuses an unanswered cadence, and says so where the '
      'answer is owed', (tester) async {
    final c = await boot();
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(c, const Locale('ar'), const AddHabitSheet()));
    await toOften(tester, ar);

    expect(find.text(ar.back), findsOneWidget,
        reason: 'sanity: this is the middle step');
    expect(primaryEnabled(tester), isTrue,
        reason: 'the button is pressable: a note that arrives before anybody '
            'has tried is nagging, so the check happens on the press');
    expect(find.text(ar.repeatPickOne), findsNothing,
        reason: 'and nothing is said before that press');

    await tester.tap(find.text(ar.continueAction));
    await tester.pumpAndSettle();
    expect(find.text(ar.repeatPickOne), findsOneWidget,
        reason: 'refused, so the row says what it is owed');
    final line = find.text(ar.repeatPickOne);
    expect(tester.widget<Text>(line).style?.color,
        tester.element(line).gp.errorInk,
        reason: 'in the error colour: it is what stops the step');
    expect(find.text(ar.howOftenQuestion), findsOneWidget,
        reason: 'and the step is still here');
    expect(find.text(ar.reminderQuestion), findsNothing);

    await pickOften(tester, ar.oftenEveryDay);
    expect(find.text(ar.repeatPickOne), findsNothing,
        reason: 'answered, so the line goes');
    await tester.tap(find.text(ar.continueAction));
    await tester.pumpAndSettle();
    expect(find.text(ar.reminderQuestion), findsOneWidget,
        reason: 'and the step lets you on');
  });

  testWidgets('the strip claims no cadence until one is picked',
      (tester) async {
    final c = await boot();
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(c, const Locale('ar'), const AddHabitSheet()));
    await toOften(tester, ar);

    expect(find.text('قراءة'), findsOneWidget,
        reason: 'the name alone: the strip must not print a cadence above '
            'the row that has not been answered');
    expect(find.text('قراءة · ${ar.oftenEveryDay}'), findsNothing);

    await pickOften(tester, ar.oftenEveryDay);
    expect(find.text('قراءة · ${ar.oftenEveryDay}'), findsOneWidget,
        reason: 'once it is true, the strip says it');
    expect(find.text('قراءة'), findsNothing);
  });

  testWidgets('[en] each choice brings its own panel and no other',
      (tester) async {
    final c = await boot();
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(c, const Locale('en'), const AddHabitSheet()));
    await toOften(tester, en, name: 'Read');

    await pickOften(tester, en.oftenEveryDay);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    expect(find.text(en.timesPerDayLabel(1)), findsOneWidget);
    expect(find.text(en.oftenWeekQuestion), findsNothing);
    expect(find.text(en.oftenDaysQuestion), findsNothing);

    await pickOften(tester, en.oftenTimesAWeek);
    expect(find.text(en.oftenWeekQuestion), findsOneWidget);
    for (var n = 1; n <= 6; n++) {
      expect(find.text('$n'), findsOneWidget, reason: '«$n» a week');
    }
    expect(find.text('7'), findsNothing, reason: 'seven a week is every day');
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    expect(find.text(en.oftenDaysQuestion), findsNothing);
    expect(find.byType(DropdownButtonFormField<int>), findsNothing,
        reason: 'the number a week was a dropdown; it is six pills now');

    await pickOften(tester, en.oftenSetDays);
    expect(find.text(en.oftenDaysQuestion), findsOneWidget);
    expect(find.text(en.oftenWeekQuestion), findsNothing,
        reason: 'the day count IS the target on set days');
    expect(find.byIcon(Icons.add_rounded), findsNothing);

    await pickOften(tester, en.oftenEveryDay);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    expect(find.text(en.oftenDaysQuestion), findsNothing);
  });

  testWidgets('a daily quit habit has no panel: it is kept once a day',
      (tester) async {
    final c = await boot();
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(c, const Locale('ar'), const AddHabitSheet()));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(choice(ar.goalTypeQuitOption));
    await tester.pumpAndSettle();
    await toOften(tester, ar, name: 'القهوة');

    expect(find.text(ar.howOftenQuestionQuit), findsOneWidget);
    expectNoneLit(tester, ar);
    await pickOften(tester, ar.oftenEveryDay);
    expect(weight(tester, ar.oftenEveryDay), FontWeight.w800);
    expectNoPanel(ar);
  });

  testWidgets('the row is painted unpicked, and only the tapped cell lights',
      (tester) async {
    final c = await boot();
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(c, const Locale('ar'), const AddHabitSheet()));
    await toOften(tester, ar);

    expectNoneLit(tester, ar);
    expect(find.text(ar.repeatPickOne), findsNothing,
        reason: 'unpicked is not the same as wrong: nothing is said until '
            'somebody presses «متابعة» without answering');

    await pickOften(tester, ar.oftenTimesAWeek);
    expect(weight(tester, ar.oftenTimesAWeek), FontWeight.w800);
    expect(weight(tester, ar.oftenEveryDay), FontWeight.w600);
    expect(weight(tester, ar.oftenSetDays), FontWeight.w600);
  });

  // ── Editing ────────────────────────────────────────────────────────────

  testWidgets('an existing habit opens on the cadence it was saved with',
      (tester) async {
    // The edit path must SEED the choice, not ask for it again: a habit
    // reopened with nothing lit would re-save as something else entirely.
    final c = await boot();
    addTearDown(c.dispose);
    await tester.pumpWidget(
        wrap(c, const Locale('en'), AddHabitSheet(existing: saved())));
    await tester.pumpAndSettle();

    expect(find.text(en.timesAWeekPhrase(3)), findsOneWidget,
        reason: 'the overview names it');
    expect(primaryEnabled(tester), isTrue,
        reason: 'Save changes must never be dead on a habit that already '
            'answered this');

    await openEditStep(tester, en, 1);
    expect(weight(tester, en.oftenTimesAWeek), FontWeight.w800,
        reason: 'a number a week is lit');
    expect(weight(tester, en.oftenEveryDay), FontWeight.w600);
    expect(find.text(en.oftenWeekQuestion), findsOneWidget,
        reason: 'so its own panel is on screen');
    expect(
      tester
          .widget<Text>(find.descendant(
              of: choice('3'), matching: find.byType(Text)))
          .style
          ?.fontWeight,
      FontWeight.w800,
      reason: 'on the number it was saved with',
    );

    await editStepDone(tester, en);
    expect(find.text(en.repeatPickOne), findsNothing,
        reason: '«Done» takes it as answered');
    expect(find.text(en.saveChanges), findsOneWidget,
        reason: 'back on the overview');
  });

  testWidgets('a daily habit reopens on every day, with its stepper',
      (tester) async {
    final c = await boot();
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(
        c,
        const Locale('en'),
        AddHabitSheet(
            existing: saved(type: HabitFrequencyType.daily, target: 2))));
    await tester.pumpAndSettle();
    await openEditStep(tester, en, 1);

    expect(weight(tester, en.oftenEveryDay), FontWeight.w800);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    expect(find.text(en.timesPerDayLabel(2)), findsOneWidget,
        reason: 'twice a day comes back as twice a day');
  });

  // ── Headings ───────────────────────────────────────────────────────────

  testWidgets('[hub] the hub writes «إضافة عادة» and the form adds none',
      (tester) async {
    final c = await boot(habits: [IslamicHabitCatalog.templates.first]);
    addTearDown(c.dispose);
    await tester.pumpWidget(
        wrap(c, const Locale('ar'), const AddHabitHub(initialTab: HubTab.addGoal)));
    await tester.pumpAndSettle();

    expect(find.text(ar.hubTitle), findsOneWidget);
    expect(find.text(ar.addGoalTitle), findsNothing,
        reason: 'no pills above Add Goal for anybody now, and the form never '
            'had a heading of its own to add');

    await toOften(tester, ar);
    expect(find.text(ar.hubTitle), findsOneWidget,
        reason: 'the hub keeps its heading on every step');
    expect(find.text(ar.addGoalTitle), findsNothing);

    await pickOften(tester, ar.oftenEveryDay);
    await tester.tap(find.text(ar.continueAction));
    await tester.pumpAndSettle();
    expect(find.text(ar.hubTitle), findsOneWidget);
    expect(find.text(ar.addGoalTitle), findsNothing);
  });

  testWidgets('[hub] the heading follows the switch to Quit, on every step',
      (tester) async {
    // Aziz, 2026-09-16: building a quit goal, the sheet said «إضافة عادة»
    // over «ما الذي تريد تقليله؟», and went on saying it after Continue.
    final c = await boot(habits: [IslamicHabitCatalog.templates.first]);
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(
        c, const Locale('ar'), const AddHabitHub(initialTab: HubTab.addGoal)));
    await tester.pumpAndSettle();

    expect(find.text(ar.hubTitle), findsOneWidget, reason: 'opens on Build');

    await tester.tap(choice(ar.goalTypeQuitOption));
    await tester.pumpAndSettle();
    expect(find.text(ar.hubTitle), findsNothing,
        reason: 'this is not a habit being added any more');
    expect(find.text(ar.hubTitleQuit), findsNWidgets(2),
        reason: 'the heading and the switch that set it, same words');

    await toOften(tester, ar, name: 'القهوة');
    expect(find.text(ar.hubTitle), findsNothing);
    expect(find.text(ar.hubTitleQuit), findsOneWidget,
        reason: 'step two: the switch is behind us, the heading is not');
    expect(find.text(ar.howOftenQuestionQuit), findsOneWidget,
        reason: 'and the step asks the quit question under it');

    await pickOften(tester, ar.oftenEveryDay);
    await tester.tap(find.text(ar.continueAction));
    await tester.pumpAndSettle();
    expect(find.text(ar.hubTitleQuit), findsOneWidget,
        reason: 'and on step three');
  });

  testWidgets('standalone, a new habit is headed with the hub\'s words',
      (tester) async {
    final c = await boot();
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(c, const Locale('ar'), const AddHabitSheet()));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(ar.hubTitle), findsOneWidget,
        reason: 'nothing above this sheet says what it is');
    expect(find.text(ar.addGoalTitle), findsNothing,
        reason: '«إضافة هدف» was the old heading; one noun now, «عادة»');

    await tester.tap(choice(ar.goalTypeQuitOption));
    await tester.pumpAndSettle();
    expect(find.text(ar.hubTitle), findsNothing);
    expect(find.text(ar.hubTitleQuit), findsNWidgets(2),
        reason: 'the heading follows the switch here too');
  });

  testWidgets('standalone editing keeps its own heading', (tester) async {
    final c = await boot();
    addTearDown(c.dispose);
    await tester.pumpWidget(
        wrap(c, const Locale('ar'), AddHabitSheet(existing: saved())));
    await tester.pumpAndSettle();

    expect(find.text(ar.editHabit), findsOneWidget);
    expect(find.text(ar.hubTitle), findsNothing);
  });

  // ── Guest ──────────────────────────────────────────────────────────────
  //
  // A guest is the account most likely to meet this form: it is the first
  // thing «المتابعة كضيف» leads to. Nothing in these changes reads the auth
  // state, which is exactly why it is worth pinning: the step behaves the
  // same, and the habit ceiling a guest DOES have (kGuestHabitLimit) is
  // checked inside _submit, after the cadence question, so an unanswered
  // form never trades one refusal for another.
  testWidgets('[guest] the step behaves exactly the same', (tester) async {
    final c = await boot(guest: true);
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(c, const Locale('ar'), const AddHabitSheet()));
    await toOften(tester, ar);

    expect(find.text(ar.howOftenQuestion), findsOneWidget);
    expectNoneLit(tester, ar);
    expectNoPanel(ar);
    expect(find.text(ar.repeatPickOne), findsNothing);

    await tester.tap(find.text(ar.continueAction));
    await tester.pumpAndSettle();
    expect(find.text(ar.repeatPickOne), findsOneWidget,
        reason: 'the cadence is asked before the tier is: a guest who has '
            'not answered the form meets this line, not the paywall');
    expect(find.text(ar.howOftenQuestion), findsOneWidget);

    await pickOften(tester, ar.oftenEveryDay);
    expect(weight(tester, ar.oftenEveryDay), FontWeight.w800);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    expect(find.text(ar.repeatPickOne), findsNothing);
  });

  testWidgets('[guest] a brand new guest gets the same step through the hub',
      (tester) async {
    // The path the App Guide sends a new person down: guest, no habits yet,
    // opening the hub on Add Goal. Walked rather than assumed, because the
    // hub and the form share the sheet (see AddHabitHub._pillsHidden).
    final c = await boot(habits: const [], guest: true);
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(
        c, const Locale('ar'), const AddHabitHub(initialTab: HubTab.addGoal)));
    await tester.pumpAndSettle();

    expect(find.text(ar.hubTitle), findsOneWidget);
    expect(find.text(ar.plansTab), findsNothing,
        reason: 'no pills above the form, and the ideas door is closed');
    expect(find.text(ar.addGoalTitle), findsNothing,
        reason: 'and no second heading under the hub\'s');

    await toOften(tester, ar);
    expect(find.text(ar.howOftenQuestion), findsOneWidget);
    expectNoneLit(tester, ar);
    expectNoPanel(ar);
    expect(find.text(ar.repeatPickOne), findsNothing);

    await tester.tap(find.text(ar.continueAction));
    await tester.pumpAndSettle();
    expect(find.text(ar.repeatPickOne), findsOneWidget);

    await pickOften(tester, ar.oftenEveryDay);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    expect(find.text(ar.repeatPickOne), findsNothing);
  });

  // ── App Guide ──────────────────────────────────────────────────────────
  //
  // Step one of the App Guide opens this very sheet with the lesson active.
  // The guide needs nothing from the form (its step completes when a habit
  // appears in habitListProvider, see guide_chain), but its "choose one" card
  // shares the hub with the form. Since 2026-10-01 that card is only for a
  // hub opened on Plans: opened on Add Goal there are no pills for it to
  // explain, and the lesson's point is reaching the form.
  testWidgets('[guide] opened on Add Goal, the lesson lands on the form',
      (tester) async {
    final c = await boot(
        habits: [IslamicHabitCatalog.templates.first], midLesson: true);
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(
        c, const Locale('ar'), const AddHabitHub(initialTab: HubTab.addGoal)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining('اختر إحدى'), findsNothing,
        reason: 'no pills to choose between, so no card asking to');

    await toOften(tester, ar);
    expect(find.text(ar.howOftenQuestion), findsOneWidget);
    expectNoneLit(tester, ar);
    expect(find.text(ar.repeatPickOne), findsNothing);

    await pickOften(tester, ar.oftenEveryDay);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget,
        reason: 'the step is the same one everybody else gets');
  });

  testWidgets('[guide] opened on Plans, choosing Add Goal clears the card and '
      'the form is the same', (tester) async {
    final c = await boot(
        habits: [IslamicHabitCatalog.templates.first], midLesson: true);
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(
        c, const Locale('ar'), const AddHabitHub(initialTab: HubTab.plans)));
    // Not pumpAndSettle: the lesson's ring pulses forever.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining('اختر إحدى'), findsOneWidget,
        reason: 'sanity: the lesson is running, over the pills');

    // The body is frosted and tap-blocked while the card is up, so the
    // guide's own next move is picking a pill. That is what clears it.
    await tester.tap(find.text(ar.addGoalTitle));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('اختر إحدى'), findsNothing,
        reason: 'choosing is what the card asks for, so it goes');

    await tester.enterText(find.byType(TextField).first, 'قراءة');
    await tester.pump();
    await tester.tap(find.text(ar.continueAction));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text(ar.howOftenQuestion), findsOneWidget);
    expectNoneLit(tester, ar);
    expect(find.text(ar.repeatPickOne), findsNothing);

    await tester.tap(choice(ar.oftenEveryDay));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
  });

  // ── What is not tested here, and where it is ───────────────────────────
  //
  // Nothing in this suite saves. It used to be that nothing COULD: driving
  // the real Create button left file-backed Hive I/O in flight that a widget
  // test's fake clock never delivered, and the file hung for the full test
  // timeout. prayer_reminder_direction_test found the way through (boxes
  // opened in memory, habits seeded in setUp, the notifications channel
  // mocked), and saves through this sheet are now read back in
  // reminder_step_test (no cue, a cue dropped on an edit) and
  // quit_limit_row_alignment_test (a quit limit's amount and unit).
  //
  // "No cadence is ever stored" is still held by the compiler rather than a
  // test: _freqType is nullable and _submit reads it into a non-nullable
  // local before the three writes, so there is no expression that could
  // write an unanswered cadence; and «متابعة» refusing, above, is the gate.
}
