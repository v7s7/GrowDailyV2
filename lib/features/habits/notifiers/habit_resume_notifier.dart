import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/services/local_store_service.dart';
import '../../auth/notifiers/auth_notifier.dart';

/// A return date as a person would say it: "الثلاثاء 6 أكتوبر", plus the
/// hour only when one was actually chosen.
///
/// Presets land on the start of a day and say nothing about time, because
/// "أسبوع" does not mean "in a week at 00:00" to anybody; only a custom pick
/// has a meaningful hour to show.
String formatResumeDate(DateTime at, bool isAr, {bool withTime = false}) {
  final locale = isAr ? 'ar' : 'en';
  final day = DateFormat('EEEE d MMMM', locale).format(at);
  if (!withTime) return day;
  // The separator follows the language, not the date: an Arabic comma spliced
  // into an English date ("Tuesday 6 October، 6:00 AM") reads as a typo.
  final comma = isAr ? '،' : ',';
  return '$day$comma ${DateFormat.jm(locale).format(at)}';
}

/// When paused habits are due to come back on their own.
///
/// Pausing stays exactly as it was: one tap, no end date, resumed by hand
/// whenever you like. This is the opt-in half. Someone who knows roughly how
/// long they will be away, a broken leg, travel, an exam week, can say so at
/// the moment they pause, and the habit returns to the board by itself
/// instead of depending on them remembering that it exists.
///
/// ── Why an explicit date instead of a duration ──────────────────────────
/// Stored as the day it comes back, not "two weeks from now", because the
/// two stop agreeing the moment the app is closed for a while. A duration
/// has to be counted from something, and the only honest something is the
/// pause date, which would then need storing too. A date is already the
/// answer.
///
/// The time of day is kept as given and compared whole, so "back on Tuesday
/// at 6am" does not arrive on Monday evening.
class HabitResumeSchedule extends StateNotifier<Map<String, DateTime>> {
  /// [storeKey] defaults to the unscoped key for tests that exercise the
  /// mechanism in isolation; the provider passes a per-identity key so one
  /// account's bookings are never read or pruned under another's session (see
  /// LocalStoreService.habitResumeDatesKeyFor).
  HabitResumeSchedule([String? storeKey])
      : _storeKey = storeKey ?? LocalStoreService.habitResumeDatesKey,
        super(const {}) {
    _ready = _load();
  }

  final String _storeKey;

  /// Completes once the stored bookings have been read.
  ///
  /// Every mutation awaits this before touching state, because the load is
  /// asynchronous and the constructor cannot be: a booking written in the
  /// gap would be silently overwritten the moment the read landed. Caught by
  /// pause_until_test, where writing and immediately reading back lost the
  /// entry. Readers may look without waiting and simply see nothing yet.
  late final Future<void> _ready;
  Future<void> get ready => _ready;

  Future<void> _load() async {
    final saved = await LocalStoreService.getSettingsMap(_storeKey);
    final out = <String, DateTime>{};
    saved.forEach((habitId, raw) {
      final at = DateTime.tryParse(raw as String? ?? '');
      if (at != null) out[habitId] = at;
    });
    if (mounted) state = out;
  }

  Future<void> _persist() => LocalStoreService.putSettingsMap(
        _storeKey,
        {
          for (final e in state.entries) e.key: e.value.toIso8601String(),
        },
      );

  /// Books [habitId] to return at [at], or cancels any booking when null.
  ///
  /// Called on every pause, including the plain manual one, so choosing
  /// "أنا أقرر" after previously setting a date actually clears the old
  /// date rather than silently leaving it armed.
  Future<void> schedule(String habitId, DateTime? at) async {
    await _ready;
    final next = {...state};
    if (at == null) {
      next.remove(habitId);
    } else {
      next[habitId] = at;
    }
    state = next;
    await _persist();
  }

  /// The habits whose return time has arrived, oldest first.
  ///
  /// Ordered so that a device opened after a long absence resumes them in
  /// the order they were meant to come back, which is the order that reads
  /// correctly if the habit cap turns some of them away (see
  /// autoResumeDueHabits).
  List<String> dueBy(DateTime now) {
    final due = [
      for (final e in state.entries)
        if (!e.value.isAfter(now)) e,
    ]..sort((a, b) => a.value.compareTo(b.value));
    return [for (final e in due) e.key];
  }

  /// Drops bookings for habits that no longer exist in any form.
  ///
  /// A booking outliving its habit is harmless (nothing resolves it, so
  /// nothing resumes) but it would sit in storage forever, and on a shared
  /// device it would belong to whoever was signed in when it was made.
  Future<void> pruneMissing(Set<String> knownHabitIds) async {
    await _ready;
    final next = {
      for (final e in state.entries)
        if (knownHabitIds.contains(e.key)) e.key: e.value,
    };
    if (next.length == state.length) return;
    state = next;
    await _persist();
  }

  /// Same-day resolution for display: the date a habit is due back, or null.
  DateTime? forHabit(String habitId) => state[habitId];
}

final habitResumeScheduleProvider =
    StateNotifierProvider<HabitResumeSchedule, Map<String, DateTime>>((ref) {
  // Per identity, the same way customHabitsProvider rebuilds per account: a
  // booking belongs to whoever was signed in when it was made, and must not be
  // visible to (or swept by) a different account or a guest sharing the device.
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  return HabitResumeSchedule(LocalStoreService.habitResumeDatesKeyFor(uid));
});

/// Presets offered next to the custom picker. Not an enum on the model:
/// nothing is persisted as a preset, they are only shortcuts for producing a
/// date, so the chooser can gain or lose one without a migration.
enum ResumePreset { week, twoWeeks, month }

extension ResumePresetDate on ResumePreset {
  /// Resolved against [from]'s effective day and kept at that day's start,
  /// so a preset picked at 11pm does not bring the habit back at 11pm.
  ///
  /// "That day's start" is [kDayCutoffHour] (6am), NOT calendar midnight: the
  /// hours 00:00–05:59 belong to the PREVIOUS effective day everywhere else in
  /// the app, so a booking at 00:00 would let the habit resume into the day
  /// before the one the user picked — a night owl opening the app at 12:30am on
  /// the return date would find it already back, inside yesterday's still-open
  /// effective day. Landing on the cutoff hour is the first instant that
  /// actually belongs to the chosen day, which is what the class doc promises.
  DateTime dateFrom(DateTime from) {
    final base = from.effectiveDay;
    final day = switch (this) {
      ResumePreset.week => base.add(const Duration(days: 7)),
      ResumePreset.twoWeeks => base.add(const Duration(days: 14)),
      // Calendar month rather than 30 days: "a month" from 31 January is
      // understood as the end of February, and DateTime normalises the
      // overflow for us.
      ResumePreset.month => DateTime(base.year, base.month + 1, base.day),
    };
    return day.add(const Duration(hours: kDayCutoffHour));
  }
}
