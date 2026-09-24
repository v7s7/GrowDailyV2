// When the app asks whether someone wants a daily reminder (Aziz,
// 2026-09-24): from the second day of use, to someone with a build habit
// and no reminder time; «بعدين» waits three days, the second «بعدين» is the
// last, «لا» is never asked again.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/settings/daily_reminder_prompt.dart';

void main() {
  final now = DateTime(2026, 9, 24, 18);
  final yesterday = DateTime(2026, 9, 23, 9);
  final thisMorning = DateTime(2026, 9, 24, 8);
  const fresh = DailyReminderPromptState();

  bool due({
    bool hasTime = false,
    Iterable<DateTime?> born = const [],
    DailyReminderPromptState state = fresh,
    DateTime? at,
  }) =>
      dailyReminderPromptDue(
        now: at ?? now,
        hasReminderTime: hasTime,
        buildHabitCreatedAt: born,
        state: state,
      );

  test('asks someone with a habit from before today and no time', () {
    expect(due(born: [yesterday]), isTrue);
  });

  test('not on the first day of use', () {
    expect(due(born: [thisMorning]), isFalse,
        reason: 'nobody has seen a day go by yet');
  });

  test('a habit with no stamped birth day is an old one', () {
    expect(due(born: [null]), isTrue);
  });

  test('not with no build habit at all', () {
    expect(due(born: const []), isFalse,
        reason: 'the evening note has nothing to say about quit habits');
  });

  test('never once a time is picked', () {
    expect(due(hasTime: true, born: [yesterday]), isFalse);
  });

  test('«بعدين» waits three days, then asks once more', () {
    final later = fresh.afterLater(now);
    expect(later.never, isFalse);
    expect(due(born: [yesterday], state: later, at: now.add(const Duration(days: 2))),
        isFalse);
    expect(due(born: [yesterday], state: later, at: now.add(const Duration(days: 3))),
        isTrue);
  });

  test('the second «بعدين» is the last', () {
    final twice = fresh.afterLater(now).afterLater(now.add(const Duration(days: 3)));
    expect(twice.never, isTrue);
    expect(due(born: [yesterday], state: twice, at: now.add(const Duration(days: 30))),
        isFalse);
  });

  test('«لا» is never asked again', () {
    expect(due(born: [yesterday], state: fresh.afterNever()), isFalse);
  });

  test('the answers survive being stored', () {
    final later = fresh.afterLater(now);
    final back = DailyReminderPromptState.fromMap(later.toMap());
    expect(back.laterCount, 1);
    expect(back.askAfter, later.askAfter);
    expect(back.never, isFalse);
    expect(DailyReminderPromptState.fromMap(fresh.afterNever().toMap()).never,
        isTrue);
    expect(DailyReminderPromptState.fromMap('garbage').laterCount, 0,
        reason: 'an unreadable store means the question may be asked');
  });
}
