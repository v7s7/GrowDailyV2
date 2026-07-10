import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter/widgets.dart';

import '../../../core/l10n/app_strings.dart';

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
  final String _raw;

  const HabitCue._preset(String key)
      : _kind = _HabitCueKind.preset,
        _presetKey = key,
        _hour24 = null,
        _minute = null,
        _raw = '';

  const HabitCue._time(int hour24, int minute)
      : _kind = _HabitCueKind.time,
        _presetKey = null,
        _hour24 = hour24,
        _minute = minute,
        _raw = '';

  const HabitCue._freeform(String raw)
      : _kind = _HabitCueKind.freeform,
        _presetKey = null,
        _hour24 = null,
        _minute = null,
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

  static final RegExp _timeCanonical = RegExp(r'^custom_time:(\d{2}):(\d{2})$');
  static final RegExp _timeEn =
      RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)$', caseSensitive: false);
  static final RegExp _timeAr = RegExp(r'^(\d{1,2}):(\d{2})\s*(ص|م)$');

  static const _arabicIndicDigits = '٠١٢٣٤٥٦٧٨٩';

  /// Dart's `\d` matches ASCII digits only, but Arabic keyboards (especially
  /// on mobile) commonly default to Arabic-Indic digits (٠-٩) — a time typed
  /// as "٧:٣٠ ص" must still be recognized as 7:30, not fall through to
  /// freeform text. Only used ahead of the time-pattern checks below; preset
  /// matching and the freeform fallback both still see the original,
  /// unmodified text.
  static String _asciiDigits(String s) {
    final buffer = StringBuffer();
    for (final ch in s.split('')) {
      final i = _arabicIndicDigits.indexOf(ch);
      buffer.write(i >= 0 ? i.toString() : ch);
    }
    return buffer.toString();
  }

  /// A known routine preset by canonical key (e.g. `'maghrib'`). Falls back
  /// to freeform if [key] isn't one of the 6 recognized keys.
  factory HabitCue.preset(String key) => _presetSynonyms.containsKey(key)
      ? HabitCue._preset(key)
      : HabitCue._freeform(key);

  /// A picked clock time, in 24-hour form (from `TimeOfDay.hour`/`.minute`).
  factory HabitCue.time(int hour24, int minute) =>
      HabitCue._time(hour24, minute);

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
    final canon = _timeCanonical.firstMatch(timeCandidate);
    if (canon != null) {
      return HabitCue._time(
          int.parse(canon.group(1)!), int.parse(canon.group(2)!));
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

  /// The exact clock time this cue resolves to, if the user picked one —
  /// null for a preset routine anchor (e.g. 'maghrib', 'before_sleep') or
  /// freeform text, since those don't have a fixed time without real
  /// prayer-time/schedule data this app doesn't have yet. Used to schedule
  /// a real per-habit reminder — see NotificationService.scheduleHabitReminders.
  TimeOfDay? get clockTime =>
      _kind == _HabitCueKind.time ? TimeOfDay(hour: _hour24!, minute: _minute!) : null;

  /// Value to persist to Firestore/Hive — always locale-independent, so it
  /// never needs to change again after a language switch.
  String toStorageValue() => switch (_kind) {
        _HabitCueKind.preset => _presetKey!,
        _HabitCueKind.time =>
          'custom_time:${_hour24!.toString().padLeft(2, '0')}:${_minute!.toString().padLeft(2, '0')}',
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

  String _timeLabel(bool isAr) {
    final raw12 = _hour24! % 12;
    final hour12 = raw12 == 0 ? 12 : raw12;
    final minute = _minute!.toString().padLeft(2, '0');
    final isPm = _hour24 >= 12;
    final period = isAr ? (isPm ? 'م' : 'ص') : (isPm ? 'PM' : 'AM');
    return '$hour12:$minute $period';
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
