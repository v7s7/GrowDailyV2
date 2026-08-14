/// Formats an "N / M" progress fraction so it survives an Arabic (RTL)
/// paragraph with its two numbers still in the order they were written.
///
/// Why this exists: a bare `'$current / $total'` is laid out by the Unicode
/// bidi algorithm as three separate runs — the number, the separator, the
/// number. Digits are *weak* characters (bidi class EN) and `/` is a common
/// separator (CS); neither carries a strong direction of its own, so inside
/// an RTL paragraph the whole group inherits the paragraph's direction and
/// the runs are painted right-to-left. "0 / 100" therefore renders on screen
/// as "100 / 0" — an XP bar that reads as 100 out of 0, an achievements
/// counter that reads as 47 of 3. Found on Profile's level row on a real
/// device; the same pattern was in five places.
///
/// The fix is to isolate the fraction in its own left-to-right embedding:
/// U+2066 LEFT-TO-RIGHT ISOLATE opens it, U+2069 POP DIRECTIONAL ISOLATE
/// closes it. "Isolate" rather than the older LRE/PDF *embedding* controls
/// on purpose — an isolate is invisible to the surrounding text's own
/// ordering, so the label sitting next to the fraction keeps flowing
/// right-to-left exactly as before. Both characters are zero-width and
/// change nothing in English, where the run order was already correct.
///
/// A plain function, not a widget, because two of the call sites hand the
/// string to another widget as a parameter (NightReview's stat `value:`,
/// QuickWins' `progressText:`) and never get to set a `textDirection` on the
/// Text that eventually renders it.
library;

const String _lri = '⁦'; // LEFT-TO-RIGHT ISOLATE
const String _pdi = '⁩'; // POP DIRECTIONAL ISOLATE

/// Wraps an already-built fraction string in a left-to-right isolate.
///
/// Use when the caller needs a separator other than the default, e.g.
/// `bidiIsolate('$done of $total')`.
String bidiIsolate(String text) => '$_lri$text$_pdi';

/// "3 / 10" — kept in that order in both languages.
///
/// [separator] defaults to a spaced slash; pass `'/'` for the tight form
/// some cards use.
String progressFraction(Object current, Object total,
        {String separator = ' / '}) =>
    bidiIsolate('$current$separator$total');
