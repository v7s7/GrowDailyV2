import 'package:intl/intl.dart';

/// Arabic-Indic digits (٠-٩) mapped to plain ASCII '0'-'9'. Every other
/// character passes through untouched, so running this on text that's
/// already ASCII is a no-op.
///
/// Two jobs, one function:
///
///  * **Parsing.** Arabic keyboards commonly default the numeric keypad to
///    ٠-٩, and `int.tryParse` / `RegExp(r'\d')` only ever understand ASCII —
///    so "٤٥" typed into a minutes field has to become 45, not fall through
///    as unparseable. Three separate call sites had each grown their own
///    copy of this loop (HabitCue._asciiDigits, room_model's
///    _normalizeDigits, reminder_picker's normalizeArabicDigits); they all
///    delegate here now.
///
///  * **Display.** Dates that went through `DateFormat` have been observed
///    rendering Arabic-Indic digits in the running app while every other
///    number on the same screen — counters, fractions, stat tiles, Grid's
///    day labels, all built with plain interpolation — stays ASCII. (Not
///    intl picking digits for the locale: `DateFormat('d', 'ar')` returns
///    the ASCII "3" in a plain test process; only 'ar_EG' and friends carry
///    Arabic-Indic symbol data. The substitution happens nearer the glyphs.)
///    [westernDate] pushes formatted dates through here so a composed date
///    keeps its locale-correct month and weekday *names* and still agrees
///    with the numbers printed next to it.
const String _arabicIndicDigits = '٠١٢٣٤٥٦٧٨٩';

/// A date formatted with [pattern] under [locale], with its digits
/// normalised to ASCII — Arabic month and weekday names, Western numbers.
///
/// A belt-and-braces wrapper: for the `ar` locale this app ships,
/// `DateFormat` already returns ASCII digits, so this is usually a no-op.
/// It exists because the *rendered* result has not always matched what
/// `DateFormat` returns (see the note above), and a composed date sitting
/// beside a plain interpolated number needs to agree with it. Cheap enough
/// to apply unconditionally; [toWesternDigits] returns the original string
/// untouched when there's nothing to convert.
String westernDate(DateTime date, String pattern, String locale) =>
    toWesternDigits(DateFormat(pattern, locale).format(date));

/// "الأحد، 19 يوليو" / "Sunday, Jul 19" — a weekday-plus-date label with
/// the right word order and the right comma for each language, and ASCII
/// digits in both.
///
/// Hand-rolled rather than one `DateFormat('EEEE, MMM d')` pattern shared
/// by both languages, because that pattern is wrong twice over in Arabic:
/// it puts the month before the day (Arabic reads "19 يوليو", not "يوليو
/// 19") and it hardcodes the Latin comma, which is not the character
/// Arabic uses. Both were shipping on the Habit Notes day headers and the
/// 14-day chart's day sheet.
String weekdayDateLabel(
  DateTime date, {
  required bool isAr,
  required String locale,
}) {
  final weekday = westernDate(date, 'EEEE', locale);
  final dayMonth = westernDate(date, isAr ? 'd MMMM' : 'MMM d', locale);
  return isAr ? '$weekday، $dayMonth' : '$weekday, $dayMonth';
}

String toWesternDigits(String input) {
  // Fast path: the overwhelming majority of strings this sees are already
  // ASCII, and rebuilding them character by character for nothing is wasted
  // work on a path that runs per-widget-build.
  if (!input.split('').any(_arabicIndicDigits.contains)) return input;
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final ch = String.fromCharCode(rune);
    final index = _arabicIndicDigits.indexOf(ch);
    buffer.write(index == -1 ? ch : index.toString());
  }
  return buffer.toString();
}
