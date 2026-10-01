import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/matrix/models/matrix_task.dart';
import 'package:grow_daily_v2/features/matrix/notifiers/matrix_notifier.dart';

// Aziz 2026-09-30: the four boxes are «الآن / خطط لها / عطها غيرك / خلها».
// A saved title equal to a box's old Arabic name was frozen by the edit
// sheet (it saved the name it opened with), so it gives way to the new one;
// a name somebody really chose stays.
void main() {
  test('the built-in Arabic names are the easy ones', () {
    expect(MatrixQuadrant.doFirst.localLabel(true), 'الآن');
    expect(MatrixQuadrant.schedule.localLabel(true), 'خطط لها');
    expect(MatrixQuadrant.delegate.localLabel(true), 'عطها غيرك');
    expect(MatrixQuadrant.eliminate.localLabel(true), 'خلها');
  });

  test('a saved old default reads as the new name, a chosen name stays', () {
    const state = MatrixState(
      quadrantTitles: {
        'doFirst': 'أولاً',
        'schedule': 'احذف',
        'eliminate': 'مو ضروري',
      },
    );
    expect(state.titleFor(MatrixQuadrant.doFirst, true), 'الآن');
    // «احذف» was box 4's old name, so on box 2 it is a real choice.
    expect(state.titleFor(MatrixQuadrant.schedule, true), 'احذف');
    expect(state.titleFor(MatrixQuadrant.delegate, true), 'عطها غيرك');
    expect(state.titleFor(MatrixQuadrant.eliminate, true), 'مو ضروري');
  });
}
