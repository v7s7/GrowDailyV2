// One evening note a night (page item 7, 2026-09-24): the note went out at
// 20:30, the time was moved to 21:00, and a second one came at 21:00.
// eveningNoteWentOut is how a later pass knows one already went out; the
// scheduler's side is in notification_voice_hookup_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/services/evening_note_record.dart';

void main() {
  // Thursday 24 Sep 2026.
  final thursday = DateTime(2026, 9, 24);
  DateTime on(int hour, [int minute = 0, int dayOffset = 0]) =>
      DateTime(thursday.year, thursday.month, thursday.day + dayOffset, hour,
          minute);

  EveningNoteRecord tonight({required DateTime armedAt, DateTime? at}) =>
      EveningNoteRecord(
        armedAt: armedAt,
        hour: 20,
        minute: 30,
        tonightAt: at ?? on(20, 30),
        tonightDay: eveningDayKey(at ?? on(20, 30)),
      );

  group("tonight's worded note", () {
    test('gone out once its minute has passed', () {
      final record = tonight(armedAt: on(18));
      expect(eveningNoteWentOut(record, on(20, 29)), isFalse);
      expect(eveningNoteWentOut(record, on(20, 30)), isTrue);
      expect(eveningNoteWentOut(record, on(22)), isTrue);
    });

    test('says nothing about the next day', () {
      final record = tonight(armedAt: on(18));
      expect(eveningNoteWentOut(record, on(9, 0, 1)), isFalse);
      expect(eveningNoteWentOut(record, on(21, 0, 1)), isFalse);
    });

    test('nothing armed, nothing gone out', () {
      expect(eveningNoteWentOut(null, on(23)), isFalse);
    });
  });

  group("today's weekly fallback", () {
    EveningNoteRecord fallbacks({required DateTime armedAt, Set<int>? days}) =>
        EveningNoteRecord(
          armedAt: armedAt,
          hour: 20,
          minute: 30,
          fallbackWeekdays: days ?? {1, 2, 3, 4, 5, 6, 7},
        );

    test('armed on an earlier day, it fired at its minute today', () {
      // A phone left closed since Monday: Thursday's copy went out at 20:30.
      final record = fallbacks(armedAt: on(9, 0, -3));
      expect(eveningNoteWentOut(record, on(20)), isFalse);
      expect(eveningNoteWentOut(record, on(20, 45)), isTrue);
    });

    test('armed after its minute today, it has not fired yet', () {
      final record = fallbacks(armedAt: on(21));
      expect(eveningNoteWentOut(record, on(22)), isFalse);
    });

    test("not armed for today's weekday, nothing went out", () {
      final record = fallbacks(
          armedAt: on(9, 0, -3), days: {1, 2, 3, 5, 6, 7}); // no Thursday
      expect(thursday.weekday, DateTime.thursday);
      expect(eveningNoteWentOut(record, on(22)), isFalse);
    });
  });

  test('a day marked as gone out stays gone out, and only that day', () {
    final record = EveningNoteRecord.wentOut(eveningDayKey(on(20, 30)));
    expect(eveningNoteWentOut(record, on(23)), isTrue);
    expect(eveningNoteWentOut(record, on(20, 0, 1)), isFalse);
  });

  test('survives being stored', () {
    final record = EveningNoteRecord(
      armedAt: on(18),
      hour: 21,
      minute: 5,
      tonightAt: on(21, 5),
      tonightDay: eveningDayKey(on(21, 5)),
      fallbackWeekdays: const {1, 2, 3, 5, 6, 7},
      wentOutOn: '2026-09-23',
    );
    expect(EveningNoteRecord.fromMap(record.toMap()), record);
    expect(EveningNoteRecord.fromMap(const {}), isNull);
  });
}
