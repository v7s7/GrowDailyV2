// No em dash in anything a user reads.
//
// A standing instruction from the owner, and one that a linter cannot express
// and code review reliably misses: a dash is easy to type, reads fine to the
// person writing it, and there were 129 of them across 8 files by the time
// anybody counted. Rewriting them all is only worth doing once, so this stops
// the next one arriving.
//
// ── What counts as copy ──────────────────────────────────────────────────
// Only string LITERALS, and only outside comments. The codebase's own prose
// uses em dashes heavily in doc comments and that is fine: nobody reads a doc
// comment inside the app. Debug log lines are exempt for the same reason, and
// they are recognised by the '[Tag] ...' prefix the app already uses for them.
//
// ── If this fails ────────────────────────────────────────────────────────
// Do not reach for a global find-and-replace. Judge the dash on its grammar:
// a comma for an aside, a full stop for two statements, a colon for something
// being introduced. In Arabic keep the phrasing impersonal, since a
// second-person verb there is gendered.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// String literals on a line, single or double quoted, escapes respected.
///
/// Built by concatenation rather than written as one raw literal: the pattern
/// has to contain both quote characters, and every way of spelling that
/// inline fights Dart's own quoting.
final _singleQuoted = r"'(?:[^'\\]|\\.)*'";
final _doubleQuoted = '"(?:[^"' r'\\' ']|' r'\\' '.)*"';
final _literal = RegExp('$_singleQuoted|$_doubleQuoted');

/// A debug line, e.g. '[NotificationService] Daily reminder set'. Printed to a
/// console, never rendered, so its punctuation is nobody's concern.
final _debugPrefix = RegExp('^[\'"]' r'\[[A-Za-z]');
bool _isDebugLine(String literal) => _debugPrefix.hasMatch(literal);

void main() {
  test('no em dash reaches user-facing copy', () {
    final offenders = <String>[];
    final dir = Directory('lib');
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!line.contains('—')) continue;
        final trimmed = line.trimLeft();
        // Comment lines are exempt: the codebase explains itself at length and
        // none of that prose is ever shown.
        if (trimmed.startsWith('//')) continue;
        for (final m in _literal.allMatches(line)) {
          final lit = m.group(0)!;
          if (!lit.contains('—')) continue;
          if (_isDebugLine(lit)) continue;
          offenders.add('${entity.path}:${i + 1}\n      $lit');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'These strings are shown to users and contain an em dash. '
          'Replace each with the punctuation its own grammar calls for: a '
          'comma for an aside, a full stop for two sentences, a colon for '
          'something introduced.\n\n${offenders.join('\n')}',
    );
  });

  test('the check can actually see an em dash', () {
    // Guards the guard. A regex that quietly stopped matching would make the
    // test above pass forever while the rule rotted.
    const sample = "  String get x => isAr ? 'مرحبا — أهلا' : 'Hello — hi';";
    final found = _literal
        .allMatches(sample)
        .map((m) => m.group(0)!)
        .where((l) => l.contains('—'))
        .toList();
    expect(found, hasLength(2),
        reason: 'both the Arabic and the English literal must be caught');
  });

  test('debug lines are exempt, and only debug lines', () {
    expect(_isDebugLine("'[NotificationService] set — now'"), isTrue);
    expect(_isDebugLine('"[Rooms] synced — ok"'), isTrue);
    expect(_isDebugLine("'Perfect day — every square filled'"), isFalse,
        reason: 'real copy must never be waved through as a log line');
    expect(_isDebugLine("'[انتهت] — done'"), isFalse,
        reason: 'a bracket is not enough; log tags are ASCII identifiers');
  });
}
