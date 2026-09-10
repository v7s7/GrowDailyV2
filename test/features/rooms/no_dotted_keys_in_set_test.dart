// A dotted field path inside set(merge: true) is silently discarded.
//
// Firestore resolves "a.b" as a path to a nested field ONLY in update().
// Passed to set(), with or without merge, the key is taken literally and the
// document gains a top-level field actually named "a.b" - which no reader
// ever looks at, and which no error reports.
//
// This shipped on 2026-09-09: every write to slotDeclinedFrom,
// slotPriorHabitIds and slotDeclinedSpans used a dotted key inside a
// set(merge: true), so the whole decline timeline persisted nothing and
// every decline silently behaved as a legacy one (declined on every day).
// Nothing failed, nothing logged; the feature simply did not exist.
//
// The correct idiom under merge is a NESTED MAP - {'slotDeclinedFrom': {'2':
// value}} - which merges key by key, leaves the other slots alone, and still
// honours FieldValue.delete() and arrayUnion on the one key it names.
//
// A source guard rather than a unit test because the failure is invisible at
// runtime: there is no exception to catch and no value to assert. The same
// reason no_em_dash_in_copy_test.dart reads source instead of behaviour.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no set() call in the rooms feature writes a dotted field key', () {
    final files = Directory('lib/features/rooms')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(files, isNotEmpty, reason: 'no source found - path is wrong');

    // A quoted map key containing a dot, where the dot is followed by an
    // interpolation or an identifier: 'slotDeclinedFrom.$i', 'a.b'. Excludes
    // strings with spaces or a file extension, which are prose or asset
    // names rather than field paths.
    final dotted = RegExp(r"'[A-Za-z_][A-Za-z0-9_]*\.(\$|[A-Za-z_])[^']*'\s*:");
    final offenders = <String>[];
    for (final f in files) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        final m = dotted.firstMatch(line);
        if (m == null) continue;
        // Only a problem inside a set(); update() resolves paths correctly.
        // Look back a little for the call this map belongs to.
        final from = i - 25 < 0 ? 0 : i - 25;
        final context = lines.sublist(from, i).join('\n');
        final lastSet = context.lastIndexOf('.set(');
        final lastUpdate = context.lastIndexOf('.update(');
        if (lastSet > lastUpdate) {
          offenders.add('${f.path}:${i + 1}  ${line.trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'dotted field keys inside set() are silently discarded by '
          'Firestore. Write a nested map instead:\n${offenders.join('\n')}',
    );
  });
}
