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

/// One quote, in both languages. The line alone: no caption, no credit.
///
/// The screen used to carry a second line under some quotes (a name, "مثل"
/// for the proverbs, "متفق عليه" for the hadith, and for three lines a
/// "منسوب إلى" hedge because the author is not certain). Aziz removed all of
/// it on 2026-09-06: "just the quote, simple and clean". Where the words are
/// someone else's, a `// Source:` comment above the entry keeps the provenance
/// for whoever edits this file, so a hadith or a proverb is not "corrected" as
/// if it were app copy. That is the only place it lives now; do not bring the
/// caption back on screen, hedged or plain.
class DailyQuote {
  final String ar;
  final String en;

  const DailyQuote({required this.ar, required this.en});

  /// The quote text in the reader's language.
  String text(bool isAr) => isAr ? ar : en;
}

/// The rotation. Longer than the longest month, so a daily line cannot repeat
/// inside one.
///
/// Arabic here is EASY SPOKEN Arabic, not Modern Standard. Aziz chose every
/// UNATTRIBUTED line in this list himself on 2026-09-01 (the attributed ones
/// arrived later, see below), so treat that wording as settled
/// and do not "correct" it toward MSA: اللي, شي, مو, عشان, خلّها and تسويه are
/// all deliberate, because they are how the sentence is actually said and are
/// understood far beyond the Gulf.
///
/// Two things he did change, and they are the rule for new lines: spell it
/// باجر, never باچر, because چ is not a letter most readers can scan; and take
/// the plainer word where it genuinely reads better (أفضل over أحسن, ما تصبح
/// عليه over اللي يصير أنت, لا يهم كم قطعت over ما يهم شقد رحت).
///
/// The hadith and the two proverbs below are quoted, not written for this app,
/// so they keep their own wording.
///
/// The eight attributed lines came from Aziz on 2026-09-04, in English. Their
/// Arabic is a TRANSLATION and therefore still a register choice, which is why
/// it reads like the rest of the list rather than like a formal rendering: a
/// stiff sentence under a name would only announce that these came from
/// somewhere else. That Arabic is mine and not yet his, so it is the one part
/// of this file that is not settled.
///
/// They are threaded through the list rather than appended, because appending
/// would have made the rotation's last eight days a solid run of credited
/// Western authors and the twenty-five before it a run without one. Two pairs
/// say nearly the same thing and are deliberately kept apart: Maxwell against
/// 'When you change your habits, everything shifts', and Durant against 'What
/// you do every day is what you become'.
///
/// Order is not otherwise meaningful: [quoteForDay] walks the list one entry
/// per day, so appending is always safe, and inserting in the middle only
/// shifts which day shows what.
const List<DailyQuote> kDailyQuotes = [
  DailyQuote(
    ar: 'عاداتك هي اللي تبنيك.',
    en: 'Your habits build you.',
  ),
  DailyQuote(
    ar: 'يوم تغيّر عاداتك، كل شي يتغيّر.',
    en: 'When you change your habits, everything shifts.',
  ),
  // Source: Bukhari and Muslim (متفق عليه). Not shown on screen.
  DailyQuote(
    ar: 'أحب الأعمال إلى الله أدومها وإن قلّ.',
    en: 'The deeds most beloved to Allah are the most constant, even if small.',
  ),
  // Source: Proverb (مثل). Not shown on screen.
  DailyQuote(
    ar: 'قطرة قطرة يمتلئ النهر.',
    en: 'Drop by drop, the river fills.',
  ),
  // Source: Proverb (مثل). Not shown on screen.
  DailyQuote(
    ar: 'من جدّ وجد.',
    en: 'Whoever strives, finds.',
  ),
  DailyQuote(
    ar: 'الصغير اللي تكرره أقوى من الكبير اللي تسويه مرة وحدة.',
    en: 'The small thing you repeat beats the big thing you do once.',
  ),
  // Jim RYUN, the runner, not Jim Rohn two entries down. The two names
  // are swapped constantly online; keep them apart.
  // Source: Jim Ryun (جيم راين). Not shown on screen.
  DailyQuote(
    ar: 'الحماس هو اللي يخليك تبدأ، والعادة هي اللي تخليك تستمر.',
    en: 'Motivation is what gets you started. Habit is what keeps you going.',
  ),
  DailyQuote(
    ar: 'ما تحتاج تكون مثالي، تحتاج تستمر.',
    en: 'You do not need to be perfect. You need to keep going.',
  ),
  // The longest line in the rotation, and deliberately not trimmed: the
  // sentence only works because the second half mirrors the first.
  // Source: Jim Rohn (جيم رون). Not shown on screen.
  DailyQuote(
    ar: 'النجاح أشياء بسيطة تلتزم بها كل يوم، والفشل أخطاء في التقدير تكررها كل يوم.',
    en: 'Success is a few simple disciplines practiced every day; while failure is simply a few errors in judgment repeated every day.',
  ),
  DailyQuote(
    ar: 'يوم واحد ما بيغيّر شي، بس الاستمرارية تغيّر كل شي.',
    en: 'One day changes nothing. Consistency changes everything.',
  ),
  DailyQuote(
    ar: 'ابدأ بشيء صغير، لكن ابدأ اليوم.',
    en: 'Start small, but start today.',
  ),
  // Source: Samuel Johnson (صمويل جونسون). Not shown on screen.
  DailyQuote(
    ar: 'سلاسل العادة أضعف من أن تُحس، حتى تصير أقوى من أن تنكسر.',
    en: 'The chains of habit are too weak to be felt until they are too strong to be broken.',
  ),
  DailyQuote(
    ar: 'اللي يفوتك اليوم ترجعه باجر، المهم ما توقف.',
    en: 'What you miss today you pick up tomorrow. What matters is not stopping.',
  ),
  DailyQuote(
    ar: 'التقدم مو خط مستقيم.',
    en: 'Progress is not a straight line.',
  ),
  // Source: John C. Maxwell (جون ماكسويل). Not shown on screen.
  DailyQuote(
    ar: 'ما تتغيّر حياتك إلا يوم تغيّر شي تسويه كل يوم.',
    en: 'You will never change your life until you change something you do daily.',
  ),
  DailyQuote(
    ar: 'عاداتك هي التي تحدد شكلك.',
    en: 'Your habits decide what your year looks like.',
  ),
  DailyQuote(
    ar: 'الانضباط أحلى من الندم.',
    en: 'Discipline tastes better than regret.',
  ),
  // Source: Benjamin Franklin (بنجامين فرانكلين). Not shown on screen.
  DailyQuote(
    ar: 'منع العادة السيئة أسهل من كسرها.',
    en: 'It is easier to prevent bad habits than to break them.',
  ),
  DailyQuote(
    ar: 'مربّع واحد اليوم أفضل من خطة كاملة باجر.',
    en: 'One square today beats a perfect plan tomorrow.',
  ),
  DailyQuote(
    ar: 'ما تفعله كل يوم هو ما تصبح عليه.',
    en: 'What you do every day is what you become.',
  ),
  DailyQuote(
    ar: 'الاستمرار أهم من الحماس.',
    en: 'Consistency matters more than motivation.',
  ),
  // Rohn's own contraction. The rest of this app spells out 'do not',
  // but a quotation is not ours to restyle.
  // Source: Jim Rohn (جيم رون). Not shown on screen.
  DailyQuote(
    ar: 'لا تتمنى الأمور أسهل، تمنى نفسك أفضل. ولا تتمنى مشاكل أقل، تمنى مهارات أكثر.',
    en: "Don't wish it were easier, wish you were better. Don't wish for fewer problems, wish for more skills.",
  ),
  DailyQuote(
    ar: 'ما في شي كبير إلا وبدايته صغيرة.',
    en: 'Nothing big ever started big.',
  ),
  DailyQuote(
    ar: 'الوقت بيمر على كل حال، خلّه يمر وأنت تبني.',
    en: 'Time passes either way. Let it pass while you build.',
  ),
  // Durant, NOT Aristotle. These are Durant's words in The Story of
  // Philosophy (1926) summarising the Nicomachean Ethics; Aristotle
  // never wrote the sentence. Do not 'correct' the attribution.
  // Source: Will Durant (ويل ديورانت). Not shown on screen.
  DailyQuote(
    ar: 'نحن نتيجة ما نكرره. والتميّز مو فعل، بل عادة.',
    en: 'We are what we repeatedly do. Excellence, then, is not an act, but a habit.',
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
  // Source: Robert Collier (روبرت كولير). Not shown on screen.
  DailyQuote(
    ar: 'النجاح مجموع جهود صغيرة تتكرر يوم بعد يوم.',
    en: 'Success is the sum of small efforts, repeated day in and day out.',
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
    ar: 'لا يهم كم قطعت من المسافة، المهم أنك لم تتوقف.',
    en: 'It is not how far you got. It is that you did not stop.',
  ),
  // Aziz's three, 2026-09-06. He sent them long; these are the short forms.
  DailyQuote(
    ar: 'مع الانضباط تتشابه أيامك، ومن دونه تتشابه سنينك.',
    en: 'With discipline, every day looks the same. Without it, every year does.',
  ),
  DailyQuote(
    ar: 'الانضباط أملّ شي، ونتيجته أحلى شي.',
    en: 'Discipline is boring. Its results never are.',
  ),
  DailyQuote(
    ar: 'إذا تبي تغيّر حياتك، عِش نفس الانضباط كل يوم.',
    en: 'To change your life, live the same discipline every single day.',
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
/// what makes the line change at the app's 10 AM cutoff along with everything
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
