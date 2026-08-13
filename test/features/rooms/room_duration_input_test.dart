// Pure-logic tests for RoomModel.parseCustomRoomDurationDays - the one
// function CreateRoomSheet's and the Extend sheet's "Custom" duration chip
// both funnel their TextField through (see each sheet's own duration
// section). Deliberately not a widget test: this codebase doesn't attempt
// to widget-test its bottom sheets (see rooms_notifier_test.dart's own doc
// comment on why Firestore/UI-backed behavior isn't unit tested here) - the
// actual decision logic worth pinning down is this one pure parse/validate
// step, which both sheets already trust as the single source of truth for
// what counts as a valid custom day count.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';

void main() {
  group('parseCustomRoomDurationDays', () {
    test('accepts a plain in-range value', () {
      expect(parseCustomRoomDurationDays('45'), 45);
    });

    test('accepts the minimum boundary, 1', () {
      expect(parseCustomRoomDurationDays('1'), 1);
    });

    test('accepts the maximum boundary, 365', () {
      expect(parseCustomRoomDurationDays('365'), 365);
    });

    test(
        'rejects zero - a room lasting less than a day is what '
        'RoomDuration.open is already for, not a fixed length of 0', () {
      expect(parseCustomRoomDurationDays('0'), isNull);
    });

    test('rejects one past the maximum, 366', () {
      expect(parseCustomRoomDurationDays('366'), isNull);
    });

    test('rejects a negative number', () {
      expect(parseCustomRoomDurationDays('-5'), isNull);
    });

    test('rejects a much larger, clearly-mistyped number', () {
      expect(parseCustomRoomDurationDays('999999999999'), isNull);
    });

    test(
        'rejects an empty string - the untouched-field state, not itself '
        'an error to show', () {
      expect(parseCustomRoomDurationDays(''), isNull);
    });

    test('rejects whitespace-only input', () {
      expect(parseCustomRoomDurationDays('   '), isNull);
    });

    test('trims surrounding whitespace from an otherwise-valid value', () {
      expect(parseCustomRoomDurationDays('  45  '), 45);
    });

    test('rejects a decimal - only whole days are a meaningful room length',
        () {
      expect(parseCustomRoomDurationDays('45.5'), isNull);
    });

    test('rejects non-numeric text', () {
      expect(parseCustomRoomDurationDays('abc'), isNull);
    });

    test(
        "rejects a value with a typed unit suffix, e.g. from someone "
        "echoing the field's own helper text back into it", () {
      expect(parseCustomRoomDurationDays('45 days'), isNull);
    });

    // Some devices switch the numeric keypad to Arabic-Indic digits when
    // the system or app is set to Arabic - see room_model.dart's own
    // _normalizeDigits doc comment. A leader typing on one of those devices
    // should get exactly the same result as typing ASCII digits, not a
    // confusing "invalid" for what looks like a perfectly good number on
    // their own screen.
    test('accepts Arabic-Indic digits, normalized the same as ASCII', () {
      expect(parseCustomRoomDurationDays('٤٥'), 45);
    });

    test('accepts a mix of Arabic-Indic and ASCII digits', () {
      expect(parseCustomRoomDurationDays('٤5'), 45);
    });

    test('custom bounds override the 1-365 default in both directions', () {
      expect(
        parseCustomRoomDurationDays('5', minDays: 7, maxDays: 30),
        isNull,
      );
      expect(
        parseCustomRoomDurationDays('45', minDays: 7, maxDays: 30),
        isNull,
      );
      expect(
        parseCustomRoomDurationDays('20', minDays: 7, maxDays: 30),
        20,
      );
    });
  });
}
