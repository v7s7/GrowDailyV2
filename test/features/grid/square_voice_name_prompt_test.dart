// A new take on a habit's day asks for its name at once, as a task's does
// (TaskDetailSheet and AddTaskSheet open the rename sheet the moment a take
// is kept). Driven with a fake microphone, as in
// voice_monthly_allowance_test.dart.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/features/grid/notifiers/square_voice_notes.dart';
import 'package:grow_daily_v2/features/matrix/widgets/voice_note_player.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';
import 'package:grow_daily_v2/features/premium/notifiers/voice_note_allowance.dart';

import '../../helpers/landing_harness.dart';

/// A microphone that grants permission and hands back a take.
class _FakeMic extends RecordPlatform {
  @override
  Future<void> create(String recorderId) async {}

  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async =>
      true;

  @override
  Future<void> start(
    String recorderId,
    RecordConfig config, {
    required String path,
  }) async {}

  @override
  Future<String?> stop(String recorderId) async => '/nowhere/take.m4a';

  @override
  Future<void> cancel(String recorderId) async {}

  @override
  Future<void> dispose(String recorderId) async {}

  @override
  Stream<RecordState> onStateChanged(String recorderId) =>
      const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// This month's count, in memory, well under the allowance.
class _MemoryUsage extends VoiceNoteUsageStore {
  int used = 0;

  @override
  Future<int> load(String? uid, String month) async => used;

  @override
  Future<void> add(String? uid, String month) async => used++;
}

void main() {
  const s = S(Locale('en'));
  final today = DateTime.now().effectiveDay;
  final key = squareVoiceKey('inbox_zero', today);
  late Directory docs;

  setUpAll(() async {
    RecordPlatform.instance = _FakeMic();
    docs = await Directory.systemTemp.createTemp('voice_name_prompt_docs_');
    final channels =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    channels.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => docs.path,
    );
    channels.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (call) async => null,
    );
    channels.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global/events'),
      (call) async => null,
    );
    channels.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) => Completer<Object?>().future,
    );
  });

  late LandingHarness h;
  setUp(() async {
    h = LandingHarness();
    await h.prepare(
      activeCatalogIds: const ['inbox_zero'],
      extraOverrides: [
        premiumAccessProvider.overrideWith((ref) => true),
        voiceNoteUsageStoreProvider.overrideWithValue(_MemoryUsage()),
      ],
    );
    (await LocalStoreService.dailyBox()).clear();
    await (await LocalStoreService.settingsBox()).delete(kGuestSquareVoiceKey);
  });
  tearDown(() => h.dispose());

  Finder recordRow() => find.byType(VoiceNoteRecordRow);
  Finder nameField() => find.ancestor(
        of: find.text(s.voiceNoteRenameHint),
        matching: find.byType(TextField),
      );

  /// The guest's stored names for today's square.
  Future<List<Object?>> storedNames() async {
    final all = (await LocalStoreService.settingsBox()).get(kGuestSquareVoiceKey);
    final list = all is Map ? all[key] : null;
    return [
      if (list is List)
        for (final n in list) (n as Map)['name'],
    ];
  }

  /// Opens today's square, then records one take and stops it, on the real
  /// clock: the take has to last a second to be kept, and the recorder's
  /// folder and the guest's list are real disk I/O.
  Future<void> recordOneTake(WidgetTester tester) async {
    await h.pumpApp(tester);
    final date = DateFormat('EEEE d MMMM', 'en').format(today);
    final square =
        find.bySemanticsLabel(RegExp('^Inbox Zero, ${RegExp.escape(date)}'));
    await tester.ensureVisible(square);
    await h.settle(tester);
    await tester.longPress(square);
    await h.settle(tester);
    await tester.ensureVisible(recordRow());
    await h.settle(tester);
    expect(nameField(), findsNothing, reason: 'no prompt before a take');

    await tester.runAsync(() async {
      await tester.tap(recordRow());
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    });
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(recordRow());
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await h.settle(tester);
  }

  testWidgets('a kept take opens the name sheet, and Save names it',
      (tester) async {
    await recordOneTake(tester);

    expect(find.text(s.voiceNoteRenameTitle), findsOneWidget,
        reason: 'the name sheet opened by itself, as on a task');
    expect(nameField(), findsOneWidget);

    await tester.enterText(nameField(), 'Step 1');
    await tester.pump();
    // The rename rewrites the guest's list in Hive: real clock again. The
    // name sheet's Save, not the square editor's own beneath it.
    final save = find.ancestor(of: nameField(), matching: find.byType(Column));
    await tester.runAsync(() async {
      await tester.tap(find.descendant(
        of: save.first,
        matching: find.widgetWithText(FilledButton, s.voiceNoteRenameSave),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await h.settle(tester);

    expect(find.text(s.voiceNoteRenameTitle), findsNothing);
    expect(
      find.descendant(of: find.byType(VoiceNoteRow), matching: find.text('Step 1')),
      findsOneWidget,
    );
    expect(await tester.runAsync(storedNames), ['Step 1'],
        reason: 'one recording, stored under its new name');
    expect(h.container.read(squareVoiceIndexProvider)[key], 1);
  });

  testWidgets('closing the sheet unsaved keeps the take as «Recording 1»',
      (tester) async {
    await recordOneTake(tester);
    expect(find.text(s.voiceNoteRenameTitle), findsOneWidget);

    // Down on the barrier, above the sheet.
    await tester.tapAt(const Offset(20, 20));
    await h.settle(tester);

    expect(find.text(s.voiceNoteRenameTitle), findsNothing);
    expect(
      find.descendant(
        of: find.byType(VoiceNoteRow),
        matching: find.text(s.voiceNoteDefaultName(1)),
      ),
      findsOneWidget,
    );
    expect(await tester.runAsync(storedNames), [''],
        reason: 'kept, unnamed');
  });
}
