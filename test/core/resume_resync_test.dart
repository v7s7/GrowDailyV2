// A resume is not evidence that anything changed.
//
// iOS fires didChangeAppLifecycleState(resumed) every time the app returns to
// the foreground, and the room resync behind it costs one participant read
// plus up to kRoomSyncWindowDays daily reads PER ROOM the account is in.
// Measured against the live project on 2026-09-12, rooms traffic was the
// second largest source of reads in the app and almost none of it discovered
// anything new.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';

void main() {
  const gap = Duration(minutes: 5);

  test('the first resume of a session always syncs', () {
    // Nothing to be stale relative to.
    expect(
      shouldResyncOnResume(last: null, now: DateTime(2026, 9, 12, 14), gap: gap),
      isTrue,
    );
  });

  test('a second resume moments later does not', () {
    expect(
      shouldResyncOnResume(
        last: DateTime(2026, 9, 12, 14, 0),
        now: DateTime(2026, 9, 12, 14, 2),
        gap: gap,
      ),
      isFalse,
    );
  });

  test('a resume once the gap has passed syncs again', () {
    // The boundary itself counts, so the gap is a "no more often than", not a
    // "strictly longer than".
    expect(
      shouldResyncOnResume(
        last: DateTime(2026, 9, 12, 14, 0),
        now: DateTime(2026, 9, 12, 14, 5),
        gap: gap,
      ),
      isTrue,
    );
  });

  test('crossing MIDNIGHT always syncs, gap or no gap', () {
    // effectiveDay rolls at midnight and that is when today's squares reset,
    // so a board carried across it shows the wrong DAY, not merely old news.
    expect(
      shouldResyncOnResume(
        last: DateTime(2026, 9, 12, 23, 59),
        now: DateTime(2026, 9, 13, 0, 1),
        gap: gap,
      ),
      isTrue,
    );
  });

  test('10:00 is NOT forced through, because the gap already bounds it', () {
    // kDayCutoffHour is when yesterday stops being markable and settles. That
    // re-grade happens with nobody watching for it, so it rides the ordinary
    // gap rather than forcing a read of every room the account is in. The
    // distinction matters: getting it wrong here would put the expensive path
    // back on a fixed daily schedule for every user at once.
    expect(
      shouldResyncOnResume(
        last: DateTime(2026, 9, 12, 9, 58),
        now: DateTime(2026, 9, 12, 10, 1),
        gap: gap,
      ),
      isFalse,
    );
  });

  test('a resume hours later on the same day syncs', () {
    expect(
      shouldResyncOnResume(
        last: DateTime(2026, 9, 12, 8),
        now: DateTime(2026, 9, 12, 20),
        gap: gap,
      ),
      isTrue,
    );
  });
}
