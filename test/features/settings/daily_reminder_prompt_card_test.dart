// The daily reminder question, design ج (Aziz, 2026-09-24): three ready
// times and «وقت ثاني», one tap sets one; «بعدين» and «لا، شكرًا»; and the
// second, last ask has no «بعدين», because one that meant "never" would say
// one thing and do another.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/settings/daily_reminder_prompt_dialog.dart';

void main() {
  Future<DailyReminderPromptAnswer?> Function() open(
    WidgetTester tester, {
    bool lastAsk = false,
  }) {
    DailyReminderPromptAnswer? answer;
    var done = false;
    return () async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: kSupportedLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: GameTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  answer = await showDailyReminderPrompt(context,
                      lastAsk: lastAsk);
                  done = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return done ? answer : null;
    };
  }

  testWidgets('asks in his words, with three ready times', (tester) async {
    await open(tester)();
    expect(find.text('متى يناسبك التذكير؟'), findsOneWidget);
    expect(find.text('إشعار واحد باليوم، يقول لك شنو خلّصت وشنو باقي.'),
        findsOneWidget);
    expect(find.text('بعد العشاء'), findsOneWidget,
        reason: '21:00 is marked, and only 21:00');
    expect(find.text('وقت ثاني'), findsOneWidget);
    expect(find.text('بعدين'), findsOneWidget);
    expect(find.text('لا، شكرًا'), findsOneWidget);
    // «وش» as a word, not his dialect (he says «شنو»); «وشنو» is «و» + «شنو».
    expect(find.textContaining(RegExp(r'(^|\s)وش(\s|$)')), findsNothing);
  });

  testWidgets('one tap on a ready time is the whole answer', (tester) async {
    DailyReminderPromptAnswer? answer;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: kSupportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: GameTheme.dark,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async =>
                answer = await showDailyReminderPrompt(context),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // The marked choice, found by its label rather than a formatted time.
    await tester.tap(find.text('بعد العشاء'));
    await tester.pumpAndSettle();
    expect(answer, isA<DailyReminderPromptPicked>());
    expect((answer! as DailyReminderPromptPicked).time,
        const TimeOfDay(hour: 21, minute: 0));
    expect(find.text('متى يناسبك التذكير؟'), findsNothing,
        reason: 'the card closes on the tap');
  });

  testWidgets('«بعدين» and «لا، شكرًا» answer what they say', (tester) async {
    for (final (label, type) in [
      ('بعدين', DailyReminderPromptLater),
      ('لا، شكرًا', DailyReminderPromptNever),
    ]) {
      DailyReminderPromptAnswer? answer;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: kSupportedLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: GameTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  answer = await showDailyReminderPrompt(context),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(answer.runtimeType, type, reason: label);
    }
  });

  // 2026-09-24: a launch saved «بعدين» 33 seconds in with nobody tapping
  // «بعدين». Closing the card was counted the same whoever closed it; now
  // only the person's own closing is an answer.
  testWidgets('a tap outside is «بعدين»; the app closing it answers nothing',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    DailyReminderPromptAnswer? answer;
    var closed = false;
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      locale: const Locale('ar'),
      supportedLocales: kSupportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: GameTheme.dark,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              answer = await showDailyReminderPrompt(context);
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    Future<void> openCard() async {
      answer = null;
      closed = false;
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('متى يناسبك التذكير؟'), findsOneWidget);
    }

    await openCard();
    await tester.tapAt(const Offset(8, 8)); // the dimmed page, not the card
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(answer, isA<DailyReminderPromptLater>(), reason: 'a tap outside');

    await openCard();
    // What a link from outside does (main.dart, _openFromOutside).
    navigator.currentState!.popUntil((route) => route.isFirst);
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(answer, isNull, reason: 'the app closed it, nobody answered');
    expect(find.text('متى يناسبك التذكير؟'), findsNothing);
  });

  testWidgets('the last ask has no «بعدين», and says it is the last',
      (tester) async {
    await open(tester, lastAsk: true)();
    expect(find.text('بعدين'), findsNothing);
    expect(find.text('ما بنسألك مرة ثانية.'), findsOneWidget);
    expect(find.text('لا، شكرًا'), findsOneWidget);
    expect(find.text('بعد العشاء'), findsOneWidget,
        reason: 'the times are still offered');
  });
}
