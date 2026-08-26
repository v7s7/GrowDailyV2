// Who gets congratulated, and who is left alone.
//
// A habit counted N times a day would fire N reward banners if nothing
// stopped it. Four a day is too many even for a habit someone is pleased
// about, and for the other kind it is not merely noisy: the app cannot tell
// drinking water from taking medicine, and congratulating a person four
// times a day for taking medicine reads as the app misunderstanding what it
// is looking at.
//
// So intermediate taps say nothing, and the count going up carries the
// meaning instead — a fact rather than a verdict. The finishing tap keeps
// exactly the banner the habit had when it was once a day, so nothing is
// taken away from the habits people do want cheered.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';

void main() {
  bool announces(int doneBefore, int target) =>
      completionAnnouncesItself(doneBefore: doneBefore, target: target);

  group('a habit that is once a day is completely unaffected', () {
    test('its only tap announces itself, exactly as it always did', () {
      expect(announces(0, 1), isTrue);
    });
  });

  group('a counted habit stays quiet until it is actually finished', () {
    test('the first of four says nothing', () {
      expect(announces(0, 4), isFalse);
    });

    test('the middle taps say nothing either', () {
      expect(announces(1, 4), isFalse);
      expect(announces(2, 4), isFalse);
    });

    test('the tap that finishes the day is the one that speaks', () {
      expect(announces(3, 4), isTrue);
    });

    test('exactly one tap per day announces, at every size', () {
      for (var target = 1; target <= 12; target++) {
        final speaking = [
          for (var done = 0; done < target; done++)
            if (announces(done, target)) done,
        ];
        expect(speaking, [target - 1],
            reason: 'target $target announced on $speaking; it must announce '
                'once, on the finishing tap');
      }
    });
  });

  group('nothing can slip past the end', () {
    test('a tap beyond the target still counts as finishing', () {
      // Reachable only if a target were lowered under a day already in
      // progress. Announcing is the right side to fail on: the day IS done.
      expect(announces(9, 4), isTrue);
    });

    test('a target of zero or less never leaves a day unannounced', () {
      expect(announces(0, 0), isTrue);
      expect(announces(0, -1), isTrue);
    });
  });
}
