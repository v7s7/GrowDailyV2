// The Repeat chips are a question now, and the sheet stops answering itself.
//
// Two things this pins, both from 2026-09-09.
//
// ONE. Step 2 used to open with «يومياً» already lit and the per-day stepper
// under it, so a habit could be created with a cadence nobody picked. Cadence
// is not cosmetic: it decides which days the Grid asks about, what the streak
// counts and which days a room scores. So the chips open unlit, everything
// under them stays away until one is tapped, and Create is held back until
// then rather than saving a default on somebody's behalf. Editing is the
// exception: an existing habit already has an answer and opens showing it.
//
// TWO. Embedded in the hub, the form no longer prints its own «إضافة هدف»
// heading under the hub's «إضافة عادة». Standalone, that heading is the only
// one there is (the Grid's edit sheet, the room habit picker and Create Room
// all open it with no chrome of their own), so it stays.
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

  /// The tappable cell of a chip, not its label: the preview card prints the
  /// cadence word too the moment one is picked.
  Finder chip(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;

  /// The footer's primary button, whose onPressed being null IS the gate.
  bool createEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed !=
      null;

  Future<void> toWhen(WidgetTester tester, S s) async {
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField).first, 'قراءة');
    await tester.pump();
    await tester.tap(find.text(s.continueAction));
    await tester.pumpAndSettle();
  }

  testWidgets('the chips open with none of them lit, and nothing under them',
      (tester) async {
    final c = await boot();
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(c, const Locale('ar'), const AddHabitSheet()));
    await toWhen(tester, ar);

    expect(find.text(ar.repeat), findsOneWidget);
    expect(find.text(ar.daily), findsOneWidget,
        reason: 'the chip and nothing else: with no cadence picked, the '
            'preview card has no cadence to print');
    expect(find.byIcon(Icons.add_rounded), findsNothing,
        reason: "Daily's per-day stepper waits for Daily");
    expect(find.text(ar.timesPerWeek), findsNothing,
        reason: "Weekly's dropdown waits for Weekly");
    expect(find.text(ar.timesPerDayLabel(1)), findsNothing);
    expect(find.byType(Switch), findsNothing,
        reason: 'and the timing question is not asked either: the step is '
            'one question until that one is answered');
  });

  testWidgets('Create refuses an unanswered cadence, and says so where the '
      'answer is owed', (tester) async {
    final c = await boot();
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(c, const Locale('ar'), const AddHabitSheet()));
    await toWhen(tester, ar);

    expect(find.text(ar.createGoal), findsOneWidget,
        reason: 'sanity: this is step two');
    expect(createEnabled(tester), isTrue,
        reason: 'the button is pressable: a note that arrives before anybody '
            'has tried is nagging, so the check happens on the press');
    expect(find.text(ar.repeatPickOne), findsNothing,
        reason: 'and nothing is said before that press');

    await tester.tap(find.text(ar.createGoal));
    await tester.pumpAndSettle();
    expect(find.text(ar.repeatPickOne), findsOneWidget,
        reason: 'refused, so the chips say what they are owed');
    expect(find.text(ar.createGoal), findsOneWidget,
        reason: 'and the form is still here: nothing was saved');

    await tester.tap(chip(ar.daily));
    await tester.pumpAndSettle();
    expect(find.text(ar.repeatPickOne), findsNothing,
        reason: 'answered, so the line goes');
  });

  testWidgets('the preview card claims no cadence until one is picked',
      (tester) async {
    final c = await boot();
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(c, const Locale('ar'), const AddHabitSheet()));
    await toWhen(tester, ar);

    expect(find.text(ar.daily), findsOneWidget,
        reason: 'the chip only: the card must not print a cadence two lines '
            'above the button that would commit it');

    await tester.tap(chip(ar.daily));
    await tester.pumpAndSettle();
    expect(find.text(ar.daily), findsNWidgets(2),
        reason: 'chip plus the preview summary, once it is true');
  });

  testWidgets('[en] each chip brings its own control and no other',
      (tester) async {
    final c = await boot();
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(c, const Locale('en'), const AddHabitSheet()));
    await toWhen(tester, en);

    await tester.tap(chip(en.weekly));
    await tester.pumpAndSettle();
    expect(find.text(en.timesPerWeek), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsNothing);

    await tester.tap(chip(en.specificDays));
    await tester.pumpAndSettle();
    expect(find.text(en.timesPerWeek), findsNothing,
        reason: 'the day count IS the target on Specific Days');
  });

  testWidgets('an existing habit opens on the cadence it was saved with',
      (tester) async {
    // The edit path must SEED the choice, not ask for it again: a habit
    // reopened with nothing lit would re-save as something else entirely.
    final c = await boot();
    addTearDown(c.dispose);
    await tester.pumpWidget(
        wrap(c, const Locale('en'), AddHabitSheet(existing: saved())));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.continueAction));
    await tester.pumpAndSettle();

    expect(find.text(en.timesPerWeek), findsOneWidget,
        reason: 'Weekly is lit, so its own control is on screen');
    expect(createEnabled(tester), isTrue,
        reason: 'Save changes must never be dead on a habit that already '
            'answered this');
  });

  testWidgets('a daily habit reopens on Daily, with its stepper',
      (tester) async {
    final c = await boot();
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(
        c,
        const Locale('en'),
        AddHabitSheet(
            existing: saved(type: HabitFrequencyType.daily, target: 2))));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.continueAction));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    expect(find.text(en.timesPerDayLabel(2)), findsOneWidget,
        reason: 'twice a day comes back as twice a day');
  });

  testWidgets('[hub] the form adds no second heading under the hub\'s',
      (tester) async {
    final c = await boot(habits: [IslamicHabitCatalog.templates.first]);
    addTearDown(c.dispose);
    await tester.pumpWidget(
        wrap(c, const Locale('ar'), const AddHabitHub(initialTab: HubTab.addGoal)));
    await tester.pumpAndSettle();

    expect(find.text(ar.hubTitle), findsOneWidget);
    expect(find.text(ar.addGoalTitle), findsOneWidget,
        reason: 'the pill, and only the pill');

    await toWhen(tester, ar);
    expect(find.text(ar.hubTitle), findsOneWidget,
        reason: 'the hub keeps its heading on every step');
    expect(find.text(ar.addGoalTitle), findsNothing,
        reason: 'the pills are gone past step one, and the form never had a '
            'heading of its own to leave behind');
  });

  testWidgets('standalone, the sheet keeps the only heading it has',
      (tester) async {
    final c = await boot();
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(c, const Locale('ar'), const AddHabitSheet()));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(ar.addGoalTitle), findsOneWidget,
        reason: 'nothing above this sheet says what it is');
  });

  testWidgets('standalone editing keeps its own heading too', (tester) async {
    final c = await boot();
    addTearDown(c.dispose);
    await tester.pumpWidget(
        wrap(c, const Locale('ar'), AddHabitSheet(existing: saved())));
    await tester.pumpAndSettle();

    expect(find.text(ar.editHabit), findsOneWidget);
  });

  // ── What the chips LOOK like, not only what follows from them ──────────
  //
  // Every other test here proves "unpicked" through absences (no stepper, no
  // dropdown, no cadence in the preview). All of those survive a chip that
  // is painted as chosen while _freqType is still null, which is the exact
  // shape of the mistake someone makes when a person complains the Create
  // button is dead for no visible reason. _SmallPick carries its state in
  // the label's weight (w800 lit, w600 not), so read that.
  FontWeight? chipWeight(WidgetTester tester, String label) => tester
      .widget<Text>(
          find.descendant(of: chip(label), matching: find.byType(Text)))
      .style
      ?.fontWeight;

  testWidgets('the chips are painted unpicked, and only the tapped one lights',
      (tester) async {
    final c = await boot();
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(c, const Locale('ar'), const AddHabitSheet()));
    await toWhen(tester, ar);

    expect(chipWeight(tester, ar.daily), FontWeight.w600);
    expect(chipWeight(tester, ar.weekly), FontWeight.w600);
    expect(chipWeight(tester, ar.specificDays), FontWeight.w600);
    expect(find.text(ar.repeatPickOne), findsNothing,
        reason: 'unpicked is not the same as wrong: nothing is said until '
            'somebody presses Create without answering');

    await tester.tap(chip(ar.weekly));
    await tester.pumpAndSettle();
    expect(chipWeight(tester, ar.weekly), FontWeight.w800);
    expect(chipWeight(tester, ar.daily), FontWeight.w600);
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
    await toWhen(tester, ar);

    expect(find.text(ar.repeat), findsOneWidget);
    expect(chipWeight(tester, ar.daily), FontWeight.w600,
        reason: 'unlit for a guest too');
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.text(ar.repeatPickOne), findsNothing);

    await tester.tap(find.text(ar.createGoal));
    await tester.pumpAndSettle();
    expect(find.text(ar.repeatPickOne), findsOneWidget,
        reason: 'the cadence is asked before the tier is: a guest who has '
            'not answered the form meets this line, not the paywall');
    expect(find.text(ar.createGoal), findsOneWidget);

    await tester.tap(chip(ar.daily));
    await tester.pumpAndSettle();
    expect(chipWeight(tester, ar.daily), FontWeight.w800);
    expect(find.byType(Switch), findsOneWidget);
    expect(find.text(ar.repeatPickOne), findsNothing);
  });

  testWidgets('[guest] a brand new guest gets the same step through the hub',
      (tester) async {
    // The path the App Guide sends a new person down: guest, no habits yet,
    // opening the hub on Add Goal. That combination is its own layout (the
    // hub hides its pills and the form drops its heading, see
    // AddHabitHub._pillsHidden), so it is worth walking rather than assuming
    // the standalone tests above cover it.
    final c = await boot(habits: const [], guest: true);
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(
        c, const Locale('ar'), const AddHabitHub(initialTab: HubTab.addGoal)));
    await tester.pumpAndSettle();

    expect(find.text(ar.hubTitle), findsOneWidget);
    expect(find.text(ar.plansTab), findsNothing,
        reason: 'no pills above a first habit');
    expect(find.text(ar.addGoalTitle), findsNothing,
        reason: 'and no second heading under the hub\'s');

    await toWhen(tester, ar);
    expect(find.text(ar.repeat), findsOneWidget);
    expect(chipWeight(tester, ar.daily), FontWeight.w600);
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.text(ar.repeatPickOne), findsNothing);

    await tester.tap(find.text(ar.createGoal));
    await tester.pumpAndSettle();
    expect(find.text(ar.repeatPickOne), findsOneWidget);

    await tester.tap(chip(ar.daily));
    await tester.pumpAndSettle();
    expect(find.byType(Switch), findsOneWidget);
    expect(find.text(ar.repeatPickOne), findsNothing);
  });

  testWidgets('[guide] the add-habit lesson still lands on the same step',
      (tester) async {
    // Step one of the App Guide opens this very sheet, with the lesson still
    // active and the hub showing its "choose one" card over the pills. The
    // guide itself needs nothing from the form (its step completes when a
    // habit appears in habitListProvider, see guide_chain), but the card and
    // the pills share the hub with the form, so this walks the two together
    // and pins that the chooser gets out of the way and the step behaves.
    final c = await boot(
        habits: [IslamicHabitCatalog.templates.first], midLesson: true);
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(
        c, const Locale('ar'), const AddHabitHub(initialTab: HubTab.addGoal)));
    // Not pumpAndSettle: the lesson's ring pulses forever.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining('اختر إحدى'), findsOneWidget,
        reason: 'sanity: the lesson is running');

    // The form underneath is frosted and tap-blocked while the card is up,
    // so the guide's own next move is picking a pill. That is what clears it.
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

    expect(find.text(ar.repeat), findsOneWidget);
    expect(chipWeight(tester, ar.daily), FontWeight.w600,
        reason: 'the step is the same one everybody else gets');
    expect(find.byType(Switch), findsNothing);
    expect(find.text(ar.repeatPickOne), findsNothing);

    await tester.tap(chip(ar.daily));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(Switch), findsOneWidget);
  });

  // ── What is deliberately NOT tested here, and why ──────────────────────
  //
  // Nothing in this suite runs _submit, so the mapping from this form to a
  // stored habit is unguarded: the cadence that gets written, the cue that
  // does not, and the alarm and quiet-hours answers that _setTimingEnabled
  // clears on the way out. That is a real gap, not an oversight.
  //
  // It was tried, twice, both ways round: drive the real Create button
  // inside a pushed route and read the habit back out of
  // CustomHabitsNotifier. The assertions pass. The file then hangs for the
  // full ten-minute test timeout every run, because the save leaves real
  // Hive I/O in flight and a widget test's fake clock never delivers it
  // (letting it land through tester.runAsync only moves the hang). A ten
  // minute red suite costs more than the coverage buys, so the guarantees
  // are held elsewhere instead:
  //
  //  * "no cadence is ever stored" is held by the compiler, not by a test:
  //    _freqType is nullable and _submit reads it into a non-nullable local
  //    before the three writes, so there is no expression that could write
  //    an unanswered cadence.
  //  * "the button waits for the answer" is the gate test above.
  //  * "switching timing off drops the cue" is timing_toggle_test's preview
  //    line, which is built by _currentCue, the same method _submit stores.
  //
  // Left uncovered: alarm and ignoreQuietHours being cleared with the
  // section. Worth revisiting if this sheet ever gets a fake habits notifier
  // to write into.
}
