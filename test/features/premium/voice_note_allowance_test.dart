// The monthly voice-note allowance (voice_note_allowance.dart): 100 a
// month per account, tasks and habit days together, back on the 1st.
// Aziz, 2026-09-26: "we need to set a limit for a monthly usage, think what
// may people need, i dont want to pay a lot".
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/features/premium/notifiers/voice_note_allowance.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sept = DateTime(2026, 9, 26, 14);
  final oct = DateTime(2026, 10, 1, 0, 5);

  group('the count', () {
    test('months are keyed by the calendar month', () {
      expect(voiceNoteMonthKey(sept), '2026-09');
      expect(voiceNoteMonthKey(DateTime(2027, 1, 1)), '2027-01');
    });

    test('100 a month, and the 100th is the last', () {
      const at99 = VoiceNoteAllowance(month: '2026-09', used: 99);
      expect(at99.leftAt(sept), 1);
      expect(at99.canRecordAt(sept), isTrue);
      const at100 = VoiceNoteAllowance(month: '2026-09', used: 100);
      expect(at100.leftAt(sept), 0);
      expect(at100.canRecordAt(sept), isFalse);
    });

    test('a new month starts again, even with the app left open', () {
      const used = VoiceNoteAllowance(month: '2026-09', used: 100);
      expect(used.usedAt(oct), 0);
      expect(used.canRecordAt(oct), isTrue);
      expect(voiceNotesBackOn(sept), DateTime(2026, 10));
      expect(voiceNotesBackOn(DateTime(2026, 12, 31)), DateTime(2027));
    });

    test('the lines say how many are left, in easy Arabic', () {
      const ar = S(Locale('ar'));
      const en = S(Locale('en'));
      expect(ar.voiceNotesLeftThisMonth(1), 'باقي لك ملاحظة وحدة هذا الشهر');
      expect(ar.voiceNotesLeftThisMonth(2), 'باقي لك ملاحظتين هذا الشهر');
      expect(ar.voiceNotesLeftThisMonth(5), 'باقي لك 5 ملاحظات هذا الشهر');
      expect(en.voiceNotesLeftThisMonth(1), '1 note left this month');
      expect(en.voiceNotesMonthUsed(100, '1 October'),
          "You've used this month's 100 voice notes. They're back on 1 October.");
    });
  });

  group('kept on the account', () {
    late FakeFirebaseFirestore db;
    late VoiceNoteUsageStore store;
    setUp(() {
      db = FakeFirebaseFirestore();
      store = VoiceNoteUsageStore(firestore: db);
    });

    test('each take adds one to its own month, never overwriting', () async {
      await store.add('u1', '2026-09');
      await store.add('u1', '2026-09');
      await store.add('u1', '2026-10');
      expect(await store.load('u1', '2026-09'), 2);
      expect(await store.load('u1', '2026-10'), 1);
      expect(await store.load('u1', '2026-11'), 0);
      final doc =
          await db.collection('users').doc('u1').collection('meta').doc(kVoiceUsageDoc).get();
      expect(doc.data()?['months'], {'2026-09': 2, '2026-10': 1});
    });

    test('the notifier reads the month back, then counts on from it',
        () async {
      for (var i = 0; i < 98; i++) {
        await store.add('u1', '2026-09');
      }
      final allowance =
          VoiceNoteAllowanceNotifier(store, 'u1', clock: () => sept);
      await Future<void>.delayed(Duration.zero);
      expect(allowance.state.loaded, isTrue);
      expect(allowance.state.leftAt(sept), 2);

      allowance.recorded();
      allowance.recorded();
      expect(allowance.state.canRecordAt(sept), isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(await store.load('u1', '2026-09'), 100,
          reason: 'stored too, so another phone reads the same count');
      allowance.dispose();
    });

    test('a count that cannot be read leaves the mic open', () async {
      final allowance = VoiceNoteAllowanceNotifier(
        _FailingStore(),
        'u1',
        clock: () => sept,
      );
      await Future<void>.delayed(Duration.zero);
      expect(allowance.state.loaded, isFalse);
      expect(allowance.state.canRecordAt(sept), isTrue);
      allowance.dispose();
    });
  });

  group('a guest, on this phone', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('voice_allowance_');
      Hive.init(tmp.path);
      await Hive.openBox<dynamic>('box_settings');
    });
    tearDown(() async {
      await Hive.deleteFromDisk();
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    test('counts the month in hand', () async {
      final store = VoiceNoteUsageStore(firestore: FakeFirebaseFirestore());
      await store.add(null, '2026-09');
      await store.add(null, '2026-09');
      expect(await store.load(null, '2026-09'), 2);
      await store.add(null, '2026-10');
      expect(await store.load(null, '2026-10'), 1);
      expect(await store.load(null, '2026-09'), 0,
          reason: 'only the month in hand is kept');
    });
  });
}

class _FailingStore extends VoiceNoteUsageStore {
  _FailingStore() : super(firestore: FakeFirebaseFirestore());

  @override
  Future<int> load(String? uid, String month) async =>
      throw StateError('offline');
}
