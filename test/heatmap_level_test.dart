import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/grid/screens/monthly_heatmap_screen.dart';

/// The heatmap colors a day by what fraction of the user's habit list it
/// completed, not by a raw count — otherwise someone tracking 2 habits
/// could never reach full green, while someone tracking 10 could look
/// "more done" on a half-finished day than a 2-habit user having a perfect
/// one.
void main() {
  test('a perfect day is always the deepest green, at any habit count', () {
    expect(heatLevel(2, 2), 4);
    expect(heatLevel(10, 10), 4);
  });

  test('80%+ but not perfect is one shade lighter', () {
    expect(heatLevel(4, 5), 3); // 80%
    expect(heatLevel(8, 10), 3); // 80%
  });

  test('50-79% is lighter still', () {
    expect(heatLevel(1, 2), 2); // 50%
    expect(heatLevel(3, 5), 2); // 60%
  });

  test('anything below half but above zero is the lightest green', () {
    expect(heatLevel(1, 5), 1); // 20%
  });

  test('no green squares that day is unpainted regardless of habit count', () {
    expect(heatLevel(0, 5), 0);
    expect(heatLevel(0, 0), 0);
  });

  test('a count that exceeds the current habit list still caps at full green', () {
    // e.g. a habit was archived after being completed on a past day.
    expect(heatLevel(6, 3), 4);
  });

  test('falls back to an absolute scale when there are no habits at all', () {
    expect(heatLevel(1, 0), 1);
    expect(heatLevel(3, 0), 2);
    expect(heatLevel(5, 0), 3);
    expect(heatLevel(8, 0), 4);
  });
}
