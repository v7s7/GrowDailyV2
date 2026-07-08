import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/features/habits/models/habit_cue.dart';

void main() {
  group('HabitCue — canonical storage', () {
    test('a preset picked from the chips stores its stable key, not text', () {
      expect(HabitCue.preset('maghrib').toStorageValue(), 'maghrib');
      expect(HabitCue.preset('before_sleep').toStorageValue(), 'before_sleep');
    });

    test('a picked time stores a locale-independent 24h value', () {
      expect(HabitCue.time(7, 30).toStorageValue(), 'custom_time:07:30');
      expect(HabitCue.time(19, 5).toStorageValue(), 'custom_time:19:05');
      expect(HabitCue.time(0, 0).toStorageValue(), 'custom_time:00:00');
    });

    test('arbitrary free text is stored verbatim', () {
      expect(HabitCue.fromStoredValue('after lunch break').toStorageValue(),
          'after lunch break');
    });
  });

  group('HabitCue — Arabic label display', () {
    test('every preset has a correct Arabic label', () {
      expect(HabitCue.preset('fajr').labelForLocale(true), 'الفجر');
      expect(HabitCue.preset('dhuhr').labelForLocale(true), 'الظهر');
      expect(HabitCue.preset('asr').labelForLocale(true), 'العصر');
      expect(HabitCue.preset('maghrib').labelForLocale(true), 'المغرب');
      expect(HabitCue.preset('isha').labelForLocale(true), 'العشاء');
      expect(HabitCue.preset('before_sleep').labelForLocale(true), 'قبل النوم');
    });

    test('a picked time shows Arabic AM/PM markers', () {
      expect(HabitCue.time(7, 30).labelForLocale(true), '7:30 ص');
      expect(HabitCue.time(19, 5).labelForLocale(true), '7:05 م');
      expect(HabitCue.time(0, 0).labelForLocale(true), '12:00 ص');
      expect(HabitCue.time(12, 0).labelForLocale(true), '12:00 م');
    });
  });

  group('HabitCue — English label display', () {
    test('every preset has a correct English label', () {
      expect(HabitCue.preset('fajr').labelForLocale(false), 'Fajr');
      expect(HabitCue.preset('maghrib').labelForLocale(false), 'Maghrib');
      expect(HabitCue.preset('before_sleep').labelForLocale(false), 'Before sleep');
    });

    test('a picked time shows English AM/PM markers', () {
      expect(HabitCue.time(7, 30).labelForLocale(false), '7:30 AM');
      expect(HabitCue.time(19, 5).labelForLocale(false), '7:05 PM');
    });
  });

  group('HabitCue — language switching does not strand old habits', () {
    test('the same stored value relabels correctly in both languages '
        'without touching storage', () {
      final cue = HabitCue.fromStoredValue('maghrib');
      expect(cue.labelForLocale(true), 'المغرب');
      expect(cue.labelForLocale(false), 'Maghrib');
      // Same storage value regardless of which language it's being viewed
      // in right now — nothing to migrate when the user flips the toggle.
      expect(cue.toStorageValue(), 'maghrib');
    });

    test('a picked time relabels in both languages from one stored value', () {
      final cue = HabitCue.fromStoredValue('custom_time:19:05');
      expect(cue.labelForLocale(false), '7:05 PM');
      expect(cue.labelForLocale(true), '7:05 م');
    });
  });

  group('HabitCue — legacy stored values still work', () {
    test('old English chip text ("Maghrib") resolves to the same preset '
        'as the canonical key', () {
      final legacy = HabitCue.fromStoredValue('Maghrib');
      final canonical = HabitCue.fromStoredValue('maghrib');
      expect(legacy.toStorageValue(), canonical.toStorageValue());
      expect(legacy.labelForLocale(true), 'المغرب');
      expect(legacy.labelForLocale(false), 'Maghrib');
    });

    test('every legacy English prayer name normalizes to its canonical key',
        () {
      expect(HabitCue.fromStoredValue('Fajr').toStorageValue(), 'fajr');
      expect(HabitCue.fromStoredValue('Dhuhr').toStorageValue(), 'dhuhr');
      expect(HabitCue.fromStoredValue('Asr').toStorageValue(), 'asr');
      expect(HabitCue.fromStoredValue('Isha').toStorageValue(), 'isha');
      expect(HabitCue.fromStoredValue('Before sleep').toStorageValue(),
          'before_sleep');
    });

    // The exact bug this refactor fixes: for a short window, the app stored
    // the Arabic label text directly (e.g. "المغرب", "قبل النوم") instead of
    // a stable key. Those existing Firestore/Hive records must keep working.
    test('Arabic text stored by the previous (pre-refactor) version still '
        'normalizes to the canonical key', () {
      expect(HabitCue.fromStoredValue('المغرب').toStorageValue(), 'maghrib');
      expect(HabitCue.fromStoredValue('قبل النوم').toStorageValue(),
          'before_sleep');
      expect(HabitCue.fromStoredValue('الفجر').toStorageValue(), 'fajr');
      // And it displays correctly in *either* language from here on, not
      // just the one it happened to be saved in.
      expect(HabitCue.fromStoredValue('المغرب').labelForLocale(false),
          'Maghrib');
    });

    test('legacy English time strings ("7:30 AM") normalize to the '
        'canonical 24h value', () {
      expect(HabitCue.fromStoredValue('7:30 AM').toStorageValue(),
          'custom_time:07:30');
      expect(HabitCue.fromStoredValue('7:30 PM').toStorageValue(),
          'custom_time:19:30');
      expect(HabitCue.fromStoredValue('12:00 AM').toStorageValue(),
          'custom_time:00:00');
    });

    test('legacy Arabic time strings ("7:30 ص") normalize to the same '
        'canonical 24h value', () {
      expect(HabitCue.fromStoredValue('7:30 ص').toStorageValue(),
          'custom_time:07:30');
      expect(HabitCue.fromStoredValue('7:30 م').toStorageValue(),
          'custom_time:19:30');
    });
  });

  group('HabitCue — freeform text passes through unchanged', () {
    test('text that matches no known preset or time pattern is left as-is '
        'in both languages', () {
      final cue = HabitCue.fromStoredValue('your quiet study block');
      expect(cue.toStorageValue(), 'your quiet study block');
      expect(cue.labelForLocale(true), 'your quiet study block');
      expect(cue.labelForLocale(false), 'your quiet study block');
    });
  });

  group('HabitCue — empty handling', () {
    test('null and blank input are both empty', () {
      expect(HabitCue.fromStoredValue(null).isEmpty, isTrue);
      expect(HabitCue.fromStoredValue('').isEmpty, isTrue);
      expect(HabitCue.fromStoredValue('   ').isEmpty, isTrue);
    });

    test('a real cue is not empty', () {
      expect(HabitCue.fromStoredValue('maghrib').isEmpty, isFalse);
    });
  });

  group('HabitCue — preview sentence grammar', () {
    test('Arabic preview leads with "بعد" for a plain prayer cue', () {
      final cue = HabitCue.fromStoredValue('maghrib');
      expect(cue.previewTextForLocale(true, 'قراءة سورة الملك'),
          'بعد المغرب، سأقوم بـ قراءة سورة الملك.');
    });

    test('Arabic preview does not double-prefix a cue with its own '
        'preposition ("before sleep")', () {
      final cue = HabitCue.fromStoredValue('before_sleep');
      final preview = cue.previewTextForLocale(true, 'قراءة سورة الملك');
      expect(preview, isNot(contains('بعد قبل')));
      expect(preview, startsWith('قبل النوم'));
    });

    test('English preview leads with "After" for a plain prayer cue', () {
      final cue = HabitCue.fromStoredValue('maghrib');
      expect(cue.previewTextForLocale(false, 'read Surat Al-Mulk'),
          'After Maghrib, I will read Surat Al-Mulk.');
    });

    test('empty cue has no preview text', () {
      expect(HabitCue.empty.previewTextForLocale(true, 'X'), '');
    });
  });
}
