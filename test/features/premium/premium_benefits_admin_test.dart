// The paywall's list of what Premium includes, with the admin tool's edits
// laid over it (premium_benefits.dart, content_edits.dart).
//
// What has to hold:
//   - with no edits the list is the code's, row for row, in its words;
//   - a built-in row's words are its S strings, so a string edited on the
//     admin tool (Wording or Premium page) reaches the row;
//   - order, a row taken off, a new icon and a row added show as saved, and
//     an open paywall repaints with no restart;
//   - the row the paywall was opened for still leads, found by its id, and
//     the colour strip stays under the theme row whatever its icon;
//   - every built-in row has an id and an icon the app can draw.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/l10n/wording_edits.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';
import 'package:grow_daily_v2/features/premium/offers/offers_store.dart';
import 'package:grow_daily_v2/features/premium/offers/paywall_offer.dart';
import 'package:grow_daily_v2/features/premium/premium_benefits.dart';
import 'package:grow_daily_v2/features/premium/screens/premium_screen.dart';
import 'package:hive/hive.dart';

void main() {
  const ar = S(Locale('ar'));
  const en = S(Locale('en'));

  tearDown(WordingEditsStore.reset);

  const added = {
    'icon': 'mic',
    'titleAr': 'ميزة من لوحة التحكم',
    'titleEn': 'A benefit from the admin tool',
    'descAr': 'وصفها هنا.',
    'descEn': 'What it does.',
  };

  group('the list', () {
    test('every built-in row has a stable id and an icon the app draws', () {
      final ids = kBuiltInPremiumBenefits.map((b) => b.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final b in kBuiltInPremiumBenefits) {
        expect(RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(b.id), isTrue,
            reason: b.id,);
        expect(b.id.startsWith('b-'), isFalse, reason: b.id);
        expect(kBenefitIcons.containsKey(b.icon), isTrue, reason: b.icon);
      }
      expect(kBenefitIcons.containsKey(kBenefitFallbackIcon), isTrue);
    });

    test('with no edits it is the code\'s list, in the code\'s words', () {
      for (final s in [ar, en]) {
        final rows = premiumBenefitsFor(s, null);
        expect(rows.map((r) => r.id), kBuiltInPremiumBenefits.map((b) => b.id));
        for (var i = 0; i < rows.length; i++) {
          expect(rows[i].title, kBuiltInPremiumBenefits[i].title(s));
          expect(rows[i].desc, kBuiltInPremiumBenefits[i].desc(s));
          expect(rows[i].icon, kBenefitIcons[kBuiltInPremiumBenefits[i].icon]);
        }
      }
      expect(premiumBenefitsFor(en, null).first.title, en.premiumBenefitHabitsTitle);
      expect(premiumBenefitsFor(en, null)[1].id, 'rooms');
    });

    test('a string edited on the admin tool reaches its row', () {
      final edited = S.edited(
        const Locale('ar'),
        WordingEdits.fromData(const {
          'strings': {
            'ar': {'premiumBenefitVoiceTitle': 'صوتك'},
          },
        }),
      );
      final voice = premiumBenefitsFor(edited, null).firstWhere((r) => r.id == 'voice');
      expect(voice.title, 'صوتك');
    });

    test('order, a row taken off, a new icon and an added row', () {
      // The Premium page saves every row it shows, in its order.
      final saved = [
        'voice',
        'b-new00001',
        ...kBuiltInPremiumBenefits
            .map((b) => b.id)
            .where((id) => id != 'voice' && id != 'future'),
      ];
      final edits = BenefitEdits.fromData({
        'order': saved,
        'hidden': ['future'],
        'icons': {'voice': 'headphones'},
        'added': {'b-new00001': added},
      });
      final rows = premiumBenefitsFor(ar, edits);
      expect(rows.map((r) => r.id), saved);
      expect(rows.first.icon, Icons.headphones_rounded);
      expect(rows[1].title, 'ميزة من لوحة التحكم');
      expect(rows[1].icon, Icons.mic_rounded);
      expect(premiumBenefitsFor(en, edits)[1].desc, 'What it does.');
    });

    test('a row the code adds after the save shows after the row it follows '
        'in the code', () {
      // Saved before 'reminders' existed: every other row, voice first.
      final saved = [
        'voice',
        ...kBuiltInPremiumBenefits
            .map((b) => b.id)
            .where((id) => id != 'voice' && id != 'reminders'),
      ];
      final rows = premiumBenefitsFor(en, BenefitEdits.fromData({'order': saved}));
      expect(rows.map((r) => r.id).take(2), ['voice', 'reminders']);
      expect(rows.length, kBuiltInPremiumBenefits.length);
    });
  });

  group('on the paywall', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('benefits_admin_');
      Hive.init(tmp.path);
      await Hive.openBox<dynamic>('box_settings');
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await tmp.delete(recursive: true);
    });

    Future<void> pumpPaywall(
      WidgetTester tester, {
      PremiumReason reason = PremiumReason.general,
      String locale = 'ar',
    }) async {
      tester.view.physicalSize = const Size(390 * 3, 2600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          premiumProvider.overrideWith((ref) => PremiumNotifier()),
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
          builder: (context, child) => WordingEditsHost(child: child!),
          home: PremiumScreen(
            reason: reason,
            offeringLoader: () async => null,
            offersSource: PaywallOffersSource(
              loadConfig: () async => OffersConfig.fallback,
              readWelcomeStart: (_) async => null,
              ensureWelcomeStarted: (now, _) async => now,
            ),
            customerInfoLoader: () async => null,
          ),
        ),
      ),);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 400));
      }
    }

    double top(WidgetTester tester, String text) =>
        tester.getTopLeft(find.text(text)).dy;

    testWidgets('an admin save repaints the open paywall', (tester) async {
      await pumpPaywall(tester);
      expect(find.text(ar.premiumBenefitFutureTitle), findsOneWidget);
      expect(find.text('ميزة من لوحة التحكم'), findsNothing);

      WordingEditsStore.debugPublish(WordingEdits.fromData(const {
        'benefits': {
          'order': ['b-new00001', 'habits'],
          'hidden': ['future'],
          'added': {'b-new00001': added},
        },
      }),);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 400));
      }
      expect(find.text(ar.premiumBenefitFutureTitle), findsNothing);
      expect(find.text('ميزة من لوحة التحكم'), findsOneWidget);
      expect(find.text('وصفها هنا.'), findsOneWidget);
      expect(top(tester, 'ميزة من لوحة التحكم'),
          lessThan(top(tester, ar.premiumBenefitHabitsTitle)),);
    });

    testWidgets('the row the paywall was opened for still leads, by its id',
        (tester) async {
      WordingEditsStore.debugPublish(WordingEdits.fromData(const {
        'benefits': {
          'icons': {'voice': 'headphones'},
        },
      }),);
      await pumpPaywall(tester, reason: PremiumReason.voice, locale: 'en');
      expect(top(tester, en.premiumBenefitVoiceTitle),
          lessThan(top(tester, en.premiumBenefitHabitsTitle)),
          reason: 'a new icon must not cost the row its lead',);
      expect(find.byIcon(Icons.headphones_rounded), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsNothing);
    });

    testWidgets('nothing leads when the admin took the row off',
        (tester) async {
      WordingEditsStore.debugPublish(WordingEdits.fromData(const {
        'benefits': {
          'hidden': ['voice'],
        },
      }),);
      await pumpPaywall(tester, reason: PremiumReason.voice, locale: 'en');
      expect(find.text(en.premiumBenefitVoiceTitle), findsNothing);
      expect(top(tester, en.premiumBenefitHabitsTitle),
          lessThan(top(tester, en.premiumBenefitRoomsTitle)),);
    });
  });
}
