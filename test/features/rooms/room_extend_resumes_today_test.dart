// Extending a room can never pause it into the future.
//
// Aziz, 2026-09-07: room PBYAS5 read موقوف to both members for the whole of
// September and no day counted. Nobody had paused anything; rooms have no
// pause button. The leader had extended the finished room on 4 September,
// picked 30 days, and then, on the calendar the old build showed next
// ("متى نكمل؟"), tapped the 30th. The gap rule faithfully recorded 3 to 29
// September as dead time. The calendar is gone: an extension resumes today,
// full stop, and the only pause that can exist is the past gap between a
// room's old finish line and the day it was extended.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';

void main() {
  final seventh = DateTime(2026, 9, 7);

  test('a finished room revived later pauses exactly the dead days', () {
    // Finished 2 September, extended on the 7th: 3rd through 6th were dead.
    expect(
      pausedSpansAfterExtend(const [], DateTime(2026, 9, 2), seventh),
      [
        {'from': '2026-09-03', 'to': '2026-09-06'}
      ],
    );
  });

  test('never a day in the future, whatever the room carried before', () {
    // PBYAS5 as the old build left it: paused through the 29th, ending on
    // 29 October. Extending again on the 7th cuts the pause to yesterday and
    // adds nothing, because the room has not ended.
    final spans = pausedSpansAfterExtend(
      const [(from: '2026-09-03', to: '2026-09-29')],
      DateTime(2026, 10, 29),
      seventh,
    );
    expect(spans, [
      {'from': '2026-09-03', 'to': '2026-09-06'}
    ]);
    for (final sp in spans) {
      expect(sp['to']!.compareTo('2026-09-07'), lessThan(0),
          reason: 'no span may reach today or beyond');
    }
  });

  test('a room that ended yesterday, or is still running, adds no pause', () {
    expect(pausedSpansAfterExtend(const [], DateTime(2026, 9, 6), seventh),
        isEmpty, reason: 'ended yesterday: nothing was dead');
    expect(pausedSpansAfterExtend(const [], DateTime(2026, 9, 7), seventh),
        isEmpty, reason: 'ends today');
    expect(pausedSpansAfterExtend(const [], DateTime(2026, 9, 20), seventh),
        isEmpty, reason: 'still running');
  });

  test('an open-ended room has no finish line and so no gap', () {
    expect(pausedSpansAfterExtend(const [], null, seventh), isEmpty);
  });

  test('past pauses are kept exactly, a wholly future one is dropped', () {
    final spans = pausedSpansAfterExtend(
      const [
        (from: '2026-08-01', to: '2026-08-05'),
        (from: '2026-09-10', to: '2026-09-20'),
        (from: '2026-09-07', to: '2026-09-08'),
      ],
      DateTime(2026, 9, 2),
      seventh,
    );
    expect(spans, [
      {'from': '2026-08-01', 'to': '2026-08-05'},
      {'from': '2026-09-03', 'to': '2026-09-06'},
    ]);
  });

  test('a span that started yesterday and ran on is cut to that one day', () {
    expect(
      pausedSpansAfterExtend(
        const [(from: '2026-09-06', to: '2026-09-30')],
        DateTime(2026, 10, 1),
        seventh,
      ),
      [
        {'from': '2026-09-06', 'to': '2026-09-06'}
      ],
    );
  });
}
