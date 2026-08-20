// The sparse-map delta written by uncompleteHabit, and the shape mistake that
// destroyed data.
//
// SetOptions(merge: true) merges a nested map key by key: keys PRESENT in the
// written data are updated, every other key is left alone. So "copy the map,
// remove the key, write the map" deletes nothing on the server. Every sparse
// per-habit map in uncompleteHabit drops its key at zero, so all of them must
// write an explicit FieldValue.delete() for that one key.
//
// The shape matters as much as the sentinel. An earlier version of the helper
// returned the BARE value and left wrapping to five call sites, which were all
// written unwrapped:
//
//     'habitCompletions': FieldValue.delete()      // deletes the WHOLE field
//     'habitCompletions': {id: FieldValue.delete()} // deletes one key
//
// The first wiped an entire day of completions and an account's whole
// habitTotalCompletions map, and the next load threw on `as Map` and set
// loadFailed, which blocks every reward write. The helper now returns the
// wrapped map so a call site cannot express the broken form.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';

void main() {
  group('shape', () {
    test('it returns a map keyed by the habit, never a bare value', () {
      // The property that makes the destructive form unrepresentable.
      final delta = habitCompletionDelta('h1', {'h1': 3});
      expect(delta, isA<Map<String, Object>>());
      expect(delta.keys, ['h1']);
    });

    test('it names only the one habit, never any other', () {
      // Anything else in the map must be left untouched by the merge, which
      // means it must not appear in the payload at all.
      final delta = habitCompletionDelta('h1', {'h1': 3, 'h2': 9});
      expect(delta.keys, ['h1']);
      expect(delta.containsKey('h2'), isFalse);
    });
  });

  group('value', () {
    test('a surviving count is written as the number', () {
      expect(habitCompletionDelta('h1', {'h1': 2})['h1'], 2);
    });

    test('a dropped key becomes an explicit delete, not an absence', () {
      // The whole point. An absent key in a merge write is a no-op, so the
      // sentinel is the only thing that actually removes anything.
      final delta = habitCompletionDelta('h1', <String, int>{});
      expect(delta['h1'], isA<FieldValue>());
    });

    test('a dropped key deletes even when other habits remain', () {
      // The case that hid the original bug: undoing the day's ONLY completion
      // leaves an empty map, which is itself the leaf and so writes whole and
      // clears. It only misbehaves while another habit is still completed,
      // which is why every obvious manual test passed.
      final delta = habitCompletionDelta('h1', {'h2': 1});
      expect(delta['h1'], isA<FieldValue>());
      expect(delta.containsKey('h2'), isFalse);
    });

    test('a null map deletes rather than throwing', () {
      // The streak maps are only built inside the snapshot branch.
      final delta = habitCompletionDelta('h1', null);
      expect(delta['h1'], isA<FieldValue>());
    });

    test('it carries non-numeric values too', () {
      // habitLastCompletedDate holds strings.
      expect(
        habitCompletionDelta('h1', {'h1': '2026-08-20'})['h1'],
        '2026-08-20',
      );
    });
  });
}
