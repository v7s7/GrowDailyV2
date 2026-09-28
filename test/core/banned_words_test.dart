// Words Aziz has banned from the app's text, as whole words. «كذا» (Aziz,
// 2026-09-28: "this is a banned word, ban it"): «هكذا» is another word and
// stays allowed. «تطفي» (Aziz, 2026-09-28: "ban this word"), said of the
// quiet-hours question, which now asks «تبي توقف ساعات الهدوء؟». Add a word
// here and every string file is checked for it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _banned = ['كذا', 'تطفي'];

/// The files that hold the app's user-facing text.
const _copyFiles = [
  'lib/core/l10n/app_strings.dart',
  'lib/core/l10n/reminder_copy.dart',
];

void main() {
  for (final word in _banned) {
    test('«$word» appears in no string the app shows', () {
      // The word on its own: no Arabic letter right before or after it.
      final alone = RegExp('(?<![\\u0621-\\u064A])$word(?![\\u0621-\\u064A])');
      for (final path in _copyFiles) {
        final lines = File(path).readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          expect(alone.hasMatch(lines[i]), isFalse,
              reason: '$path:${i + 1}: ${lines[i].trim()}');
        }
      }
    });
  }

  test('the check sees the word alone and lets «هكذا» through', () {
    final alone = RegExp('(?<![\\u0621-\\u064A])كذا(?![\\u0621-\\u064A])');
    expect(alone.hasMatch('كذا الشغل'), isTrue);
    expect(alone.hasMatch('هكذا يراك'), isFalse);
  });
}
