// A take still running when Premium ends has to stop.
//
// Recording asked for Premium before anything else, stopping included, so a
// take started with Premium could not be stopped once Premium ended: Stop
// opened the paywall, the take kept running, and at the cap the timer that
// stops it called the same function every second and opened a new paywall
// each time. Found by the Premium-lapse audit of 2026-09-26. The same two
// lines changed in AddTaskSheet and TaskDetailSheet; this drives the square
// editor's copy with a fake microphone.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/features/matrix/widgets/voice_note_player.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';

import '../../helpers/landing_harness.dart';

/// A microphone that grants permission, records nothing and keeps nothing.
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
  Future<String?> stop(String recorderId) async => null;

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

final _premium = StateProvider<bool>((ref) => true);

void main() {
  const s = S(Locale('en'));
  final today = DateTime.now().effectiveDay;
  late Directory docs;

  setUpAll(() async {
    // Before anything builds VoiceNoteService, whose recorder takes the
    // platform it finds when it is made.
    RecordPlatform.instance = _FakeMic();
    docs = await Directory.systemTemp.createTemp('voice_stop_docs_');
    final channels =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    channels.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => docs.path,
    );
    // The service's player (audioplayers), never played here. Its global
    // setup answers; its own creation is held, because the next step would
    // listen on a channel named after a random player id, which no mock can
    // name in advance.
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
        premiumAccessProvider.overrideWith((ref) => ref.watch(_premium)),
      ],
    );
    (await LocalStoreService.dailyBox()).clear();
  });
  tearDown(() => h.dispose());

  Finder recordRow() => find.byType(VoiceNoteRecordRow);
  bool recording(WidgetTester tester) =>
      tester.widget<VoiceNoteRecordRow>(recordRow()).recording;

  /// The mic tapped on the real clock: starting a take creates its folder on
  /// disk, and disk I/O started on the test's fake clock never finishes.
  Future<void> tapMic(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(recordRow());
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
  }

  testWidgets('Stop still stops once Premium has ended, and sells nothing',
      (tester) async {
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

    await tapMic(tester);
    expect(recording(tester), isTrue, reason: 'sanity: the take started');

    h.container.read(_premium.notifier).state = false;
    await tester.pump();

    await tapMic(tester);
    await h.settle(tester);
    expect(find.text(s.voiceNoteGateTitle), findsNothing,
        reason: 'Stop is not an upsell');
    expect(recording(tester), isFalse, reason: 'the take stopped');
  });
}
