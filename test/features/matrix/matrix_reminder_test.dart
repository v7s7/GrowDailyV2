// Pure-logic tests for the Matrix task-reminder feature — formatReminderMoment
// (reminder_picker.dart) and shouldScheduleTaskReminder (matrix_notifier.dart)
// are both plain, Firestore/Hive/NotificationService-free functions by
// design (same reasoning as rooms_notifier_test.dart's nextLeaderAfter and
// prayer_times_service_test.dart's resolveRegion), so this file never spins
// up a ProviderContainer or touches flutter_local_notifications' platform
// channel at all.
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/features/matrix/models/matrix_task.dart';
import 'package:grow_daily_v2/features/matrix/notifiers/matrix_notifier.dart';
import 'package:grow_daily_v2/features/matrix/widgets/custom_offset_sheet.dart';
import 'package:grow_daily_v2/features/matrix/widgets/reminder_picker.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// [reminderAt] is the single-reminder convenience the pre-multi-reminder
/// tests below were written against and still read clearly with; pass
/// [reminderAts] instead for a stack.
MatrixTask _task({
  DateTime? reminderAt,
  List<DateTime>? reminderAts,
  bool isDone = false,
}) =>
    MatrixTask(
      id: 't1',
      title: 'Test task',
      quadrant: MatrixQuadrant.doFirst,
      isDone: isDone,
      createdAt: DateTime(2026, 7, 16),
      reminderAts: MatrixTask.normalizeReminders(
        reminderAts ?? (reminderAt == null ? const [] : [reminderAt]),
      ),
      order: 0,
    );

void main() {
  // formatReminderMoment formats through intl's DateFormat, which throws
  // LocaleDataException on any locale whose symbol data was never loaded —
  // main.dart loads 'en'/'ar' once at startup (see its own initializeDate
  // Formatting calls); this file has to do the same before either is used.
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ar');
  });

  group('formatReminderMoment', () {
    final now = DateTime(2026, 7, 16, 9);

    test('same calendar day as now reads "Today"', () {
      expect(
        formatReminderMoment(DateTime(2026, 7, 16, 17), false, now: now),
        'Today · 5:00 PM',
      );
    });

    test('the very next calendar day reads "Tomorrow"', () {
      expect(
        formatReminderMoment(DateTime(2026, 7, 17, 9, 30), false, now: now),
        'Tomorrow · 9:30 AM',
      );
    });

    test('anything further out falls back to a month/day date', () {
      expect(
        formatReminderMoment(DateTime(2026, 7, 20, 14), false, now: now),
        'Jul 20 · 2:00 PM',
      );
    });

    test('Arabic uses the Arabic Today/Tomorrow labels', () {
      expect(
        formatReminderMoment(DateTime(2026, 7, 16, 17), true, now: now),
        startsWith('اليوم'),
      );
      expect(
        formatReminderMoment(DateTime(2026, 7, 17, 9), true, now: now),
        startsWith('غدًا'),
      );
    });

    test('follows the real calendar day, not the app\'s 6am cutoff', () {
      // A reminder 20 minutes after an 11:50pm "now" is technically still
      // "tonight," but it's a different calendar date — this documents
      // that formatReminderMoment deliberately ignores
      // DateTimeGameExt.effectiveDay's 6am cutoff (see the function's own
      // doc comment): a reminder fires at a real wall-clock moment, so
      // "Today" here means the device's actual calendar today.
      final lateNow = DateTime(2026, 7, 16, 23, 50);
      expect(
        formatReminderMoment(DateTime(2026, 7, 17, 0, 10), false, now: lateNow),
        'Tomorrow · 12:10 AM',
      );
    });
  });

  group('shouldScheduleTaskReminder', () {
    final now = DateTime(2026, 7, 16, 9);
    final future = DateTime(2026, 7, 16, 17);
    final past = DateTime(2026, 7, 16, 8);

    test('fires when reminderAt is future, task is open, master switch is on',
        () {
      expect(
        shouldScheduleTaskReminder(
          _task(reminderAt: future),
          masterEnabled: true,
          now: now,
        ),
        isTrue,
      );
    });

    test('does not fire when there is no reminderAt at all', () {
      expect(
        shouldScheduleTaskReminder(_task(), masterEnabled: true, now: now),
        isFalse,
      );
    });

    test('does not fire once the task is already done', () {
      expect(
        shouldScheduleTaskReminder(
          _task(reminderAt: future, isDone: true),
          masterEnabled: true,
          now: now,
        ),
        isFalse,
      );
    });

    test('does not fire once the picked moment has already passed', () {
      expect(
        shouldScheduleTaskReminder(
          _task(reminderAt: past),
          masterEnabled: true,
          now: now,
        ),
        isFalse,
      );
    });

    test('a reminderAt exactly equal to now does not fire (strict isAfter)',
        () {
      expect(
        shouldScheduleTaskReminder(
          _task(reminderAt: now),
          masterEnabled: true,
          now: now,
        ),
        isFalse,
      );
    });

    test('does not fire when the app-wide master notification switch is off',
        () {
      expect(
        shouldScheduleTaskReminder(
          _task(reminderAt: future),
          masterEnabled: false,
          now: now,
        ),
        isFalse,
      );
    });
  });

  group('MatrixTask.reminderAt persistence', () {
    test('toMap/fromMap round-trips reminderAt', () {
      final original = _task(reminderAt: DateTime(2026, 7, 18, 14, 30));
      final restored = MatrixTask.fromMap(original.toMap());
      expect(restored.reminderAt, original.reminderAt);
    });

    test('toMap omits reminderAt entirely when unset', () {
      expect(_task().toMap().containsKey('reminderAt'), isFalse);
    });

    test('copyWith(reminderAts: []) clears an existing value', () {
      final task = _task(reminderAt: DateTime(2026, 7, 18, 14, 30));
      expect(task.copyWith(reminderAts: const []).reminderAt, isNull);
      expect(task.copyWith(reminderAts: const []).reminderAts, isEmpty);
    });

    test('copyWith without reminderAts leaves them untouched', () {
      final original = DateTime(2026, 7, 18, 14, 30);
      final task = _task(reminderAt: original);
      expect(task.copyWith(title: 'Renamed').reminderAt, original);
    });
  });

  group('MatrixTask.reminderAnchorAt persistence', () {
    // The user's repro, as a stored task: anchor at noon with two warnings
    // before it and one nudge after.
    final anchor = DateTime(2026, 8, 17, 12);
    final ladder = [
      DateTime(2026, 8, 17, 11, 50),
      DateTime(2026, 8, 17, 11, 55),
      anchor,
      DateTime(2026, 8, 17, 12, 15),
    ];

    test('toMap/fromMap round-trips the anchor', () {
      final original = MatrixTask.create(
        'Try the reminder',
        MatrixQuadrant.doFirst,
        reminderAts: ladder,
        reminderAnchorAt: anchor,
      );
      final restored = MatrixTask.fromMap(original.toMap());
      expect(restored.reminderAnchorAt, anchor);
      expect(restored.reminderAts, ladder);
      // And the whole point: reopening reproduces the ladder that was built,
      // rather than re-framing it around the latest alarm.
      expect(
        offsetsFrom(
          anchor: restored.reminderAnchorAt,
          reminders: restored.reminderAts,
        ),
        {-10, -5, 15},
      );
    });

    test('toMap omits the anchor entirely when unset', () {
      expect(_task().toMap().containsKey('reminderAnchorAt'), isFalse);
    });

    test('a task stored without an anchor still loads, falling back', () {
      // Exactly the shape the current shipped build writes: reminderAts,
      // no reminderAnchorAt. It must keep looking the way it looks today.
      final legacy = _task(reminderAts: ladder).toMap()
        ..remove('reminderAnchorAt');
      expect(MatrixTask.fromMap(legacy).reminderAnchorAt, ladder.last);
    });

    test('clearing reminders clears the anchor with them', () {
      final task = MatrixTask.create(
        'Try the reminder',
        MatrixQuadrant.doFirst,
        reminderAts: ladder,
        reminderAnchorAt: anchor,
      );
      final cleared = task.copyWith(reminderAts: const []);
      expect(cleared.reminderAnchorAt, isNull);
      expect(cleared.reminderAts, isEmpty);
    });

    test('replacing reminders re-resolves an anchor left behind', () {
      // A caller that changes the list without thinking about the anchor
      // must not be able to leave one pointing at a moment the task no
      // longer fires at.
      final task = MatrixTask.create(
        'Try the reminder',
        MatrixQuadrant.doFirst,
        reminderAts: ladder,
        reminderAnchorAt: anchor,
      );
      final moved = task.copyWith(
        reminderAts: [
          DateTime(2026, 8, 18, 9),
          DateTime(2026, 8, 18, 9, 30),
        ],
      );
      expect(moved.reminderAnchorAt, DateTime(2026, 8, 18, 9, 30));
    });

    test('a copyWith that touches nothing else keeps the anchor', () {
      final task = MatrixTask.create(
        'Try the reminder',
        MatrixQuadrant.doFirst,
        reminderAts: ladder,
        reminderAnchorAt: anchor,
      );
      expect(task.copyWith(title: 'Renamed').reminderAnchorAt, anchor);
      expect(task.copyWith(isDone: true).reminderAnchorAt, anchor);
    });
  });

  group('MatrixTask.normalizeReminders', () {
    test('sorts ascending so rows render in the order they will fire', () {
      final out = MatrixTask.normalizeReminders([
        DateTime(2026, 7, 16, 16),
        DateTime(2026, 7, 16, 15),
        DateTime(2026, 7, 16, 15, 30),
      ]);
      expect(out, [
        DateTime(2026, 7, 16, 15),
        DateTime(2026, 7, 16, 15, 30),
        DateTime(2026, 7, 16, 16),
      ]);
    });

    test('dedupes to the minute, so two picks of 3:30 collapse to one', () {
      // The picker only ever yields minute precision; seconds differing is
      // an artefact of when the dialog was dismissed, not user intent.
      final out = MatrixTask.normalizeReminders([
        DateTime(2026, 7, 16, 15, 30, 5),
        DateTime(2026, 7, 16, 15, 30, 41),
      ]);
      expect(out, hasLength(1));
    });

    test('an empty input stays empty', () {
      expect(MatrixTask.normalizeReminders(const []), isEmpty);
    });
  });

  group('legacy single-reminder migration', () {
    test('a task stored with only the old reminderAt key still loads it', () {
      // Exactly what a task saved by any build before multi-reminders
      // looks like on disk: a scalar `reminderAt`, no `reminderAts` array.
      final restored = MatrixTask.fromMap({
        'id': 't-legacy',
        'title': 'Old task',
        'quadrant': 'doFirst',
        'isDone': false,
        'createdAt': DateTime(2026, 7, 16).toIso8601String(),
        'reminderAt': DateTime(2026, 7, 18, 14, 30).toIso8601String(),
        'order': 0,
      });
      expect(restored.reminderAts, [DateTime(2026, 7, 18, 14, 30)]);
      expect(restored.reminderAt, DateTime(2026, 7, 18, 14, 30));
    });

    test('the new array wins when both keys are present', () {
      final restored = MatrixTask.fromMap({
        'id': 't-both',
        'title': 'Task',
        'quadrant': 'doFirst',
        'isDone': false,
        'createdAt': DateTime(2026, 7, 16).toIso8601String(),
        'reminderAt': DateTime(2026, 7, 18, 14, 30).toIso8601String(),
        'reminderAts': [
          DateTime(2026, 7, 18, 14, 30).toIso8601String(),
          DateTime(2026, 7, 18, 15).toIso8601String(),
        ],
        'order': 0,
      });
      expect(restored.reminderAts, hasLength(2));
    });

    test('toMap keeps the legacy key in step with the first entry', () {
      // An older install (or a downgrade) reads only this key — writing
      // the array alone would silently drop the reminder for them.
      final map = _task(
        reminderAts: [
          DateTime(2026, 7, 18, 15),
          DateTime(2026, 7, 18, 14, 30),
        ],
      ).toMap();
      expect(
        map['reminderAt'],
        DateTime(2026, 7, 18, 14, 30).toIso8601String(),
      );
      expect(map['reminderAts'], hasLength(2));
    });

    test('a multi-reminder task round-trips through toMap/fromMap', () {
      final original = _task(
        reminderAts: [
          DateTime(2026, 7, 18, 15),
          DateTime(2026, 7, 18, 14, 30),
          DateTime(2026, 7, 18, 16),
        ],
      );
      final restored = MatrixTask.fromMap(original.toMap());
      expect(restored.reminderAts, original.reminderAts);
    });
  });

  group('futureTaskReminders', () {
    final now = DateTime(2026, 7, 16, 15, 15);
    // The user's own example: a 5pm meeting warned about three times.
    final stack = [
      DateTime(2026, 7, 16, 15),
      DateTime(2026, 7, 16, 15, 30),
      DateTime(2026, 7, 16, 16),
    ];

    test('returns only the moments still ahead of now', () {
      expect(
        futureTaskReminders(
          _task(reminderAts: stack),
          masterEnabled: true,
          now: now,
        ),
        [DateTime(2026, 7, 16, 15, 30), DateTime(2026, 7, 16, 16)],
      );
    });

    test('a partly-elapsed stack still counts as schedulable', () {
      expect(
        shouldScheduleTaskReminder(
          _task(reminderAts: stack),
          masterEnabled: true,
          now: now,
        ),
        isTrue,
      );
    });

    test('nothing is scheduled once the whole stack has passed', () {
      final afterAll = DateTime(2026, 7, 16, 17);
      expect(
        futureTaskReminders(
          _task(reminderAts: stack),
          masterEnabled: true,
          now: afterAll,
        ),
        isEmpty,
      );
    });

    test('a done task schedules nothing even with future reminders', () {
      expect(
        futureTaskReminders(
          _task(reminderAts: stack, isDone: true),
          masterEnabled: true,
          now: now,
        ),
        isEmpty,
      );
    });
  });

  group('latestMissedTaskReminder', () {
    final stack = [
      DateTime(2026, 7, 16, 15),
      DateTime(2026, 7, 16, 15, 30),
      DateTime(2026, 7, 16, 16),
    ];

    test('picks the most recent missed moment, not every missed one', () {
      // Opening the app at 4:15 having missed all three must catch up
      // once, keyed to 4:00 — three identical notifications at once would
      // be indistinguishable from a bug.
      expect(
        latestMissedTaskReminder(
          _task(reminderAts: stack),
          masterEnabled: true,
          now: DateTime(2026, 7, 16, 16, 15),
        ),
        DateTime(2026, 7, 16, 16),
      );
    });

    test('the guard key advances as later reminders come due', () {
      // At 3:45 the catch-up would be keyed to 3:30; at 4:15 to 4:00. A
      // different key each time is what lets the once-only guard in
      // MatrixNotifier fire again for the newly-passed moment instead of
      // going permanently silent after the first.
      expect(
        latestMissedTaskReminder(
          _task(reminderAts: stack),
          masterEnabled: true,
          now: DateTime(2026, 7, 16, 15, 45),
        ),
        DateTime(2026, 7, 16, 15, 30),
      );
    });

    test('null when nothing has passed yet', () {
      expect(
        latestMissedTaskReminder(
          _task(reminderAts: stack),
          masterEnabled: true,
          now: DateTime(2026, 7, 16, 14),
        ),
        isNull,
      );
    });

    test('null once the task is done, however much was missed', () {
      expect(
        latestMissedTaskReminder(
          _task(reminderAts: stack, isDone: true),
          masterEnabled: true,
          now: DateTime(2026, 7, 16, 17),
        ),
        isNull,
      );
    });
  });

  group('canAddReminder', () {
    test('free gets exactly one reminder per task', () {
      expect(canAddReminder(current: 0, isPremium: false), isTrue);
      expect(canAddReminder(current: 1, isPremium: false), isFalse);
    });

    test('premium is uncapped', () {
      expect(canAddReminder(current: 1, isPremium: true), isTrue);
      expect(canAddReminder(current: 25, isPremium: true), isTrue);
    });

    test('the free limit matches kFreeTaskReminders', () {
      // Guards against the constant and the gate drifting apart.
      expect(
        canAddReminder(current: kFreeTaskReminders - 1, isPremium: false),
        isTrue,
      );
      expect(
        canAddReminder(current: kFreeTaskReminders, isPremium: false),
        isFalse,
      );
    });
  });

  group('remindersFor', () {
    final anchor = DateTime(2026, 7, 16, 17); // the 5pm meeting

    test('the anchor alone is a reminder in its own right', () {
      expect(remindersFor(anchor: anchor, offsets: const {}), [anchor]);
    });

    test('no anchor means no reminders, whatever offsets are selected', () {
      expect(remindersFor(anchor: null, offsets: const {-30}), isEmpty);
    });

    test('builds the ladder, sorted, anchor last', () {
      // The user's own example: 3:00 / 3:30 / 4:00 warnings before a 5pm
      // meeting, expressed as two hours / ninety / sixty minutes before.
      expect(
        remindersFor(anchor: anchor, offsets: const {-120, -90, -60}),
        [
          DateTime(2026, 7, 16, 15),
          DateTime(2026, 7, 16, 15, 30),
          DateTime(2026, 7, 16, 16),
          anchor,
        ],
      );
    });

    test('positive offsets land after the anchor', () {
      expect(
        remindersFor(anchor: anchor, offsets: const {15}),
        [anchor, DateTime(2026, 7, 16, 17, 15)],
      );
    });

    test('an offset that collides with the anchor collapses, not duplicates',
        () {
      expect(remindersFor(anchor: anchor, offsets: const {0}), [anchor]);
    });
  });

  group('offsetsFrom', () {
    test('round-trips a before-ladder exactly', () {
      final anchor = DateTime(2026, 7, 16, 17);
      const offsets = {-60, -30};
      final reminders = remindersFor(anchor: anchor, offsets: offsets);
      expect(offsetsFrom(anchor: anchor, reminders: reminders), offsets);
      expect(
        remindersFor(
          anchor: anchor,
          offsets: offsetsFrom(anchor: anchor, reminders: reminders),
        ),
        reminders,
      );
    });

    test('no anchor means no offsets', () {
      expect(offsetsFrom(anchor: null, reminders: const []), isEmpty);
      expect(
        offsetsFrom(anchor: null, reminders: [DateTime(2026, 7, 16, 17)]),
        isEmpty,
      );
    });

    test("the anchor's own entry contributes no offset", () {
      final only = DateTime(2026, 7, 16, 17);
      expect(offsetsFrom(anchor: only, reminders: [only]), isEmpty);
    });

    test('THE FIX: an after-ladder comes back as an after-ladder', () {
      // This is the bug the anchor field exists to kill. The old
      // splitReminders assumed reminders.last was the anchor, so "15 after
      // 5:00" reopened claiming 5:15 was the moment you'd picked and 5:00
      // was a warning 15 minutes ahead of it — the same two alarms telling
      // a story the user never wrote. With the real anchor supplied, the
      // ladder comes back exactly as it was built.
      final anchor = DateTime(2026, 7, 16, 17);
      final reminders = remindersFor(anchor: anchor, offsets: const {15});
      expect(offsetsFrom(anchor: anchor, reminders: reminders), {15});
      expect(reminders.last, DateTime(2026, 7, 16, 17, 15));
    });

    test('a mixed ladder keeps every sign', () {
      // The user's own repro: an anchor with two warnings before it and one
      // nudge after. Every one of those three has to survive with its own
      // direction intact.
      final anchor = DateTime(2026, 8, 17, 12);
      const offsets = {-10, -5, 15};
      final reminders = remindersFor(anchor: anchor, offsets: offsets);
      expect(reminders, [
        DateTime(2026, 8, 17, 11, 50),
        DateTime(2026, 8, 17, 11, 55),
        anchor,
        DateTime(2026, 8, 17, 12, 15),
      ]);
      expect(offsetsFrom(anchor: anchor, reminders: reminders), offsets);
    });
  });

  group('MatrixTask.resolveAnchor', () {
    final a = DateTime(2026, 7, 16, 16);
    final b = DateTime(2026, 7, 16, 17);

    test('keeps a candidate that is genuinely one of the moments', () {
      expect(MatrixTask.resolveAnchor(a, [a, b]), a);
    });

    test('matches to the minute, not the millisecond', () {
      // normalizeReminders dedupes on minute buckets and keeps whichever
      // DateTime it saw first, so a stored anchor can carry seconds the
      // list entry doesn't. Both are "4:00 PM" to the user.
      final withSeconds = DateTime(2026, 7, 16, 16, 0, 41);
      expect(MatrixTask.resolveAnchor(withSeconds, [a, b]), withSeconds);
    });

    test('falls back to the last moment for a task saved without one', () {
      // Legacy tasks have no recoverable anchor — the flat list genuinely
      // does not contain the information. reminders.last is what the old
      // splitReminders guessed, so those tasks keep looking exactly as they
      // did rather than being re-framed a second, differently-wrong way.
      expect(MatrixTask.resolveAnchor(null, [a, b]), b);
    });

    test('rejects an anchor the task does not actually fire at', () {
      // Self-healing: an old build editing a task saved by a new one writes
      // reminderAts without touching reminderAnchorAt, and merge-set leaves
      // the stale value behind. An anchor outside the list would render as
      // a bold time no notification ever matches.
      final orphan = DateTime(2026, 7, 16, 9, 30);
      expect(MatrixTask.resolveAnchor(orphan, [a, b]), b);
    });

    test('no reminders means no anchor, whatever was stored', () {
      expect(MatrixTask.resolveAnchor(a, const []), isNull);
    });
  });

  group('formatOffsetCompact', () {
    const en = S(Locale('en'));
    const ar = S(Locale('ar'));

    test('states its own direction, which is what killed the toggle', () {
      expect(formatOffsetCompact(-15, false, en), '15m before');
      expect(formatOffsetCompact(15, false, en), '15m after');
    });

    test('Arabic leads with the preposition and uses Arabic-Indic digits', () {
      // Word order first: "قبل ١٥ د", never "١٥ د قبل", which is English
      // word order wearing Arabic words.
      expect(formatOffsetCompact(-15, true, ar), 'قبل ١٥ د');
      expect(formatOffsetCompact(15, true, ar), 'بعد ١٥ د');
      // Deliberately NOT DateFormat's output, which is ASCII ("5:05 م") —
      // a bare chip label gets no Arabic run for the font to substitute
      // digits inside, so it carries the codepoints itself.
      expect(
        DateFormat('h:mm a', 'ar').format(DateTime(2026, 8, 16, 17, 5)),
        startsWith('5:05'),
      );
    });

    test('picks the largest unit that divides, abbreviated', () {
      expect(formatOffsetCompact(-60, false, en), '1h before');
      expect(formatOffsetCompact(-1440, false, en), '1d before');
      // 90 doesn't divide into hours, so it stays in minutes rather than
      // becoming "1.5h".
      expect(formatOffsetCompact(-90, false, en), '90m before');
    });

    test('Arabic keeps its natural noun for one and two', () {
      // "قبل ساعة" is both shorter and better than "قبل ١ س".
      expect(formatOffsetCompact(-60, true, ar), 'قبل ساعة');
      expect(formatOffsetCompact(-120, true, ar), 'قبل ساعتين');
      expect(formatOffsetCompact(-2880, true, ar), 'قبل يومين');
    });

    test('agrees with formatOffsetVerbose about the unit', () {
      // Both go through splitOffsetUnit, so a chip reading "1h before" can
      // never sit above a list row reading "60 minutes before".
      for (final o in [-2880, -1440, -120, -90, -60, -15, 15, 30]) {
        final (compactValue, compactUnit) = splitOffsetUnit(o.abs());
        expect(
          formatOffsetVerbose(o, false, en),
          contains('$compactValue '),
          reason: 'verbose and compact disagree on $o',
        );
        expect(compactUnit, isNotNull);
      }
    });

    test('five presets plus the custom cell fill two 3-column rows', () {
      // The custom field is the sixth cell of the same grid, so the preset
      // count has to stay at five or the default layout goes ragged.
      expect(kReminderOffsetPresets, hasLength(5));
      // Unsigned: direction is the قبل/بعد toggle above the grid, applied
      // to whichever presets you tap.
      expect(kReminderOffsetPresets.every((o) => !o.isNegative), isTrue);
    });

    test('spells the hours out rather than showing 60 / 120', () {
      expect(reminderOffsetLabel(60, false), '1 hour');
      expect(reminderOffsetLabel(60, true), 'ساعة');
      expect(reminderOffsetLabel(120, false), '2 hours');
      expect(reminderOffsetLabel(120, true), 'ساعتان');
    });

    test('Arabic chips carry Arabic-Indic codepoints', () {
      // Deliberately NOT compared against DateFormat's output, which is
      // ASCII ("5:05 م"). A bare chip label gets no Arabic run for the font
      // to substitute digits inside, so it carries the codepoints itself.
      expect(
        DateFormat('h:mm a', 'ar').format(DateTime(2026, 8, 16, 17, 5)),
        startsWith('5:05'),
      );
      expect(reminderOffsetLabel(30, true), '٣٠');
      expect(reminderOffsetLabel(5, true), '٥');
      expect(reminderOffsetLabel(30, false), '30');
    });
  });

  group('formatOffsetVerbose', () {
    const en = S(Locale('en'));
    const ar = S(Locale('ar'));

    test('picks the largest unit that divides evenly', () {
      expect(formatOffsetVerbose(-1440, false, en), '1 day before');
      expect(formatOffsetVerbose(-120, false, en), '2 hours before');
      expect(formatOffsetVerbose(-45, false, en), '45 minutes before');
    });

    test('a value that does not divide stays in minutes', () {
      // 90 could be "1.5 hours", but a fraction is harder to scan and
      // impossible to type back into a whole-number field.
      expect(formatOffsetVerbose(-90, false, en), '90 minutes before');
    });

    test('sign picks the direction word', () {
      expect(formatOffsetVerbose(15, false, en), '15 minutes after');
      expect(formatOffsetVerbose(-15, false, en), '15 minutes before');
    });

    test('English singular vs plural', () {
      expect(formatOffsetVerbose(-1, false, en), '1 minute before');
      expect(formatOffsetVerbose(-2, false, en), '2 minutes before');
    });

    test('Arabic uses singular, dual and plural correctly', () {
      // The rule that makes an Arabic UI read as written rather than
      // translated: ١ دقيقة, ٢ دقيقتين (genitive dual, because it follows a
      // preposition), ٣-١٠ دقائق, ١١+ back to the singular noun — and the
      // preposition leads throughout.
      expect(formatOffsetVerbose(-1, true, ar), 'قبل دقيقة');
      expect(formatOffsetVerbose(-2, true, ar), 'قبل دقيقتين');
      expect(formatOffsetVerbose(-5, true, ar), 'قبل ٥ دقائق');
      expect(formatOffsetVerbose(-45, true, ar), 'قبل ٤٥ دقيقة');
      expect(formatOffsetVerbose(-120, true, ar), 'قبل ساعتين');
      expect(formatOffsetVerbose(-1440, true, ar), 'قبل يوم');
      expect(formatOffsetVerbose(-2880, true, ar), 'قبل يومين');
      expect(formatOffsetVerbose(1440, true, ar), 'بعد يوم');
    });
  });

  group('day-spanning stacks stay distinguishable', () {
    // Regression guard for a bug that only appeared once day-scale offsets
    // existed: the preview formatted times only, so a reminder two days
    // before a 10:31 anchor rendered as "10:31 AM · 10:31 AM" — the same
    // string twice, for two moments 48 hours apart.
    test('two reminders 48h apart do not format identically', () {
      final anchor = DateTime(2026, 8, 27, 10, 31);
      final reminders = remindersFor(
        anchor: anchor,
        offsets: {-2 * ReminderUnit.days.inMinutes},
      );
      final now = DateTime(2026, 8, 16, 9);
      final labels = reminders
          .map((d) => formatReminderMoment(d, false, now: now))
          .toSet();
      expect(reminders, hasLength(2));
      expect(
        labels,
        hasLength(2),
        reason: 'each reminder must render as a distinct label',
      );
    });

    test('the offset label names the unit, not a raw minute count', () {
      // The grid chip for an unlisted offset used to read "2880 before".
      const en = S(Locale('en'));
      expect(formatOffsetVerbose(-2880, false, en), '2 days before');
    });

    test('Arabic leads with the preposition, English trails it', () {
      // "١٥ دقيقة قبل" is English word order wearing Arabic words — the
      // preposition belongs at the front in Arabic.
      const ar = S(Locale('ar'));
      const en = S(Locale('en'));
      expect(formatOffsetVerbose(-15, true, ar), 'قبل ١٥ دقيقة');
      expect(formatOffsetVerbose(15, true, ar), 'بعد ١٥ دقيقة');
      expect(formatOffsetVerbose(-15, false, en), '15 minutes before');
    });

    test('Arabic uses the genitive dual after a preposition', () {
      // "قبل دقيقتان" is nominative; after قبل/بعد it must be دقيقتين.
      const ar = S(Locale('ar'));
      expect(formatOffsetVerbose(-2, true, ar), 'قبل دقيقتين');
      expect(formatOffsetVerbose(-120, true, ar), 'قبل ساعتين');
      expect(formatOffsetVerbose(2880, true, ar), 'بعد يومين');
    });

    test('withDirection: false drops the preposition for tab-scoped chips', () {
      const ar = S(Locale('ar'));
      const en = S(Locale('en'));
      expect(
        formatOffsetVerbose(-2880, true, ar, withDirection: false),
        'يومين',
      );
      expect(
        formatOffsetVerbose(-2880, false, en, withDirection: false),
        '2 days',
      );
    });
  });

  group('ReminderUnit', () {
    test('units convert to the minutes the model stores', () {
      expect(ReminderUnit.minutes.inMinutes, 1);
      expect(ReminderUnit.hours.inMinutes, 60);
      expect(ReminderUnit.days.inMinutes, 1440);
    });

    test('a day offset lands on the same clock time the day before', () {
      // The whole point of the day unit: "remind me the day before" without
      // anyone typing 1440.
      final anchor = DateTime(2026, 8, 20, 17);
      final reminders = remindersFor(
        anchor: anchor,
        offsets: {-ReminderUnit.days.inMinutes},
      );
      expect(reminders.first, DateTime(2026, 8, 19, 17));
    });
  });

  group('normalizeArabicDigits', () {
    test('Arabic-Indic input parses as a number', () {
      // An Arabic keypad emits ٤٥; int.tryParse only understands ASCII, so
      // without this the custom-minutes field is a silent no-op.
      expect(int.tryParse(normalizeArabicDigits('٤٥')), 45);
      expect(int.tryParse(normalizeArabicDigits('٥')), 5);
    });

    test('plain ASCII passes through untouched', () {
      expect(normalizeArabicDigits('45'), '45');
    });
  });
}
