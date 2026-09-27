// The FAQ on Help & Support, with the admin tool's edits laid over it.
//
// Aziz, 2026-09-26: "make the faq ... all in the admin change firebase,
// online change not hard code". What has to hold on the phone:
//   - with no edits the screen is the code's FAQ, group by group;
//   - a question taken off, moved, reworded or added on the admin tool
//     shows that way, and a save repaints the open screen with no restart;
//   - an open answer stays open when its words change under it;
//   - every built-in question has an id the admin tool can key edits by.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/l10n/wording_edits.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/profile/screens/help_support_screen.dart';

void main() {
  const ar = S(Locale('ar'));
  const en = S(Locale('en'));

  tearDown(WordingEditsStore.reset);

  group('the built-in FAQ', () {
    test('every question has a stable id the admin tool can use', () {
      final ids = kFaqEntries.map((e) => e.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'an id used twice');
      for (final id in ids) {
        expect(RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(id), isTrue,
            reason: id,);
        // The admin tool's own additions start with these.
        for (final prefix in ['q-', 'g-', 'b-']) {
          expect(id.startsWith(prefix), isFalse, reason: id);
        }
      }
    });

    test('with no edits, the FAQ is the code\'s, in the code\'s groups', () {
      final sections = faqSectionsFor(null);
      expect(
        sections.map((s) => s.id).toList(),
        [
          for (final g in FaqGroup.values)
            if (kFaqEntries.any((e) => e.group == g)) g.name,
        ],
      );
      expect(
        sections.expand((s) => s.items).map((i) => i.id).toList(),
        [
          for (final g in FaqGroup.values)
            for (final e in kFaqEntries.where((e) => e.group == g)) e.id,
        ],
      );
      expect(sections.first.title(true), ar.faqGroupTitle('basics'));
      expect(sections.first.title(false), en.faqGroupTitle('basics'));
    });
  });

  group('on screen', () {
    Future<void> pumpHelp(WidgetTester tester, {String locale = 'ar'}) async {
      tester.view.physicalSize = const Size(390 * 3, 5200 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        locale: Locale(locale),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: GameTheme.dark,
        builder: (context, child) => WordingEditsHost(child: child!),
        home: const HelpSupportScreen(),
      ),);
      await tester.pumpAndSettle();
    }

    FaqEntry entry(String id) => kFaqEntries.firstWhere((e) => e.id == id);

    testWidgets('with no edits every built-in question shows', (tester) async {
      await pumpHelp(tester);
      for (final e in kFaqEntries) {
        expect(find.text(e.questionAr), findsOneWidget, reason: e.id);
      }
      expect(find.text(ar.faqGroupTitle('rooms')), findsOneWidget);
    });

    testWidgets('an admin save repaints the open screen: taken off, '
        'reworded, moved, and a new group with a new question first',
        (tester) async {
      await pumpHelp(tester);
      final streak = entry('streak');
      final xp = entry('xp-gold');
      final markDone = entry('mark-done');
      expect(find.text(xp.questionAr), findsOneWidget);

      WordingEditsStore.debugPublish(WordingEdits.fromData(const {
        'faq': {
          'order': [
            {'group': 'g-new00001', 'items': ['q-new00001', 'mark-done']},
            {'group': 'basics', 'items': ['streak']},
          ],
          'hidden': ['xp-gold'],
          'text': {
            'q-new00001': {
              'qAr': 'سؤال من لوحة التحكم؟',
              'qEn': 'A question from the admin tool?',
              'aAr': 'جواب من لوحة التحكم.',
              'aEn': 'An answer from the admin tool.',
            },
            'streak': {'qAr': 'كيف تنحسب سلسلتي؟'},
          },
          'groups': {
            'g-new00001': {'ar': 'البداية', 'en': 'Start here'},
          },
        },
      }),);
      await tester.pumpAndSettle();

      expect(find.text(xp.questionAr), findsNothing,
          reason: 'taken off on the admin tool',);
      expect(find.text('كيف تنحسب سلسلتي؟'), findsOneWidget);
      expect(find.text(streak.questionAr), findsNothing);
      expect(find.text('البداية'), findsOneWidget);
      final added = find.text('سؤال من لوحة التحكم؟');
      expect(added, findsOneWidget);
      // The new group comes first, with the new question above the moved one.
      final addedTop = tester.getTopLeft(added).dy;
      expect(addedTop, lessThan(tester.getTopLeft(find.text(markDone.questionAr)).dy));
      expect(tester.getTopLeft(find.text('البداية')).dy, lessThan(addedTop));
      expect(tester.getTopLeft(find.text(markDone.questionAr)).dy,
          lessThan(tester.getTopLeft(find.text(ar.faqGroupTitle('basics'))).dy),);
      // Every other built-in question is still there, where the code puts it.
      for (final e in kFaqEntries) {
        if (e.id == 'xp-gold' || e.id == 'streak') continue;
        expect(find.text(e.questionAr), findsOneWidget, reason: e.id);
      }
    });

    testWidgets('an open answer stays open when its words change',
        (tester) async {
      await pumpHelp(tester, locale: 'en');
      final plans = entry('plans');
      await tester.tap(find.text(plans.questionEn));
      await tester.pumpAndSettle();
      expect(find.text(plans.answerEn), findsOneWidget);

      WordingEditsStore.debugPublish(WordingEdits.fromData(const {
        'faq': {
          'text': {
            'plans': {'qEn': 'Guest, free or Premium?', 'aEn': 'A shorter answer.'},
          },
        },
      }),);
      await tester.pumpAndSettle();
      expect(find.text('Guest, free or Premium?'), findsOneWidget);
      expect(find.text('A shorter answer.'), findsOneWidget,
          reason: 'the answer was open, and the edit did not close it',);
    });

    testWidgets('back to built-in puts the code\'s FAQ back', (tester) async {
      WordingEditsStore.debugPublish(WordingEdits.fromData(const {
        'faq': {
          'hidden': ['delete-account'],
        },
      }),);
      await pumpHelp(tester);
      expect(find.text(entry('delete-account').questionAr), findsNothing);
      WordingEditsStore.debugPublish(WordingEdits.empty);
      await tester.pumpAndSettle();
      expect(find.text(entry('delete-account').questionAr), findsOneWidget);
    });
  });
}
