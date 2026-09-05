// The support email the app actually opens.
//
// This is the only way to reach a human from inside the app, and a malformed
// mailto does not fail loudly: the mail app opens blank, or nothing happens
// at all, and nobody finds out until somebody could not report a problem.
// It also cannot be checked on a simulator, which has no mail account, so it
// is checked here instead.
//
// What it carries is the other half. A bare mailto opened an empty message
// and every conversation started with the same two questions back: which
// phone, and which version. The person writing in does not know, and asking
// costs a round trip before anyone has read the problem.
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/features/profile/screens/help_support_screen.dart';

void main() {
  const ar = S(Locale('ar'));
  const en = S(Locale('en'));

  Uri parsed(S s) => Uri.parse(supportMailto(s));

  group('the address', () {
    test('is a real mailto pointing at the support account', () {
      final uri = parsed(en);
      expect(uri.scheme, 'mailto');
      expect(uri.path, kSupportEmail);
      expect(kSupportEmail, isNotNull,
          reason: 'a null address ships an app with no way to reach anyone');
    });

    test('matches what the published privacy policy tells people to use', () {
      // public/privacy.html names this address. The two drifting apart means
      // someone writes to a mailbox nobody reads.
      expect(kSupportEmail, 'alkubaisi1818@gmail.com');
    });
  });

  group('what the message opens with', () {
    test('a subject, so a mailbox can sort them', () {
      for (final s in [ar, en]) {
        expect(parsed(s).queryParameters['subject'], isNotEmpty);
      }
      expect(parsed(en).queryParameters['subject'], contains('Grow Daily'));
      expect(parsed(ar).queryParameters['subject'], contains('Grow Daily'));
    });

    test('a prompt in the writer\'s own language, never a blank body', () {
      // An empty message is the moment people close it again.
      expect(parsed(ar).queryParameters['body'], contains('اكتب مشكلتك'));
      expect(parsed(en).queryParameters['body'], contains('Describe the'));
    });

    test('the device, under a divider and below the writing space', () {
      final body = parsed(en).queryParameters['body']!;
      expect(body, contains('Platform:'));
      expect(body, contains('Language: en'));
      expect(body, contains('\n--\n'),
          reason: 'the technical part has to be separated from their words');
      expect(body.indexOf('Describe the'), lessThan(body.indexOf('--')),
          reason: 'what they type must land above the device block');
    });

    test('the language line follows the app, not the device', () {
      expect(parsed(ar).queryParameters['body'], contains('Language: ar'));
      expect(parsed(en).queryParameters['body'], contains('Language: en'));
    });
  });

  group('the app version', () {
    test('is written into the mail when package_info has answered', () {
      final body =
          Uri.parse(supportMailto(en, appVersion: '1.0.0 (65)')).queryParameters['body']!;
      expect(body, contains('Grow Daily 1.0.0 (65)'));
    });

    test('is left out entirely rather than filled with a guess', () {
      // Null only in the frame or two before the platform channel answers.
      // "unknown" would be no more useful than silence and worse to read.
      final body = Uri.parse(supportMailto(en)).queryParameters['body']!;
      expect(body, contains('App: Grow Daily\n'));
      expect(body.toLowerCase(), isNot(contains('unknown')));
      expect(body.toLowerCase(), isNot(contains('null')));
    });
  });

  group('the questions are grouped', () {
    test('every entry belongs to a group', () {
      // The renderer walks FaqGroup.values and shows only what it finds, so
      // an untagged entry would vanish from the screen rather than fail.
      expect(kFaqEntries, isNotEmpty);
      for (final group in FaqGroup.values) {
        expect(kFaqEntries.where((e) => e.group == group), isNotEmpty,
            reason: 'FaqGroup.${group.name} renders a heading over nothing');
      }
    });

    test('no group is so long it defeats the point of grouping', () {
      // Sixteen in one list is what this replaced. A group creeping back up
      // to that size means it wants splitting again.
      for (final group in FaqGroup.values) {
        expect(kFaqEntries.where((e) => e.group == group).length,
            lessThanOrEqualTo(6),
            reason: 'FaqGroup.${group.name} is getting long');
      }
    });

    test('every group has a heading in both languages', () {
      for (final group in FaqGroup.values) {
        expect(ar.faqGroupTitle(group.name), isNotEmpty);
        expect(en.faqGroupTitle(group.name), isNotEmpty);
        expect(ar.faqGroupTitle(group.name),
            isNot(en.faqGroupTitle(group.name)));
      }
    });
  });

  test('it survives a round trip through Uri parsing', () {
    // The body has newlines and the subject has spaces; both have to come
    // back out intact or the mail app receives something it cannot open.
    for (final s in [ar, en]) {
      final uri = parsed(s);
      expect(uri.queryParameters.keys, containsAll(['subject', 'body']));
      expect(uri.toString(), supportMailto(s));
    }
  });
}
