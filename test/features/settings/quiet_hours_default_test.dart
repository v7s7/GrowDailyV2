// Quiet hours are off until the person turns them on (Aziz, 2026-09-28).
//
// They were on for everyone, 22:00 to 07:00, and 'quietHoursEnabled' went
// into every saved copy of the settings, so that key cannot tell a choice
// from the default. The switch lives under 'quietHoursOn' now, and a copy
// saved before it existed keeps quiet hours on only when the person had
// visibly changed them: the start, the end, or the prayer switch. These pin
// that reading, and what gets written back.
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/settings/models/notification_settings.dart';

void main() {
  /// A copy as build 82 and earlier wrote it: every key, the old switch on.
  Map<String, dynamic> before({
    Object? on = true,
    String start = '22:0',
    String end = '7:0',
    bool prayerToo = false,
  }) =>
      {
        'masterEnabled': true,
        if (on != null) 'quietHoursEnabled': on,
        'quietHoursStart': start,
        'quietHoursEnd': end,
        'quietHoursAppliesToPrayer': prayerToo,
      };

  bool read(Map<String, dynamic> map) =>
      NotificationSettings.fromMap(map).quietHoursEnabled;

  group('the default', () {
    test('a fresh install has quiet hours off', () {
      expect(const NotificationSettings().quietHoursEnabled, isFalse);
    });

    test('so does nothing saved at all', () {
      expect(read(const {}), isFalse);
    });

    test('the window itself is still 22:00 to 07:00, for turning them on', () {
      const s = NotificationSettings();
      expect(s.quietHoursStart, const TimeOfDay(hour: 22, minute: 0));
      expect(s.quietHoursEnd, const TimeOfDay(hour: 7, minute: 0));
    });
  });

  group('a copy saved before the new key', () {
    test('the untouched default reads as off', () {
      expect(read(before()), isFalse,
          reason: 'on only because it was the default, not a choice',);
    });

    test('a moved start keeps them on', () {
      expect(read(before(start: '23:30')), isTrue);
    });

    test('a moved end keeps them on', () {
      expect(read(before(end: '6:0')), isTrue);
    });

    test('the prayer switch turned on keeps them on', () {
      expect(read(before(prayerToo: true)), isTrue);
    });

    test('a switch somebody turned off stays off, times moved or not', () {
      expect(read(before(on: false)), isFalse);
      expect(read(before(on: false, start: '23:0', prayerToo: true)), isFalse);
    });

    test('a missing old switch is read the old way, as on', () {
      expect(read(before(on: null)), isFalse,
          reason: 'on, but the default window: still not a choice',);
      expect(read(before(on: null, end: '8:0')), isTrue);
    });

    test('a start that cannot be read is the default one', () {
      expect(read(before(start: 'nonsense')), isFalse);
    });
  });

  group('the new key', () {
    test('wins over everything the old keys say', () {
      expect(read({...before(start: '23:0'), 'quietHoursOn': false}), isFalse);
      expect(read({...before(on: false), 'quietHoursOn': true}), isTrue);
      expect(read({...before(), 'quietHoursOn': true}), isTrue,
          reason: 'turned on with the default window is a choice too',);
    });

    test('anything but a bool there falls back to the old reading', () {
      expect(read({...before(end: '6:0'), 'quietHoursOn': 'yes'}), isTrue);
      expect(read({...before(), 'quietHoursOn': null}), isFalse);
    });
  });

  group('what is written', () {
    test('the switch under its own key, and the old key always true', () {
      final off = const NotificationSettings().toMap();
      expect(off['quietHoursOn'], isFalse);
      expect(off['quietHoursEnabled'], isTrue,
          reason: 'what the server and older builds read: a push from '
              'someone else waits out the night whatever this switch says',);

      final on = const NotificationSettings(quietHoursEnabled: true).toMap();
      expect(on['quietHoursOn'], isTrue);
      expect(on['quietHoursEnabled'], isTrue);
    });

    test('a read-back is the same answer, both ways, forever', () {
      for (final map in [
        before(),
        before(start: '23:30'),
        before(on: false, end: '6:0'),
        before(prayerToo: true),
      ]) {
        final first = NotificationSettings.fromMap(map);
        final again = NotificationSettings.fromMap(first.toMap());
        expect(again.quietHoursEnabled, first.quietHoursEnabled,
            reason: 'from $map',);
        expect(NotificationSettings.fromMap(again.toMap()).quietHoursEnabled,
            first.quietHoursEnabled,);
      }
    });

    test('turned on and saved, it reads as on even with the default window',
        () {
      final saved = const NotificationSettings()
          .copyWith(quietHoursEnabled: true)
          .toMap();
      expect(read(saved), isTrue);
    });

    test('turned off and saved, a custom window does not bring it back', () {
      final saved = NotificationSettings.fromMap(before(start: '23:0'))
          .copyWith(quietHoursEnabled: false)
          .toMap();
      expect(read(saved), isFalse);
      expect(saved['quietHoursStart'], '23:0',
          reason: 'the window is kept for the next time they turn it on',);
    });
  });
}
