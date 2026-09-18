import '../l10n/reminder_copy.dart' show ReminderUnit;
import 'western_digits.dart';

/// The Arabic decimal separator, which an Arabic decimal keypad types
/// instead of a point. Built from its code point: as a literal it is easy to
/// misread as a comma.
final String _arabicDecimalSeparator = String.fromCharCode(0x066B);

/// The minutes a typed reminder shift comes to: "4.5" under hours is 270.
///
/// Both custom shift fields read through this one rule, Add Habit's offset
/// sheet and a task's custom reminder sheet, so a value means the same in
/// each. Hours and days take a fraction, which is how people say them. Both
/// fields used to take whole numbers only, on a keypad with no point, so a
/// 4.5-hour reminder had to be worked out by hand in minutes, and Aziz's
/// came out as 260, ten short (2026-09-18).
///
/// The point is whatever the keypad gives: "." on most, the Arabic decimal
/// separator on an Arabic one, "," where decimals are written that way.
/// Arabic-Indic digits count the same as Latin ones. The result is rounded
/// to the whole minute a reminder is kept in. Null for anything that is not
/// one positive amount: empty, a second point, zero, or under half a minute.
int? typedOffsetMinutes(String text, ReminderUnit unit) {
  final normalized = toWesternDigits(text.trim())
      .replaceAll(_arabicDecimalSeparator, '.')
      .replaceAll(',', '.');
  // Digits and at most one point, and at least one digit. Checked before
  // parsing because double.tryParse also takes "1e2" and "Infinity".
  if (!RegExp(r'^(\d+\.?\d*|\.\d+)$').hasMatch(normalized)) return null;
  final value = double.tryParse(normalized);
  // Finite too: a pasted run of 310 digits parses as Infinity, which
  // round() throws on, in a getter the sheet calls while it builds.
  if (value == null || !value.isFinite || value <= 0) return null;
  final minutes = (value * unit.inMinutes).round();
  return minutes > 0 ? minutes : null;
}
