/// Reminder wording that knows *when* it is firing relative to the thing it
/// is about.
///
/// ── Why this file exists ────────────────────────────────────────────
/// Both reminder features let you fire early or late: a habit carries a
/// signed `reminderOffsetMinutes` (negative = before its clock time or its
/// prayer, positive = after), and a Matrix task stores a whole stack of
/// absolute moments around one hand-picked anchor. The notifications
/// themselves knew none of that. Every task reminder said «حان الوقت»
/// / "It's time" and every habit reminder leaned on the same wording, so a
/// reminder deliberately set for an hour BEFORE a 8:25 appointment arrived
/// at 7:25 announcing the time had come. The person who set it is then
/// being told something they can see is false, which is the fastest way to
/// teach someone to ignore a notification.
///
/// So the copy is derived from the offset, not fixed: it counts down before
/// the moment, states the moment on time, and counts up after it. All of it
/// is pure, top-level, and language-agnostic in shape (`isAr` in, string
/// out), so the wording can be asserted directly in a unit test the way
/// `formatOffsetVerbose` already is, instead of only being observable by
/// installing the app and waiting.
///
/// ── The register ────────────────────────────────────────────────────
/// Bahraini, and deliberately *impersonal*. Arabic second-person verbs are
/// gendered ("خلّصت" vs "خلّصتي"), and a notification has no idea who is
/// reading it, so the phrasing talks about the task or the habit rather
/// than to the person: "فات وقتها قبل ساعة", never "فاتتك". Possessive ك is
/// fine unvocalized, which is why "مهمتك" and "بانتظارك" still appear.
library;

// ── Counting an offset ──────────────────────────────────────────────
//
// Moved here from features/matrix/widgets so notification copy and the
// picker chips count the same way. They are the two halves of one promise:
// somebody taps a chip that says «قبل ساعة» and later gets a notification
// about it, and the two disagreeing about whether that is "ساعة" or "١ س"
// or "60 دقيقة" reads as two different reminders.

/// Western digits → Arabic-Indic codepoints, for labels that have to do this
/// by hand.
///
/// The reason is font shaping, not number formatting. intl produces ASCII
/// either way: `DateFormat('h:mm a', 'ar')` returns the string "9:20 م". But
/// a number rendered *inside* an Arabic run ("اليوم · 9:20 ص") gets Arabic
/// contextual digit substitution applied by the font, and the user sees
/// ٩:٢٠. A chip label like a bare "15" has no Arabic context, so the same
/// font leaves it Western — two identical ASCII strings, two different glyph
/// sets on screen, side by side. So matching the row means matching what's
/// *rendered*, hence the explicit conversion.
String arabicDigits(int n) => n
    .toString()
    .split('')
    .map((d) => String.fromCharCode(d.codeUnitAt(0) + 0x0660 - 0x30))
    .join();

/// The units a custom offset can be entered in. Stored as minutes on the
/// way out — the offset set is signed minutes throughout, so a unit is
/// purely an input convenience and never reaches the model.
enum ReminderUnit {
  minutes(1),
  hours(60),
  days(1440);

  const ReminderUnit(this.inMinutes);
  final int inMinutes;
}

/// Largest unit that divides [magnitude] evenly, and how many of it. 120 →
/// (2, hours), 1440 → (1, days), 90 → (90, minutes) — a value that doesn't
/// divide stays in minutes rather than becoming "1.5 hours", which would be
/// both harder to scan and impossible to type back in.
///
/// Shared by every offset phrasing in the app (the picker's
/// `formatOffsetVerbose` / `formatOffsetCompact` and [countedOffsetPhrase]
/// below) so no two of them can disagree about which unit a given offset is
/// expressed in.
(int, ReminderUnit) splitOffsetUnit(int magnitude) =>
    magnitude % ReminderUnit.days.inMinutes == 0
        ? (magnitude ~/ ReminderUnit.days.inMinutes, ReminderUnit.days)
        : magnitude % ReminderUnit.hours.inMinutes == 0
            ? (magnitude ~/ ReminderUnit.hours.inMinutes, ReminderUnit.hours)
            : (magnitude, ReminderUnit.minutes);

/// "45 minutes" / "٤٥ دقيقة" — the size of an offset, counted, with no
/// direction word on it. [magnitude] is unsigned minutes.
///
/// Arabic counts properly: singular for one, dual for two, plural for 3–10,
/// and back to the singular noun from 11 up. The dual is spelled in its
/// genitive form ("ساعتين", not "ساعتان") because that is what every phrase
/// in this app puts it in — either after a preposition ("قبل ساعتين") or in
/// the Gulf spoken register the notification copy uses, which does not
/// inflect it at all.
String countedOffsetPhrase(int magnitude, bool isAr) {
  final (value, unit) = splitOffsetUnit(magnitude);
  if (!isAr) {
    const names = {
      ReminderUnit.minutes: 'minute',
      ReminderUnit.hours: 'hour',
      ReminderUnit.days: 'day',
    };
    return '$value ${value == 1 ? names[unit]! : '${names[unit]!}s'}';
  }
  const arabicForms = {
    // singular, genitive dual, plural (3–10)
    ReminderUnit.minutes: ('دقيقة', 'دقيقتين', 'دقائق'),
    ReminderUnit.hours: ('ساعة', 'ساعتين', 'ساعات'),
    ReminderUnit.days: ('يوم', 'يومين', 'أيام'),
  };
  final (one, two, few) = arabicForms[unit]!;
  return switch (value) {
    1 => one,
    2 => two,
    // 3–10 take the plural; 11 and up revert to the singular noun.
    <= 10 => '${arabicDigits(value)} $few',
    _ => '${arabicDigits(value)} $one',
  };
}

/// Signed whole minutes from [anchor] to [fireTime]: negative when the
/// reminder lands before the moment it is about, positive when it lands
/// after, zero when it is the moment itself.
///
/// Rounds rather than truncates. A Matrix task's picked moments are all
/// zero-second (see `pickReminderMoment`) so in practice the difference is
/// already whole minutes, but `Duration.inMinutes` truncates *towards zero*,
/// which turns a stored -59.7 minutes into -59 and would print "باقي ٥٩
/// دقيقة" for something the user set as a flat hour.
int signedOffsetMinutes(DateTime fireTime, DateTime anchor) =>
    (fireTime.difference(anchor).inSeconds / 60).round();

// ── Matrix task reminders ───────────────────────────────────────────
//
// Title carries the timing, body carries the task's own text — the same
// title/body split these notifications already used, just with a title that
// now says something true. "Something needs you, and here is when" is what
// is glanceable from a lock screen; "here is what" follows underneath.

/// Title for one of a task's reminders, given how far it sits from the
/// moment the user actually picked ([MatrixTask.reminderAnchorAt]).
///
/// [offsetMinutes] is signed, per [signedOffsetMinutes]. Zero (including the
/// "we have no anchor to measure against" fallback for a task saved before
/// the anchor was stored) keeps the original wording, which was never wrong
/// for a reminder that really does fire on the dot.
String taskReminderTitle({required int offsetMinutes, required bool isAr}) {
  if (offsetMinutes == 0) return isAr ? 'حان الوقت' : "It's time";
  final gap = countedOffsetPhrase(offsetMinutes.abs(), isAr);
  return offsetMinutes < 0
      ? (isAr ? 'باقي $gap على مهمتك' : '$gap until your task')
      : (isAr ? 'صار لها $gap، وبعدها بانتظارك' : "It's been $gap. Still waiting.");
}

/// Title for the catch-up notification fired when a task's moment came and
/// went without the reminder ever reaching the person (app closed through
/// it, device off, OS simply didn't deliver) — see
/// `NotificationService.fireOverdueTaskReminder`.
///
/// Distinct from [taskReminderTitle]'s "after" branch on purpose: a
/// deliberate follow-up nudge set for +20 is a plan, and a catch-up is an
/// apology for being late, so it states the lateness plainly instead of
/// pretending to be the nudge that never arrived. [minutesLate] is measured
/// from the task's own anchor, not from whichever reminder in the stack was
/// missed last, so a +20 follow-up that went missing still reports how long
/// ago the *task* was due.
String overdueTaskReminderTitle({
  required int minutesLate,
  required bool isAr,
}) {
  if (minutesLate < 1) return isAr ? 'حان الوقت' : "It's time";
  final gap = countedOffsetPhrase(minutesLate, isAr);
  return isAr ? 'فات وقتها قبل $gap' : 'This was due $gap ago';
}

// ── Habit reminders ─────────────────────────────────────────────────
//
// Mirror image of the task split: a habit reminder's TITLE is already the
// habit's own name (that is what makes "Mark Done" from the lock screen
// unambiguous), so the timing has to go in the body, alongside whatever
// encouragement was already there.

/// The streak-protection line a habit reminder leads with once there's a
/// streak worth protecting. Its own function because it is now appended to
/// three different bodies and they must not drift apart.
String habitStreakLine(int streak, bool isAr) => isAr
    ? 'لا تفقد سلسلتك المكوّنة من $streak يوم.'
    : "Don't lose your $streak-day streak.";

/// Body for one habit's reminder.
///
/// [offsetMinutes] is the habit's signed shift for this particular slot (a
/// multi-time habit carries one per time). [anchorLabel] names the moment
/// the offset is measured from when there is a name worth saying — a
/// prayer, so "باقي ٤٥ دقيقة على المغرب" rather than the vaguer "على
/// وقتها". A plain clock time passes null: the fire time IS a clock time,
/// and repeating it back ("باقي ١٥ دقيقة على ٩:٠٠") tells the reader
/// nothing they can't see in the notification's own timestamp.
///
/// [onTimeLine] is what the body used to be unconditionally — the streak
/// line, or a rotating nudge — and is still exactly what an on-time
/// reminder says. Offsets only ever *replace* that lead sentence, never the
/// streak clause, because "you are 45 minutes out" and "you have 7 days
/// riding on this" are two different things to say and the second is the
/// reason to act.
String habitReminderBody({
  required int offsetMinutes,
  required int streak,
  required String? anchorLabel,
  required bool isAr,
  required String onTimeLine,
}) {
  if (offsetMinutes == 0) return onTimeLine;
  final gap = countedOffsetPhrase(offsetMinutes.abs(), isAr);
  final lead = offsetMinutes < 0
      ? (anchorLabel != null
          ? (isAr ? 'باقي $gap على $anchorLabel.' : '$gap until $anchorLabel.')
          : (isAr ? 'باقي $gap على وقتها.' : '$gap to go.'))
      : (anchorLabel != null
          ? (isAr ? 'فات $anchorLabel قبل $gap.' : '$anchorLabel was $gap ago.')
          : (isAr ? 'فات وقتها قبل $gap.' : '$gap past due.'));
  return streak > 0 ? '$lead ${habitStreakLine(streak, isAr)}' : lead;
}

/// Body for the one-hour snooze fired from a habit reminder's "Snooze 1h"
/// action.
///
/// Says what is actually known — an hour has passed since the snooze — and
/// not «حان الوقت», which this had no standing to claim: the reminder being
/// snoozed may itself have been an early or a late one, and the snooze is
/// measured from whenever the button was tapped rather than from the habit's
/// own moment, so the real distance to that moment is unknowable here. The
/// hour, on the other hand, is exact: the schedule is literally now + 1h.
String snoozedReminderBody(bool isAr) => isAr
    ? 'صار لها ساعة من التأجيل.'
    : 'An hour since you snoozed.';

/// Title for the one combined notification 2+ habits landing inside the
/// bundle window share.
///
/// Bundling groups by the CLOCK, so one bundle can hold habits with
/// different offsets — a 9:00 habit reminded 15 minutes early and a 8:50
/// habit reminded on time both fire at 8:45. Only a bundle whose members
/// genuinely agree gets the specific wording; a mixed one falls back to
/// "waiting", which is true whatever each member's own offset is. The old
/// "ready" is kept for the all-on-time case and nothing else, since a
/// bundle of reminders that are all 15 minutes early is precisely the case
/// where "ready" is the lie this file exists to stop telling.
String habitBundleTitle({
  required List<int> offsetMinutes,
  required bool isAr,
}) {
  final count = offsetMinutes.length;
  if (offsetMinutes.every((o) => o == 0)) {
    return isAr ? '$count عادات جاهزة' : '$count habits ready';
  }
  final first = offsetMinutes.first;
  if (first < 0 && offsetMinutes.every((o) => o == first)) {
    final gap = countedOffsetPhrase(first.abs(), isAr);
    return isAr
        ? 'باقي $gap على $count عادات'
        : '$gap until $count habits';
  }
  return isAr ? '$count عادات تنتظرك' : '$count habits waiting';
}
