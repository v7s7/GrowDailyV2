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

/// The streak line a habit reminder leads with once there's a streak. Its
/// own function because it is appended to three different bodies and they
/// must not drift apart.
///
/// Framed forward, not as a loss. It used to read «لا تفقد سلسلتك المكوّنة
/// من ٧ أيام» / "Don't lose your 7-day streak": the same number, pointed at
/// what the reader stands to lose. Loss framing does move people, but it
/// turns every reminder into a small threat, and the person it leans on
/// hardest is the one who already missed a day. Pointing the number at
/// tomorrow instead keeps the whole stake and drops the threat.
///
/// The day count goes through [countedOffsetPhrase] (a streak is a count of
/// days, and days are one of its units), so it declines properly: «يومين»
/// for two, «٧ أيام» for 3 to 10, back to «١٥ يوم» from 11 up. A streak of
/// one is spelled out on its own: «يوم ورا بعض» counts a day against
/// nothing.
///
/// [variantIndex] adds a second phrasing that says out loud that it is
/// going well, rather than leaving the reader to infer it from the number.
/// It defaults to the first line so the early/late bodies in
/// [habitReminderBody], which have no variant of their own to spend, keep
/// saying exactly one thing.
///
/// [everyDay] is false for a habit pinned to specific weekdays. Its streak
/// counts the days it RUNS ON (see scheduledGap), so «٣ أيام ورا بعض» /
/// "3 days in a row" would be read as three consecutive calendar days and
/// be false for a Wed/Sat habit; those count «مرات» / times instead.
String habitStreakLine(
  int streak,
  bool isAr, {
  int variantIndex = 0,
  bool everyDay = true,
}) {
  if (!isAr) {
    if (streak == 1) {
      return _pick(
        everyDay
            ? const [
                'One day down. Today makes it two.',
                "One day down and it's already working. Today makes it two.",
              ]
            : const [
                'One down. Today makes it two.',
                "One down and it's already working. Today makes it two.",
              ],
        variantIndex,
      );
    }
    final run = everyDay ? '$streak days in a row' : '$streak in a row';
    return _pick([
      '$run. Today makes it ${streak + 1}.',
      '$run and going strong. Today makes it ${streak + 1}.',
    ], variantIndex);
  }
  if (streak == 1) {
    return _pick(
      everyDay
          ? const [
              'يوم واحد في السلسلة، واليوم يخليها يومين.',
              'يوم واحد في السلسلة والبداية زينة، واليوم يخليها يومين.',
            ]
          : const [
              'مرة وحدة في السلسلة، واليوم يخليها ثنتين.',
              'مرة وحدة في السلسلة والبداية زينة، واليوم يخليها ثنتين.',
            ],
      variantIndex,
    );
  }
  final counted = everyDay
      ? countedOffsetPhrase(streak * ReminderUnit.days.inMinutes, true)
      : _countedRepeats(streak, true);
  final next = arabicDigits(streak + 1);
  return _pick([
    '$counted ورا بعض، واليوم يخليها $next.',
    '$counted ورا بعض وماشية عدل، واليوم يخليها $next.',
  ], variantIndex);
}

/// How many of today's target are still owed, counted the way a repetition
/// is counted out loud: «وحدة», «ثنتين», «٣ مرات», «١١ مرة».
///
/// Separate from [countedOffsetPhrase] because that one counts *units of
/// time* and this counts logs of a habit, which is a different noun in
/// Arabic and no noun at all in English ("2 more", not "2 more times").
String _countedRepeats(int n, bool isAr) {
  // Capitalised: it opens the second sentence of the English line.
  if (!isAr) return n == 1 ? 'One more' : '$n more';
  return switch (n) {
    1 => 'وحدة',
    2 => 'ثنتين',
    <= 10 => '${arabicDigits(n)} مرات',
    _ => '${arabicDigits(n)} مرة',
  };
}

/// "It only takes 2 minutes" for a habit that carries a timer, and so is
/// the one kind of habit that knows exactly how long it takes.
///
/// Null when there is no timer, or when the duration isn't a whole number
/// of minutes: the phrase counts minutes, and a reminder has no business
/// saying «وقتها ٩٠ ثانية بس».
String? _timerLead(int? timerSeconds, bool isAr) {
  if (timerSeconds == null || timerSeconds < 60 || timerSeconds % 60 != 0) {
    return null;
  }
  final phrase = countedOffsetPhrase(timerSeconds ~/ 60, isAr);
  return isAr ? 'وقتها $phrase بس.' : 'It only takes $phrase.';
}

/// Which line of a state's pool this reminder gets. See [habitOnTimeLine]
/// for what the caller mixes into [variantIndex].
String _pick(List<String> pool, int variantIndex) =>
    pool[variantIndex.abs() % pool.length];

/// The one sentence a habit reminder says under the habit's own name when
/// it fires on the dot.
///
/// ── Why this is a ladder and not a pool ─────────────────────
/// It was one rotating pool of four generic lines, so a brand new habit,
/// the most fragile thing in the app, drew «بضع دقائق لهذه العادة اليوم» /
/// "A few minutes for this one today": a sentence that names no number,
/// asks for nothing, and says "هذه العادة" about a habit the title directly
/// above it has already named. Every reminder anyone actually likes does
/// the opposite. Duolingo's are specific and carry a stake, Finch's are
/// warm and never charge you for a gap, and Habitica's whole reminder
/// feature is letting a habit say its own words instead of "complete
/// habit". What they share is that the notification knows something about
/// THIS habit and says it.
///
/// So the line is picked by the habit's real state, most specific first:
///   1. part of today already logged, which is both the most useful thing
///      the app knows and the one thing the title above cannot show;
///   1b. for a flexible weekly quota, where the week stands, since the week
///      is what that habit is measured by (see below);
///   2. a live streak, pointed forward by [habitStreakLine];
///   3. never once completed, so the ask is the first square and not a
///      streak the habit doesn't have yet;
///   4. completed before but lapsed, with the gap named and no blame
///      attached, because "3 days" is a fact and "you broke it" is a
///      charge;
///   5. whatever is left, warm and short.
///
/// ── Lapsed means a day it RUNS ON was missed ──────────────
/// State 4 is entered on [missedSinceLastDone], never on the size of
/// [lastDoneDaysAgo]. The two agree for a daily habit and disagree for
/// every other cadence, and the disagreement was a reported bug: a habit
/// set to two weekdays, done on the first and reminded on the second, was
/// told «صار لها ٣ أيام، وما ضاع شي» about a gap that owed nothing. Three
/// days had passed and not one of them was a day the habit ran, so it had
/// not lapsed, and a reminder that says otherwise is saying it is fine to
/// be late to someone who is not late. The caller counts the missed days
/// on the habit's own schedule (see NotificationService.reminderFactsAtFireDay);
/// [lastDoneDaysAgo] only ever supplies the wording of a lapse that is real.
///
/// ── A weekly quota is judged by its week ──────────────────
/// [weekTarget] is set for a habit that runs "N times a week, any days",
/// with [weekDone] how many of this week are logged (null while the week's
/// squares are not loaded, in which case nothing is claimed about the week)
/// and [owedToday] whether skipping today puts the target out of reach
/// (see DayDemand.owed). Such a habit has no days of its own to be late on,
/// so it never draws the streak line either: its streak counter is a
/// calendar count and says nothing true about a week.
/// Each state carries more than one phrasing, and the extra ones are the
/// two things a reminder is actually for: saying it is going well where
/// there is something to say that about (states 1 and 2), and saying it
/// would be a shame to let today go where there is not (3 and 5). State 4
/// gets neither, because the person it is talking to has already missed
/// days and does not need either a cheer or a nudge about it.
/// States 3 to 5 prepend the habit's real length when it carries a timer,
/// which is the honest version of what «بضع دقائق» was gesturing at.
///
/// ── The register ─────────────────────────────────────
/// Impersonal, per this file's header, and it costs more here than
/// anywhere else in the file: the obvious motivational sentence is an
/// imperative, and an Arabic imperative is gendered («لوّن» vs «لوّني»). The
/// old pool simply picked masculine and was wrong for half the people
/// reading it. Every line below is nominal or third-person about the habit
/// or the day, so none of them has a gender to get wrong.
///
/// [variantIndex] picks within a state's pool. The caller mixes the day
/// with the habit id, so the wording holds still for one habit on one day
/// (a mid-day reschedule must not visibly reword a pending notification)
/// while two habits firing in the same minute don't say the same sentence
/// twice.
///
/// [lastDoneDaysAgo] is null for a habit never completed, and otherwise
/// counts effective days back from the day this reminder FIRES rather than
/// from today, so a reminder armed tonight for Thursday still says a true
/// number when it arrives.
String habitOnTimeLine({
  required int streak,
  required int completedCount,
  required int dailyTarget,
  required int? lastDoneDaysAgo,
  required int missedSinceLastDone,
  required int? timerSeconds,
  required int variantIndex,
  required bool isAr,
  bool everyDay = true,
  int? weekTarget,
  int? weekDone,
  bool owedToday = false,
}) {
  // 1. Some of today is already in. Nothing else the app knows beats
  //    telling someone exactly where they stand on the thing they're
  //    being pinged about.
  if (completedCount > 0 && completedCount < dailyTarget) {
    final left = _countedRepeats(dailyTarget - completedCount, isAr);
    if (!isAr) {
      return _pick([
        '$completedCount of $dailyTarget today. $left to go.',
        '$completedCount of $dailyTarget today and going well. '
            '$left to go.',
      ], variantIndex);
    }
    final done = arabicDigits(completedCount);
    final target = arabicDigits(dailyTarget);
    return _pick([
      '$done من $target اليوم، وباقي $left.',
      '$done من $target اليوم وماشية عدل، وباقي $left.',
    ], variantIndex);
  }
  // 1b. A flexible weekly quota measures itself by the week, and the week
  //     is the one thing its title cannot show. Once the target is met the
  //     rest of the week owes nothing and the line says so instead of
  //     nagging; a day the quota genuinely needs is named as such. Nothing
  //     is said while the week's squares are unknown: a claim about the
  //     week needs the week.
  if (weekTarget != null && weekDone != null) {
    final target = isAr ? arabicDigits(weekTarget) : '$weekTarget';
    final done = isAr ? arabicDigits(weekDone) : '$weekDone';
    if (weekDone >= weekTarget) {
      return isAr
          ? 'هدف الأسبوع تم، $done من $target، ومربع اليوم زيادة.'
          : 'Week target met, $done of $target. Today is a bonus square.';
    }
    final left = _countedRepeats(weekTarget - weekDone, isAr);
    final needed = isAr ? '، واليوم مطلوب.' : ', and today is one of them.';
    if (weekDone > 0) {
      if (owedToday) {
        return isAr
            ? '$done من $target هذا الأسبوع، وباقي $left$needed'
            : '$done of $target this week. $left to go$needed';
      }
      return _pick(
        isAr
            ? [
                '$done من $target هذا الأسبوع، وباقي $left.',
                '$done من $target هذا الأسبوع وماشية عدل، وباقي $left.',
              ]
            : [
                '$done of $target this week. $left to go.',
                '$done of $target this week and going well. $left to go.',
              ],
        variantIndex,
      );
    }
    if (owedToday) {
      return isAr
          ? 'باقي $left هذا الأسبوع$needed'
          : '$left to go this week$needed';
    }
  }
  // 2. A live streak is its own reason to act. Never for a quota habit:
  //    see the doc comment.
  if (streak > 0 && weekTarget == null) {
    return habitStreakLine(
      streak,
      isAr,
      variantIndex: variantIndex,
      everyDay: everyDay,
    );
  }

  final lead = _timerLead(timerSeconds, isAr);
  final String line;
  if (lastDoneDaysAgo == null) {
    // 3. Never done once. Ask for the first square.
    line = _pick(
      isAr
          ? const [
              'أول مربع فيها اليوم، ومن هنا تبدأ العادة.',
              'عادة جديدة تنتظر أول مربع لها.',
              'أول يوم هو الأصعب، وبعده تمشي مع نفسها.',
              'أول مربع فيها اليوم، وخسارة يفوت.',
            ]
          : const [
              'First square today. This is where it starts.',
              'A new habit waiting on its first square.',
              'The first day is the hard one, then it carries itself.',
              'First square today. A shame to let it slip.',
            ],
      variantIndex,
    );
  } else if (missedSinceLastDone > 0 && lastDoneDaysAgo >= 2) {
    // 4. Done before, and a day it runs on has ended without it. Name the
    //    gap, and leave the door open. The gap is still counted in calendar
    //    days, since that is how long it has actually been; only the
    //    DECISION that there is a lapse to name is on the schedule.
    final gap = countedOffsetPhrase(
        lastDoneDaysAgo * ReminderUnit.days.inMinutes, isAr);
    line = _pick(
      isAr
          ? [
              'صار لها $gap. مربع واحد اليوم وترجع السلسلة.',
              'آخر مرة كانت قبل $gap، واليوم بداية جديدة لها.',
              'صار لها $gap، وما ضاع شي. مربع واحد يرجعها.',
            ]
          : [
              "It's been $gap. One square today and the streak is back.",
              'Last done $gap ago. Today is a clean start.',
              "It's been $gap and nothing is lost. One square brings it back.",
            ],
      variantIndex,
    );
  } else {
    // 5. Nothing specific to say, so say something short and kind.
    line = _pick(
      isAr
          ? const [
              'وقتها الحين، ومربع اليوم على بعد دقايق.',
              'اليوم ما زال فيه وقت لها.',
              'وقتها الحين، وخسارة لو تفوت اليوم.',
            ]
          : const [
              "It's time. Today's square is minutes away.",
              "There's still time for this one today.",
              "It's time. Don't let today slip by.",
            ],
      variantIndex,
    );
  }
  return lead == null ? line : '$lead $line';
}

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
///
/// [everyDay] reaches the streak clause, see [habitStreakLine].
String habitReminderBody({
  required int offsetMinutes,
  required int streak,
  required String? anchorLabel,
  required bool isAr,
  required String onTimeLine,
  bool everyDay = true,
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
  return streak > 0
      ? '$lead ${habitStreakLine(streak, isAr, everyDay: everyDay)}'
      : lead;
}

// ── Action buttons ──────────────────────────────────────────────────
//
// The two buttons under a habit reminder, and the two under a quit
// check-in. They were English on an Arabic device, which is the one part of
// the notification the reader is meant to ACT on, so the whole ping stopped
// being in their language exactly where it asked for something.
//
// Nominal, not imperative, for the reason the file header gives: «تمت» is a
// statement about the habit and works for whoever taps it, where «سجّل» has
// to pick a gender. They are short on purpose too, since both platforms
// truncate a button label hard.

/// "Done" for a habit reminder's completion button.
String markDoneAction(bool isAr) => isAr ? 'تمت' : 'Mark Done';

/// The Done button on a task's ringing alarm. «تم» rather than «تمت»: a
/// task is masculine where a habit is feminine, and the button sits under
/// the task's own title.
String taskDoneAction(bool isAr) => isAr ? 'تم' : 'Done';

/// The Stop button on a ringing alarm, where iOS asks the app for one.
String alarmStopAction(bool isAr) => isAr ? 'إيقاف' : 'Stop';

/// "Snooze an hour" for a habit reminder's postpone button. Matches what
/// [snoozedReminderBody] later says about it.
String snoozeAction(bool isAr) => isAr ? 'تأجيل ساعة' : 'Snooze 1h';

/// A quit check-in's two answers. «التزام» covers both quit shapes the way
/// "On Track" does (avoid-completely and stay-under-a-limit alike), and
/// «زلة» is the ordinary word for a slip, with none of the weight of
/// «فشل».
String onTrackAction(bool isAr) => isAr ? 'التزام' : 'On Track';
String slippedAction(bool isAr) => isAr ? 'زلة' : 'Slipped';

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
  // Counted the same way countedOffsetPhrase counts its units: dual for
  // two (a bundle's most common size, and «2 عادات» is exactly the error
  // that function exists to avoid), plural for 3–10, singular from 11 up.
  // Genitive/spoken dual («عادتين») for the register the file header
  // documents.
  final counted = !isAr
      ? '$count habits'
      : switch (count) {
          2 => 'عادتين',
          <= 10 => '${arabicDigits(count)} عادات',
          _ => '${arabicDigits(count)} عادة',
        };
  if (offsetMinutes.every((o) => o == 0)) {
    if (!isAr) return '$counted ready';
    // The adjective agrees the way the noun declined: dual with dual,
    // feminine singular with a non-human plural, and with the 11+
    // singular noun.
    return switch (count) {
      2 => 'عادتين جاهزتين',
      _ => '$counted جاهزة',
    };
  }
  final first = offsetMinutes.first;
  if (first < 0 && offsetMinutes.every((o) => o == first)) {
    final gap = countedOffsetPhrase(first.abs(), isAr);
    return isAr ? 'باقي $gap على $counted' : '$gap until $counted';
  }
  if (!isAr) return '$counted waiting';
  // «بانتظارك» for the dual dodges the verb having to agree with a dual
  // feminine subject, and matches the task copy's own register.
  return count == 2 ? 'عادتين بانتظارك' : '$counted تنتظرك';
}

/// Offsets (in minutes) an extra reminder can sit at, relative to its
/// anchor — a task's reminder time, or a habit's clock time or prayer.
/// Unsigned: direction is a separate two-chip toggle the user sets once and
/// then applies to as many offsets as they like.
///
/// Five, which together with the custom cell makes six on a 3-column grid:
/// two complete rows with no ragged gap.
///
/// Lives here, beside the copy that words a reminder, rather than in either
/// screen that draws the grid: Tasks and Add Habit ask the identical
/// question and are meant to be indistinguishable, and a preset list owned
/// by one of them is a preset list the other can drift away from.
const kReminderOffsetPresets = <int>[5, 10, 15, 30, 60];

/// Chip label for an offset: the number for minutes, a word for the hours,
/// since "120" reads worse than "ساعتان" at a glance. Direction comes from
/// the قبل/بعد toggle above the grid, not from the label.
String reminderOffsetLabel(int minutes, bool isAr) {
  if (minutes == 60) return isAr ? 'ساعة' : '1 hour';
  if (minutes == 120) return isAr ? 'ساعتان' : '2 hours';
  return isAr ? arabicDigits(minutes) : '$minutes';
}

// ── The daily reminder, the streak nudge and the weekly note ────────
//
// Aziz, 2026-09-07: "some daily reminder talks like you didn't do anything".
// It did. The تذكير يومي was five fixed lines drawn by the date, so a person
// who had coloured five of six squares was told at eight o'clock «عاداتك
// تنتظرك» and «لا تكسر السلسلة», and a person who had finished everything
// was told the same. The app reschedules that reminder on every change of
// state (main.dart's _recomputeNotifications), so it knows exactly where
// the day stands and can say that instead. Tonight's line is derived here
// from what is done; a fixed pool survives only as the fallback for a
// phone that has not opened the app in days and has no fresh state to
// speak from, and it makes no claim about the day at all.
//
// Four decisions Aziz made the same evening, asked one by one:
//   1. The voice is warm and proud: what is done comes first and is praised
//      («يومك ماشي عدل»), what is left is small («والباقي عادتين بس»).
//   2. Variety. The forward-pointed streak line stays, but as one voice
//      among several, so the same evening does not read the same every
//      day; some nights it is simply time for your habits.
//   3. A light Islamic warmth where it falls naturally («ما شاء الله» over
//      a good day, «بسم الله» over a first square, «الحمد لله» over a good
//      week), never in every line: a water habit reads the same as أذكار.
//   4. The fallback keeps coming every day until the app is opened again.
//
// Same register as the rest of this file: about the day, never a gendered
// imperative, and never a loss («لا تكسر», «على المحك») pointed at the
// reader. Duolingo built a brand on the guilt owl, and in a 2022 survey of
// its users most felt guilty about a missed day and a third felt anxious
// about the notifications. These habits are صلاة and أذكار; guilt is the
// wrong instrument for them.
//
// One grammatical trick carries the whole "proud" voice without a gender:
// «٢ من ٧ خلّصت». An inanimate plural takes the feminine singular, so the
// verb belongs to the habits, not to the reader. Verb first, «خلّصت ٢ من
// ٧», would be second person and wrong for half the people reading it.

/// How many habits are still owed, counted the way Arabic counts the noun:
/// «عادة وحدة», «عادتين», «٣ عادات», «١١ عادة».
String _countedHabits(int n, bool isAr) {
  if (!isAr) return n == 1 ? '1 habit' : '$n habits';
  return switch (n) {
    1 => 'عادة وحدة',
    2 => 'عادتين',
    <= 10 => '${arabicDigits(n)} عادات',
    _ => '${arabicDigits(n)} عادة',
  };
}

typedef ReminderLine = ({String title, String body});

ReminderLine _pickLine(List<ReminderLine> pool, int variantIndex) =>
    pool[variantIndex.abs() % pool.length];

/// Tonight's daily reminder, from where the day actually stands, or null
/// when nothing is owed (every habit due today is done, or none was due).
/// Null means the reminder must not fire at all: a ping after a finished
/// day is the purest form of "you did nothing".
///
/// Three states, most specific first, each with three voices that
/// [variantIndex] (the caller's day seed) rotates through:
///   1. part of today is done: the number first, praised, then what is left;
///   2. nothing yet but a streak is live: the streak pointed at tomorrow by
///      [habitStreakLine], with or without «ما شاء الله», or simply that it
///      is time;
///   3. nothing yet and no streak: an open door and one square.
ReminderLine? dailyReminderLine({
  required int done,
  required int total,
  required int streak,
  required int variantIndex,
  required bool isAr,
}) {
  if (total <= 0 || done >= total) return null;
  if (done > 0) {
    final left = _countedHabits(total - done, isAr);
    if (!isAr) {
      return _pickLine([
        (
          title: 'Your day is going well',
          body: '$done of $total done, only $left left.',
        ),
        (
          title: 'Ma sha Allah, almost there',
          body: '$done of $total done. $left to go, and the day is complete.',
        ),
        (
          title: 'Your day is going well',
          body: '$done of $total done and going strong, only $left left.',
        ),
      ], variantIndex);
    }
    final d = arabicDigits(done);
    final t = arabicDigits(total);
    return _pickLine([
      (title: 'يومك ماشي عدل', body: '$d من $t خلّصت، والباقي $left بس.'),
      (
        title: 'ما شاء الله، شوي ويكتمل يومك',
        body: '$d من $t خلّصت. باقي $left واليوم يكتمل.',
      ),
      (
        title: 'يومك ماشي عدل',
        body: '$d من $t خلّصت وماشية عدل، والباقي $left بس.',
      ),
    ], variantIndex);
  }
  if (streak > 0) {
    final streakLine = habitStreakLine(streak, isAr);
    if (!isAr) {
      return _pickLine([
        (title: 'Time for your habits', body: streakLine),
        (title: 'Today is still open', body: 'Ma sha Allah, $streakLine'),
        (
          title: 'Time for your habits',
          body: 'Bismillah. One square opens the day, and the streak carries on.',
        ),
      ], variantIndex);
    }
    return _pickLine([
      (title: 'وقت عاداتك', body: streakLine),
      (title: 'يومك مفتوح إلى الآن', body: 'ما شاء الله، $streakLine'),
      (
        title: 'وقت عاداتك',
        body: 'بسم الله، مربع واحد يفتح اليوم، والسلسلة تكمل.',
      ),
    ], variantIndex);
  }
  if (!isAr) {
    return _pickLine([
      (title: 'Today is still open', body: 'One square is enough to begin.'),
      (title: 'Time for your habits', body: 'Bismillah. A small step today counts.'),
      (
        title: 'A light reminder',
        body: 'Which habit fits right now? One square is enough.',
      ),
    ], variantIndex);
  }
  return _pickLine([
    (title: 'يومك مفتوح إلى الآن', body: 'مربع واحد يكفي للبداية.'),
    (title: 'وقت عاداتك', body: 'بسم الله، خطوة صغيرة اليوم تنحسب.'),
    (title: 'تذكير خفيف', body: 'أي عادة تنفع الحين؟ مربع واحد يكفي.'),
  ], variantIndex);
}

/// The recurring fallback copy of the daily reminder, seven weekly repeats
/// armed every time the app recomputes so a phone that stays closed for
/// days still hears something, every day, until it is opened again (Aziz's
/// choice over letting it fade). It knows nothing about the day, so it
/// claims nothing about it: no "waiting", no "don't break", no streak.
/// [dayIndex] is the caller's weekday, so one weekday always draws one line.
ReminderLine dailyFallbackLine(int dayIndex, bool isAr) {
  const ar = <ReminderLine>[
    (title: 'وقت عاداتك', body: 'بسم الله، شوي وقت الحين يلوّن مربع اليوم.'),
    (title: 'يومك مفتوح إلى الآن', body: 'خطوة صغيرة اليوم تنحسب.'),
    (title: 'تذكير خفيف', body: 'أي عادة تنفع الحين؟'),
    (title: 'إلى الآن فيه وقت', body: 'مربع واحد يكفي، والشبكة تحفظه.'),
    (title: 'عاداتك على بعد لمسة', body: 'دقايق بسيطة، ومربع جديد في الشبكة.'),
  ];
  const en = <ReminderLine>[
    (title: 'Time for your habits', body: "Bismillah. A few minutes now colors today's square."),
    (title: 'Today is still open', body: 'A small step today counts.'),
    (title: 'A light reminder', body: 'Which habit fits right now?'),
    (title: 'Still time today', body: 'One square is enough, and the grid keeps it.'),
    (title: 'Your habits, one touch away', body: 'A few easy minutes, one new square.'),
  ];
  return _pickLine(isAr ? ar : en, dayIndex);
}

/// The evening streak nudge: what is done first, what is left, and the
/// streak pointed at tomorrow. It used to open with «سلسلتك على المحك» /
/// "Your streak is on the line" and list only what was missing, which is a
/// threat followed by a to-do list. Only ever built for a live streak with
/// something still owed, which is when the caller fires it at all.
/// [urgentTasks] adds the Matrix line when the person has opted into it;
/// [variantIndex] alternates the plain body with one that opens on
/// «ما شاء الله».
ReminderLine streakRiskCopy({
  required int done,
  required int total,
  required int streak,
  required int urgentTasks,
  required bool isAr,
  int variantIndex = 0,
}) {
  final left = _countedHabits(total - done, isAr);
  final streakLine = habitStreakLine(streak, isAr);
  final warm = variantIndex.abs() % 2 == 1;
  if (!isAr) {
    final title =
        streak == 1 ? 'Your streak has begun' : 'Your $streak-day streak is going';
    final today = done > 0
        ? '$done of $total done, only $left left.'
        : '$left to go today.';
    final tasks = urgentTasks > 0
        ? ' · $urgentTasks urgent task${urgentTasks == 1 ? '' : 's'} waiting'
        : '';
    return (
      title: title,
      body: warm
          ? 'Ma sha Allah, $streakLine $today$tasks'
          : '$today $streakLine$tasks',
    );
  }
  final title = streak == 1
      ? 'سلسلتك بدأت'
      : 'سلسلتك ${countedOffsetPhrase(streak * ReminderUnit.days.inMinutes, true)} ماشية';
  final today = done > 0
      ? '${arabicDigits(done)} من ${arabicDigits(total)} خلّصت، والباقي $left بس.'
      : 'باقي $left اليوم.';
  final tasks =
      urgentTasks > 0 ? ' · ${arabicDigits(urgentTasks)} مهمة عاجلة بانتظارك' : '';
  return (
    title: title,
    body: warm
        ? 'ما شاء الله، $streakLine $today$tasks'
        : '$today $streakLine$tasks',
  );
}

/// The Friday note. A week with nothing coloured used to read «لم يُلوَّن أي
/// يوم بعد هذا الأسبوع» / "No days colored yet this week", a verdict about
/// absence in a register nobody here speaks; it is now a quiet week and an
/// open door. The other lines count the days impersonally («ملوّنة», not
/// «لوّنت», which is masculine), point the streak forward, and open on
/// «الحمد لله» when five or more of the seven were coloured.
String weeklyDigestBody({
  required int greenDays,
  required int streak,
  required bool isAr,
}) {
  if (greenDays <= 0) {
    return isAr
        ? 'أسبوع هادي، ويصير. مربع واحد يكفي لبداية جديدة.'
        : 'A quiet week, it happens. One square is enough for a fresh start.';
  }
  final thanks = greenDays >= 5;
  if (!isAr) {
    final line = '${thanks ? 'Alhamdulillah, ' : ''}'
        '$greenDays of 7 days colored this week';
    return streak > 0 ? '$line, and a $streak-day streak going.' : '$line.';
  }
  final line = '${thanks ? 'الحمد لله، ' : ''}'
      '${arabicDigits(greenDays)} من ٧ أيام ملوّنة هذا الأسبوع';
  if (streak <= 0) return '$line.';
  if (streak == 1) return '$line، والسلسلة بدأت.';
  final run = countedOffsetPhrase(streak * ReminderUnit.days.inMinutes, true);
  return '$line، وسلسلة $run ماشية.';
}

// ── A quit habit's reminder ─────────────────────────────────────────
//
// A quit habit with a clock or prayer cue used to get the build wording:
// "It's time. Don't let today slip by." about something the person is
// trying NOT to do, with Mark Done / Snooze under it. The reminder for a
// quit habit is a check-in, and it carries the check-in's two answers
// (التزام / زلة, see onTrackAction and slippedAction), so its body names
// them. Impersonal like everything in this file; «كيف اليوم» asks about the
// day, not the person.

/// The body of a quit habit's timed reminder. [isLimit] is the set-a-limit
/// shape, whose question is about the limit rather than about a slip.
String quitReminderBody({required bool isLimit, required bool isAr}) {
  if (isAr) {
    return isLimit
        ? 'ضمن الحد إلى الآن؟ التزام أو زلة.'
        : 'كيف اليوم إلى الآن؟ التزام أو زلة.';
  }
  return isLimit
      ? 'Within the limit so far? Kept or slipped.'
      : 'How is today so far? Kept or slipped.';
}
