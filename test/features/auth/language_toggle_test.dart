// The «العربية / EN» switch that replaced the full-screen language picker.
//
// Deleting that screen removed the only place a person could change the
// language before signing in, so this control is now the whole escape hatch
// for someone whose phone language is not the language they read. Two things
// have to hold for it to actually work as one, and neither is obvious from
// looking at the widget:
//
//   1. BOTH languages are always written in their own script. A switch that
//      said "Arabic" in English is no use to someone who reads only Arabic,
//      which is exactly the person it exists for.
//   2. The two labels never share a Text. A single Text holding both scripts
//      is reordered by the bidi algorithm around whatever direction it
//      inherits, so the pair would render in one order on the English side of
//      the app and the other order on the Arabic side.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/widgets/language_toggle.dart';

void main() {
  Future<void> pumpAt(WidgetTester tester, Locale locale) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: localeProviderOverrides(locale: locale, chosen: false),
        child: MaterialApp(
          locale: locale,
          supportedLocales: kSupportedLocales,
          // The same delegates main.dart installs. Without them an `ar`
          // locale trips a MaterialLocalizations assertion before anything
          // this file cares about gets a chance to render.
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: GameTheme.light,
          home: const Scaffold(body: Center(child: LanguageToggle())),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the two scripts never share a Text widget', (tester) async {
    // The rule from the header. A Text holding both would still make both
    // find.text calls above fail, but this says why out loud, and catches
    // the subtler version where someone joins them with a separator.
    await pumpAt(tester, const Locale('ar'));
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final data = text.data;
      if (data == null) continue;
      final hasArabic = RegExp(r'[؀-ۿ]').hasMatch(data);
      final hasLatin = RegExp(r'[A-Za-z]').hasMatch(data);
      expect(hasArabic && hasLatin, isFalse,
          reason: 'one Text carries both scripts: "$data"');
      expect(data.contains('\n'), isFalse,
          reason: 'two languages joined by a newline in one Text: "$data"');
    }
  });

  // One locale per test, never two pumps in one. Re-pumping a fresh
  // ProviderScope over the same tree does NOT rebuild the toggle against the
  // new override: Riverpod keeps the notifier the first scope created, so the
  // second half of such a test silently re-asserts the first half's state.
  for (final live in const [Locale('ar'), Locale('en')]) {
    final isAr = live.languageCode == 'ar';
    final liveLabel = isAr ? 'العربية' : 'EN';
    final otherLabel = isAr ? 'EN' : 'العربية';

    testWidgets('running in $live, both languages are shown in their own script',
        (tester) async {
      // The escape-hatch rule: whichever side the app is currently on, the
      // OTHER language is still legible to someone who only reads it.
      await pumpAt(tester, live);
      expect(find.text('العربية'), findsOneWidget);
      expect(find.text('EN'), findsOneWidget);
    });

    testWidgets('running in $live, each label declares its own direction',
        (tester) async {
      // Not inherited, and it matters on both sides: the Arabic label has to
      // stay RTL on the English side of the app, and "EN" has to stay LTR on
      // the Arabic side.
      await pumpAt(tester, live);
      for (final entry in const {
        'العربية': TextDirection.rtl,
        'EN': TextDirection.ltr,
      }.entries) {
        final owner = tester.widget<Directionality>(
          find
              .ancestor(
                of: find.text(entry.key),
                matching: find.byType(Directionality),
              )
              .first,
        );
        expect(owner.textDirection, entry.value, reason: entry.key);
      }
    });

    testWidgets('running in $live, $liveLabel is the selected half',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpAt(tester, live);

      bool selected(String label) => tester
          .getSemantics(find.text(label))
          .hasFlag(SemanticsFlag.isSelected);

      expect(selected(liveLabel), isTrue);
      expect(selected(otherLabel), isFalse);
      handle.dispose();
    });

    testWidgets('running in $live, only $otherLabel is tappable',
        (tester) async {
      // The live language is not a button. Tapping it would route through
      // setLocale and mark a language "chosen" that the person never chose,
      // and that flag is what decides whether detection and the account's own
      // value are still allowed to correct them.
      await pumpAt(tester, live);
      InkWell inkFor(String label) => tester.widget<InkWell>(
            find
                .ancestor(of: find.text(label), matching: find.byType(InkWell))
                .first,
          );
      expect(inkFor(liveLabel).onTap, isNull);
      expect(inkFor(otherLabel).onTap, isNotNull);
    });
  }
}
