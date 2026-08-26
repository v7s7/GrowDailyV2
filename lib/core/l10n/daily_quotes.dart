/// The line of the day shown above the board on Grid.
///
/// ── Why one list, not two ───────────────────────────────────────────────
/// Every other bilingual string in this app branches on `isAr` inside its own
/// getter (see app_strings.dart), which works because each getter owns exactly
/// one sentence. A rotating set cannot be written that way: two parallel
/// `const [...]` lists, one per language, are two things that must stay the
/// same length AND stay in the same order forever, and nothing would catch it
/// the day they stopped. Somebody inserting a quote into the Arabic list only
/// would silently shift every later day onto a mismatched pair, so the Arabic
/// reader and the English reader would be shown different quotes on the same
/// day, and switching language mid-day would change the line.
///
/// Pairing the two languages in one entry makes that unrepresentable: an entry
/// physically cannot exist in one language and not the other.
///
/// ── Why the day picks the quote, not a shuffle ──────────────────────────
/// [quoteForDay] is a pure function of the date, so the line is the same all
/// day, on every screen, on every device the account is signed in to, and it
/// changes when the app's day changes rather than at midnight or on rebuild.
/// A random pick would re-roll on every widget rebuild, which on a scrolling
/// board means the quote flickering between lines as you scroll.
library;

/// One quote, in both languages, with an optional attribution.
///
/// [sourceAr]/[sourceEn] are set only where the words are someone else's and
/// saying so matters: the hadith, and traditional proverbs. Lines written for
/// this app carry no source, because inventing an attribution for them would
/// be worse than leaving it off.
class DailyQuote {
  final String ar;
  final String en;
  final String? sourceAr;
  final String? sourceEn;

  const DailyQuote({
    required this.ar,
    required this.en,
    this.sourceAr,
    this.sourceEn,
  });

  /// The quote text in the reader's language.
  String text(bool isAr) => isAr ? ar : en;

  /// The attribution in the reader's language, or null when the line has none.
  String? source(bool isAr) => isAr ? sourceAr : sourceEn;
}

/// The rotation. Roughly a month long, so a daily line does not repeat inside
/// the same month.
///
/// Arabic is Bahraini/Gulf, matching the app's newer copy rather than the older
/// MSA it still carries in places. Order is not meaningful: [quoteForDay] walks
/// the list one entry per day, so appending is always safe, and inserting in
/// the middle only shifts which day shows what.
const List<DailyQuote> kDailyQuotes = [
  DailyQuote(
    ar: 'عاداتك هي اللي تبنيك.',
    en: 'Your habits build you.',
  ),
  DailyQuote(
    ar: 'لمن تغيّر عاداتك، كل شي يتغيّر.',
    en: 'When you change your habits, everything shifts.',
  ),
  DailyQuote(
    ar: 'أحب الأعمال إلى الله أدومها وإن قلّ.',
    en: 'The deeds most beloved to Allah are the most constant, even if small.',
    sourceAr: 'متفق عليه',
    sourceEn: 'Bukhari and Muslim',
  ),
  DailyQuote(
    ar: 'قطرة قطرة يمتلئ النهر.',
    en: 'Drop by drop, the river fills.',
    sourceAr: 'مثل',
    sourceEn: 'Proverb',
  ),
  DailyQuote(
    ar: 'من جدّ وجد.',
    en: 'Whoever strives, finds.',
    sourceAr: 'مثل',
    sourceEn: 'Proverb',
  ),
  DailyQuote(
    ar: 'الصغير اللي تكرره أقوى من الكبير اللي تسويه مرة وحدة.',
    en: 'The small thing you repeat beats the big thing you do once.',
  ),
  DailyQuote(
    ar: 'ما تحتاج تكون مثالي، تحتاج تستمر.',
    en: 'You do not need to be perfect. You need to keep going.',
  ),
  DailyQuote(
    ar: 'يوم واحد ما يغيّر شي، بس الأيام كلها تغيّر كل شي.',
    en: 'One day changes nothing. All the days change everything.',
  ),
  DailyQuote(
    ar: 'ابدأ صغير، بس ابدأ اليوم.',
    en: 'Start small, but start today.',
  ),
  DailyQuote(
    ar: 'اللي يفوتك اليوم ترجعه باچر، المهم ما توقف.',
    en: 'What you miss today you pick up tomorrow. What matters is not stopping.',
  ),
  DailyQuote(
    ar: 'التقدم مو خط مستقيم.',
    en: 'Progress is not a straight line.',
  ),
  DailyQuote(
    ar: 'عاداتك هي اللي تقرر شكل سنتك.',
    en: 'Your habits decide what your year looks like.',
  ),
  DailyQuote(
    ar: 'الانضباط أحلى من الندم.',
    en: 'Discipline tastes better than regret.',
  ),
  DailyQuote(
    ar: 'مربّع واحد اليوم أحسن من خطة كاملة باچر.',
    en: 'One square today beats a perfect plan tomorrow.',
  ),
  DailyQuote(
    ar: 'اللي تسويه كل يوم هو اللي يصير أنت.',
    en: 'What you do every day is what you become.',
  ),
  DailyQuote(
    ar: 'الاستمرار أهم من الحماس.',
    en: 'Consistency matters more than motivation.',
  ),
  DailyQuote(
    ar: 'ما في شي كبير إلا وبدايته صغيرة.',
    en: 'Nothing big ever started big.',
  ),
  DailyQuote(
    ar: 'الوقت بيمر على كل حال، خلّه يمر وأنت تبني.',
    en: 'Time passes either way. Let it pass while you build.',
  ),
  DailyQuote(
    ar: 'أصعب خطوة هي الأولى، والباقي عادة.',
    en: 'The hardest step is the first. The rest is habit.',
  ),
  DailyQuote(
    ar: 'لا تقارن يومك الأول بيوم غيرك المية.',
    en: "Do not compare your first day to someone else's hundredth.",
  ),
  DailyQuote(
    ar: 'رجوعك بعد الانقطاع أقوى شي تسويه.',
    en: 'Coming back after a break is the strongest thing you do.',
  ),
  DailyQuote(
    ar: 'خلّها سهلة عشان تكملها.',
    en: 'Make it easy so you keep it.',
  ),
  DailyQuote(
    ar: 'النية بلا عمل أمنية.',
    en: 'Intention without action is just a wish.',
  ),
  DailyQuote(
    ar: 'اللي يزرع كل يوم، يحصد كل سنة.',
    en: 'Plant every day, harvest every year.',
  ),
  DailyQuote(
    ar: 'ما يهم شقد رحت بعيد، يهم إنك ما وقفت.',
    en: 'It is not how far you got. It is that you did not stop.',
  ),
];

/// The day the rotation is counted from. Arbitrary and fixed: only the
/// DISTANCE from it matters, and pinning it keeps the same date showing the
/// same quote across releases and devices.
final DateTime _rotationEpoch = DateTime.utc(2026, 1, 1);

/// The quote for [day].
///
/// [day] is an app day, not a raw clock reading, so callers pass
/// `DateTime.now().effectiveDay` (see DateTimeGameExt.effectiveDay). That is
/// what makes the line change at the app's 6am cutoff along with everything
/// else, rather than at midnight, so somebody up at 2am still sees the line
/// that belongs to the day they are still living.
DailyQuote quoteForDay(DateTime day) => kDailyQuotes[_indexForDay(day)];

int _indexForDay(DateTime day) {
  // Compared in UTC so a daylight-saving shift cannot make a day 23 or 25
  // hours long and round the difference to the wrong number of days. Bahrain
  // does not observe DST, but an account travelling does, and a quote that
  // skipped or repeated a day would be a strange thing to have to explain.
  final days = DateTime.utc(day.year, day.month, day.day)
      .difference(_rotationEpoch)
      .inDays;
  // Dart's % is non-negative for a positive divisor, so dates before the
  // epoch wrap to the end of the list rather than throwing.
  return days % kDailyQuotes.length;
}
