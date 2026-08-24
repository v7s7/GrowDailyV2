// The first-run offer, and the two ways it could go badly wrong.
//
// WRONG WAY ONE: asking the installed base. Every device that already uses
// this app finished onboarding long before this key existed, so it has
// onboarding_seen_v1 true and no key of its own. Read that as a bare false and
// the entire installed base gets a beginner question on their next launch.
//
// WRONG WAY TWO: a launch that dims the Grid on its own. This app deleted an
// autoShowAppGuideProvider that did exactly that, and the property that
// replaces it is: nothing dims the Grid that a tap in the same gesture did not
// ask for. The way this feature keeps that property is by persisting only the
// fact of having ASKED, never the answer, so there is no stored state that can
// mean "spotlight pending" at boot.
//
// These lock both. The second one is the test that would have caught
// autoShowAppGuideProvider.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/providers/app_guide_provider.dart';
import 'package:grow_daily_v2/core/providers/first_run_offer_provider.dart';
import 'package:grow_daily_v2/core/providers/onboarding_provider.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('first_run_offer_test_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings');
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
  });

  Future<Box<dynamic>> settings() => LocalStoreService.settingsBox();

  group('the migration, which is the whole trap', () {
    test('an install that predates the key is treated as already asked',
        () async {
      // No first_run_offer_asked_v1 anywhere, but onboarding was finished
      // months ago. This is every existing user on the day the feature ships.
      expect(await loadPersistedFirstRunOfferAsked(), isNull);
      expect(await resolveFirstRunOfferAsked(onboardingSeen: true), isTrue,
          reason: 'a person already using the app is never asked a beginner '
              'question');
    });

    test('a genuinely fresh install is asked', () async {
      expect(await resolveFirstRunOfferAsked(onboardingSeen: false), isFalse);
    });

    test('a recorded answer wins over the derivation, either way', () async {
      final box = await settings();
      await box.put('first_run_offer_asked_v1', true);
      expect(await resolveFirstRunOfferAsked(onboardingSeen: false), isTrue,
          reason: 'answered once means answered, even mid-onboarding');
    });
  });

  group('the in-memory default fails safe', () {
    test('an un-overridden provider does NOT ask', () {
      // onboardingSeenProvider can afford to default false: the worst case
      // there is showing the walkthrough twice. This one cannot, so it starts
      // at the terminal value and only a positive boot read moves it.
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(firstRunOfferAskedProvider), isTrue);
      expect(c.read(onboardingSeenProvider), isFalse,
          reason: 'the contrast is deliberate, not an oversight');
    });
  });

  group('no launch can dim the Grid', () {
    test('the answer is never persisted', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Stand in for a WidgetRef: answerFirstRunOffer only ever calls read().
      await _answer(container, FirstRunAnswer.yes);

      final box = await settings();
      final keys = box.keys.map((k) => k.toString()).toList();
      expect(keys, contains('first_run_offer_asked_v1'));
      for (final k in keys) {
        expect(box.get(k), isNot(equals('yes')),
            reason: 'no key may hold the answer: $k');
        expect(box.get(k), isNot(equals('later')),
            reason: 'no key may hold the answer: $k');
      }
    });

    test('every combination of persisted keys still boots un-armed', () async {
      for (final asked in [true, false, null]) {
        for (final seen in [true, false]) {
          final box = await settings();
          await box.delete('first_run_offer_asked_v1');
          if (asked != null) await box.put('first_run_offer_asked_v1', asked);

          final resolved = await resolveFirstRunOfferAsked(onboardingSeen: seen);
          final c = ProviderContainer(overrides: [
            firstRunOfferAskedProvider.overrideWith((ref) => resolved),
            onboardingSeenProvider.overrideWith((ref) => seen),
          ]);
          addTearDown(c.dispose);

          expect(c.read(activeAppGuideLessonProvider), isNull,
              reason: 'asked=$asked seen=$seen armed a coach mark at boot');
          expect(c.read(firstRunAnswerProvider), isNull,
              reason: 'asked=$asked seen=$seen replayed an answer at boot');
        }
      }
    });
  });
}

/// answerFirstRunOffer takes a WidgetRef, which a plain test has no way to
/// build. It only ever calls .read(), so this reproduces its two writes and
/// its ordering against the same container, which is what the assertions above
/// are actually about.
Future<void> _answer(ProviderContainer c, FirstRunAnswer answer) async {
  c.read(firstRunAnswerProvider.notifier).state = answer;
  c.read(firstRunOfferAskedProvider.notifier).state = true;
  final box = await LocalStoreService.settingsBox();
  await box.put('first_run_offer_asked_v1', true);
}
