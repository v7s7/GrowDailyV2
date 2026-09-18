// The admin's wording edits, laid over the built-in text.
//
// What has to hold, and none of it is visible by reading the code once:
//   - a malformed document can cost an entry, never a screen: nothing blank,
//     nothing thrown, and the built-in text wherever an edit is unusable;
//   - an edit reaches the string it names and no other, in its own language
//     only, and a string with more than one wording is never flattened by one;
//   - the {parts} of an edit are filled with the very values the built-in
//     sentence uses, so a plural that comes from the code survives an edit;
//   - a save repaints what is already on screen, with no restart;
//   - the generated layer knows every string in S, so a string added without
//     rerunning the generator fails here instead of quietly not being
//     editable.
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/l10n/daily_quotes.dart';
import 'package:grow_daily_v2/core/l10n/wording_edits.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/grid/widgets/daily_quote_line.dart';

void main() {
  const ar = Locale('ar');
  const en = Locale('en');

  tearDown(WordingEditsStore.reset);

  group('reading the document', () {
    test('anything that is not a document is no edits at all', () {
      for (final junk in [null, 'text', 42, <Object?>[], <String, Object?>{}]) {
        expect(WordingEdits.fromData(junk).isEmpty, isTrue, reason: '$junk');
      }
    });

    test('a bad entry costs that entry and nothing else', () {
      final edits = WordingEdits.fromData(const {
        'strings': {
          'ar': {
            'signIn': 'ادخل',
            'createAccount': 7,
            'email': '   ',
            'password': '',
          },
          'en': 'not a map',
        },
        'version': 3.0,
      });
      expect(edits.ar, {'signIn': 'ادخل'});
      expect(edits.en, isEmpty);
      expect(edits.version, 3);
    });

    test('a quote needs both languages, and no usable quote is the built-in '
        'rotation, never an empty Grid line', () {
      final edits = WordingEdits.fromData(const {
        'quotes': [
          {'ar': ' الأول ', 'en': ' First '},
          {'ar': 'بلا إنجليزي'},
          {'ar': 'x', 'en': '  '},
          'not a map',
        ],
      });
      expect(edits.quotes!.single.ar, 'الأول');
      expect(edits.quotes!.single.en, 'First');

      expect(WordingEdits.fromData(const {'quotes': <Object?>[]}).quotes, isNull);
      expect(
        WordingEdits.fromData(const {
          'quotes': [
            {'ar': '', 'en': ''},
          ],
        }).quotes,
        isNull,
      );
    });

    test('this device\'s copy reads back as what was saved', () {
      final edits = WordingEdits.fromData(const {
        'strings': {
          'ar': {'signIn': 'ادخل'},
          'en': {'signIn': 'Log in'},
        },
        'quotes': [
          {'ar': 'سطر', 'en': 'Line'},
        ],
        'version': 9,
      });
      final again = WordingEdits.fromData(edits.toJson());
      expect(again.toJson(), edits.toJson());
    });

    test('every language but Arabic reads the English edits, as S does', () {
      const edits = WordingEdits(ar: {'a': 'ع'}, en: {'a': 'E'});
      expect(edits.stringsFor('ar'), {'a': 'ع'});
      expect(edits.stringsFor('en'), {'a': 'E'});
      expect(edits.stringsFor('fr'), {'a': 'E'});
    });
  });

  group('filling the {parts} of an edit', () {
    test('known parts are filled in place', () {
      expect(
        fillWording('{n} من {total}', {
          'n': () => '2',
          'total': () => '5',
        }),
        '2 من 5',
      );
    });

    test('a part the app cannot fill sets the whole edit aside', () {
      // Only possible when the code renamed or dropped a value after the edit
      // was saved: the admin tool refuses unknown parts. A raw {name} must
      // never reach a reader, so the caller falls back to the built-in text.
      expect(
        fillWording('{n} من {total} {unknown}', {
          'n': () => '2',
          'total': () => '5',
        }),
        isNull,
      );
      expect(wordingPartsKnown('بدون أقواس', const []), isTrue);
      expect(wordingPartsKnown('{level} فقط', const ['level']), isTrue);
      expect(wordingPartsKnown('{lvl}', const ['level']), isFalse);
      expect(plainWording('ادخل'), 'ادخل');
      expect(plainWording('ادخل {name}'), isNull);
      expect(plainWording(null), isNull);
    });

    test('a value is written once, even when it holds a brace of its own', () {
      expect(
        fillWording('{name} ثم {level}', {
          'name': () => '{level}',
          'level': () => '7',
        }),
        '{level} ثم 7',
      );
    });

    test('a part can appear twice, and a missing one is never computed', () {
      var computed = 0;
      expect(
        fillWording('{a}-{a}', {
          'a': () => 'x',
          'b': () {
            computed++;
            return 'y';
          },
        }),
        'x-x',
      );
      expect(computed, 0);
    });

    test('text with no braces comes back untouched', () {
      expect(fillWording('بدون أقواس', {'a': () => 'x'}), 'بدون أقواس');
      expect(fillWording('بدون أقواس', {}), 'بدون أقواس');
    });
  });

  group('S with edits laid over it', () {
    test('no edits for the language is plain S, not a copy of it', () {
      expect(S.edited(ar, WordingEdits.empty).runtimeType, S);
      expect(
        S.edited(ar, const WordingEdits(en: {'signIn': 'Log in'})).runtimeType,
        S,
        reason: 'English edits must not wrap the Arabic strings',
      );
    });

    test('an edit replaces its own string, in its own language only', () {
      const edits = WordingEdits(ar: {'signIn': 'ادخل حسابك'});
      final edited = S.edited(ar, edits);
      expect(edited.signIn, 'ادخل حسابك');
      expect(edited.createAccount, const S(ar).createAccount);
      expect(S.edited(en, edits).signIn, const S(en).signIn);
    });

    test('an edit keeps the values the built-in sentence computes, plural '
        'and all', () {
      const plain = S(ar);
      const edits = WordingEdits(
        ar: {
          'reconnectFound': 'المستوى {level}: {daysInSentence(days)} و'
              '{habitsCount(habits)}',
        },
      );
      final edited = S.edited(ar, edits);
      for (final (habits, days) in [(1, 1), (2, 2), (3, 11)]) {
        expect(
          edited.reconnectFound(habits, days, 22),
          'المستوى 22: ${plain.daysInSentence(days)} و'
          '${plain.habitsCount(habits)}',
        );
      }
    });

    test('a part the code computes privately still fills', () {
      // habitReminderBeforePrayer's Arabic reads «قبل {prayer}
      // {_byAmount(amount)}», and _byAmount is private to app_strings.dart.
      // The generated layer is a part of that library for exactly this.
      const plain = S(ar);
      final builtIn = plain.habitReminderBeforePrayer('الفجر', '15 دقيقة');
      final amountPhrase = builtIn.substring('قبل الفجر '.length);
      final edited = S.edited(
        ar,
        const WordingEdits(
          ar: {
            'habitReminderBeforePrayer': '{_byAmount(amount)} قبل {prayer}',
          },
        ),
      );
      expect(
        edited.habitReminderBeforePrayer('الفجر', '15 دقيقة'),
        '$amountPhrase قبل الفجر',
      );
    });

    test('an edit naming a part the string no longer has shows the built-in '
        'text, never a raw {name}', () {
      const plain = S(ar);
      final edited = S.edited(
        ar,
        const WordingEdits(
          ar: {
            // A method whose code has since dropped {level}.
            'reconnectFound': 'المستوى {lvl}: {daysInSentence(days)}',
            // A getter that fills nothing.
            'signIn': 'ادخل يا {name}',
            // And one good edit beside them, which still applies.
            'createAccount': 'حساب جديد',
          },
        ),
      );
      expect(edited.reconnectFound(3, 5, 22), plain.reconnectFound(3, 5, 22));
      expect(edited.signIn, plain.signIn);
      expect(edited.createAccount, 'حساب جديد');
    });

    test('a string with more than one wording ignores an edit', () {
      const plain = S(ar);
      final edited = S.edited(
        ar,
        const WordingEdits(
          ar: {
            'daysInSentence': 'يوم',
            'signIn': 'x',
          },
        ),
      );
      for (final n in [1, 2, 3, 11]) {
        expect(edited.daysInSentence(n), plain.daysInSentence(n));
      }
      expect(kBuiltInOnlyWordingKeys, contains('daysInSentence'));
    });
  });

  group('the generated layer', () {
    // Every public string member S declares, read straight off the source.
    Set<String> declaredStrings() {
      final lines =
          File('lib/core/l10n/app_strings.dart').readAsLinesSync();
      final start = lines.indexWhere((l) => l.startsWith('class S {'));
      expect(start, isNot(-1), reason: 'class S not found');
      final member = RegExp(
        r'^  (?:String|List<String>) (?:get )?([a-zA-Z]\w*)\s*(?:=>|\(|\{|$)',
      );
      final names = <String>{};
      for (var i = start + 1; i < lines.length; i++) {
        if (lines[i] == '}') break;
        final m = member.firstMatch(lines[i]);
        if (m != null) names.add(m.group(1)!);
      }
      return names;
    }

    test('knows every string in S, so each one is either editable or '
        'listed as built-in only', () {
      final declared = declaredStrings();
      final known = {...kEditableWordingKeys, ...kBuiltInOnlyWordingKeys};
      final missing = declared.difference(known);
      final gone = known.difference(declared);
      expect(
        missing.isEmpty && gone.isEmpty,
        isTrue,
        reason: 'app_strings_edited.g.dart is out of date '
            '(new: $missing, removed: $gone). Rerun: cd docs/wording/generator '
            '&& dart run bin/gen_wording_edits.dart',
      );
    });

    test('no string is in both lists or listed twice', () {
      expect(kEditableWordingKeys.toSet().length, kEditableWordingKeys.length);
      expect(
        kBuiltInOnlyWordingKeys.toSet().length,
        kBuiltInOnlyWordingKeys.length,
      );
      expect(
        kEditableWordingKeys.toSet().intersection(
              kBuiltInOnlyWordingKeys.toSet(),
            ),
        isEmpty,
      );
    });
  });

  group('the daily quote', () {
    test('comes from the saved rotation when there is one', () {
      const saved = [
        DailyQuote(ar: 'أ', en: 'A'),
        DailyQuote(ar: 'ب', en: 'B'),
      ];
      final day = DateTime(2026, 9, 18);
      final picked = quoteForDay(day, from: saved);
      expect(saved, contains(picked));
      expect(
        quoteForDay(day.add(const Duration(days: 1)), from: saved),
        isNot(same(picked)),
      );
    });

    test('an empty rotation falls back to the built-in one', () {
      final day = DateTime(2026, 9, 18);
      expect(quoteForDay(day, from: const []), same(quoteForDay(day)));
    });
  });

  group('on screen', () {
    Widget app(Locale locale, Widget child) => MaterialApp(
          locale: locale,
          supportedLocales: kSupportedLocales,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: GameTheme.light,
          home: WordingEditsHost(child: Scaffold(body: child)),
        );

    testWidgets('a save repaints a string that is already showing',
        (tester) async {
      await tester.pumpWidget(
        app(
          ar,
          Builder(builder: (context) => Text(S.of(context).signIn)),
        ),
      );
      expect(find.text(const S(ar).signIn), findsOneWidget);

      WordingEditsStore.debugPublish(
        const WordingEdits(ar: {'signIn': 'ادخل حسابك'}),
      );
      await tester.pump();
      expect(find.text('ادخل حسابك'), findsOneWidget);

      // Taking the edit away brings the built-in text straight back.
      WordingEditsStore.debugPublish(WordingEdits.empty);
      await tester.pump();
      expect(find.text(const S(ar).signIn), findsOneWidget);
    });

    testWidgets('the Grid line follows a saved rotation and back',
        (tester) async {
      await tester.pumpWidget(app(ar, const DailyQuoteLine()));
      final builtIn = quoteForDay(DateTime.now()).ar;
      expect(find.text(builtIn), findsOneWidget);

      WordingEditsStore.debugPublish(
        const WordingEdits(
          quotes: [
            DailyQuote(ar: 'سطر واحد فقط', en: 'Only one line'),
          ],
        ),
      );
      await tester.pump();
      expect(find.text('سطر واحد فقط'), findsOneWidget);

      WordingEditsStore.debugPublish(WordingEdits.empty);
      await tester.pump();
      expect(find.text(builtIn), findsOneWidget);
    });
  });

  group('following the document', () {
    late Directory dir;
    late Box<dynamic> box;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('wording_edits_test');
      Hive.init(dir.path);
      box = await Hive.openBox<dynamic>('settings_wording_test');
    });

    tearDown(() async {
      await box.deleteFromDisk();
      dir.deleteSync(recursive: true);
    });

    test('a save arrives, is kept on the device, and outlives a restart',
        () async {
      final db = FakeFirebaseFirestore();
      WordingEditsStore.listen(firestore: db, box: box, retryOnResume: false);
      await pumpEventQueue();
      expect(WordingEditsStore.current.isEmpty, isTrue);
      expect(box.get(WordingEditsStore.cacheKey), isNull);

      await db.doc(kWordingDocPath).set({
        'strings': {
          'ar': {'signIn': 'ادخل حسابك'},
        },
        'version': 1,
      });
      await pumpEventQueue();
      expect(WordingEditsStore.current.ar, {'signIn': 'ادخل حسابك'});
      expect(box.get(WordingEditsStore.cacheKey), isA<String>());

      // A cold start: nothing in memory, the copy on the device restores it
      // before any network.
      await WordingEditsStore.reset();
      expect(WordingEditsStore.current.isEmpty, isTrue);
      await WordingEditsStore.loadCached(box);
      expect(WordingEditsStore.current.ar, {'signIn': 'ادخل حسابك'});
    });

    test('the document going away puts the built-in text back and drops the '
        'copy', () async {
      final db = FakeFirebaseFirestore();
      await db.doc(kWordingDocPath).set({
        'quotes': [
          {'ar': 'سطر', 'en': 'Line'},
        ],
      });
      WordingEditsStore.listen(firestore: db, box: box, retryOnResume: false);
      await pumpEventQueue();
      expect(WordingEditsStore.current.quotes, hasLength(1));
      expect(box.get(WordingEditsStore.cacheKey), isA<String>());

      await db.doc(kWordingDocPath).delete();
      await pumpEventQueue();
      expect(WordingEditsStore.current.isEmpty, isTrue);
      expect(box.get(WordingEditsStore.cacheKey), isNull);
    });

    test('an unreadable copy on the device means built-in text, not a crash',
        () async {
      await box.put(WordingEditsStore.cacheKey, '{not json');
      await WordingEditsStore.loadCached(box);
      expect(WordingEditsStore.current.isEmpty, isTrue);
    });
  });
}
