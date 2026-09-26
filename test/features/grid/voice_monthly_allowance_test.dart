// The monthly voice-note allowance on the square editor's mic
// (voice_note_allowance.dart, 100 a month). Driven with a fake microphone,
// as in voice_stop_after_lapse_test.dart; the two task sheets call the same
// two functions (voiceNoteMonthAllows, voiceNoteAllowanceHint).
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
import 'package:grow_daily_v2/core/utils/western_digits.dart';
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

/// This month's count, in memory.
class _MemoryUsage extends VoiceNoteUsageStore {
  _MemoryUsage(this.used);
  int used;

  @override
  Future<int> load(String? uid, String month) async => used;

  @override
  Future<void> add(String? uid, String month) async => used++;
}

void main() {
  const s = S(Locale('en'));
  final today = DateTime.now().effectiveDay;
  late Directory docs;

  setUpAll(() async {
    RecordPlatform.instance = _FakeMic();
    docs = await Directory.systemTemp.createTemp('voice_allowance_docs_');
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
  late _MemoryUsage usage;

  Future<void> prepare(int used) async {
    usage = _MemoryUsage(used);
    h = LandingHarness();
    await h.prepare(
      activeCatalogIds: const ['inbox_zero'],
      extraOverrides: [
        premiumAccessProvider.overrideWith((ref) => true),
        voiceNoteUsageStoreProvider.overrideWithValue(usage),
      ],
    );
    (await LocalStoreService.dailyBox()).clear();
  }

  tearDown(() => h.dispose());

  Finder recordRow() => find.byType(VoiceNoteRecordRow);
  VoiceNoteRecordRow row(WidgetTester tester) =>
      tester.widget<VoiceNoteRecordRow>(recordRow());

  Future<void> openEditor(WidgetTester tester) async {
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
  }

  group('with the month used up', () {
    setUp(() => prepare(kVoiceNotesPerMonth));

    testWidgets('the mic says when notes come back, and records nothing',
        (tester) async {
      await openEditor(tester);
      final backOn =
          westernDate(voiceNotesBackOn(DateTime.now()), 'd MMMM', 'en');
      expect(row(tester).hint, s.voiceNotesBackOnHint(backOn));
      expect(find.text(s.voiceNotesBackOnHint(backOn)), findsOneWidget);

      await tester.tap(recordRow());
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(s.voiceNotesMonthUsed(kVoiceNotesPerMonth, backOn)),
          findsOneWidget);
      expect(row(tester).recording, isFalse);
      expect(usage.used, kVoiceNotesPerMonth);
      // The notice leaves on its own timer.
      await tester.pump(const Duration(seconds: 4));
      await h.settle(tester);
    });
  });

  group('with 3 left', () {
    setUp(() => prepare(kVoiceNotesPerMonth - 3));

    testWidgets('it says so, and a kept take counts one', (tester) async {
      await openEditor(tester);
      expect(row(tester).hint, s.voiceNotesLeftThisMonth(3));

      // On the real clock: the take has to last a second to be kept, and
      // the recorder's folder is real disk I/O.
      await tester.runAsync(() async {
        await tester.tap(recordRow());
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      });
      await tester.pump();
      expect(row(tester).recording, isTrue, reason: 'sanity: it started');
      await tester.runAsync(() async {
        await tester.tap(recordRow());
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await h.settle(tester);

      expect(row(tester).recording, isFalse);
      expect(usage.used, kVoiceNotesPerMonth - 2, reason: 'stored');
      expect(
        h.container
            .read(voiceNoteAllowanceProvider)
            .leftAt(DateTime.now()),
        2,
      );
      expect(row(tester).hint, s.voiceNotesLeftThisMonth(2));
    });
  });

  group('with plenty left', () {
    setUp(() => prepare(10));

    testWidgets('the mic reads as it always did', (tester) async {
      await openEditor(tester);
      expect(row(tester).hint, isNull);
      expect(find.text(s.voiceNoteTapToRecord), findsWidgets);
    });
  });
}
