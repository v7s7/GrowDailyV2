// Which of my habits a room's plan entry is, when the leader named it
// differently (habit_name_match.dart, behind suggestExistingMatch).
//
// Aziz, 2026-09-24: a leader added «الضحى» and «الوتر» to a room and the
// link sheet offered nothing, though he had «صلاة الضحى» and «صلاة الوتر».
// The first test is that room, with his own habit list from the screenshot.
//
// The other half matters as much: a guess is pre-selected in the sheet, so
// a wrong one links the wrong habit unless the person notices. Every pair
// that names two DIFFERENT habits is pinned to "no guess" here: the sunnah
// and the obligatory prayer, morning and evening adhkar, doing a thing and
// quitting it, reading the Quran and memorising it.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/habit_name_match.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';

IslamicHabitTemplate _habit(String name, {String? id, String? nameAr}) =>
    IslamicHabitTemplate(
      id: id ?? 'h_$name',
      name: name,
      nameAr: nameAr,
      description: '',
      category: HabitCategory.custom,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 10,
      goldReward: 5,
    );

/// Aziz's habits, in the order his link sheet listed them.
final _mine = [
  _habit('سنة الفجر'),
  _habit('أذكار الصباح'),
  _habit('صلاة الضحى'),
  _habit('الصدقة ولو بالقليل'),
  _habit('قراءة القرآن'),
  _habit('تنعيم اللحية'),
  _habit('اخذ كرياتين'),
  _habit('تمرين'),
  _habit('صلاة الوتر'),
  _habit('شامبو ضد القشرة'),
  _habit('سورة الملك'),
];

String? _pick(String planName, [List<IslamicHabitTemplate>? mine]) =>
    suggestExistingMatch(planName, mine ?? _mine)?.name;

void main() {
  test('the room in the screenshot: each new plan habit finds the one it is',
      () {
    expect(_pick('الضحى'), 'صلاة الضحى');
    expect(_pick('الوتر'), 'صلاة الوتر');
    expect(_pick('سنة الفجر'), 'سنة الفجر');
    // He has nothing for the after-Dhuhr sunnah: "add as new" stays.
    expect(_pick('سنة الظهر البعدية'), isNull);
  });

  group('two different habits are never offered for each other', () {
    const different = [
      ['سنة الفجر', 'صلاة الفجر'],
      ['صلاة الفجر', 'سنة الفجر'],
      ['أذكار الصباح', 'أذكار المساء'],
      ['أذكار الصباح والمساء', 'أذكار الصباح'],
      ['التدخين', 'ترك التدخين'],
      ['قراءة القرآن', 'حفظ القرآن'],
      ['القراءة', 'قراءة القرآن'],
      ['صلاة الظهر', 'صلاة العصر'],
      ['سنة الظهر', 'سنة العصر'],
      ['سنة الظهر البعدية', 'سنة الظهر'],
      ['تمرين', 'تنعيم اللحية'],
      ['Sugar', 'No Added Sugar'],
      ['Morning Athkar', 'Evening Athkar'],
    ];
    for (final pair in different) {
      test('«${pair[0]}» and «${pair[1]}»', () {
        expect(habitNameMatchScore(pair[0], pair[1]), 0);
        expect(habitNameMatchScore(pair[1], pair[0]), 0);
        expect(_pick(pair[0], [_habit(pair[1])]), isNull);
      });
    }
  });

  test('spelling that does not change a word is the same name', () {
    const same = [
      ['صَلاةُ الضُّحى', 'صلاه الضحي'],
      ['أذكار الصباح', 'اذكار الصباح'],
      ['إستغفار', 'استغفار'],
      ['القرآن', 'القران'],
      ['الوتـــر', 'الوتر'],
      ['قراءة ١٠ صفحات', 'قراءة 10 صفحات'],
      ['  Read   Quran ', 'read quran'],
      ['سنة الفجر!', 'سنة الفجر'],
    ];
    for (final pair in same) {
      expect(
        habitNameMatchScore(pair[0], pair[1]),
        kHabitMatchExact,
        reason: '${pair[0]} / ${pair[1]}',
      );
    }
  });

  test('«صلاة», «ركعتين» and the article say nothing about which habit', () {
    expect(habitNameMatchScore('الضحى', 'صلاة الضحى'), kHabitMatchSameHabit);
    expect(
      habitNameMatchScore('ركعتين الضحى', 'صلاة الضحى'),
      kHabitMatchSameHabit,
    );
    expect(habitNameMatchScore('المشي', 'المشي يوميا'), kHabitMatchSameWords);
    expect(habitNameMatchScore('كتاب', 'قراءة كتاب'), kHabitMatchSameWords);
  });

  test('a few extra words that do not change the habit still match', () {
    expect(
      habitNameMatchScore('الصدقة', 'الصدقة ولو بالقليل'),
      kHabitMatchExtraWords,
    );
    expect(habitNameMatchScore('كرياتين', 'اخذ كرياتين'), kHabitMatchExtraWords);
    expect(
      habitNameMatchScore('صلاة الفجر', 'صلاة الفجر في المسجد'),
      kHabitMatchExtraWords,
    );
    expect(_pick('الصدقة'), 'الصدقة ولو بالقليل');
    expect(_pick('كرياتين'), 'اخذ كرياتين');
  });

  test('one habit named in Arabic and in English', () {
    const same = [
      ['الوتر', 'Witr'],
      ['قيام الليل', 'صلاة التهجد'],
      ['Tahajjud', 'قيام الليل'],
      ['Qiyam', 'التهجد'],
      ['Duha Prayer', 'الضحى'],
      ['Morning Athkar', 'أذكار الصباح'],
      ['Morning azkar', 'اذكار الصبح'],
      ['Surah Al-Mulk', 'سورة الملك'],
      ['ورد القرآن', 'قراءة القرآن'],
      ['Read Quran', 'تلاوة القرآن'],
      ['صوم الاثنين والخميس', 'Monday & Thursday Fast'],
      ['Charity', 'الصدقة'],
    ];
    for (final pair in same) {
      expect(
        habitNameMatchScore(pair[0], pair[1]),
        kHabitMatchSameHabit,
        reason: '${pair[0]} / ${pair[1]}',
      );
    }
  });

  group('a catalog habit is found by what it is, not what it is called now',
      () {
    final fajr = IslamicHabitCatalog.templates.firstWhere(
      (t) => t.id == 'prayer_fajr',
    );
    test('the plan names it in either catalog language or a common name', () {
      expect(catalogHabitIdFor('صلاة الفجر'), 'prayer_fajr');
      expect(catalogHabitIdFor('Fajr Prayer'), 'prayer_fajr');
      expect(catalogHabitIdFor('الفجر'), 'prayer_fajr');
      expect(catalogHabitIdFor('أذكار الصباح'), 'morning_athkar');
      expect(catalogHabitIdFor('الضحى'), isNull, reason: 'not a catalog habit');
    });
    test('the Arabic catalog name matches when the plan is in Arabic', () {
      expect(
        suggestExistingMatch('صلاة الفجر', [_habit('تمرين'), fajr]),
        same(fajr),
      );
    });
    test('a preset this person renamed is still found by its id', () {
      final renamed = _habit('فجري بالمسجد', id: 'prayer_fajr');
      expect(suggestExistingMatch('صلاة الفجر', [renamed])?.id, 'prayer_fajr');
      expect(suggestExistingMatch('الفجر', [renamed])?.id, 'prayer_fajr');
      // A custom habit that merely LOOKS like it is not a catalog habit.
      expect(suggestExistingMatch('الضحى', [renamed]), isNull);
    });
  });

  test('a typo still finds the habit, with less certainty than a match', () {
    final typo = habitNameMatchScore('صلاة الضجى', 'صلاة الضحى');
    expect(typo, greaterThan(0));
    expect(typo, lessThan(kHabitMatchTypo));
    expect(
      habitNameMatchScore('Gym Consistancy', 'Gym Consistency'),
      greaterThan(0),
    );
    // Not a typo: two prayers three letters apart.
    expect(habitNameMatchScore('سنة الظهر', 'سنة العصر'), 0);
  });

  test('the surest match wins, and a tie goes to the habit listed first', () {
    final both = [_habit('صلاة الفجر'), _habit('سنة الفجر')];
    expect(_pick('سنة الفجر', both), 'سنة الفجر');
    expect(_pick('الفجر', both), 'صلاة الفجر');
    final twoShampoos = [_habit('شامبو ضد القشرة'), _habit('شامبو للشعر')];
    expect(_pick('شامبو', twoShampoos), 'شامبو ضد القشرة');
    final exactLater = [_habit('صلاة الضحى'), _habit('الضحى')];
    expect(_pick('الضحى', exactLater), 'الضحى');
  });

  test('no two groups of same-habit names share a name', () {
    // «ركعتا الفجر» once did: with «ركعتا» dropped as filler it read as
    // «الفجر», and the sunnah and the obligatory prayer became one habit.
    expect(sameHabitTableConflicts(), isEmpty);
  });

  group('conflicts', _conflictTests);

  test('nothing to compare is no guess', () {
    expect(suggestExistingMatch('الضحى', const []), isNull);
    expect(suggestExistingMatch('', _mine), isNull);
    expect(suggestExistingMatch('   ', _mine), isNull);
    expect(habitNameMatchScore('الضحى', ''), 0);
  });
}

// ── Conflicts: the whole plan settled at once (suggestPlanMatches) ──────

List<String?> _ids(List<PlanMatch> matches) =>
    [for (final m in matches) m.habitId];

void _conflictTests() {
  test('a row two habits fit equally opens on neither, and names both', () {
    final mine = [_habit('صلاة الضحى'), _habit('الضحى ركعتين'), _habit('تمرين')];
    final m = suggestPlanMatches(['الضحى'], mine);
    expect(m.single.habitId, isNull);
    expect(m.single.tornBetween, ['h_صلاة الضحى', 'h_الضحى ركعتين']);
    expect(m.single.isTorn, isTrue);
  });

  test('a habit goes to the row it fits best, not the first row listed', () {
    // «صلاة الضحى» is exactly the second row and only an alias of the first.
    final mine = [_habit('صلاة الضحى')];
    final m = suggestPlanMatches(['الضحى', 'صلاة الضحى'], mine);
    expect(_ids(m), [null, 'h_صلاة الضحى']);
  });

  test('a clear row settles first, which can leave a torn row one choice',
      () {
    // Row 0 fits both Duha habits equally; row 1 is exactly one of them.
    final mine = [_habit('صلاة الضحى'), _habit('ركعتين الضحى')];
    final m = suggestPlanMatches(['الضحى', 'ركعتين الضحى'], mine);
    expect(_ids(m), ['h_صلاة الضحى', 'h_ركعتين الضحى']);
    expect(m.every((x) => !x.isTorn), isTrue);
  });

  test('a torn row holds its habits back from a weaker row', () {
    final mine = [_habit('صلاة الضحى'), _habit('الضحى ركعتين')];
    // Row 1 would take «صلاة الضحى» on a weaker match if row 0 let it go.
    final m = suggestPlanMatches(['الضحى', 'صلاة الضحى في البيت'], mine);
    expect(m[0].isTorn, isTrue);
    expect(m[1].habitId, isNull);
  });

  test('never one habit for two rows, and taken habits are never offered',
      () {
    final mine = [_habit('صلاة الوتر'), _habit('سنة الفجر')];
    final m = suggestPlanMatches(['الوتر', 'Witr', 'سنة الفجر'], mine,
        taken: {'h_سنة الفجر'});
    final ids = _ids(m).whereType<String>().toList();
    expect(ids.toSet().length, ids.length);
    expect(ids, isNot(contains('h_سنة الفجر')));
    expect(m[2].habitId, isNull);
  });

  test('rows not asked about stay empty', () {
    final m = suggestPlanMatches([null, 'الوتر'], [_habit('صلاة الوتر')]);
    expect(_ids(m), [null, 'h_صلاة الوتر']);
    expect(m[0].isTorn, isFalse);
  });

  test('the screenshot room, settled at once, is unchanged', () {
    final m = suggestPlanMatches(
      ['سنة الظهر البعدية', 'سنة الفجر', 'الضحى', 'الوتر'],
      _mine,
    );
    expect(_ids(m), [null, 'h_سنة الفجر', 'h_صلاة الضحى', 'h_صلاة الوتر']);
  });
}
