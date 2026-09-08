// Guards GameTextStyles.selectionWidthStyle: Flutter 3.41's new
// BoxWidthStyle.max default made a double-tapped Arabic word paint as the
// whole line whenever the text wrapped (the engine adds a phantom box from
// the word to the paragraph edge on RTL lines). See the constant's doc.
import 'dart:io';
import 'dart:ui' show BoxWidthStyle;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';

const _text = 'اشعارات اليومية يخليك تحس كانك مو مسوي شي ، اعدل الاسلوب';

Future<List<TextBox>> _boxesForWord(WidgetTester tester, {BoxWidthStyle? widthStyle}) async {
  final ctrl = TextEditingController(text: _text);
  await tester.pumpWidget(MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: 340,
            child: TextField(
              controller: ctrl,
              selectionWidthStyle: widthStyle,
              style: const TextStyle(fontSize: 17, height: 1.4),
              maxLines: 3,
              minLines: 1,
            ),
          ),
        ),
      ),
    ),
    ),
  );
  await tester.pumpAndSettle();
  final editable = tester.renderObject<RenderEditable>(
    find.descendant(
      of: find.byType(EditableText),
      matching: find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Editable'),
    ),
  );
  final idx = _text.indexOf('تحس');
  final where = editable.localToGlobal(
    editable.getLocalRectForCaret(TextPosition(offset: idx + 1)).center,
  );
  await tester.tapAt(where);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tapAt(where);
  await tester.pumpAndSettle();
  expect(ctrl.selection.textInside(ctrl.text), 'تحس', reason: 'double tap selects the word');
  return editable.getBoxesForSelection(ctrl.selection);
}

void main() {
  testWidgets('the Flutter default paints a wrapped Arabic word as the whole line', (tester) async {
    final boxes = await _boxesForWord(tester);
    // If this starts failing, the engine fixed BoxWidthStyle.max for RTL and
    // the pinned style can be dropped.
    expect(boxes.length, 2, reason: 'phantom box to the paragraph edge');
    expect(boxes.map((b) => b.left), contains(0.0));
  });

  testWidgets('the pinned style paints only the word', (tester) async {
    final boxes = await _boxesForWord(tester, widthStyle: GameTextStyles.selectionWidthStyle);
    expect(boxes.length, 1);
    expect(boxes.single.left, greaterThan(0.0));
    expect(boxes.single.right - boxes.single.left, lessThan(100));
  });

  test('every TextField in lib pins selectionWidthStyle', () {
    final missing = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!RegExp(r'\bTextField\($').hasMatch(lines[i])) continue;
        final next = i + 1 < lines.length ? lines[i + 1] : '';
        if (!next.contains('selectionWidthStyle: GameTextStyles.selectionWidthStyle')) {
          missing.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(missing, isEmpty, reason: 'add selectionWidthStyle: GameTextStyles.selectionWidthStyle');
  });
}
