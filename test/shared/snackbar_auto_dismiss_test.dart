// Every notice leaves on its own.
//
// Flutter 3.41 added SnackBar.persist and defaulted it to `action != null`.
// A bar carrying an Undo therefore stops honouring its own `duration` and
// stays until somebody taps the action or swipes it off, and the single
// timer ScaffoldMessenger arms fires once, sees persist, and returns without
// clearing itself, so nothing ever arms a second one. Since the messenger
// lives above the Navigator, that pinned bar then follows the person onto
// every screen they open next. It shipped that way: a "شلنا العلامة"
// with تراجع, raised on the Grid, was still sitting over Room Detail
// minutes later.
//
// Two guards, because the flag is invisible at the call site:
//   1. the behaviour itself, driven through a real ScaffoldMessenger, so an
//      upgrade that changes the semantics again fails here;
//   2. a source scan, so a new SnackBar that carries an action cannot ship
//      without persist: false.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps a Scaffold and shows [bar] on it, returning the messenger.
Future<ScaffoldMessengerState> _show(WidgetTester tester, SnackBar bar) async {
  late ScaffoldMessengerState messenger;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            messenger = ScaffoldMessenger.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  messenger.showSnackBar(bar);
  await tester.pump(); // start the entrance
  await tester.pump(const Duration(milliseconds: 400)); // finish it
  return messenger;
}

void main() {
  testWidgets('a bar carrying an Undo still dismisses itself', (tester) async {
    await _show(
      tester,
      SnackBar(
        content: const Text('mark cleared'),
        duration: const Duration(seconds: 6),
        persist: false,
        action: SnackBarAction(label: 'undo', onPressed: () {}),
      ),
    );
    expect(find.text('mark cleared'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(
      find.text('mark cleared'),
      findsNothing,
      reason: 'a 6 second bar must be gone at 6 seconds',
    );
  });

  testWidgets('without persist: false the same bar never leaves',
      (tester) async {
    // Documents the trap rather than a wanted behaviour: this is exactly the
    // stuck popup, reproduced. If a future Flutter drops the persist default
    // this test flips, and the `persist: false` sprinkled through lib/ can go
    // with it.
    final messenger = await _show(
      tester,
      SnackBar(
        content: const Text('mark cleared'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(label: 'undo', onPressed: () {}),
      ),
    );

    await tester.pump(const Duration(seconds: 30));
    expect(find.text('mark cleared'), findsOneWidget);

    // Leave the tree clean: an undismissed bar holds an animation the test
    // binding would otherwise still be driving at teardown.
    messenger.removeCurrentSnackBar();
    await tester.pumpAndSettle();
  });

  test('every SnackBar with an action opts out of persist', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final match in RegExp(r'\bSnackBar\(').allMatches(source)) {
        // The constructor's own argument list, found by balancing brackets
        // from its opening paren. Cheaper and steadier than a Dart parse for
        // a check this narrow.
        final open = match.end - 1;
        var depth = 0;
        var close = -1;
        for (var i = open; i < source.length; i++) {
          if (source[i] == '(') depth++;
          if (source[i] == ')') {
            depth--;
            if (depth == 0) {
              close = i;
              break;
            }
          }
        }
        if (close < 0) continue;
        final args = source.substring(match.end, close);
        final carriesAction = RegExp(r'^\s*action:', multiLine: true)
            .hasMatch(args);
        if (!carriesAction) continue;
        if (args.contains('persist:')) continue;
        final before = source.substring(0, match.start);
        final line = '\n'.allMatches(before).length + 1;
        offenders.add('${entity.path}:$line');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'These SnackBars carry an action, so Flutter pins them open '
          'forever unless they pass persist: false. See AppSnackBar.\n'
          '  ${offenders.join('\n  ')}',
    );
  });
}
