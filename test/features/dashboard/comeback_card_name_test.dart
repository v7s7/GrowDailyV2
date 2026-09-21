// The comeback card greets you by the name you chose.
//
// It used to greet you by your email: `user?.email?.split('@').first`, which
// put «مرحبًا بعودتك، alkubaisi1818» on the card of someone who had set a
// display name long before. Profile has always read the saved name, so the
// two screens disagreed about who you are, and the one that got it wrong is
// the only line in the app that says your name back to you.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/shared/widgets/comeback_card.dart';

const _base = DashboardState(
  level: 1,
  currentLevelXp: 0,
  cumulativeXp: 0,
  gold: 0,
  streak: 0,
  completions: {},
  // Non-zero is what makes the card render at all (showComebackBonus).
  previousStreak: 6,
);

Future<void> pumpCard(WidgetTester tester, DashboardState state) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: GameTheme.dark,
        home: Scaffold(body: ComebackCard(state: state)),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets('greets the saved display name', (tester) async {
    await pumpCard(
      tester,
      _base.copyWith(displayName: 'أبو سعود'),
    );

    expect(find.text('مرحبًا بعودتك، أبو سعود'), findsOneWidget);
  });

  testWidgets('an email is never shown as a name', (tester) async {
    // The account has a name saved, and the email local part is a string the
    // card must not reach for even when it looks name-shaped.
    await pumpCard(tester, _base.copyWith(displayName: 'عزيز'));

    expect(find.textContaining('@'), findsNothing);
    expect(find.textContaining('alkubaisi'), findsNothing);
  });

  testWidgets('no name saved means no name in the greeting', (tester) async {
    // A guest, or an account whose document has not loaded yet: the card
    // drops the name rather than inventing "Warrior" or splitting an email.
    await pumpCard(tester, _base);

    expect(find.text('مرحبًا بعودتك'), findsOneWidget);
  });
}
