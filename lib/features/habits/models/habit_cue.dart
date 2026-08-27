import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter/widgets.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/utils/western_digits.dart';

/// Canonical, locale-independent identity for a habit's "cue" — the routine
/// it's anchored to: a prayer, "before sleep", a picked clock time, or free
/// text the user typed. `cueAfter` on [HabitModel]/[IslamicHabitTemplate] is
/// a single freeform string field in Firestore/Hive; this class is the one
/// place that knows how to turn that stored string into a stable storage
/// key ([toStorageValue]) and a locale-correct display label
/// ([labelForLocale]) — so neither the database nor the hardcoded English
/// catalog cues (`'Fajr'`, `'Asr'`, ...) ever have to change just because
/// someone switches the app's language, and a habit created in one language
/// still reads correctly after switching to the other.
enum _HabitCueKind { preset, time, freeform }

class HabitCue {
  final _HabitCueKind _kind;
  final String? _presetKey;
  final int? _hour24;
  final int? _minute;

  /// Times 2..N of a habit counted several times a day, in the order the
  /// person arranged them. EMPTY for every cue ever written before this
  /// existed, which is what keeps the whole change backward compatible:
  /// [_hour24]/[_minute] still hold the FIRST time, so every existing reader
  /// of [clockTime] keeps seeing exactly what it saw before.
  ///
  /// Order is meaningful and must be preserved on the round trip. The
  /// notification slot a reminder occupies is its INDEX here (see
  /// NotificationService.scheduleSmartReminders), and a slot's notification id
  /// is a hash of `habitId#slot` — so re-ordering this list silently re-points
  /// every already-scheduled reminder at a different slot, stranding the old
  /// ones in the OS scheduler with nothing able to cancel them.
  final List<TimeOfDay> _extraTimes;

  /// The signed minute shift each time's reminder fires at, index-aligned with
  /// [clockTimes]: negative is before, positive after, 0 is on the dot.
  ///
  /// Carried INSIDE the cue rather than in a parallel field on the habit,
  /// because a list of times and a list of offsets stored apart is a pair that
  /// can desync — reorder one, clamp one, drop one, and every reminder after
  /// the mistake is silently shifted by somebody else's number. Here they are
  /// one string and sort together by construction.
  ///
  /// Empty for a single-time cue, which keeps using the habit's own
  /// reminderOffsetMinutes exactly as it always has. See [offsetsAreOwn].
  final List<int> _offsets;
  final String _raw;

  const HabitCue._preset(String key)
      : _kind = _HabitCueKind.preset,
        _presetKey = key,
        _hour24 = null,
        _minute = null,
        _extraTimes = const [],
        _offsets = const [],
        _raw = '';

  const HabitCue._time(int hour24, int minute,
      [List<TimeOfDay> extras = const [], List<int> offsets = const []])
      : _kind = _HabitCueKind.time,
        _presetKey = null,
        _hour24 = hour24,
        _minute = minute,
        _extraTimes = extras,
        _offsets = offsets,
        _raw = '';

  const HabitCue._freeform(String raw)
      : _kind = _HabitCueKind.freeform,
        _presetKey = null,
        _hour24 = null,
        _minute = null,
        _extraTimes = const [],
        _offsets = const [],
        _raw = raw;

  static const empty = HabitCue._freeform('');

  /// The 6 known routine anchors, canonical key -> recognized synonyms
  /// (itself, its old English chip text, and the Arabic text this app
  /// briefly stored directly before this refactor) — every one of these
  /// resolves back to the same stable key regardless of which form is on
  /// disk.
  static const Map<String, List<String>> _presetSynonyms = {
    'fajr': ['fajr', 'Fajr', 'الفجر'],
    'dhuhr': ['dhuhr', 'Dhuhr', 'الظهر'],
    'asr': ['asr', 'Asr', 'العصر'],
    'maghrib': ['maghrib', 'Maghrib', 'المغرب'],
    'isha': ['isha', 'Isha', 'العشاء'],
    'before_sleep': ['before_sleep', 'Before sleep', 'قبل النوم'],
    'morning': ['morning', 'Morning', 'الصباح'],
    'afternoon': ['afternoon', 'Afternoon', 'بعد الظهر'],
    'evening': ['evening', 'Evening', 'المساء'],
    'after_work_school': [
      'after_work_school',
      'After work/school',
      'بعد العمل/المدرسة',
    ],
    'after_school_work': [
      'after_school_work',
      'After school/work',
      'بعد المدرسة/العمل',
    ],
    'work_block': ['work_block', 'Work block', 'وقت العمل'],
  };

  /// One entry of a `custom_time:` run: `HH:MM`, optionally followed by a
  /// SIGNED minute shift (`08:00-15` is "quarter of an hour before eight").
  ///
  /// Matched per part rather than as one big pattern over the whole run,
  /// because a repeated capture group only ever keeps its LAST match — a
  /// single anchored pattern would silently discard every time but the final
  /// one. A legacy single value (`custom_time:07:30`) matches this with no
  /// suffix and round-trips byte-identically, which is the whole
  /// backward-compatibility guarantee: nothing already on disk moves.
  static final RegExp _timePart = RegExp(r'^(\d{2}):(\d{2})([+-]\d{1,3})?$');
  static final RegExp _timeEn =
      RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)$', caseSensitive: false);
  static final RegExp _timeAr = RegExp(r'^(\d{1,2}):(\d{2})\s*(ص|م)$');

  /// Dart's `\d` matches ASCII digits only, but Arabic keyboards (especially
  /// on mobile) commonly default to Arabic-Indic digits (٠-٩) — a time typed
  /// as "٧:٣٠ ص" must still be recognized as 7:30, not fall through to
  /// freeform text. Only used ahead of the time-pattern checks below; preset
  /// matching and the freeform fallback both still see the original,
  /// unmodified text.
  ///
  /// Delegates to the shared helper — this was one of three hand-rolled
  /// copies of the same ten-character loop (see [toWesternDigits]).
  static String _asciiDigits(String s) => toWesternDigits(s);

  /// A known routine preset by canonical key (e.g. `'maghrib'`). Falls back
  /// to freeform if [key] isn't one of the 6 recognized keys.
  factory HabitCue.preset(String key) => _presetSynonyms.containsKey(key)
      ? HabitCue._preset(key)
      : HabitCue._freeform(key);

  /// A picked clock time, in 24-hour form (from `TimeOfDay.hour`/`.minute`).
  factory HabitCue.time(int hour24, int minute) =>
      HabitCue._time(hour24, minute);

  /// Several picked clock times, for a habit counted more than once a day.
  ///
  /// Order is kept exactly as given — see [_extraTimes] for why re-ordering is
  /// not a cosmetic choice. Duplicates are dropped (two reminders at the same
  /// minute is one reminder and a wasted slot), and an empty list is an empty
  /// cue rather than a malformed one.
  /// Several times, each carrying its own signed offset in minutes.
  ///
  /// The multi-time form of [HabitCue.time]. Offsets ride along through the
  /// sort, so re-ordering the input can never shuffle a shift onto somebody
  /// else's time.
  factory HabitCue.timesWithOffsets(List<(TimeOfDay, int)> entries) {
    final byMinute = <int, int>{};
    for (final (t, off) in entries) {
      // First write wins on a duplicate minute, matching the dedupe rule in
      // HabitCue.times: a repeat is a mistake, not a second reminder.
      byMinute.putIfAbsent(t.hour * 60 + t.minute, () => off);
    }
    final mins = byMinute.keys.toList()..sort();
    if (mins.isEmpty) return HabitCue.empty;
    final kept = mins.take(_maxTimes).toList();
    return HabitCue._time(
      kept.first ~/ 60,
      kept.first % 60,
      kept.length > 1
          ? List.unmodifiable([
              for (final m in kept.skip(1))
                TimeOfDay(hour: m ~/ 60, minute: m % 60),
            ])
          : const [],
      List.unmodifiable([for (final m in kept) byMinute[m]!]),
    );
  }

  factory HabitCue.times(List<TimeOfDay> times) =>
      HabitCue.timesWithOffsets([for (final t in times) (t, 0)]);

  /// The most times one habit can carry. Kept equal to
  /// NotificationService._maxHabitReminderSlots and kMaxTimesPerDay — the
  /// three are asserted equal in test (they cannot import each other: one
  /// lives inside a `part of` a widget file).
  static const int _maxTimes = 12;

  /// Parses whatever is currently on disk (or being typed/edited): a
  /// canonical key, a legacy English or Arabic preset name, a canonical or
  /// legacy time string, or arbitrary custom text. This is the single
  /// fallback/migration point — nothing else in the app needs to know
  /// about the old formats.
  factory HabitCue.fromStoredValue(String? stored) {
    final raw = (stored ?? '').trim();
    if (raw.isEmpty) return HabitCue.empty;

    final lower = raw.toLowerCase();
    for (final entry in _presetSynonyms.entries) {
      // Arabic has no case, so .toLowerCase() on an Arabic synonym is a
      // harmless no-op — this loop works for both scripts unmodified.
      if (entry.value.any((s) => s.toLowerCase() == lower)) {
        return HabitCue._preset(entry.key);
      }
    }

    final timeCandidate = _asciiDigits(raw);
    // ── A `custom_time:` value is OURS, valid or not ─────────────────────
    //
    // Anything carrying this prefix was written by this app, so a malformed
    // one is damage, not user text. Letting it fall through to the freeform
    // branch below is what makes that damage invisible: isEmpty is false for
    // freeform, so every screen renders the raw token «custom_time:9x:99» as
    // if the person had typed it, and reopening Add Habit drops them into
    // Custom Text mode with the token sitting in an editable field. Resolving
    // to empty instead costs the reminder and says so.
    if (timeCandidate.startsWith('custom_time:')) {
      final body = timeCandidate.substring('custom_time:'.length);
      if (body.isEmpty) return HabitCue.empty;
      final entries = <(TimeOfDay, int)>[];
      for (final part in body.split(',')) {
        final m = _timePart.firstMatch(part);
        if (m == null) return HabitCue.empty;
        final h = int.parse(m.group(1)!);
        final min = int.parse(m.group(2)!);
        // The pattern proves the SHAPE and says nothing about the range, so
        // `custom_time:99:99` matches it. TimeOfDay does not validate either —
        // it would hold hour 99 and produce a fire time 99 hours out. Out of
        // range is damage, and damage takes the same exit as a malformed
        // value: empty, never freeform.
        if (h > 23 || min > 59) return HabitCue.empty;
        final off = m.group(3);
        if (off != null && (off.length > 4)) return HabitCue.empty;
        entries.add((
          TimeOfDay(hour: h, minute: min),
          off == null ? 0 : int.parse(off),
        ));
      }
      // Through the same factory as a fresh pick, so a hand-edited document
      // holding a duplicate, an out-of-order pair or a 13th time is
      // canonicalized on READ rather than costing a slot or a phantom
      // override later.
      return HabitCue.timesWithOffsets(entries);
    }
    final en = _timeEn.firstMatch(timeCandidate);
    if (en != null) {
      return HabitCue._time(
        _to24(int.parse(en.group(1)!), en.group(3)!.toUpperCase() == 'PM'),
        int.parse(en.group(2)!),
      );
    }
    final ar = _timeAr.firstMatch(timeCandidate);
    if (ar != null) {
      return HabitCue._time(
        _to24(int.parse(ar.group(1)!), ar.group(3)! == 'م'),
        int.parse(ar.group(2)!),
      );
    }

    return HabitCue._freeform(raw);
  }

  static int _to24(int hour12, bool pm) {
    final h = hour12 % 12;
    return pm ? h + 12 : h;
  }

  bool get isEmpty => _kind == _HabitCueKind.freeform && _raw.trim().isEmpty;

  static const _prayerKeys = {'fajr', 'dhuhr', 'asr', 'maghrib', 'isha'};

  /// Whether this cue resolved to one of the 5 daily prayers specifically
  /// (as opposed to a non-prayer preset like 'before_sleep', a picked
  /// clock time, or freeform text) — used by the Add Habit sheet's "Prayer"
  /// timing mode to restore its selected-prayer chip when editing a habit.
  bool get isPrayer =>
      _kind == _HabitCueKind.preset && _prayerKeys.contains(_presetKey);

  /// The canonical prayer key ('fajr'…'isha') if [isPrayer], else null.
  String? get prayerKey => isPrayer ? _presetKey : null;

  /// The exact clock time this cue resolves to, if the user picked one —
  /// null for a preset routine anchor (e.g. 'maghrib', 'before_sleep') or
  /// freeform text. A prayer preset resolves to a real time too, but through
  /// [prayerKey] + PrayerTimesService instead of this getter (it needs a
  /// saved location to compute from, which this pure class has no way to
  /// hold); the handful of non-prayer presets ('before_sleep', 'morning', …)
  /// still have no fixed time this app can derive on its own. Used to
  /// schedule a real per-habit reminder — see
  /// NotificationService.scheduleSmartReminders.
  TimeOfDay? get clockTime =>
      _kind == _HabitCueKind.time ? TimeOfDay(hour: _hour24!, minute: _minute!) : null;

  /// Every clock time this cue carries, first one first — the input the
  /// scheduler walks to fill one reminder slot per time.
  ///
  /// Exactly `[clockTime]` for a single-time cue, so a caller can move to this
  /// getter without changing behaviour for any habit that already exists.
  /// Empty for a prayer, a preset routine or freeform text, none of which have
  /// a fixed time this app can derive on its own (see [clockTime]).
  /// Whether this cue carries its OWN per-time shifts, in which case the
  /// habit-level reminderOffsetMinutes must not also be applied.
  ///
  /// True exactly when there is more than one time. A single-time habit keeps
  /// the habit-level field it has always used, so nothing about an existing
  /// habit changes; a multi-time one answers entirely from here, so there is
  /// never a question of which of two numbers wins or whether they stack.
  bool get offsetsAreOwn => clockTimes.length > 1;

  /// The signed shift for the time in [slot], or 0 when this cue does not
  /// carry its own (see [offsetsAreOwn]).
  int offsetForSlot(int slot) =>
      slot >= 0 && slot < _offsets.length ? _offsets[slot] : 0;

  /// Every shift, index-aligned with [clockTimes].
  List<int> get clockOffsets => List.unmodifiable([
        for (var i = 0; i < clockTimes.length; i++) offsetForSlot(i),
      ]);

  String _timesToStorage() {
    final all = clockTimes;
    final parts = <String>[];
    for (var i = 0; i < all.length; i++) {
      final off = offsetForSlot(i);
      final suffix = off == 0 ? '' : (off > 0 ? '+$off' : '$off');
      parts.add('${_pad2(all[i].hour)}:${_pad2(all[i].minute)}$suffix');
    }
    return parts.join(',');
  }

  List<TimeOfDay> get clockTimes {
    final first = clockTime;
    if (first == null) return const [];
    return List.unmodifiable([first, ..._extraTimes]);
  }

  /// Value to persist to Firestore/Hive — always locale-independent, so it
  /// never needs to change again after a language switch.
  String toStorageValue() => switch (_kind) {
        _HabitCueKind.preset => _presetKey!,
        // Emits the legacy single-value form byte-for-byte when there is only
        // one time, so re-saving an untouched habit rewrites the same string.
        // Emits the legacy single-value form byte-for-byte when there is one
        // time and no shift, so re-saving an untouched habit rewrites the same
        // string and nothing on disk migrates.
        _HabitCueKind.time => 'custom_time:${_timesToStorage()}',
        _HabitCueKind.freeform => _raw,
      };

  /// Human label for [isAr] — this is what every screen shows.
  String labelForLocale(bool isAr) => switch (_kind) {
        _HabitCueKind.preset => _presetLabel(_presetKey!, isAr),
        _HabitCueKind.time => _timeLabel(isAr),
        _HabitCueKind.freeform => _raw,
      };

  String labelFor(BuildContext context) =>
      labelForLocale(S.of(context).isAr);

  static String _presetLabel(String key, bool isAr) => switch (key) {
        'fajr' => isAr ? 'الفجر' : 'Fajr',
        'dhuhr' => isAr ? 'الظهر' : 'Dhuhr',
        'asr' => isAr ? 'العصر' : 'Asr',
        'maghrib' => isAr ? 'المغرب' : 'Maghrib',
        'isha' => isAr ? 'العشاء' : 'Isha',
        'before_sleep' => isAr ? 'قبل النوم' : 'Before sleep',
        'morning' => isAr ? 'الصباح' : 'Morning',
        'afternoon' => isAr ? 'بعد الظهر' : 'Afternoon',
        'evening' => isAr ? 'المساء' : 'Evening',
        'after_work_school' => isAr ? 'بعد العمل/المدرسة' : 'After work/school',
        'after_school_work' => isAr ? 'بعد المدرسة/العمل' : 'After school/work',
        'work_block' => isAr ? 'وقت العمل' : 'Work block',
        _ => key,
      };

  static String _pad2(int n) => n.toString().padLeft(2, '0');

  static String _oneTimeLabel(int hour24, int minute, bool isAr) {
    final raw12 = hour24 % 12;
    final hour12 = raw12 == 0 ? 12 : raw12;
    final isPm = hour24 >= 12;
    final period = isAr ? (isPm ? 'م' : 'ص') : (isPm ? 'PM' : 'AM');
    return '$hour12:${_pad2(minute)} $period';
  }

  /// Joined with "و" / "and" rather than commas, because this label is
  /// dropped into a SENTENCE ([previewTextForLocale] → S.planPreview: «بعد
  /// {cue}، سأقوم بـ {name}»). A comma-separated run reads as a broken list
  /// inside that frame, and the last item needs the conjunction in both
  /// languages anyway.
  String _timeLabel(bool isAr) {
    final labels = [
      _oneTimeLabel(_hour24!, _minute!, isAr),
      for (final t in _extraTimes) _oneTimeLabel(t.hour, t.minute, isAr),
    ];
    if (labels.length == 1) return labels.first;
    final join = isAr ? ' و' : ' and ';
    return '${labels.sublist(0, labels.length - 1).join(isAr ? '، ' : ', ')}'
        '$join${labels.last}';
  }

  /// "After Maghrib, I will X." / "بعد المغرب، سأقوم بـ X." — pure form,
  /// directly testable without a BuildContext.
  String previewTextForLocale(bool isAr, String habitName) {
    if (isEmpty) return '';
    return S(Locale(isAr ? 'ar' : 'en'))
        .planPreview(labelForLocale(isAr), habitName);
  }

  String previewTextFor(BuildContext context, String habitName) =>
      previewTextForLocale(S.of(context).isAr, habitName);
}
