import '../../core/extensions/datetime_ext.dart';
import '../../core/services/local_store_service.dart';

/// When the app asks whether someone wants a daily reminder, and what their
/// answers remember.
///
/// Aziz, 2026-09-24: the evening note used to go out at 20:30 for anyone who
/// had never picked a daily reminder time, a notification nobody chose. It
/// is sent only at a picked time now, and in its place the app ASKS, the way
/// other apps do: pick a time, later, or never.
///
/// The rules, all his:
///   - on opening the app, from the second day of use: someone who started
///     today has not seen a day go by yet, and the question means nothing;
///   - only to someone with a habit the note can speak about (a build habit;
///     quit habits never appear in it) and no daily reminder time;
///   - «بعدين» asks again three days later, and a second «بعدين» is the
///     last: it never asks again;
///   - «لا» never asks again.
///
/// Stored on the device (Hive settings box), not the account: it is a
/// question about this phone's notifications.

/// How long «بعدين» waits before asking again.
const Duration kDailyReminderPromptLaterGap = Duration(days: 3);

/// How many «بعدين» answers the question survives. The second is the last.
const int kDailyReminderPromptMaxLater = 2;

/// What the person has answered so far.
class DailyReminderPromptState {
  const DailyReminderPromptState({
    this.laterCount = 0,
    this.askAfter,
    this.never = false,
  });

  /// How many times they answered «بعدين».
  final int laterCount;

  /// Not asked again before this moment (set by «بعدين»).
  final DateTime? askAfter;

  /// They answered «لا»: never asked again.
  final bool never;

  /// After «بعدين» at [now]: three days' rest, or never once it is the
  /// second time.
  DailyReminderPromptState afterLater(DateTime now) => DailyReminderPromptState(
        laterCount: laterCount + 1,
        askAfter: now.add(kDailyReminderPromptLaterGap),
        never: laterCount + 1 >= kDailyReminderPromptMaxLater,
      );

  /// After «لا».
  DailyReminderPromptState afterNever() => DailyReminderPromptState(
        laterCount: laterCount,
        askAfter: askAfter,
        never: true,
      );

  Map<String, Object?> toMap() => {
        'later': laterCount,
        if (askAfter != null) 'askAfter': askAfter!.millisecondsSinceEpoch,
        'never': never,
      };

  static DailyReminderPromptState fromMap(Object? raw) {
    if (raw is! Map) return const DailyReminderPromptState();
    final later = raw['later'];
    final after = raw['askAfter'];
    return DailyReminderPromptState(
      laterCount: later is int ? later : 0,
      askAfter:
          after is int ? DateTime.fromMillisecondsSinceEpoch(after) : null,
      never: raw['never'] == true,
    );
  }
}

/// Whether the question should be asked at [now].
///
/// [buildHabitCreatedAt] is the creation day of each active build habit;
/// null for one created before the app stamped that date, which is an old
/// habit, so it counts as before today.
bool dailyReminderPromptDue({
  required DateTime now,
  required bool hasReminderTime,
  required Iterable<DateTime?> buildHabitCreatedAt,
  required DailyReminderPromptState state,
}) {
  if (hasReminderTime || state.never) return false;
  if (state.laterCount >= kDailyReminderPromptMaxLater) return false;
  final after = state.askAfter;
  if (after != null && now.isBefore(after)) return false;
  final today = now.effectiveDay;
  return buildHabitCreatedAt
      .any((born) => born == null || born.effectiveDay.isBefore(today));
}

/// Hive settings-box key for [DailyReminderPromptState].
const _kPromptKey = 'daily_reminder_prompt_v1';

/// The stored answers, or none yet. A store that cannot be read means the
/// question may be asked, never that it is suppressed forever.
Future<DailyReminderPromptState> readDailyReminderPromptState() async {
  try {
    final box = await LocalStoreService.settingsBox();
    return DailyReminderPromptState.fromMap(box.get(_kPromptKey));
  } catch (_) {
    return const DailyReminderPromptState();
  }
}

Future<void> writeDailyReminderPromptState(
    DailyReminderPromptState state) async {
  try {
    final box = await LocalStoreService.settingsBox();
    await box.put(_kPromptKey, state.toMap());
  } catch (_) {
    // No store (unit tests): the answer lasts for this run only.
  }
}
