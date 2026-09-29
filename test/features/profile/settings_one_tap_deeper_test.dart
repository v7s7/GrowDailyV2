// Settings, one tap deeper (Aziz picked option C of the Settings canvas,
// 2026-09-28).
//
// The first page is five rows, each opening its own short page, each with
// its current state written under it. The extra tap is only fair if that
// second line tells the truth, so most of what is pinned here is the line:
//  - «الإشعارات» never says an ON word (Aziz turned «شغّالة» down); it
//    says what the page holds, and names only an OFF state, and WHERE it is
//    off (the phone first, since with the phone blocking nothing in the app
//    can help);
//  - «الشكل» and «اللغة وموقع الصلاة» carry the values their pages set.
// Plus the two things that came with the move: the Premium banner stops
// selling Premium to someone who has it, and the prayer widget's link lands
// on the prayer location page with Settings under it.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/constants/game_constants.dart';
import 'package:grow_daily_v2/core/providers/app_guide_provider.dart';
import 'package:grow_daily_v2/core/providers/home_tab_provider.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';
import 'package:grow_daily_v2/features/profile/screens/profile_screen.dart';
import 'package:grow_daily_v2/features/settings/models/notification_settings.dart';
import 'package:grow_daily_v2/features/settings/notifiers/notification_settings_notifier.dart';
import 'package:grow_daily_v2/features/settings/widgets/notification_summary.dart';
import 'package:hive/hive.dart';

class _FixedNotificationSettings extends NotificationSettingsNotifier {
  _FixedNotificationSettings(NotificationSettings value) {
    state = value;
  }
}

class _FakeUser extends Fake implements User {}

void main() {
  // Opened before any test body: real disk I/O started inside testWidgets
  // never finishes (see LandingHarness).
  setUp(() async {
    final tmp = await Directory.systemTemp.createTemp('settings_deeper_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>(GameConstants.boxSettings);
  });

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    Widget home = const SettingsScreen(),
    Locale locale = const Locale('en'),
    bool? phoneAllows = true,
    bool neverAsked = false,
    bool masterOn = true,
    bool premium = false,
    bool guideSeen = true,
    bool signedIn = false,
    String? requestedPage,
    double width = 402,
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: [
        systemNotificationPermissionProvider
            .overrideWithValue(() async => phoneAllows),
        notificationPermissionNeverAskedProvider
            .overrideWithValue(() async => neverAsked),
        notificationSettingsProvider.overrideWith((ref) =>
            _FixedNotificationSettings(
                NotificationSettings(masterEnabled: masterOn))),
        premiumAccessProvider.overrideWithValue(premium),
        appGuideBadgeSeenProvider.overrideWith((ref) => guideSeen),
        authStateProvider.overrideWith(
            (ref) => Stream<User?>.value(signedIn ? _FakeUser() : null)),
      ],
    );
    addTearDown(container.dispose);
    if (requestedPage != null) {
      container.read(requestedSettingsPageProvider.notifier).state =
          requestedPage;
    }
    Widget page(String name) => Scaffold(body: Text(name));
    await tester.pumpWidget(
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
          theme: GameTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: home,
          routes: {
            '/notification-settings': (_) => page('NOTIFICATIONS PAGE'),
            '/prayer-location': (_) => page('PRAYER PLACE PAGE'),
            '/app-guide': (_) => page('APP GUIDE PAGE'),
            '/help-support': (_) => page('HELP PAGE'),
          },
        ),
      ),
    );
    // The permission answer and the auth stream land on later microtasks.
    await tester.pump();
    await tester.pump();
    return container;
  }

  group('the first page', () {
    testWidgets('is five rows, in this order', (tester) async {
      // Signed in: a guest's Account line IS «Sign Out» (the only thing on
      // that page for them), which would read as a row left behind.
      await pump(tester, signedIn: true);
      final ys = [
        for (final l in [
          'Notifications',
          'Look',
          'Language and prayer location',
          'Help',
          'Account',
        ])
          tester.getTopLeft(find.text(l)).dy,
      ];
      expect(ys, orderedEquals([...ys]..sort()));
      // Nothing that moved inside is still on the first page.
      for (final gone in ['Dark Mode', 'Appearance', 'Font', 'Language',
          'Prayer location', 'Bottom bar', 'App Guide', 'Sign Out']) {
        expect(find.text(gone), findsNothing, reason: gone);
      }
    });

    testWidgets('each row opens its own page', (tester) async {
      await pump(tester);

      Future<void> openAndBack(String row, List<String> expected,
          [Type? pageType]) async {
        await tester.tap(find.text(row));
        await tester.pumpAndSettle();
        for (final e in expected) {
          expect(find.text(e), findsWidgets, reason: '$row should show $e');
        }
        // By type too: a label alone can match the first page itself (a
        // guest's Account line IS «Sign Out»).
        if (pageType != null) {
          expect(find.byType(pageType), findsOneWidget, reason: row);
        }
        final nav = tester.state<NavigatorState>(find.byType(Navigator));
        nav.pop();
        await tester.pumpAndSettle();
      }

      await openAndBack('Notifications', ['NOTIFICATIONS PAGE']);
      await openAndBack('Look', const [
        'Dark Mode',
        'Appearance',
        'Font',
        'Pages',
        'Bottom bar',
        'Doum on the Habits page',
      ], SettingsLookScreen);
      await openAndBack('Language and prayer location',
          ['Language', 'Prayer location'], SettingsLanguagePlaceScreen);
      await openAndBack(
          'Help', ['App Guide', 'Help & Support'], SettingsHelpScreen);
      await openAndBack('Account', ['Sign Out'], SettingsAccountScreen);
    });

    testWidgets('a signed-in account reaches Delete Account from here',
        (tester) async {
      // App Store 5.1.1(v): deletion has to stay findable in the app.
      await pump(tester, signedIn: true);
      await tester.tap(find.text('Account'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsAccountScreen), findsOneWidget);
      expect(find.text('How you sign in'), findsOneWidget);
      expect(find.text('Delete Account'), findsOneWidget);
    });

    testWidgets('a long row name wraps rather than losing its end',
        (tester) async {
      // "Language and prayer location" is wider than the row on a 360pt
      // phone at a larger text size, and the name is the only thing that
      // says which page opens.
      await pump(tester, width: 360, textScale: 1.3);
      final name = tester.renderObject<RenderParagraph>(
          find.text('Language and prayer location'));
      expect(name.didExceedMaxLines, isFalse);
    });
  });

  group('the Notifications line', () {
    testWidgets('says what the page holds while nothing is off',
        (tester) async {
      await pump(tester);
      expect(find.text('Habits, daily reminder, quiet hours'), findsOneWidget);
      expect(find.text('Off'), findsNothing);
    });

    testWidgets('names the app switch when that is what is off',
        (tester) async {
      await pump(tester, masterOn: false);
      expect(find.text('Off'), findsOneWidget);
      expect(find.text('Habits, daily reminder, quiet hours'), findsNothing);
    });

    // One tree per test: a second pump reuses the line's State, and with it
    // the first pump's answer from the phone.
    testWidgets('names the phone when the phone blocks', (tester) async {
      await pump(tester, phoneAllows: false);
      expect(find.text("Off in your phone's settings"), findsOneWidget);
    });

    testWidgets('names the phone first, even with the app switch off too',
        (tester) async {
      await pump(tester, phoneAllows: false, masterOn: false);
      expect(find.text("Off in your phone's settings"), findsOneWidget);
      expect(find.text('Off'), findsNothing);
    });

    testWidgets('a phone never asked is not a phone that blocks',
        (tester) async {
      // iOS reads a permission it was never asked for as "not enabled", but
      // there is no switch in the phone's Settings app to point at yet.
      await pump(tester, phoneAllows: false, neverAsked: true);
      expect(find.text("Off in your phone's settings"), findsNothing);
      expect(find.text('Habits, daily reminder, quiet hours'), findsOneWidget);
    });

    testWidgets('the phone is asked again when the app comes back',
        (tester) async {
      var allows = true;
      final container = ProviderContainer(overrides: [
        systemNotificationPermissionProvider
            .overrideWithValue(() async => allows),
        notificationPermissionNeverAskedProvider
            .overrideWithValue(() async => false),
        notificationSettingsProvider.overrideWith((ref) =>
            _FixedNotificationSettings(const NotificationSettings())),
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
      ]);
      addTearDown(container.dispose);
      await tester.binding.setSurfaceSize(const Size(402, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ));
      await tester.pump();
      expect(find.text("Off in your phone's settings"), findsNothing);
      // Turned off in the phone's Settings app, then back to this one.
      allows = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(find.text("Off in your phone's settings"), findsOneWidget);
    });

    testWidgets('a phone that cannot say is no claim either way',
        (tester) async {
      await pump(tester, phoneAllows: null);
      expect(find.text('Habits, daily reminder, quiet hours'), findsOneWidget);
    });

    testWidgets('never an ON word in Arabic', (tester) async {
      await pump(tester, locale: const Locale('ar'));
      expect(find.text('العادات، التذكير اليومي، ساعات الهدوء'),
          findsOneWidget);
      expect(find.textContaining('شغّال'), findsNothing);
      expect(find.textContaining('مفعّل'), findsNothing);
    });
  });

  testWidgets('Look and Language lines carry their pages\' values',
      (tester) async {
    await pump(tester);
    expect(find.text('Light · Emerald & Gold'), findsOneWidget);
    // Nothing saved in this test's box.
    expect(find.text('English · Not set'), findsOneWidget);
  });

  group('the Premium banner', () {
    testWidgets('offers Premium to a free account', (tester) async {
      await pump(tester);
      expect(find.text('Unlock every Premium feature'), findsOneWidget);
      expect(find.text('Every Premium feature is yours'), findsNothing);
    });

    testWidgets('tells an account that has it, without selling it again',
        (tester) async {
      await pump(tester, premium: true);
      expect(find.text('Every Premium feature is yours'), findsOneWidget);
      expect(find.text('Unlock every Premium feature'), findsNothing);
    });
  });

  testWidgets('the App Guide\'s new dot shows on Help until it is seen',
      (tester) async {
    Finder dotIn(String row) => find.descendant(
          of: find.ancestor(of: find.text(row), matching: find.byType(InkWell))
              .first,
          matching: find.byWidgetPredicate((w) =>
              w is Container &&
              w.constraints?.maxWidth == 7 &&
              w.constraints?.maxHeight == 7),
        );
    await pump(tester, guideSeen: false);
    expect(dotIn('Help'), findsOneWidget);
    await pump(tester, guideSeen: true);
    expect(dotIn('Help'), findsNothing);
  });

  group('the Account page', () {
    testWidgets('a guest has only Sign Out', (tester) async {
      await pump(tester);
      expect(find.text('Sign Out'), findsOneWidget,
          reason: 'the Account line for a guest is Sign Out');
      await pump(tester, home: const SettingsAccountScreen());
      expect(find.text('Sign Out'), findsOneWidget);
      expect(find.text('How you sign in'), findsNothing);
      expect(find.text('Delete Account'), findsNothing);
    });

    testWidgets('a signed-in account keeps sign-in methods and delete',
        (tester) async {
      await pump(tester, signedIn: true);
      expect(find.text('Sign-in methods and sign out'), findsOneWidget);
      await pump(tester, home: const SettingsAccountScreen(), signedIn: true);
      expect(find.text('How you sign in'), findsOneWidget);
      expect(find.text('Sign Out'), findsOneWidget);
      // App Store 5.1.1(v): deletion stays in the app, below the card.
      final delete = tester.getTopLeft(find.text('Delete Account')).dy;
      expect(delete, greaterThan(tester.getTopLeft(find.text('Sign Out')).dy));
    });
  });

  group('the prayer widget\'s link', () {
    testWidgets('asked before Settings existed: the place page opens on top',
        (tester) async {
      final container =
          await pump(tester, requestedPage: kSettingsPagePrayerLocation);
      await tester.pumpAndSettle();
      expect(find.text('PRAYER PLACE PAGE'), findsOneWidget);
      expect(container.read(requestedSettingsPageProvider), isNull,
          reason: 'a request is answered once');
      // Back lands on Settings.
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.text('Language and prayer location'), findsOneWidget);
    });

    testWidgets('asked while Settings is open (a bar tab): heard and opened',
        (tester) async {
      final container = await pump(tester);
      expect(find.text('PRAYER PLACE PAGE'), findsNothing);
      container.read(requestedSettingsPageProvider.notifier).state =
          kSettingsPagePrayerLocation;
      await tester.pumpAndSettle();
      expect(find.text('PRAYER PLACE PAGE'), findsOneWidget);
      expect(container.read(requestedSettingsPageProvider), isNull);
    });

    testWidgets('a page this build does not know opens nothing',
        (tester) async {
      final container = await pump(tester, requestedPage: 'focus');
      await tester.pumpAndSettle();
      expect(find.text('PRAYER PLACE PAGE'), findsNothing);
      expect(find.text('Look'), findsOneWidget);
      expect(container.read(requestedSettingsPageProvider), isNull);
    });
  });
}
