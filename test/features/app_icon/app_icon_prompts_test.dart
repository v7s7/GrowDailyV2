// The moments the Home Screen icon speaks up on its own
// (lib/features/app_icon/app_icon_prompts.dart):
//  - right after a theme is picked: with «مع المظهر» on the icon takes the
//    theme's colour; otherwise a card offers it, «مو الحين» twice ends that;
//  - when the plant grows (30 and 90 full days): «نبتتك كبرت» once per
//    newly opened shape, and «استخدمها» puts the new shape on the phone in
//    the colour it already has (the original colours after the Ramadan
//    icon, which has none for the other shapes);
//  - once each Ramadan, from 1 Ramadan until Eid: «رمضان مبارك» offers the
//    Ramadan icon, first when both cards are due, one card a call.
// All of them run on iPhones only, so every test pins the platform to iOS.
//
// Harness built in setUp, never in a test body (see LandingHarness).
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/providers/day_clock_provider.dart';
import 'package:grow_daily_v2/core/providers/theme_provider.dart';
import 'package:grow_daily_v2/features/app_icon/app_icon_catalog.dart';
import 'package:grow_daily_v2/features/app_icon/app_icon_prompts.dart';
import 'package:grow_daily_v2/features/app_icon/app_icon_providers.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';

import '../../helpers/landing_harness.dart';
import 'app_icon_fakes.dart';

/// Outside Ramadan; and Ramadan 1448 (1 Ramadan 8 February 2027, Eid
/// 9 March).
final _september = DateTime(2026, 9, 25, 14);
final _inRamadan = DateTime(2027, 2, 20, 14);

void main() {
  late LandingHarness h;
  late FakeIconPhone phone;
  tearDown(() => h.dispose());

  Future<void> prepare({
    AppIconChoice showing = AppIconChoice.shipped,
    AppIconPrefs prefs = const AppIconPrefs(loaded: true),
    String theme = 'ocean',
    bool premium = true,
    int days = 12,
    PlantGrowth growth = const PlantGrowth(loaded: true),
    DateTime? today,
  }) async {
    phone = FakeIconPhone(showing);
    h = LandingHarness();
    await h.prepare(
      extraOverrides: [
        appIconServiceProvider.overrideWithValue(phone),
        appIconPrefsProvider.overrideWith((ref) => MemIconPrefs(prefs)),
        plantGrowthProvider.overrideWith((ref) => MemPlantGrowth(growth)),
        plantFullDaysProvider.overrideWith((ref) async => days),
        premiumAccessProvider.overrideWithValue(premium),
        themePresetProvider.overrideWith((ref) => ThemePresetNotifier(theme)),
        // A fixed day, and no boundary timer left running after the test.
        dayClockProvider.overrideWithValue(today ?? _september),
      ],
    );
  }

  /// A screen with one button that runs [action] the way the app does.
  Future<void> host(
    WidgetTester tester,
    Future<void> Function(BuildContext, WidgetRef) action,
  ) async {
    await tester.pumpWidget(
      h.app(
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => action(context, ref),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await h.settle(tester);
    await tester.tap(find.text('go'));
    // The growth card waits a beat before it shows (so a completion's own
    // celebration goes first); settling alone never runs out that timer.
    await tester.pump(const Duration(seconds: 1));
    await h.settle(tester);
  }

  Future<void> offer(BuildContext context, WidgetRef ref) => offerIconForTheme(
        ProviderScope.containerOf(context, listen: false),
        ScaffoldMessenger.of(context),
      );

  group('after a theme is picked', () {
    group('following the theme', () {
      setUp(
        () => prepare(
          prefs: const AppIconPrefs(loaded: true, followTheme: true),
          showing: const AppIconChoice(PlantShape.grown, 'sage'),
        ),
      );

      testWidgets('the icon takes the colour and keeps its shape',
          (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          await host(tester, offer);
          expect(phone.sets, [const AppIconChoice(PlantShape.grown, 'ocean')]);
          expect(find.text('Match the app icon too?'), findsNothing);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    });

    group('not following', () {
      setUp(() => prepare());

      testWidgets('offers it; the box makes it automatic from now on',
          (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          await host(tester, offer);
          expect(find.text('Match the app icon too?'), findsOneWidget);
          expect(
            find.text('The Ocean icon on your Home Screen'),
            findsOneWidget,
          );
          expect(phone.sets, isEmpty);

          await tester.tap(find.text('Always match my theme'));
          await tester.pump();
          await tester.tap(find.text('Change it'));
          await h.settle(tester);
          expect(phone.sets, [const AppIconChoice(PlantShape.sprout, 'ocean')]);
          expect(h.container.read(appIconPrefsProvider).followTheme, isTrue);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

      testWidgets('«مو الحين» changes nothing and is counted', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          await host(tester, offer);
          await tester.tap(find.text('Not now'));
          await h.settle(tester);
          expect(phone.sets, isEmpty);
          expect(h.container.read(appIconPrefsProvider).offerDeclines, 1);
          expect(h.container.read(appIconPrefsProvider).followTheme, isFalse);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    });

    group('asked twice already', () {
      setUp(
        () =>
            prepare(prefs: const AppIconPrefs(loaded: true, offerDeclines: 2)),
      );

      testWidgets('is left alone', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          await host(tester, offer);
          expect(find.text('Match the app icon too?'), findsNothing);
          expect(phone.sets, isEmpty);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    });

    group('icon already in the theme\'s colour', () {
      setUp(
        () => prepare(showing: const AppIconChoice(PlantShape.bloom, 'ocean')),
      );

      testWidgets('says nothing', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          await host(tester, offer);
          expect(find.text('Match the app icon too?'), findsNothing);
          expect(phone.sets, isEmpty);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    });

    group('a Premium colour on a free account', () {
      setUp(
        () => prepare(
          premium: false,
          prefs: const AppIconPrefs(loaded: true, followTheme: true),
        ),
      );

      testWidgets('is never put on the phone', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          await host(tester, offer);
          expect(phone.sets, isEmpty);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    });

    group('on Android', () {
      setUp(
        () => prepare(
          prefs: const AppIconPrefs(loaded: true, followTheme: true),
        ),
      );

      testWidgets('nothing happens at all', (tester) async {
        await host(tester, offer);
        expect(phone.sets, isEmpty);
      });
    });
  });

  group('when the plant grows', () {
    group('35 days, the grown plant just opened', () {
      setUp(
        () => prepare(
          days: 35,
          showing: const AppIconChoice(PlantShape.sprout, 'sage'),
        ),
      );

      testWidgets('shows once, and «استخدمها» keeps the colour',
          (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          await host(tester, maybeShowIconCard);
          expect(find.text('Your plant grew'), findsOneWidget);
          expect(
            find.text('You have 35 full days now, and a new icon shape is '
                'yours.'),
            findsOneWidget,
          );
          expect(
            find.text('The bloom after 55 more full days.'),
            findsOneWidget,
          );
          await tester.tap(find.text('Use it'));
          await h.settle(tester);
          expect(phone.sets, [const AppIconChoice(PlantShape.grown, 'sage')]);
          expect(
            h.container.read(plantGrowthProvider).celebrated,
            PlantShape.grown,
          );

          // Once: the same count again shows nothing.
          await tester.tap(find.text('go'));
          await tester.pump(const Duration(seconds: 1));
          await h.settle(tester);
          expect(find.text('Your plant grew'), findsNothing);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    });

    group('150 days the first time it is seen', () {
      setUp(() => prepare(days: 150));

      testWidgets('one card, for the bloom', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          await host(tester, maybeShowIconCard);
          expect(find.text('Your plant is in bloom'), findsOneWidget);
          // Nothing is ahead of the bloom, so no "next" line.
          expect(find.textContaining('The bloom after'), findsNothing);
          expect(find.textContaining('The grown plant after'), findsNothing);
          await tester.tap(find.text('Later'));
          await h.settle(tester);
          expect(phone.sets, isEmpty);
          expect(
            h.container.read(plantGrowthProvider).celebrated,
            PlantShape.bloom,
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    });

    group('35 days, with the Ramadan icon on the phone', () {
      setUp(() => prepare(days: 35, showing: AppIconChoice.ramadan));

      testWidgets('the new shape comes in the original colours',
          (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          await host(tester, maybeShowIconCard);
          expect(find.text('Your plant grew'), findsOneWidget);
          await tester.tap(find.text('Use it'));
          await h.settle(tester);
          expect(
            phone.sets,
            [const AppIconChoice(PlantShape.grown, 'emerald_gold')],
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    });

    // A phone still in a Premium colour after Premium ended keeps it, like a
    // paid theme, but a NEW icon in that colour is an edit, and the icon
    // page sends that edit to the paywall. Until 2026-09-26 this card put it
    // on the phone with no question asked.
    group('35 days, a Premium colour kept after Premium ended', () {
      setUp(
        () => prepare(
          days: 35,
          premium: false,
          showing: const AppIconChoice(PlantShape.sprout, 'sage'),
        ),
      );

      testWidgets('the grown plant comes in the original colours',
          (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          await host(tester, maybeShowIconCard);
          expect(find.text('Your plant grew'), findsOneWidget);
          await tester.tap(find.text('Use it'));
          await h.settle(tester);
          expect(
            phone.sets,
            [const AppIconChoice(PlantShape.grown, 'emerald_gold')],
            reason: 'never the Premium colour without Premium',
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    });

    group('12 days', () {
      setUp(() => prepare());

      testWidgets('nothing to say yet', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          await host(tester, maybeShowIconCard);
          expect(find.text('Your plant grew'), findsNothing);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    });
  });

  group('once each Ramadan', () {
    const ramadanBody = 'The Ramadan icon is open to everyone all month.';

    group('in Ramadan, following the theme', () {
      setUp(
        () => prepare(
          today: _inRamadan,
          prefs: const AppIconPrefs(loaded: true, followTheme: true),
          showing: const AppIconChoice(PlantShape.sprout, 'ocean'),
        ),
      );

      testWidgets('«استخدمها» puts it on, and a theme will not take it off',
          (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          await host(tester, maybeShowIconCard);
          expect(find.text('Ramadan Mubarak'), findsOneWidget);
          expect(find.text(ramadanBody), findsOneWidget);
          expect(h.container.read(appIconPrefsProvider).ramadanCardYear, 1448);
          await tester.tap(find.text('Use it'));
          await h.settle(tester);
          expect(phone.sets, [AppIconChoice.ramadan]);
          expect(h.container.read(appIconPrefsProvider).followTheme, isFalse);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    });

    group('in Ramadan, «بعدين»', () {
      setUp(() => prepare(today: _inRamadan));

      testWidgets('changes nothing, and the card is done for this Ramadan',
          (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          await host(tester, maybeShowIconCard);
          await tester.tap(find.text('Later'));
          await h.settle(tester);
          expect(phone.sets, isEmpty);

          await tester.tap(find.text('go'));
          await tester.pump(const Duration(seconds: 1));
          await h.settle(tester);
          expect(find.text('Ramadan Mubarak'), findsNothing);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    });

    group('the next Ramadan', () {
      setUp(
        () => prepare(
          today: DateTime(2028, 2, 10, 9),
          prefs: const AppIconPrefs(loaded: true, ramadanCardYear: 1448),
        ),
      );

      testWidgets('has a card of its own', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          await host(tester, maybeShowIconCard);
          expect(find.text('Ramadan Mubarak'), findsOneWidget);
          expect(h.container.read(appIconPrefsProvider).ramadanCardYear, 1449);
          // Closed before the test ends: a card left open keeps the one-at-
          // a-time line waiting, and the next test's call with it.
          await tester.tap(find.text('Later'));
          await h.settle(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    });

    for (final (moment, day) in [
      ('in September', DateTime(2026, 9, 25, 14)),
      // The picker opens the tile on the eve; the greeting waits for the
      // month itself.
      ('on the eve', DateTime(2027, 2, 7, 20)),
      ('on Eid', DateTime(2027, 3, 9, 9)),
    ]) {
      group(moment, () {
        // The grown plant is due too, so the plant card's turn proves the
        // call ran and passed Ramadan's by.
        setUp(() => prepare(today: day, days: 35));

        testWidgets('there is no Ramadan card', (tester) async {
          debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
          try {
            await host(tester, maybeShowIconCard);
            expect(find.text('Ramadan Mubarak'), findsNothing);
            expect(find.text('Your plant grew'), findsOneWidget);
            expect(h.container.read(appIconPrefsProvider).ramadanCardYear, 0);
            await tester.tap(find.text('Later'));
            await h.settle(tester);
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        });
      });
    }

    group('a phone already showing the Ramadan icon', () {
      setUp(
        () => prepare(
          today: _inRamadan,
          showing: AppIconChoice.ramadan,
          days: 35,
        ),
      );

      testWidgets('is not told about it', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          await host(tester, maybeShowIconCard);
          expect(find.text('Ramadan Mubarak'), findsNothing);
          expect(h.container.read(appIconPrefsProvider).ramadanCardYear, 1448);
          // The plant's card has the turn instead, grown in the original
          // colours since the Ramadan icon has none for other shapes.
          expect(find.text('Your plant grew'), findsOneWidget);
          await tester.tap(find.text('Later'));
          await h.settle(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    });

    group('in Ramadan with the grown plant due too', () {
      setUp(() => prepare(today: _inRamadan, days: 35));

      testWidgets('one card a call, Ramadan\'s first', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          await host(tester, maybeShowIconCard);
          expect(find.text('Ramadan Mubarak'), findsOneWidget);
          expect(find.text('Your plant grew'), findsNothing);
          await tester.tap(find.text('Later'));
          await h.settle(tester);
          expect(
            find.text('Your plant grew'),
            findsNothing,
            reason: 'never straight after another card',
          );

          await tester.tap(find.text('go'));
          await tester.pump(const Duration(seconds: 1));
          await h.settle(tester);
          expect(find.text('Your plant grew'), findsOneWidget);
          await tester.tap(find.text('Later'));
          await h.settle(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    });

    group('on Android, in Ramadan', () {
      setUp(() => prepare(today: _inRamadan));

      testWidgets('nothing at all', (tester) async {
        await host(tester, maybeShowIconCard);
        expect(find.text('Ramadan Mubarak'), findsNothing);
      });
    });
  });
}
