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
/// than to the person: "صار لها ساعة", never "فاتتك". Possessive ك is
/// fine unvocalized, which is why "مهمتك" and "بانتظارك" still appear.
///
/// The ask is the one exception. Aziz's picks of 2026-09-11 give every habit
/// reminder one short spoken ask («سوي عادتك الحين», «خلّك جاهز»), in the
/// app's masculine second person, the way the one reminder he loved already
/// did. Everything around the ask stays about the habit or the day.
///
/// ── And it does not tell anyone they failed ─────────────────────────
/// A late reminder states the clock and asks for the thing. It does not
/// deliver a verdict on the day. «فات» is barred for exactly that reason:
/// "فات الفجر قبل ١٥ دقيقة" tells the reader they have already lost
/// something, at the one moment they can still do it. The prayer is an
/// anchor, so the honest and kinder sentence is the call to prayer itself,
/// followed by the ask: «اذن الفجر قبل ١٥ دقيقة، سوي عادتك الحين». Same
/// rule as the daily reminder's, which never states an absence as a
/// verdict. Anything past due says how long it has been and what to do
/// about it, never what was lost.
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
  return isAr ? 'وقتها كان قبل $gap' : 'This was due $gap ago';
}

// ── Habit reminders ─────────────────────────────────────────────────
//
// Mirror image of the task split: a habit reminder's TITLE is already the
// habit's own name (that is what makes "Mark Done" from the lock screen
// unambiguous), so the timing has to go in the body, alongside whatever
// encouragement was already there.

/// The forward streak line, which points today's run at tomorrow. Habit
/// reminders used to lead with it; since Aziz's picks of 2026-09-11 they
/// praise a run with [lateStreakPraise] instead, and this line now feeds
/// only the daily reminder ([dailyReminderLine]).
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
/// It defaults to the first line.
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

/// «الثانية» for the second round of a habit done several times a day, on up
/// to «العاشرة», then «رقم ١١». Never the first: a round is only named once
/// one is already logged today, since a تمت tapped on the lock screen does
/// not reword the other slots and «المرة الأولى» could be false by then.
String _roundName(int round, bool isAr) {
  if (isAr) {
    const names = {
      2: 'الثانية',
      3: 'الثالثة',
      4: 'الرابعة',
      5: 'الخامسة',
      6: 'السادسة',
      7: 'السابعة',
      8: 'الثامنة',
      9: 'التاسعة',
      10: 'العاشرة',
    };
    return names[round] ?? 'رقم ${arabicDigits(round)}';
  }
  const names = {
    2: 'two',
    3: 'three',
    4: 'four',
    5: 'five',
    6: 'six',
    7: 'seven',
    8: 'eight',
    9: 'nine',
    10: 'ten',
  };
  return names[round] ?? '$round';
}

/// The sentence a habit reminder says under the habit's own name when it
/// fires on the dot.
///
/// ── The voice, Aziz's pick of 2026-09-11 ──────────────────
/// Built on the one reminder he loved, «اذن الفجر قبل ١٥ دقيقة. سوي عادتك
/// الحين. ملتزم صارلك ٣ أيام 👏🏼»: a plain clock fact, one short ask, and
/// one true, proud fact from the habit's own data. So the line is picked by
/// the habit's real state, most specific first:
///   1. part of today already logged, for a habit done several times a
///      day: which round this is and how much is done, «وقت المرة الثانية.
///      سويها الحين. ١ من ٣ خلّصت 👏🏼», or «وقت المرة الأخيرة.» for the
///      last one;
///   1b. for a flexible weekly quota, where the week stands, since the week
///      is what that habit is measured by (see below);
///   2. otherwise the moment and the ask: «اذن الفجر. سوي عادتك الحين.» for a
///      habit anchored to a prayer ([anchorLabel]), «وقتها الحين. سوي عادتك.»
///      for a clock time, followed by at most one tail:
///      - the praise tail ([lateStreakPraise]) for a live streak, counted on
///        the habit's own days per [everyDay];
///      - «بسم الله، أول مربع لها.» for a clock habit never once done.
///      A timer habit never once done says its real length in place of
///      «وقتها الحين.» («وقتها دقيقتين بس.»), which is the honest version of
///      «بضع دقائق». Done before with no streak, it keeps «وقتها الحين.»:
///      that is the only case Aziz saw the length in (catalog A4, option 2).
///
/// ── What went ─────────────────────────────────────────────
/// The loss lines («وخسارة لو تفوت اليوم», «عادة جديدة تنتظر أول مربع لها»)
/// and the gap lines («صار لها ٣ أيام. مربع واحد اليوم وترجع السلسلة»). A gap
/// states an absence and a loss points at one; the plain ask replaces both.
/// So [lastDoneDaysAgo] now only tells a habit never done from one done
/// before, and no line names how long it has been.
///
/// ── A weekly quota is judged by its week ──────────────────
/// [weekTarget] is set for a habit that runs "N times a week, any days",
/// with [weekDone] how many of this week are logged (null while the week's
/// squares are not loaded, in which case nothing is claimed about the week)
/// and [owedToday] whether skipping today puts the target out of reach
/// (see DayDemand.owed). Such a habit has no days of its own to be late on,
/// so it never draws the praise tail either: its streak counter is a
/// calendar count and says nothing true about a week.
///
/// [variantIndex] picks within a quota state's pool. The caller mixes the
/// day the reminder FIRES with the habit id, so the wording holds still for
/// one habit on one day (a mid-day reschedule must not visibly reword a
/// pending notification) while two habits firing in the same minute don't
/// say the same sentence twice.
///
/// [lastDoneDaysAgo] is null for a habit never completed, and otherwise
/// counts effective days back from the day this reminder FIRES rather than
/// from today, so a reminder armed tonight for Thursday still says a true
/// thing when it arrives.
String habitOnTimeLine({
  required int streak,
  required int completedCount,
  required int dailyTarget,
  required int? lastDoneDaysAgo,
  required int? timerSeconds,
  required int variantIndex,
  required bool isAr,
  bool everyDay = true,
  int? weekTarget,
  int? weekDone,
  bool owedToday = false,
  String? anchorLabel,
}) {
  // 1. Some of today is already in. Name the round this slot is for, and
  //    praise what is done: the one fact the title above cannot show.
  if (completedCount > 0 && completedCount < dailyTarget) {
    final isLast = dailyTarget - completedCount == 1;
    if (!isAr) {
      final moment = isLast
          ? 'Time for the last one.'
          : 'Time for round ${_roundName(completedCount + 1, false)}.';
      return '$moment Do it now. $completedCount of $dailyTarget done 👏🏼';
    }
    final moment = isLast
        ? 'وقت المرة الأخيرة.'
        : 'وقت المرة ${_roundName(completedCount + 1, true)}.';
    return '$moment سويها الحين. '
        '${arabicDigits(completedCount)} من ${arabicDigits(dailyTarget)} '
        'خلّصت 👏🏼';
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
  // 2. The moment, the ask, and at most one true tail. Never the praise for
  //    a quota habit: see the doc comment.
  final praised = streak > 0 && weekTarget == null;
  final String moment;
  final String ask;
  if (anchorLabel != null) {
    moment = isAr ? 'اذن $anchorLabel.' : "It's $anchorLabel.";
    ask = isAr ? 'سوي عادتك الحين.' : 'Do it now.';
  } else {
    final timerLead = !praised && lastDoneDaysAgo == null
        ? _timerLead(timerSeconds, isAr)
        : null;
    moment = timerLead ?? (isAr ? 'وقتها الحين.' : "It's time.");
    ask = isAr ? 'سوي عادتك.' : 'Do it now.';
  }
  final String? tail;
  if (praised) {
    tail = lateStreakPraise(streak, isAr, everyDay: everyDay);
  } else if (lastDoneDaysAgo == null && anchorLabel == null) {
    tail = isAr ? 'بسم الله، أول مربع لها.' : 'Bismillah, its first square.';
  } else {
    tail = null;
  }
  return tail == null ? '$moment $ask' : '$moment $ask $tail';
}

/// The ask a late reminder makes, rotated so the same words are not the
/// only thing the person ever reads.
///
/// Aziz's own wording, 2026-09-09: one phrase repeating every time «هي عادية
/// بس فيه احلى لا تخليها تتكرر بس هي». So the clock fact stays fixed and the
/// ask moves. On 2026-09-11 he kept «سوي عادتك الحين.» as the first ask and
/// replaced the other three («مستعد تنجز هالعادة الحين؟» and the two «يلا
/// يا ...، خلص اللي عليك» lines) with two in the same short voice. The
/// caller seeds [variantIndex] from the day the reminder FIRES, so a phone
/// left closed hears a different ask on the mornings armed ahead.
String lateReminderAsk(int variantIndex, bool isAr) => _pick(
      isAr
          ? const [
              'سوي عادتك الحين.',
              'تقدر تسويها الحين.',
              'يلا، سويها الحين.',
            ]
          : const [
              'Do it now.',
              'You can do it now.',
              'Come on, do it now.',
            ],
      variantIndex,
    );

/// The praise tail every habit reminder ends on when there is a streak:
/// warm and backward-looking, where [habitStreakLine] counts forward.
///
/// Aziz, 2026-09-09, on «سوي عادتك الحين» landing straight before «٧ أيام
/// ورا بعض، واليوم يخليها ٨»: «ماحب انه ... احذف». Two calls to action in one
/// breath, the second of which is really an arithmetic fact. A reminder that
/// is already asking owes the streak praise, not a second ask, so it says
/// what has been kept rather than what today would make it.
///
/// [everyDay] is false for a habit pinned to specific weekdays. Its streak
/// counts the days it RUNS ON (see scheduledGap), so «ملتزم صارلك ٤ أيام»
/// would read as four calendar days and be false for a Wed/Sat habit; it
/// counts times instead: «سويتها آخر مرة», «ملتزم مرتين ورا بعض», «ملتزم ٤
/// مرات ورا بعض», «ملتزم ١١ مرة ورا بعض».
String lateStreakPraise(int streak, bool isAr, {bool everyDay = true}) {
  if (!isAr) {
    if (!everyDay) {
      return switch (streak) {
        1 => 'You did it last time 👏🏼',
        2 => "You've kept it up twice in a row 👏🏼",
        _ => "You've kept it up $streak times in a row 👏🏼",
      };
    }
    return streak == 1
        ? "You've kept it up a day 👏🏼"
        : "You've kept it up $streak days 👏🏼";
  }
  if (!everyDay) {
    return switch (streak) {
      1 => 'سويتها آخر مرة 👏🏼',
      2 => 'ملتزم مرتين ورا بعض 👏🏼',
      <= 10 => 'ملتزم ${arabicDigits(streak)} مرات ورا بعض 👏🏼',
      _ => 'ملتزم ${arabicDigits(streak)} مرة ورا بعض 👏🏼',
    };
  }
  final counted = switch (streak) {
    1 => 'يوم',
    2 => 'يومين',
    <= 10 => '${arabicDigits(streak)} أيام',
    _ => '${arabicDigits(streak)} يوم',
  };
  return 'ملتزم صارلك $counted 👏🏼';
}

/// Body for one habit's reminder.
///
/// [offsetMinutes] is the habit's signed shift for this particular slot (a
/// multi-time habit carries one per time). [anchorLabel] names the prayer the
/// offset is measured from, so «باقي ٤٥ دقيقة على أذان المغرب» rather than
/// the vaguer «على وقتها». A plain clock time passes null: the fire time IS a
/// clock time, and repeating it back («باقي ١٥ دقيقة على ٩:٠٠») tells the
/// reader nothing they can't see in the notification's own timestamp.
///
/// [onTimeLine] is what an on-time reminder says ([habitOnTimeLine], which
/// already names the prayer at the adhan itself). An early or a late one
/// says its clock fact instead, then the ask, then the praise tail for a
/// live streak ([lateStreakPraise], on the habit's own days per [everyDay]):
///   - early: «باقي ١٥ دقيقة على أذان المغرب. خلّك جاهز. ملتزم صارلك ٣ أيام
///     👏🏼», or «على وقتها» for a clock time;
///   - late: «اذن الفجر قبل ١٥ دقيقة. سوي عادتك الحين. ملتزم صارلك ٣ أيام
///     👏🏼», or «صار لها ٣٠ دقيقة» for a clock time, with the ask rotated by
///     [variantIndex] (see [lateReminderAsk]).
/// Neither counts the streak forward («واليوم يخليها ٨»): Aziz cut that from
/// the late reminder on 2026-09-09, and the early one had no ask at all
/// until 2026-09-11.
String habitReminderBody({
  required int offsetMinutes,
  required int streak,
  required String? anchorLabel,
  required bool isAr,
  required String onTimeLine,
  bool everyDay = true,
  int variantIndex = 0,
}) {
  if (offsetMinutes == 0) return onTimeLine;
  final gap = countedOffsetPhrase(offsetMinutes.abs(), isAr);
  final praise = streak > 0
      ? ' ${lateStreakPraise(streak, isAr, everyDay: everyDay)}'
      : '';
  if (offsetMinutes < 0) {
    final lead = anchorLabel != null
        ? (isAr
            ? 'باقي $gap على أذان $anchorLabel.'
            : '$gap until the $anchorLabel adhan.')
        : (isAr ? 'باقي $gap على وقتها.' : '$gap to go.');
    final ready = isAr ? 'خلّك جاهز.' : 'Get ready.';
    return '$lead $ready$praise';
  }
  // Late. The clock fact, then the ask, then praise for the run if there is
  // one - never the forward-counting streak line, see [lateStreakPraise].
  final stamp = anchorLabel != null
      ? (isAr ? 'اذن $anchorLabel قبل $gap' : '$anchorLabel was $gap ago')
      : (isAr ? 'صار لها $gap' : "It's been $gap");
  final ask = lateReminderAsk(variantIndex, isAr);
  return '$stamp. $ask$praise';
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

/// The Done button on a task's ringing alarm. It says what the tap records,
/// because it sits beside the system's Stop and a bare «تم» did not (Aziz
/// chose these words on 2026-09-11). A verb, unlike the nominal buttons
/// above, but first person past has no gender to get wrong: «خلّصت» is the
/// same word whoever taps it. Tasks only; a habit's alarm carries Stop
/// alone, see AlarmService.
String taskDoneAction(bool isAr) => isAr ? 'خلّصت المهمة' : 'I did the task';

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

/// The longest a bundle's title may be, in characters, and still spell its
/// habits out by name. A notification title gets one line on the lock
/// screen before it is cut, and a list of names cut off mid-name reads worse
/// than a count. About 32 Arabic characters fit beside the timestamp on a
/// phone held upright; past that the title counts the habits instead.
const kBundleTitleMaxChars = 32;

/// Title for the one combined notification 2+ habits landing inside the
/// bundle window share: the habits themselves, «سنة الفجر وأذكار الصباح», or
/// «سنة الفجر، أذكار الصباح والوتر» for three or more.
///
/// That three-name example is 30 characters and fits. Most real trios do
/// not: [kBundleTitleMaxChars] is 32, so «سنة الفجر، أذكار الصباح وقيام
/// الليل» (35) is titled «٣ عادات» instead. A bundle of three therefore
/// usually reads as the count in practice, and only a bundle of two
/// reliably reads as names.
///
/// It used to be a count with a verdict on it, «عادتين بانتظارك» / «٣ عادات
/// تنتظرك»: the habits waiting on the reader. Aziz, 2026-09-11: name them,
/// and let the body say the moment. When the names do not fit
/// [kBundleTitleMaxChars] it falls back to the count alone, «عادتين» / «٣
/// عادات».
String habitBundleTitle({required List<String> names, required bool isAr}) {
  final count = names.length;
  if (count < 2) return names.join();
  final head = names.sublist(0, count - 1);
  // «و» is written joined to the name after it.
  final joined = isAr
      ? '${head.join('، ')} و${names.last}'
      : '${head.join(', ')} and ${names.last}';
  if (joined.length <= kBundleTitleMaxChars) return joined;
  return _countedHabits(count, isAr);
}

/// One member of a bundle as its body needs to see it: the moment it fires
/// against, and the facts recalculated for the day it fires on
/// (NotificationService.reminderFactsAtFireDay), never today's.
typedef BundleMember = ({
  int offsetMinutes,
  String? anchorLabel,
  DateTime fireTime,
  int streak,
  bool everyDay,
  bool isQuota,
});

/// Body for a bundle, in the voice of a single reminder: the moment, the
/// ask, and the praise.
///   - one prayer, the same shift after it: «اذن الفجر قبل ١٥ دقيقة. سوي
///     عاداتك الحين.»;
///   - the same shift before, at the same minute: «باقي ١٥ دقيقة على أذان
///     الفجر. خلّك جاهز.», or «على وقتها» when they are not one prayer;
///   - one adhan on the dot: «اذن الفجر. سوي عاداتك الحين.»;
///   - one clock minute on the dot: «وقتها الحين. سويها وحدة وحدة.»;
///   - anything mixed: «عادتين مع بعض. سويها وحدة وحدة.».
/// Bundling groups by the clock and knows nothing about offsets, so a mixed
/// bundle is real, and the generic line is the one true of every member.
///
/// The praise is said only when it is true of every member: each has a
/// streak and none is a weekly quota, and either all run every day or all
/// run on set weekdays. It shows the smallest streak among them, except a
/// weekday bundle whose smallest streak is one, which says no praise (see
/// [_bundlePraise]).
String habitBundleBody({
  required List<BundleMember> members,
  required bool isAr,
}) {
  final first = members.first;
  final offset = first.offsetMinutes;
  final sameOffset = members.every((m) => m.offsetMinutes == offset);
  final prayer = first.anchorLabel;
  final onePrayer =
      prayer != null && members.every((m) => m.anchorLabel == prayer);
  bool atFirstMinute(BundleMember m) =>
      m.fireTime.year == first.fireTime.year &&
      m.fireTime.month == first.fireTime.month &&
      m.fireTime.day == first.fireTime.day &&
      m.fireTime.hour == first.fireTime.hour &&
      m.fireTime.minute == first.fireTime.minute;
  final oneMinute = members.every(atFirstMinute);
  final String lead;
  if (sameOffset && onePrayer && offset > 0) {
    final gap = countedOffsetPhrase(offset, isAr);
    lead = isAr
        ? 'اذن $prayer قبل $gap. سوي عاداتك الحين.'
        : '$prayer was $gap ago. Do them now.';
  } else if (sameOffset && offset < 0 && oneMinute) {
    final gap = countedOffsetPhrase(-offset, isAr);
    lead = onePrayer
        ? (isAr
            ? 'باقي $gap على أذان $prayer. خلّك جاهز.'
            : '$gap until the $prayer adhan. Get ready.')
        : (isAr ? 'باقي $gap على وقتها. خلّك جاهز.' : '$gap to go. Get ready.');
  } else if (sameOffset && offset == 0 && onePrayer) {
    lead = isAr ? 'اذن $prayer. سوي عاداتك الحين.' : "It's $prayer. Do them now.";
  } else if (sameOffset &&
      offset == 0 &&
      oneMinute &&
      members.every((m) => m.anchorLabel == null)) {
    lead = isAr ? 'وقتها الحين. سويها وحدة وحدة.' : "It's time. One at a time.";
  } else {
    final count = members.length;
    lead = isAr
        ? '${_countedHabits(count, true)} مع بعض. سويها وحدة وحدة.'
        : '${count == 2 ? 'Two habits' : '$count habits'} together. '
            'One at a time.';
  }
  final praise = _bundlePraise(members, isAr);
  return praise == null ? lead : '$lead $praise';
}

/// The praise a bundle can say about all of its members at once, or null.
String? _bundlePraise(List<BundleMember> members, bool isAr) {
  if (members.any((m) => m.isQuota || m.streak <= 0)) return null;
  final everyDay = members.first.everyDay;
  if (members.any((m) => m.everyDay != everyDay)) return null;
  final smallest =
      members.map((m) => m.streak).reduce((a, b) => a < b ? a : b);
  // A weekday habit's praise for one run is «سويتها آخر مرة», about a single
  // habit, and it would follow a plural ask («سوي عاداتك الحين»). The weekday
  // form Aziz saw for a bundle, «ملتزم N مرات ورا بعض», has no wording for
  // one, so the bundle says no praise rather than a new line.
  if (!everyDay && smallest == 1) return null;
  return lateStreakPraise(smallest, isAr, everyDay: everyDay);
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

/// A count of days the way the notification copy says it: «يوم», «يومين»,
/// «٧ أيام», «١٤ يوم».
String _countedDays(int n, bool isAr) {
  if (!isAr) return n == 1 ? '1 day' : '$n days';
  return countedOffsetPhrase(n * ReminderUnit.days.inMinutes, true);
}

/// How many more of today's habits the streak still needs:
/// (4 x total + 4) ~/ 5 minus done, which is the 80% rule
/// (kStreakDayCompletionThreshold in dashboard_notifier.dart) in whole
/// numbers. Zero or less once the finished habits already cover it.
int habitsStillNeededForStreak({required int done, required int total}) =>
    (4 * total + 4) ~/ 5 - done;

/// «وعندك مهمتين عاجلتين.»: the urgent tasks, as a sentence of their own.
String _urgentTasksSentence(int n, bool isAr) {
  if (!isAr) return 'Plus $n urgent task${n == 1 ? '' : 's'}.';
  return switch (n) {
    1 => 'وعندك مهمة عاجلة وحدة.',
    2 => 'وعندك مهمتين عاجلتين.',
    <= 10 => 'وعندك ${arabicDigits(n)} مهام عاجلة.',
    _ => 'وعندك ${arabicDigits(n)} مهمة عاجلة.',
  };
}

/// The evening streak note, in the voice Aziz picked on 2026-09-11: the
/// streak in the title, and in the body what is done, praised, then the one
/// ask that keeps the streak, sized to exactly what it still needs today
/// ([habitsStillNeededForStreak]) and naming what it turns into.
///   - title «سلسلتك ماشية ٧ أيام», or «سلسلتك بدأت» for a streak of one;
///   - body «٢ من ٥ خلّصت 👏🏼 سوي عادتين بس، وتصير ٨ أيام.», or with nothing
///     done yet «بسم الله، سوي ٤ عادات اليوم وتصير ٨ أيام.».
/// [urgentTasks] adds its own short sentence when the person has opted into
/// it, «وعندك مهمتين عاجلتين.». It used to trail the body as « · ٢ مهمة
/// عاجلة بانتظارك», which both miscounted the dual and said the tasks were
/// waiting on the reader.
///
/// It used to open with the forward streak line and say only what was left,
/// and it kept saying so after 80% was done, when the streak was already
/// safe. Null here whenever the streak needs nothing more; the caller also
/// sends nothing once today's point is earned (see
/// NotificationService.eveningStreakNoteFor).
ReminderLine? streakRiskCopy({
  required int done,
  required int total,
  required int streak,
  required int urgentTasks,
  required bool isAr,
}) {
  final needed = habitsStillNeededForStreak(done: done, total: total);
  if (streak <= 0 || needed <= 0) return null;
  final next = _countedDays(streak + 1, isAr);
  final tasks =
      urgentTasks > 0 ? ' ${_urgentTasksSentence(urgentTasks, isAr)}' : '';
  if (!isAr) {
    final title = streak == 1
        ? 'Your streak has begun'
        : 'Your $streak-day streak is going';
    final today = done > 0
        ? '$done of $total done 👏🏼 Just $needed more and it turns '
            '${streak + 1}.'
        : 'Bismillah. ${_countedHabits(needed, false)} today and it turns '
            '${streak + 1}.';
    return (title: title, body: '$today$tasks');
  }
  final title =
      streak == 1 ? 'سلسلتك بدأت' : 'سلسلتك ماشية ${_countedDays(streak, true)}';
  final today = done > 0
      ? '${arabicDigits(done)} من ${arabicDigits(total)} خلّصت 👏🏼 '
          'سوي ${_countedHabits(needed, true)} بس، وتصير $next.'
      : 'بسم الله، سوي ${_countedHabits(needed, true)} اليوم وتصير $next.';
  return (title: title, body: '$today$tasks');
}

/// Friday's numbered note for THIS week, Aziz's pick of 2026-09-11: the habit
/// with the most green days as the title, and the count, praised, as the
/// body: «٥ أيام خضرا هذا الأسبوع 👏🏼 والليلة تختم الأسبوع.», with «التزام» in
/// place of «خضرا» for a quit habit.
///
/// It is only true of the week it counts, so the caller sends it once, on
/// that Friday, and never as the weekly repeat: the repeat used to carry
/// «هذا الأسبوع» with the numbers of whichever week last opened the app, and
/// a phone left closed heard last week's count every Friday after.
/// Null below three green days, which is not a week to hold up.
ReminderLine? weeklyNoteCopy({
  required String habitName,
  required int greenDays,
  required bool isQuit,
  required bool isAr,
}) {
  if (greenDays < 3) return null;
  if (!isAr) {
    return (
      title: habitName,
      body: '${isQuit ? 'Kept' : 'Green'} $greenDays days this week 👏🏼 '
          'Tonight closes the week.',
    );
  }
  return (
    title: habitName,
    body: '${_countedDays(greenDays, true)} ${isQuit ? 'التزام' : 'خضرا'} '
        'هذا الأسبوع 👏🏼 والليلة تختم الأسبوع.',
  );
}

/// The weekly repeat, which has to stay true on any Friday it fires, however
/// long the phone stays closed: tomorrow is a new week, and the longest run
/// ever reached cannot go down. «سبق ووصلت ١٤ يوم ورا بعض 👏🏼 ومربع واحد يفتح
/// الأسبوع.», or just «مربع واحد يفتح الأسبوع.» when [longestStreak] is under
/// three.
ReminderLine weeklyRepeatCopy({
  required int longestStreak,
  required bool isAr,
}) {
  final proud = longestStreak >= 3;
  if (!isAr) {
    return (
      title: 'A new week tomorrow',
      body: proud
          ? "You've reached $longestStreak days in a row before 👏🏼 "
              'One square opens the week.'
          : 'One square opens the week.',
    );
  }
  return (
    title: 'أسبوع جديد باجر',
    body: proud
        ? 'سبق ووصلت ${_countedDays(longestStreak, true)} ورا بعض 👏🏼 '
            'ومربع واحد يفتح الأسبوع.'
        : 'مربع واحد يفتح الأسبوع.',
  );
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
