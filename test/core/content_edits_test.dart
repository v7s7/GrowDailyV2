// The FAQ and the paywall's benefit list, edited on the admin tool and laid
// over the app's own lists (content_edits.dart).
//
// What has to hold:
//   - the app resolves an edited list exactly as the admin tool's preview
//     does: both run the same cases, from
//     scripts/admin_lookup/test/fixtures/content_cases.json, which
//     scripts/admin_lookup/test/content.test.js runs against the admin
//     tool's content_rules.js;
//   - a malformed document costs the entry that is malformed, never the
//     list, and nothing unusable reaches a screen;
//   - the device's copy reads back as what was saved.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/wording_edits.dart';

void main() {
  final cases = jsonDecode(
    File('scripts/admin_lookup/test/fixtures/content_cases.json')
        .readAsStringSync(),
  ) as Map<String, dynamic>;

  group('the cases the admin tool runs too: the FAQ', () {
    final faq = cases['faqBuiltIn'] as Map<String, dynamic>;
    final groups = [
      for (final g in (faq['groups'] as List).cast<Map<String, dynamic>>())
        FaqBuiltInGroup(
          id: g['id'] as String,
          ar: g['ar'] as String,
          en: g['en'] as String,
        ),
    ];
    final items = [
      for (final i in (faq['items'] as List).cast<Map<String, dynamic>>())
        FaqBuiltInItem(
          group: i['group'] as String,
          item: FaqItem(
            id: i['id'] as String,
            questionAr: i['qAr'] as String,
            questionEn: i['qEn'] as String,
            answerAr: i['aAr'] as String,
            answerEn: i['aEn'] as String,
          ),
        ),
    ];

    for (final c in (cases['faqCases'] as List).cast<Map<String, dynamic>>()) {
      test(c['name'], () {
        final sections = resolveFaq(
          groups: groups,
          items: items,
          edits: FaqEdits.fromData(c['edits']),
        );
        expect(
          [
            for (final s in sections)
              [s.id, [for (final i in s.items) i.id]],
          ],
          c['layout'],
        );
        (c['titles'] as Map<String, dynamic>? ?? {}).forEach((id, title) {
          final s = sections.firstWhere((s) => s.id == id);
          expect({'ar': s.titleAr, 'en': s.titleEn}, title, reason: id);
        });
        (c['texts'] as Map<String, dynamic>? ?? {}).forEach((id, words) {
          final i = sections.expand((s) => s.items).firstWhere((i) => i.id == id);
          expect(
            {
              'qAr': i.questionAr,
              'qEn': i.questionEn,
              'aAr': i.answerAr,
              'aEn': i.answerEn,
            },
            words,
            reason: id,
          );
        });
        // Nothing blank ever reaches the screen.
        for (final s in sections) {
          expect(s.items, isNotEmpty);
          expect(s.titleAr.trim(), isNotEmpty);
          expect(s.titleEn.trim(), isNotEmpty);
          for (final i in s.items) {
            for (final t in [i.questionAr, i.questionEn, i.answerAr, i.answerEn]) {
              expect(t.trim(), isNotEmpty);
            }
          }
        }
      });
    }
  });

  group('the cases the admin tool runs too: the benefit list', () {
    final benefits = cases['benefitBuiltIn'] as Map<String, dynamic>;
    final builtIn = [
      for (final b
          in (benefits['items'] as List).cast<Map<String, dynamic>>())
        BenefitBuiltIn(id: b['id'] as String, icon: b['icon'] as String),
    ];
    final known = {for (final i in benefits['icons'] as List) i as String};

    for (final c
        in (cases['benefitCases'] as List).cast<Map<String, dynamic>>()) {
      test(c['name'], () {
        final slots = resolveBenefits(
          builtIn: builtIn,
          knownIcons: known,
          fallbackIcon: benefits['fallbackIcon'] as String,
          edits: BenefitEdits.fromData(c['edits']),
        );
        expect(
          [
            for (final s in slots)
              if (s.added == null)
                [s.id, s.icon]
              else
                [s.id, s.icon, s.added!.toJson()],
          ],
          c['list'],
        );
      });
    }
  });

  group('reading the document', () {
    test('anything that is not a usable map is no edits at all', () {
      for (final junk in [
        null,
        'text',
        7,
        <Object?>[],
        <String, Object?>{},
        {'order': 'x', 'hidden': 3, 'text': [], 'groups': 'no'},
      ]) {
        expect(FaqEdits.fromData(junk), isNull, reason: '$junk');
        expect(BenefitEdits.fromData(junk), isNull, reason: '$junk');
      }
    });

    test('a bad entry costs that entry and nothing else', () {
      final faq = FaqEdits.fromData({
        'order': [
          {'group': 'basics', 'items': ['a', 7, 'a', ' b ']},
          'junk',
          {'items': ['c']},
          {'group': 'basics', 'items': ['d']},
        ],
        'hidden': ['c', '', 'c'],
        'text': {
          'a': {'qAr': ' كيف؟ ', 'other': 'x', 'aEn': '   '},
          'b': 'not a map',
        },
        'groups': {
          'basics': {'en': 'The basics'},
          'x': {'ar': ''},
        },
      })!;
      expect(faq.order!.map((g) => [g.group, g.items]).toList(), [
        ['basics', ['a', 'b']],
      ]);
      expect(faq.hidden, {'c'});
      expect(faq.text.keys, ['a']);
      expect(faq.text['a']!.questionAr, 'كيف؟');
      expect(faq.text['a']!.answerEn, isNull);
      expect(faq.groups.keys, ['basics']);

      final benefits = BenefitEdits.fromData({
        'order': ['habits', 'habits', 3],
        'icons': {'habits': 'star', 'voice': ''},
        'added': {
          'b-good': {
            'icon': 'mic',
            'titleAr': 'ميزة',
            'titleEn': 'A thing',
            'descAr': 'وصف.',
            'descEn': 'What it does.',
          },
          'b-half': {'icon': 'mic', 'titleAr': 'x', 'titleEn': 'x'},
        },
      })!;
      expect(benefits.order, ['habits']);
      expect(benefits.icons, {'habits': 'star'});
      expect(benefits.added.keys, ['b-good']);
    });

    test('the document carries both lists beside the strings, and this '
        'device\'s copy reads back as what was saved', () {
      final edits = WordingEdits.fromData(const {
        'strings': {
          'ar': {'premiumHeadline': 'عنوان'},
          'en': <String, Object?>{},
        },
        'faq': {
          'order': [
            {'group': 'g-extra01', 'items': ['q-new00001', 'mark-done']},
          ],
          'hidden': ['xp-gold'],
          'text': {
            'q-new00001': {'qAr': 'س؟', 'qEn': 'Q?', 'aAr': 'ج.', 'aEn': 'A.'},
          },
          'groups': {
            'g-extra01': {'ar': 'أكثر', 'en': 'More'},
          },
        },
        'benefits': {
          'order': ['voice', 'habits'],
          'hidden': ['future'],
          'icons': {'voice': 'headphones'},
        },
        'version': 9,
      });
      expect(edits.isEmpty, isFalse);
      expect(edits.faq, isNotNull);
      expect(edits.benefits, isNotNull);
      final again = WordingEdits.fromData(jsonDecode(jsonEncode(edits.toJson())));
      expect(jsonEncode(again.toJson()), jsonEncode(edits.toJson()));
      expect(again.faq!.hidden, {'xp-gold'});
      expect(again.benefits!.icons, {'voice': 'headphones'});
    });

    test('what counts as empty matches the admin tool, next-line characters '
        'included', () {
      final nel = String.fromCharCode(0x85);
      expect(
        FaqEdits.fromData({
          'hidden': [nel],
          'text': {
            'a': {'qEn': ' $nel'},
          },
        }),
        isNull,
      );
      expect(
        FaqEdits.fromData({
          'hidden': ['${nel}c$nel'],
        })!.hidden,
        {'c'},
      );
    });

    test('a document holding only a list edit is still an edit', () {
      expect(
        WordingEdits.fromData(const {
          'faq': {
            'hidden': ['x'],
          },
        }).isEmpty,
        isFalse,
      );
      expect(
        WordingEdits.fromData(const {
          'benefits': {
            'hidden': ['x'],
          },
        }).isEmpty,
        isFalse,
      );
    });
  });
}
