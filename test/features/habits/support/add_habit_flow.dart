// Walks AddHabitSheet's three steps the way a person does (canvas v8,
// built 2026-10-01): «العادة» (type the name, «متابعة»), «كم مرة» (one
// choice in one row, «متابعة»), «التذكير (اختياري)» (a clock time or a
// prayer, or nothing, then «أضف العادة»). An edit opens on an overview of
// the three answers; a row opens its step and «تم» comes back.
//
// Shared by the habit sheet tests so a change to the flow is fixed in one
// place.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/features/habits/catalog/habit_ideas.dart';
import 'package:grow_daily_v2/features/habits/widgets/habit_ideas_page.dart';

/// The tappable cell of a choice rather than its label: a picked answer is
/// printed again in the strip at the top of the next steps, so the label
/// alone can be ambiguous. Works for the segmented rows (a GestureDetector)
/// and for InkWell chips and cards.
Finder choice(String label) => find
    .ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate(
        (w) => w is InkWell || (w is GestureDetector && w.onTap != null),
      ),
    )
    .first;

/// Types [name] into the name box (the first TextField on step 1).
Future<void> typeName(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.enterText(find.byType(TextField).first, name);
  await tester.pump();
}

/// Presses the footer's primary button, whatever it says.
Future<void> pressPrimary(WidgetTester tester) async {
  final button = find.byType(FilledButton);
  await tester.ensureVisible(button.last);
  await tester.tap(button.last);
  await tester.pumpAndSettle();
}

/// Step 1 to step 2: names the habit and presses «متابعة».
Future<void> toOften(
  WidgetTester tester,
  S s, {
  String name = 'قراءة',
}) async {
  await typeName(tester, name);
  await tester.tap(find.text(s.continueAction));
  await tester.pumpAndSettle();
}

/// How often, by its label on the row: [S.oftenEveryDay],
/// [S.oftenTimesAWeek] or [S.oftenSetDays].
Future<void> pickOften(WidgetTester tester, String label) async {
  await tester.tap(choice(label));
  await tester.pumpAndSettle();
}

/// Step 1 to step 3: names the habit, picks [often] (every day unless
/// said), and presses «متابعة» twice. Nothing is picked on step 3.
Future<void> toReminder(
  WidgetTester tester,
  S s, {
  String name = 'قراءة',
  String? often,
}) async {
  await toOften(tester, s, name: name);
  await pickOften(tester, often ?? s.oftenEveryDay);
  await tester.tap(find.text(s.continueAction));
  await tester.pumpAndSettle();
}

/// Taps «مع وقت صلاة» on step 3, which shows the five prayers.
Future<void> pickPrayerKind(WidgetTester tester, S s) async {
  await tester.tap(choice(s.reminderWithPrayer));
  await tester.pumpAndSettle();
}

/// Taps «على ساعة معيّنة» on step 3. With no time picked yet that opens the
/// time picker straight away; [confirm] presses its OK (the picker opens on
/// the current time), otherwise it is left open for the test.
Future<void> pickClockKind(
  WidgetTester tester,
  S s, {
  bool confirm = true,
}) async {
  await tester.tap(choice(s.reminderAtClock));
  await tester.pumpAndSettle();
  // No picker opens when the habit already has a time.
  final dialog = find.byType(Dialog);
  if (!confirm || dialog.evaluate().isEmpty) return;
  final ok = find.text(
    MaterialLocalizations.of(tester.element(dialog.last)).okButtonLabel,
  );
  if (ok.evaluate().isNotEmpty) {
    await tester.tap(ok.last);
    await tester.pumpAndSettle();
  }
}

/// «أضف العادة» on step 3.
Future<void> addHabit(WidgetTester tester, S s) async {
  final button = find.text(s.addHabitAction);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

/// On an edit's overview, opens the row for [step]: 0 the habit, 1 how
/// often, 2 the reminder.
Future<void> openEditStep(WidgetTester tester, S s, int step) async {
  await tester.pump(const Duration(milliseconds: 400));
  final label = switch (step) {
    0 => s.addHabitStepWhat,
    1 => s.addHabitStepOften,
    _ => s.addHabitStepReminderShort,
  };
  await tester.tap(choice(label));
  await tester.pumpAndSettle();
}

/// «تم» on an edit's step page, back to the overview.
Future<void> editStepDone(WidgetTester tester, S s) async {
  await tester.tap(find.text(s.habitEditStepDone));
  await tester.pumpAndSettle();
}

/// «احفظ التغييرات» on an edit's overview.
Future<void> saveEdit(WidgetTester tester, S s) async {
  final button = find.text(s.saveChanges);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

// ── The ideas page (habit_ideas_page.dart, 2026-10-01) ─────────────────────

/// Reads the built-in ideas once, for any test that opens the ideas page.
/// Call it from setUpAll.
///
/// The file is over 50 KB, and past that size rootBundle.loadString decodes
/// it on another isolate (compute). Inside a testWidgets body, which runs
/// in fake time, that isolate's answer never arrives: the page spins on its
/// loading circle and pumpAndSettle times out. loadBuiltInIdeas keeps what
/// it read for the rest of the run, so reading it here, in real time,
/// leaves the page nothing to wait for.
Future<void> preloadIdeas() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadBuiltInIdeas();
}

/// Step 1's ideas card, by its title: «أفكار وخطط جاهزة» where the page
/// offers plans too (the hub, a habit to build), «أفكار لعاداتك» anywhere
/// else. That second title is also the page's own, so look for it before
/// the page is open.
Finder ideasCard(S s, {bool withPlans = false}) =>
    choice(withPlans ? s.ideasEntryTitle : s.ideasEntryTitleNoPlans);

/// Taps step 1's ideas card and waits for the page and its ideas.
Future<void> openIdeas(
  WidgetTester tester,
  S s, {
  bool withPlans = false,
}) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(ideasCard(s, withPlans: withPlans));
  await tester.pumpAndSettle();
}

/// The ideas page's back button, which closes it with nothing picked.
Future<void> closeIdeas(WidgetTester tester) async {
  await tester.tap(find
      .descendant(
        of: find.byType(HabitIdeasPage),
        matching: find.byType(IconButton),
      )
      .first);
  await tester.pumpAndSettle();
}
