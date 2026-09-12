import 'dart:math' as math;

import 'room_model.dart';

/// What one plan slot did on one day, as far as the room can actually tell.
enum RoomSlotOutcome {
  /// The habit was completed that day.
  done,

  /// Marked جزئي: half the work, and half the credit ([RoomParticipant.
  /// creditFor] scores it 0.5).
  partial,

  /// Asked for, and stood down with تخطّي. Worth nothing, exactly like
  /// [missed]; drawn with the تخطّي glyph so a choice does not read as a
  /// failure. Only ever named from [RoomParticipant.dailyHabitMarks], since
  /// the counts cannot tell it from a miss.
  skipped,

  /// Asked for, and nothing was recorded.
  missed,

  /// The day asked nothing of this slot: an off-day of a named-weekday
  /// habit, or a day a weekly quota had already bought.
  rest,

  /// This member skipped the slot when they joined, or dropped it later
  /// (see [kDeclinedSlot]). It counts neither for nor against them.
  declined,
}

/// One plan slot's name, what it did, and what that was WORTH to the day.
class RoomSlotDay {
  final String name;
  final RoomSlotOutcome outcome;

  /// This habit's share of the day, 0..1.
  ///
  /// A day is worth 1 and is split between the habits it asked for, which is
  /// exactly how [RoomParticipant.creditFor] divides it: two habits make each
  /// one worth 0.5, three make each 0.33, and a جزئي is worth half of its
  /// own share. Aziz asked for that arithmetic to be on screen rather than
  /// implied (2026-09-10): "if room started with 2 habit the info should be
  /// +0.5 +0.5, so we know that this is how it being counted".
  ///
  /// Zero for a rest, a declined slot, a تخطّي and a missed one.
  final double share;

  const RoomSlotDay({
    required this.name,
    required this.outcome,
    required this.share,
  });
}

/// Several slots that landed the same way, for a day whose counts do not say
/// WHICH slot was which.
///
/// The honest middle ground between naming habits we cannot name and saying
/// nothing at all: the outcome and the count are certain, so the arithmetic
/// can still be shown in full.
class RoomSlotGroup {
  final RoomSlotOutcome outcome;
  final int count;

  /// What this group contributed to the day: [count] times one slot's share.
  final double share;

  const RoomSlotGroup({
    required this.outcome,
    required this.count,
    required this.share,
  });
}

/// One day of one member's room record, in the shape a person reads it:
/// a score out of what was asked, the marks behind it, and, when the room
/// can honestly say so, which habit did what.
///
/// Every number here is read through the SAME accessors the leaderboard is
/// ranked on — [RoomParticipant.scheduledCountFor], [RoomParticipant.
/// creditFor]'s own arithmetic — for the reason this feature has already
/// paid for twice: a second way of computing one fact eventually disagrees
/// with the first, and then one day has two answers on two screens.
class RoomDayBreakdown {
  /// How many habits the day asked for. The denominator.
  final int scheduled;

  /// How many were completed.
  final int done;

  /// How many were marked جزئي.
  final int partial;

  /// How many were rested. DISPLAY ONLY, and deliberately absent from
  /// [credited] and [scheduled]: see [RoomParticipant.dailyRestedCount]'s
  /// wall. A rest stops a day being drawn as a failure; it does not pay.
  final int rested;

  /// [done] plus half of [partial], exactly as [RoomParticipant.creditFor]
  /// weighs them.
  final double credited;

  /// What the day ASKED for, in fractions of a habit rather than whole ones.
  ///
  /// Equal to [scheduled] on almost every day. It differs only where a
  /// flexible weekly quota is carrying target/D of a closed week instead of a
  /// whole slot on the days it is answerable for, which is the weekly-share
  /// ruling (see [RoomParticipant.dailyScheduledWeight]). The percentage and
  /// the bar divide by THIS, because it is what the leaderboard is ranked on;
  /// the «من 3 عادات» line keeps using [scheduled], because three habits is
  /// what the day actually asked of a person.
  final double demand;

  /// One row per plan slot that was part of THIS day, or empty when the room
  /// cannot say which slot did what (see [roomDayBreakdown]). Never a guess.
  final List<RoomSlotDay> slots;

  /// The fallback for a day [slots] cannot describe: the same outcomes and
  /// the same arithmetic, grouped instead of named.
  final List<RoomSlotGroup> groups;

  /// The habits [groups] are drawn from: named, never attributed.
  ///
  /// A day whose counts say "one done, one missed" out of صلاة الوتر and
  /// قراءة القرآن knows both names perfectly well. What it cannot say is
  /// which was which. Listing the pool under the grouped rows puts every
  /// habit of the day on screen, which is what somebody opening the card
  /// came to see, while still refusing to tell a person they skipped a
  /// habit they may well have done. Aziz, 2026-09-12: "why the friday now
  /// not showing all 3 habits?"
  ///
  /// Empty wherever naming it could mislead: an 'own'-mode room holds no
  /// plan names at all, and a day with a slot excused OUTSIDE the groups (a
  /// quota week's rest, say) would otherwise list a habit that none of the
  /// rows beneath it speaks for.
  final List<String> groupNames;

  const RoomDayBreakdown({
    required this.scheduled,
    required this.demand,
    required this.done,
    required this.partial,
    required this.rested,
    required this.credited,
    required this.slots,
    required this.groups,
    this.groupNames = const [],
  });

  /// What one of this day's habits is worth on its own: a day is 1, split
  /// between the habits it asked for.
  double get shareEach => demand <= 0 ? 0 : 1 / demand;

  /// The day's credit in WHOLE habits: [done] plus half of [partial].
  ///
  /// What «3 من 3» counts. [credited] is the weighted number the percentage
  /// and the bar divide by [demand], and on a day a weekly quota is sharing
  /// out the two differ: three habits can all be done while the day is worth
  /// less than three, because that week's quota came up short. Printing the
  /// weighted number against [scheduled] would read «2.29 من 3», which is
  /// true of nothing a person did.
  double get plainCredited => done + partial * 0.5;

  /// How many of the day's habits went unanswered.
  int get missed {
    final open = scheduled - done - partial;
    return open < 0 ? 0 : open;
  }

  /// A day that asked nothing at all.
  bool get asksNothing => scheduled == 0;

  /// The share of the day that was earned, 0..1. The same number
  /// [RoomParticipant.creditFor] returns, and a day that asked nothing is a
  /// whole day, exactly as it is there.
  double get ratio {
    if (scheduled == 0 || demand <= 0) return 1;
    final r = credited / demand;
    return r < 0 ? 0 : (r > 1 ? 1 : r);
  }
}

/// Reads one day out of a member's participant document.
///
/// Which habit did what comes from [RoomParticipant.dailyHabitMarks], the
/// per-habit record the sync writes beside the counts, whenever the rows it
/// produces add up to the counts the score reads. That is every day a
/// current build has graded, so the card names every habit, every day:
/// Aziz, 2026-09-11, "why some times it says the habit that done, and
/// sometimes the name is not mention? lets make it mention all the time".
///
/// A day with no usable marks (graded only by an older build, or a closed
/// day whose squares no longer match what the room paid) falls back to the
/// counts alone. The counts never say which habit each one was, so rather
/// than guess, [RoomDayBreakdown.slots] is then filled only when the counts
/// leave no room for doubt:
///
///  * the day asked nothing, so every live slot rested; or
///  * nothing was excused (every live slot was asked for) AND all of them
///    landed the same way: all done, all جزئي, or none of either.
///
/// A one-habit plan is always in that set. A mixed day in a bigger plan
/// returns no rows, and the caller shows the marks as counts instead.
/// Declined slots are certain either way and are always named: skipping a
/// slot is this member's own recorded choice.
///
/// Slots the leader has withdrawn from the plan are left out entirely, the
/// same way [RoomParticipant.countedHabitIdsIn] leaves them out of grading.
///
/// [namesVisible] is whether the viewer may read this member's own habit
/// names. It only matters in an 'own'-mode room: a shared room's plan is
/// public, while an own-mode member's habits are theirs to hide
/// ([RoomParticipant.hideDetails]).
RoomDayBreakdown roomDayBreakdown({
  required RoomModel room,
  required RoomParticipant participant,
  required String dateKey,
  bool namesVisible = true,
}) {
  final scheduled = participant.scheduledCountFor(dateKey);
  final done = participant.dailyDoneCount[dateKey] ?? 0;
  final partial = participant.partialCountFor(dateKey);
  final rested = participant.dailyRestedCount[dateKey] ?? 0;
  // The WEIGHTED pair, which is what the leaderboard is ranked on. Both fall
  // back to the whole-habit counts on a day the grader recorded no weight
  // for, so a plan with no flexible quota in it, and every day graded by an
  // older build, reads exactly as it did. See
  // RoomParticipant.dailyScheduledWeight.
  final demand = participant.scheduledWeightFor(dateKey);
  final credited = participant.doneWeightFor(dateKey).clamp(0.0, demand);
  final each = demand <= 0 ? 0.0 : 1 / demand;
  // A day whose demand is not a whole number of habits cannot be split evenly
  // between them.
  final weighted = (demand - scheduled).abs() > 1e-9;

  final marked = _slotsFromMarks(
    room: room,
    participant: participant,
    dateKey: dateKey,
    scheduled: scheduled,
    done: done,
    partial: partial,
    each: each,
    demand: demand,
    credited: credited,
    namesVisible: namesVisible,
  );
  if (marked != null) {
    return RoomDayBreakdown(
      scheduled: scheduled,
      demand: demand,
      done: done,
      partial: partial,
      rested: rested,
      credited: scheduled == 0 ? 0 : credited,
      slots: marked,
      groups: const [],
    );
  }

  final live = <String>[];
  final liveIsQuota = <bool>[];
  final declined = <String>[];
  final named = _namedSlotsOn(
    room: room,
    participant: participant,
    dateKey: dateKey,
    live: live,
    liveIsQuota: liveIsQuota,
    declined: declined,
  );

  // Whether the slots the day left out are exactly the quota ones, so they
  // can be drawn as the rest their own week bought rather than left nameless.
  var quotaExcused = false;
  RoomSlotOutcome? uniform;
  final quotaCount = liveIsQuota.where((q) => q).length;
  // Not on a weighted day: there the rows carry unequal shares that have to
  // sum to the weighted total, and this path only knows how to split a day
  // evenly. A member whose device writes marks takes the path above instead.
  if (named && !weighted) {
    final asked = live.length - quotaCount;
    if (scheduled == 0) {
      uniform = RoomSlotOutcome.rest;
    } else if (live.length == scheduled) {
      // Nothing was excused, so every live slot is one of the counted ones
      // and the totals below describe all of them at once.
      if (done == live.length) {
        uniform = RoomSlotOutcome.done;
      } else if (partial == live.length) {
        uniform = RoomSlotOutcome.partial;
      } else if (done == 0 && partial == 0) {
        uniform = RoomSlotOutcome.missed;
      }
    } else if (quotaCount > 0 && asked == scheduled) {
      // Hoor, Thursday 10 September: three slots on the plan, a denominator
      // of two, and no marks on her document to say which two. It is still
      // not a guess. Every non-quota slot was asked for (a named-weekday slot
      // excused by its own weekday would make `asked` exceed `scheduled` and
      // this branch would not fire), so the slots the day left out are
      // precisely the quota ones, and the counts then describe the rest.
      //
      // Before this, that day read «2 من عادتين» on a three-habit room with
      // nothing said about تمرين at all. Aziz, 2026-09-12: "It shows 2 out of
      // 2 and we are in three habit room, so why no details like other days?"
      if (done == asked) {
        uniform = RoomSlotOutcome.done;
        quotaExcused = true;
      } else if (partial == asked) {
        uniform = RoomSlotOutcome.partial;
        quotaExcused = true;
      } else if (done == 0 && partial == 0) {
        uniform = RoomSlotOutcome.missed;
        quotaExcused = true;
      }
    }
  }
  // One outcome per live row: the quota slots rest, everything else lands the
  // way the counts say they all did.
  final rowOutcomes = [
    for (var i = 0; i < live.length; i++)
      quotaExcused && liveIsQuota[i]
          ? RoomSlotOutcome.rest
          : (uniform ?? RoomSlotOutcome.rest),
  ];
  // Mixed, or a day where some slots were excused and some were not: the
  // counts are known, the attribution is not, and inventing it here would be
  // the room telling somebody they skipped a habit they may well have done.
  final attributable = named && (uniform != null || live.isEmpty);

  // ONE habit can still be named on a day the counts cannot fully explain.
  //
  // Hoor's Friday 11 September: three slots, all three asked, two done, and
  // no marks on her document to say which two. Her quotaOkWeeks holds that
  // week though, and a met quota leaves ONLY the days it was actually done in
  // the denominator (weeklyQuotaScheduledDays). So تمرين is in this day's
  // count precisely because she trained, which is a proof rather than a
  // guess, and the card can say so.
  //
  // The other two stay a pair on purpose. The document cannot tell whether
  // صلاة الوتر or قراءة القرآن was the one she missed, and naming either
  // would be the room telling her she skipped a habit she may well have done.
  //
  // Aziz, 2026-09-12: "if u checked the data it should show that she trained
  // yesterday so how does it count".
  final doneBesideQuota = done - quotaCount;
  final quotaProven = named &&
      !weighted &&
      !attributable &&
      quotaCount > 0 &&
      live.length == scheduled &&
      // A جزئي or a تخطّي in the remainder would make "so many done, so many
      // not" untrue, and this path cannot place them.
      partial == 0 &&
      rested == 0 &&
      doneBesideQuota >= 0 &&
      done < live.length &&
      participant.quotaWeekWasMet(dateKey);
  final provenRows = <RoomSlotDay>[
    if (quotaProven)
      for (var i = 0; i < live.length; i++)
        if (liveIsQuota[i])
          RoomSlotDay(
            name: live[i],
            outcome: RoomSlotOutcome.done,
            share: _shareFor(RoomSlotOutcome.done, each),
          ),
  ];
  final remainderGroups = <RoomSlotGroup>[
    if (quotaProven && doneBesideQuota > 0)
      RoomSlotGroup(
        outcome: RoomSlotOutcome.done,
        count: doneBesideQuota,
        share: doneBesideQuota * each,
      ),
    if (quotaProven && live.length - quotaCount - doneBesideQuota > 0)
      RoomSlotGroup(
        outcome: RoomSlotOutcome.missed,
        count: live.length - quotaCount - doneBesideQuota,
        share: 0,
      ),
  ];

  // The habits the grouped rows speak for, so a day that cannot attribute
  // them can still put every name on screen. See RoomDayBreakdown.groupNames.
  //
  // On the proven path the groups cover exactly the non-quota slots, because
  // the quota one has a named row of its own. On the fallback path they cover
  // every live slot, but ONLY where the live slots and the rows describe the
  // same set: a day still holding a slot no group speaks for (one a met quota
  // week excused, whose rest never reaches dailyRestedCount) would otherwise
  // list a habit that the «أُنجز ١ / ما أُنجز ١» beneath it never counted,
  // which misleads worse than saying nothing.
  final groupPool = <String>[];
  if (quotaProven) {
    for (var i = 0; i < live.length; i++) {
      if (!liveIsQuota[i]) groupPool.add(live[i]);
    }
  } else if (named &&
      !attributable &&
      !weighted &&
      live.length == scheduled + rested) {
    groupPool.addAll(live);
  }

  return RoomDayBreakdown(
    scheduled: scheduled,
    demand: demand,
    done: done,
    partial: partial,
    rested: rested,
    credited: scheduled == 0 ? 0 : credited,
    groupNames: groupPool,
    slots: quotaProven
        ? provenRows
        : attributable
        ? [
            for (var i = 0; i < live.length; i++)
              RoomSlotDay(
                name: live[i],
                outcome: rowOutcomes[i],
                share: _shareFor(rowOutcomes[i], each),
              ),
            for (final name in declined)
              RoomSlotDay(
                name: name,
                outcome: RoomSlotOutcome.declined,
                share: 0,
              ),
          ]
        : const [],
    // Suppressed on a weighted day as well as an attributable one. Groups
    // exist for a day whose slots cannot be told apart, which means the quota
    // cannot be told from the rest either: splitting the day evenly between
    // them would print rows that do not sum to the total beside them, and
    // arithmetic that does not add up defeats the point of showing it. The
    // card falls back to the day's own fraction and bar, both of which are
    // weighted and correct.
    groups: quotaProven
        ? remainderGroups
        : attributable || weighted
        ? const []
        : [
            if (done > 0)
              RoomSlotGroup(
                outcome: RoomSlotOutcome.done,
                count: done,
                share: done * each,
              ),
            if (partial > 0)
              RoomSlotGroup(
                outcome: RoomSlotOutcome.partial,
                count: partial,
                share: partial * each * 0.5,
              ),
            if (scheduled - done - partial > 0)
              RoomSlotGroup(
                outcome: RoomSlotOutcome.missed,
                count: scheduled - done - partial,
                share: 0,
              ),
            if (rested > 0)
              RoomSlotGroup(
                outcome: RoomSlotOutcome.rest,
                count: rested,
                share: 0,
              ),
          ],
  );
}

/// The day's rows read from [RoomParticipant.dailyHabitMarks], or null when
/// there are none this card can stand behind.
///
/// One row per plan slot on this day: the habit that filled it THAT day
/// ([RoomParticipant.habitInSlotOn], so a declined slot's earlier days still
/// name the habit that was graded), with the mark the sync recorded for it.
/// A slot with no mark was not part of the day at all (it joined the plan
/// later, or its habit had not started), so it gets no row, the same way the
/// denominator left it out. That is what keeps a slot the leader added on
/// day 9 off day 3's card.
///
/// Null unless the rows add up to the counts beside them: the same number
/// asked, done and جزئي. Checked on the ROWS, not only on the map, so a mark
/// for a habit no slot shows any more can never produce a card whose lines
/// do not sum to its own total.
List<RoomSlotDay>? _slotsFromMarks({
  required RoomModel room,
  required RoomParticipant participant,
  required String dateKey,
  required int scheduled,
  required int done,
  required int partial,
  required double each,
  required double demand,
  required double credited,
  required bool namesVisible,
}) {
  final marks = participant.habitMarksFor(dateKey);
  if (marks == null) return null;
  final rows = <RoomSlotDay>[];
  // Which rows are a flexible quota, index for index with [rows]. Only they
  // can be worth something other than a whole habit of the day.
  final quota = <bool>[];
  final declined = <RoomSlotDay>[];

  void add(String name, RoomHabitMark mark, String habitId) {
    final outcome = _outcomeOf(mark);
    rows.add(
      RoomSlotDay(name: name, outcome: outcome, share: _shareFor(outcome, each)),
    );
    quota.add(participant.ruleFor(habitId, dateKey)?.isFlexibleQuota ?? false);
  }

  if (room.habitMode == RoomHabitMode.shared) {
    for (var i = 0; i < room.sharedHabits.length; i++) {
      final template = room.sharedHabits[i];
      if (template.isRemoved) continue;
      final name = template.name.trim();
      if (name.isEmpty) return null;
      final habitId = participant.habitInSlotOn(i, dateKey);
      if (habitId == null) {
        // Declined that day. Named, as on every other path, from the day the
        // slot entered the plan.
        if (participant.slotDeclinedOn(i, dateKey) &&
            dateKey.compareTo(room.slotJoinedPlanKey(i)) >= 0) {
          declined.add(
            RoomSlotDay(
              name: name,
              outcome: RoomSlotOutcome.declined,
              share: 0,
            ),
          );
        }
        continue;
      }
      final mark = marks[habitId];
      if (mark == null) continue;
      add(name, mark, habitId);
    }
  } else {
    // An own-mode room holds no plan names. A member's habits are their own,
    // listed index for index in linkedHabitNames, and hidden from everybody
    // else when that member asked for it.
    if (!namesVisible) return null;
    final ids = participant.linkedHabitIds;
    final names = participant.linkedHabitNames;
    for (var i = 0; i < ids.length; i++) {
      final mark = marks[ids[i]];
      if (mark == null) continue;
      final name = i < names.length ? names[i].trim() : '';
      if (name.isEmpty) return null;
      add(name, mark, ids[i]);
    }
  }

  var asked = 0;
  var doneRows = 0;
  var partialRows = 0;
  for (final r in rows) {
    if (r.outcome != RoomSlotOutcome.rest) asked++;
    if (r.outcome == RoomSlotOutcome.done) doneRows++;
    if (r.outcome == RoomSlotOutcome.partial) partialRows++;
  }
  if (asked != scheduled || doneRows != done || partialRows != partial) {
    return null;
  }
  if (rows.isEmpty && declined.isEmpty) return null;
  // An even split, unless the day's demand is not a whole number of habits.
  // When it is not, a flexible quota is carrying target/D of a closed week
  // rather than a whole slot, so the rows cannot all be worth the same: every
  // other slot is worth one habit of the day's demand, and the quota rows
  // share whatever credit is left over. Keeping the rows summing to the total
  // beside them is the whole reason the card shows them at all.
  //
  // A quota row can be «راحة» and still be worth something here, which is the
  // ruling working as intended: the week's shortfall is carried by every day
  // of it, including the ones the quota excused.
  if (demand > 0 && (demand - scheduled).abs() > 1e-9) {
    var plainCredit = 0.0;
    var quotaRows = 0;
    for (var i = 0; i < rows.length; i++) {
      if (quota[i]) {
        quotaRows++;
      } else {
        plainCredit += _shareFor(rows[i].outcome, 1);
      }
    }
    final left = credited - plainCredit;
    final perQuota =
        quotaRows == 0 || left <= 0 ? 0.0 : left / quotaRows;
    return [
      for (var i = 0; i < rows.length; i++)
        RoomSlotDay(
          name: rows[i].name,
          outcome: rows[i].outcome,
          share: (quota[i] ? perQuota : _shareFor(rows[i].outcome, 1)) / demand,
        ),
      ...declined,
    ];
  }
  return [...rows, ...declined];
}

RoomSlotOutcome _outcomeOf(RoomHabitMark mark) => switch (mark) {
      RoomHabitMark.done => RoomSlotOutcome.done,
      RoomHabitMark.partial => RoomSlotOutcome.partial,
      RoomHabitMark.skipped => RoomSlotOutcome.skipped,
      RoomHabitMark.missed => RoomSlotOutcome.missed,
      RoomHabitMark.rest => RoomSlotOutcome.rest,
    };

/// The shares as they should be PRINTED, adjusted so the numbers on screen
/// add up to the total beside them.
///
/// Two thirds and a sixth print as 0.67 and 0.17, which sum to 0.84 while
/// the day says 83%. That was visible on the first build of this card, and
/// arithmetic that does not add up defeats the whole reason for showing it.
///
/// Largest remainder, the same method a receipt uses: floor everything, then
/// hand the leftover pennies to the entries with the biggest fractions. A
/// zero share is never bumped, because "this habit added nothing" is a fact
/// rather than a rounding choice.
///
/// Pure, so the property that matters can be tested directly: the rounded
/// list sums to the rounded total, always.
List<double> roundedShares(List<double> shares, {int decimals = 2}) {
  if (shares.isEmpty) return const [];
  final scale = math.pow(10, decimals).toDouble();
  final target = (shares.fold<double>(0, (a, b) => a + b) * scale).round();
  final units = [for (final v in shares) (v * scale).floor()];
  var residue = target - units.fold<int>(0, (a, b) => a + b);
  if (residue > 0) {
    final order = [for (var i = 0; i < shares.length; i++) i]..sort((a, b) {
      // Compared at a tolerance, not exactly. Equal fractions are the COMMON
      // case here (n habits of the same size all round identically), and in
      // binary they are never quite equal: two thirds and a sixth leave
      // 0.6666666666666572 and 0.666666666666664, so noise in the
      // thirteenth decimal was silently deciding which row absorbed the
      // rounding.
      final fa = ((shares[a] * scale - units[a]) * 1e9).round();
      final fb = ((shares[b] * scale - units[b]) * 1e9).round();
      final byFraction = fb.compareTo(fa);
      if (byFraction != 0) return byFraction;
      // Then the share itself, so the BIGGEST contributor absorbs it, which
      // is both deterministic and the one a reader would pick.
      return shares[b].compareTo(shares[a]);
    });
    for (final i in order) {
      if (residue == 0) break;
      if (shares[i] <= 0) continue;
      units[i] += 1;
      residue -= 1;
    }
  }
  return [for (final u in units) u / scale];
}

/// What one slot's outcome is worth, given what one slot of this day is
/// worth. A جزئي is half of its own share, the same half it is everywhere
/// else in this app.
double _shareFor(RoomSlotOutcome outcome, double each) => switch (outcome) {
      RoomSlotOutcome.done => each,
      RoomSlotOutcome.partial => each * 0.5,
      RoomSlotOutcome.skipped ||
      RoomSlotOutcome.missed ||
      RoomSlotOutcome.rest ||
      RoomSlotOutcome.declined =>
        0,
    };

/// Fills [live] and [declined] with the names of the plan slots that were
/// part of [dateKey], and says whether naming is possible at all.
///
/// A slot the leader added on day 9 was not something this member failed on
/// day 3, so it must not appear on day 3's card at all. Aziz, 2026-09-10:
/// "some habit are being added after, not from day 1... only the counted
/// days for it should show it".
///
/// The join test is [RoomParticipant.slotOpenBy], the SAME one
/// [RoomParticipant.countedHabitCountOn] uses to build the denominator. That
/// is deliberate: if the rows were filtered by a different rule than the
/// number they sum to, the two would eventually disagree on screen. It fails
/// open for a slot with no recorded rule, exactly as that one does.
bool _namedSlotsOn({
  required RoomModel room,
  required RoomParticipant participant,
  required String dateKey,
  required List<String> live,
  required List<bool> liveIsQuota,
  required List<String> declined,
}) {
  // An 'own'-mode room holds no names: every member picks their own habits
  // and the document carries only ids. Nothing to label a row with.
  if (room.habitMode != RoomHabitMode.shared) return false;
  for (var i = 0; i < room.sharedHabits.length; i++) {
    final template = room.sharedHabits[i];
    if (template.isRemoved) continue;
    final name = template.name.trim();
    if (name.isEmpty) return false;
    final isDeclined = participant.slotDeclinedOn(i, dateKey);
    // A declined slot has no habit id to ask about, so fall back to the
    // room's own record of when the slot entered the plan.
    final habitId = participant.habitInSlotOn(i, dateKey);
    final joined = habitId != null
        ? participant.slotOpenBy(habitId, dateKey)
        : dateKey.compareTo(room.slotJoinedPlanKey(i)) >= 0;
    if (!joined) continue;
    if (isDeclined) {
      declined.add(name);
    } else {
      live.add(name);
      // Only a FLEXIBLE quota can be excused without a weekday rule saying
      // so, which is what lets a day name the slot its own week bought.
      liveIsQuota.add(
        habitId != null &&
            (participant.ruleFor(habitId, dateKey)?.isFlexibleQuota ?? false),
      );
    }
  }
  return live.isNotEmpty || declined.isNotEmpty;
}
