// How the app decides which language to open in, now that it has three
// sources for that answer instead of one.
//
// Until this change the app read the device locale NOWHERE: app_strings.dart
// defaulted to Locale('en') and MaterialApp took its locale from the app's own
// provider, so the first-launch LanguagePickerScreen was the only code path in
// the entire app that could produce Arabic. That screen is gone now, replaced
// by detection plus the LanguageToggle on the auth screen, which is only safe
// because of what these lock.
//
// The precedence these lock, strongest first:
//   1. a language the person picked in the app     (chosen flag true)
//   2. the language recorded on their account      (adopted, flag untouched)
//   3. the language their phone is set to          (detected, nothing stored)
//   4. English
//
// The trap in the middle is the chosen flag. It is what separates "this is
// what they decided" from "this is our best guess", and if a guess ever sets
// it, the two overruling rules below silently stop working: a detected
// language stops following the OS, and an account's language stops reaching a
// device that never chose one.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('locale_resolution_test_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings');
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
  });

  Future<Box<dynamic>> settings() => LocalStoreService.settingsBox();

  group('reading the device', () {
    test('an Arabic phone opens in Arabic', () {
      expect(resolveInitialLocale(const [Locale('ar')]), const Locale('ar'));
    });

    test('country and script are ignored, so every Arabic locale counts', () {
      // The regression this pins: matching on the full tag would send ar_BH,
      // the locale this app is actually built for, to English.
      for (final tag in const [
        Locale('ar', 'BH'),
        Locale('ar', 'EG'),
        Locale('ar', 'SA'),
        Locale.fromSubtags(languageCode: 'ar', scriptCode: 'Arab'),
      ]) {
        expect(resolveInitialLocale([tag]), const Locale('ar'), reason: '$tag');
      }
    });

    test('an English phone opens in English', () {
      expect(
        resolveInitialLocale(const [Locale('en', 'GB')]),
        const Locale('en'),
      );
    });

    test('a language the app does not speak falls back to English', () {
      expect(
        resolveInitialLocale(const [Locale('fr'), Locale('es')]),
        const Locale('en'),
      );
    });

    test('a phone that asks for nothing at all falls back to English', () {
      expect(resolveInitialLocale(const []), const Locale('en'));
    });

    test("the device's order wins, not this app's", () {
      // platformDispatcher.locales is the full ordered preference list, and
      // reading only its first entry is the common way to get this wrong:
      // someone whose phone reads "Spanish, then Arabic, then English" wants
      // Arabic, and taking locales.first would hand them English by way of
      // the fallback.
      expect(
        resolveInitialLocale(
          const [Locale('es'), Locale('ar'), Locale('en')],
        ),
        const Locale('ar'),
      );
      // And the app's own list order must not leak in: kSupportedLocales
      // lists English first, so a scan over it rather than over the device's
      // list would answer English to both of these.
      expect(
        resolveInitialLocale(const [Locale('ar'), Locale('en')]),
        const Locale('ar'),
      );
      expect(
        resolveInitialLocale(const [Locale('en'), Locale('ar')]),
        const Locale('en'),
      );
    });
  });

  group('the chosen flag, and the installed base', () {
    test('a fresh install has chosen nothing', () async {
      expect(await loadPersistedLanguageChosen(), isFalse);
    });

    test('an install that predates the flag counts as having chosen', () async {
      // WRONG WAY: read a missing flag as a bare false. Before this key
      // existed the picker was the only writer of the locale key, so every
      // existing user has a stored locale and no flag. A bare false demotes
      // their settled language to a guess, which means their phone's
      // language would start overruling the one they picked.
      await (await settings()).put('selected_locale_v1', 'ar');
      expect(await loadPersistedLanguageChosen(), isTrue);
    });

    test('a stored locale with the flag explicitly false stays a guess',
        () async {
      // This is the state adoptAccountLocale leaves behind: a language is
      // stored so the next cold start opens in it without a flash, but it is
      // still the account's guess, not a decision, so a later change made on
      // another device can still land here.
      final box = await settings();
      await box.put('selected_locale_v1', 'ar');
      await box.put('language_chosen_v1', false);
      expect(await loadPersistedLanguageChosen(), isFalse);
    });

    test('a real pick is remembered as a pick', () async {
      final box = await settings();
      await box.put('selected_locale_v1', 'en');
      await box.put('language_chosen_v1', true);
      expect(await loadPersistedLanguageChosen(), isTrue);
    });
  });

  group('what boot seeds into the providers', () {
    ProviderContainer boot({required Locale locale, required bool chosen}) =>
        ProviderContainer(
          overrides: localeProviderOverrides(locale: locale, chosen: chosen),
        );

    test('a detected language renders without counting as a choice', () {
      // The pair that used to be impossible to express, because the old
      // override derived "chosen" from "a locale exists": running in Arabic
      // while nobody has actually picked Arabic. Everything downstream turns
      // on being able to tell those apart.
      final c = boot(locale: const Locale('ar'), chosen: false);
      addTearDown(c.dispose);
      expect(c.read(localeProvider), const Locale('ar'));
      expect(c.read(languageChosenProvider), isFalse);
    });

    test('a chosen language renders and is marked as chosen', () {
      final c = boot(locale: const Locale('ar'), chosen: true);
      addTearDown(c.dispose);
      expect(c.read(localeProvider), const Locale('ar'));
      expect(c.read(languageChosenProvider), isTrue);
    });
  });

  group('whether the account language is adopted at all', () {
    // The rule sign-in runs, every branch of it. This is the part that could
    // not be exercised on a simulator without real credentials, so it is
    // tested here instead of assumed.
    Locale? decide({
      required bool chosen,
      required Locale current,
      required Locale? account,
    }) =>
        localeToAdoptFromAccount(
          deviceHasChosen: chosen,
          current: current,
          account: account,
        );

    test('the case the whole feature exists for', () {
      // Reinstalled on an English phone, account reads Arabic, nobody has
      // picked anything on this device yet.
      expect(
        decide(
          chosen: false,
          current: const Locale('en'),
          account: const Locale('ar'),
        ),
        const Locale('ar'),
      );
    });

    test('a person who picked is never corrected by the server', () {
      // The veto, and the one that would be most annoying to get wrong:
      // tapping English on the auth screen and being flipped back to Arabic
      // a second later by an old value on the account.
      expect(
        decide(
          chosen: true,
          current: const Locale('en'),
          account: const Locale('ar'),
        ),
        isNull,
      );
    });

    test('an account with no language on it changes nothing', () {
      // A brand-new account, or one whose device never synced.
      expect(
        decide(chosen: false, current: const Locale('ar'), account: null),
        isNull,
      );
    });

    test('an account that already agrees changes nothing', () {
      // Returning null rather than the same value is what keeps the caller
      // from writing to Hive and rebuilding the app on every sign-in.
      expect(
        decide(
          chosen: false,
          current: const Locale('ar'),
          account: const Locale('ar'),
        ),
        isNull,
      );
    });

    test('it works in the other direction too', () {
      // Arabic phone, English account. The account still wins: it is the
      // language this person actually reads the app in on their other device.
      expect(
        decide(
          chosen: false,
          current: const Locale('ar'),
          account: const Locale('en'),
        ),
        const Locale('en'),
      );
    });
  });

  group('adopting the account language', () {
    testWidgets('applies it and stores it, without claiming it was chosen',
        (tester) async {
      late WidgetRef captured;
      await tester.pumpWidget(
        ProviderScope(
          overrides: localeProviderOverrides(
            locale: const Locale('en'),
            chosen: false,
          ),
          child: Consumer(
            builder: (context, ref, _) {
              captured = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // runAsync, because the Hive write below is real disk I/O and awaiting
      // it under the widget tester's fake clock hangs the file with no
      // failure message.
      await tester.runAsync(() async {
        await adoptAccountLocale(captured, const Locale('ar'));
      });

      expect(captured.read(localeProvider), const Locale('ar'));
      // The load-bearing half. Marking this as chosen would freeze the
      // device on this value, so a language changed later on another device
      // would never reach it again.
      expect(captured.read(languageChosenProvider), isFalse);
      expect((await settings()).get('selected_locale_v1'), 'ar');
      expect(await loadPersistedLanguageChosen(), isFalse);
    });
  });
}
