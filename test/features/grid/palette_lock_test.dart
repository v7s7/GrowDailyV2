// Which squares the palette must treat as paid completions.
//
// Aziz, 2026-09-07: the palette's «لم يكتمل» on a blue steps square only
// recoloured it; the completion, the gold and the streak all stayed. The
// old lock listed green and mid-count yellow, on today only. The rule now
// covers blue and the grace day, and tells a canonical completion from a
// flat-painted colour by the receipt the flat path always leaves.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/palette_lock.dart';

void main() {
  bool locked({
    bool isOpenDay = true,
    bool isToday = true,
    required SquareState current,
    int doneToday = 1,
    int target = 1,
    int flatPaid = 0,
  }) =>
      paletteLockedFor(
        isOpenDay: isOpenDay,
        isToday: isToday,
        current: current,
        doneToday: doneToday,
        target: target,
        flatPaid: flatPaid,
      );

  test('a green square done today is locked', () {
    expect(locked(current: SquareState.complete), isTrue);
  });

  test('a blue square done today is locked, the steps ladder paints those', () {
    expect(locked(current: SquareState.bonus), isTrue);
  });

  test('yesterday inside its grace window is locked like today', () {
    expect(
      locked(current: SquareState.complete, isToday: false, doneToday: 0),
      isTrue,
      reason: 'the completions map is today\'s, so the count says nothing '
          'about yesterday; the colour and the missing receipt do',
    );
    expect(locked(current: SquareState.bonus, isToday: false, doneToday: 0),
        isTrue);
  });

  test('a closed day is never locked: the past is a record', () {
    for (final s in SquareState.values) {
      expect(locked(current: s, isOpenDay: false, isToday: false), isFalse,
          reason: '$s');
    }
  });

  test('a colour the flat path painted is not a completion', () {
    // A palette-painted blue on an old build left a 15 XP receipt; its
    // refund belongs to the flat path, which knows what it paid.
    expect(locked(current: SquareState.bonus, flatPaid: 15), isFalse);
    expect(locked(current: SquareState.partial, target: 4, flatPaid: 5),
        isFalse);
  });

  test('today with nothing counted is not locked, whatever the colour', () {
    expect(locked(current: SquareState.complete, doneToday: 0), isFalse);
    expect(locked(current: SquareState.bonus, doneToday: 0), isFalse);
  });

  test('mid-count yellow is locked only for a counted habit', () {
    expect(locked(current: SquareState.partial, target: 4), isTrue);
    expect(locked(current: SquareState.partial, target: 1), isFalse,
        reason: 'a single-tap habit\'s جزئي is always palette-painted');
  });

  test('red, skipped and empty squares never lock', () {
    for (final s in [
      SquareState.failed,
      SquareState.skipped,
      SquareState.none,
    ]) {
      expect(locked(current: s), isFalse, reason: '$s');
    }
  });
}
