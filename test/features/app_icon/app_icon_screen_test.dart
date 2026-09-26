// Settings › التخصيص › أيقونة التطبيق (lib/features/app_icon/app_icon_screen.dart).
//
// Pinned: the page opens on what the phone shows; shapes still ahead are
// locked and say how many full days off they are; a shape and a colour are
// picked separately and reach the phone together, ONCE, on «استخدم هذه
// الأيقونة» (iOS raises an alert per change); «مع المظهر» takes the theme's
// colour and is saved with the icon; a free account meets the paywall on a
// Premium colour and nothing changes. The Ramadan icon is locked the rest
// of the year and says when it opens; in Ramadan it moves up and anyone can
// use it; whoever has it keeps it after.
//
// Harness built in setUp, never in a test body (see LandingHarness).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/providers/day_clock_provider.dart';
import 'package:grow_daily_v2/core/providers/theme_provider.dart';
import 'package:grow_daily_v2/features/app_icon/app_icon_catalog.dart';
import 'package:grow_daily_v2/features/app_icon/app_icon_providers.dart';
import 'package:grow_daily_v2/features/app_icon/app_icon_screen.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';
import 'package:grow_daily_v2/features/premium/screens/premium_screen.dart';

import '../../helpers/landing_harness.dart';
import 'app_icon_fakes.dart';

/// 135 days before the Ramadan icon opens (the eve of 1 Ramadan 1448, 7
/// February 2027), and a day inside Ramadan 1448.
final _september = DateTime(2026, 9, 25, 14);
final _inRamadan = DateTime(2027, 2, 20, 14);

void main() {
  late LandingHarness h;
  late FakeIconPhone phone;
  tearDown(() => h.dispose());

  Future<void> prepare({
    bool premium = true,
    int days = 12,
    AppIconChoice showing = AppIconChoice.shipped,
    AppIconPrefs prefs = const AppIconPrefs(loaded: true),
    DateTime? today,
  }) async {
    phone = FakeIconPhone(showing);
    h = LandingHarness();
    await h.prepare(
      extraOverrides: [
        appIconServiceProvider.overrideWithValue(phone),
        appIconPrefsProvider.overrideWith((ref) => MemIconPrefs(prefs)),
        plantGrowthProvider.overrideWith((ref) => MemPlantGrowth()),
        plantFullDaysProvider.overrideWith((ref) async => days),
        premiumAccessProvider.overrideWithValue(premium),
        themePresetProvider.overrideWith((ref) => ThemePresetNotifier('sage')),
        // A fixed day, and no boundary timer left running after the test.
        dayClockProvider.overrideWithValue(today ?? _september),
      ],
    );
  }

  /// Tall enough for the last row of colours: a ListView only builds what
  /// is on screen, and a finder cannot see a tile that was never built.
  Future<void> open(WidgetTester tester, {Locale? locale}) async {
    await tester.binding.setSurfaceSize(const Size(402, 1700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(h.app(home: const AppIconScreen(), locale: locale));
    await h.settle(tester);
  }

  group('Premium, 12 days in', () {
    setUp(() => prepare());

    testWidgets('opens on the phone\'s icon, in Arabic', (tester) async {
      await open(tester, locale: const Locale('ar'));
      expect(find.text('أيقونة التطبيق'), findsOneWidget);
      expect(
        find.textContaining('نبتة · الأصلية', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('أيقونتك الحين'), findsOneWidget);
      expect(find.text('هذه أيقونتك الحين'), findsOneWidget);
      // The two shapes still ahead say how many full days off they are.
      expect(find.text('باقي 18 يومًا كاملًا'), findsOneWidget);
      expect(find.text('باقي 78 يومًا كاملًا'), findsOneWidget);
      expect(
        find.text('عندك 12 يومًا كاملًا. النبتة الكبيرة بعد 18 يومًا كاملًا.'),
        findsOneWidget,
      );
      expect(find.textContaining('اليوم الكامل: تنجز فيه 80%'), findsOneWidget);
      // The Ramadan icon, at the end, locked, saying when it opens.
      expect(find.text('موسمية'), findsOneWidget);
      expect(find.text('تفتح في رمضان'), findsOneWidget);
      expect(
        find.text('أيقونة رمضان تفتح للكل في رمضان، بعد 135 يومًا.'),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.text('موسمية')).dy,
        greaterThan(tester.getTopLeft(find.text('اللون')).dy),
      );
    });

    testWidgets('the Ramadan icon cannot be picked before Ramadan',
        (tester) async {
      await open(tester);
      await tester.tap(find.text('Ramadan'));
      await h.settle(tester);
      expect(find.text('Use this icon'), findsNothing);
      expect(
        find.text('Sprout · Original', findRichText: true),
        findsOneWidget,
      );
      expect(phone.sets, isEmpty);
    });

    testWidgets('a shape and a colour reach the phone together, once',
        (tester) async {
      await open(tester);
      await tester.tap(find.text('Seedling'));
      await h.settle(tester);
      expect(find.text('Preview'), findsOneWidget);
      expect(phone.sets, isEmpty, reason: 'a tap alone must not change it');

      await tester.tap(find.text('Ocean'));
      await h.settle(tester);
      expect(phone.sets, isEmpty);

      await tester.tap(find.text('Use this icon'));
      await h.settle(tester);
      expect(phone.sets, [const AppIconChoice(PlantShape.seedling, 'ocean')]);
      expect(find.text('This is your icon now'), findsOneWidget);
      expect(find.text('Your icon now'), findsOneWidget);
    });

    testWidgets('a shape still ahead stays locked', (tester) async {
      await open(tester);
      await tester.tap(find.text('In bloom'));
      await h.settle(tester);
      expect(find.text('Use this icon'), findsNothing);
      expect(
        find.text('Sprout · Original', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('«مع المظهر» takes the theme\'s colour and is kept on Use',
        (tester) async {
      await open(tester);
      await tester.tap(find.text('Match my theme'));
      await h.settle(tester);
      expect(find.text('Sprout · Sage', findRichText: true), findsOneWidget);

      await tester.tap(find.text('Use this icon'));
      await h.settle(tester);
      expect(phone.sets, [const AppIconChoice(PlantShape.sprout, 'sage')]);
      expect(h.container.read(appIconPrefsProvider).followTheme, isTrue);

      // Picking a colour by hand is the other way to make the same choice,
      // so it turns following off again.
      await tester.tap(find.text('Navy'));
      await h.settle(tester);
      await tester.tap(find.text('Use this icon'));
      await h.settle(tester);
      expect(phone.sets.last, const AppIconChoice(PlantShape.sprout, 'navy'));
      expect(h.container.read(appIconPrefsProvider).followTheme, isFalse);
    });
  });

  group('Grown far enough', () {
    setUp(() => prepare(days: 140));

    testWidgets('every shape is open and says so', (tester) async {
      await open(tester);
      expect(find.textContaining('full days to go'), findsNothing);
      expect(
        find.text('140 full days so far. Every shape is yours.'),
        findsOneWidget,
      );
      await tester.tap(find.text('In bloom'));
      await h.settle(tester);
      await tester.tap(find.text('Use this icon'));
      await h.settle(tester);
      expect(
        phone.sets,
        [const AppIconChoice(PlantShape.bloom, 'emerald_gold')],
      );
    });
  });

  group('Free', () {
    setUp(() => prepare(premium: false));

    testWidgets('Premium colours carry a lock and open the paywall',
        (tester) async {
      await open(tester);
      // 9 theme colours and 5 more; the two shapes still ahead and the
      // Ramadan icon (September) are the other locks on the page.
      expect(find.byIcon(Icons.lock_rounded), findsNWidgets(14 + 2 + 1));
      await tester.tap(find.text('Ocean'));
      await h.settle(tester);
      expect(find.byType(PremiumScreen), findsOneWidget);
      expect(phone.sets, isEmpty);
    });

    testWidgets('the free colours and every open shape still work',
        (tester) async {
      await open(tester);
      await tester.tap(find.text('Baby Pink'));
      await h.settle(tester);
      await tester.tap(find.text('Seedling'));
      await h.settle(tester);
      await tester.tap(find.text('Use this icon'));
      await h.settle(tester);
      expect(
        phone.sets,
        [const AppIconChoice(PlantShape.seedling, 'baby_pink')],
      );
    });
  });

  group('Premium lapsed, the phone still in Ocean', () {
    setUp(
      () => prepare(
        premium: false,
        showing: const AppIconChoice(PlantShape.sprout, 'ocean'),
      ),
    );

    testWidgets('keeps it, but a new icon in it goes to the paywall',
        (tester) async {
      await open(tester);
      expect(find.text('Sprout · Ocean', findRichText: true), findsOneWidget);
      await tester.tap(find.text('Seedling'));
      await h.settle(tester);
      await tester.tap(find.text('Use this icon'));
      await h.settle(tester);
      expect(find.byType(PremiumScreen), findsOneWidget);
      expect(phone.sets, isEmpty);
    });

    testWidgets('and can always go back to a free colour', (tester) async {
      await open(tester);
      await tester.tap(find.text('Original'));
      await h.settle(tester);
      await tester.tap(find.text('Use this icon'));
      await h.settle(tester);
      expect(phone.sets, [AppIconChoice.shipped]);
    });
  });

  // «مع المظهر» on, the theme Premium (Sage), and Premium ended. The saved
  // switch cannot apply without Premium, so the page reads it off; compared
  // with the saved on, it opened as already changed, «previewing», with a
  // «استخدم» that went to the paywall before anything was touched.
  group('Premium lapsed, following a Premium theme', () {
    setUp(
      () => prepare(
        premium: false,
        showing: const AppIconChoice(PlantShape.sprout, 'sage'),
        prefs: const AppIconPrefs(loaded: true, followTheme: true),
      ),
    );

    testWidgets('opens on the icon it has, with nothing to apply',
        (tester) async {
      await open(tester);
      expect(find.text('Sprout · Sage', findRichText: true), findsOneWidget);
      expect(find.text('Your icon now'), findsOneWidget);
      expect(find.text('This is your icon now'), findsOneWidget);
      expect(find.text('Use this icon'), findsNothing);
      expect(phone.sets, isEmpty);
    });
  });

  group('In Ramadan, a free account', () {
    setUp(() => prepare(premium: false, today: _inRamadan));

    testWidgets('the Ramadan icon is open, first, and anyone can use it',
        (tester) async {
      await open(tester);
      expect(find.text('All Ramadan'), findsOneWidget);
      expect(find.text('Opens in Ramadan'), findsNothing);
      expect(
        find.text('Open to everyone all through Ramadan. Pick it and it '
            'stays after.'),
        findsOneWidget,
      );
      // Under the preview, above the shapes.
      expect(
        tester.getTopLeft(find.text('Seasonal')).dy,
        lessThan(tester.getTopLeft(find.text('Shape')).dy),
      );

      await tester.tap(find.text('Ramadan'));
      await h.settle(tester);
      expect(
        find.text('Ramadan', findRichText: true),
        findsNWidgets(2),
        reason: 'the tile, and the preview naming it',
      );
      expect(find.text('Preview'), findsOneWidget);
      await tester.tap(find.text('Use this icon'));
      await h.settle(tester);
      expect(find.byType(PremiumScreen), findsNothing);
      expect(phone.sets, [AppIconChoice.ramadan]);
      expect(h.container.read(appIconPrefsProvider).followTheme, isFalse);
      expect(find.text('This is your icon now'), findsOneWidget);
    });

    testWidgets('a shape picked after it leaves it', (tester) async {
      await open(tester);
      await tester.tap(find.text('Ramadan'));
      await h.settle(tester);
      await tester.tap(find.text('Seedling'));
      await h.settle(tester);
      expect(
        find.text('Seedling · Original', findRichText: true),
        findsOneWidget,
      );
      await tester.tap(find.text('Use this icon'));
      await h.settle(tester);
      expect(
        phone.sets,
        [const AppIconChoice(PlantShape.seedling, 'emerald_gold')],
      );
    });
  });

  group('After Ramadan, the phone still showing it', () {
    setUp(() => prepare(showing: AppIconChoice.ramadan));

    testWidgets('it is kept, and a shape replaces it in the original colours',
        (tester) async {
      await open(tester);
      expect(find.text('Your icon now'), findsOneWidget);
      expect(find.text('This is your icon now'), findsOneWidget);
      expect(find.text('Opens in Ramadan'), findsOneWidget);
      await tester.tap(find.text('Seedling'));
      await h.settle(tester);
      await tester.tap(find.text('Use this icon'));
      await h.settle(tester);
      expect(
        phone.sets,
        [const AppIconChoice(PlantShape.seedling, 'emerald_gold')],
      );
    });
  });
}
