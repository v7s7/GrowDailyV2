# Habit pause and Room grading: design pass

Status: **implemented** on branch `claude/musing-tu-a17ad7`, in the worktree
at `.claude/worktrees/musing-tu-a17ad7`, not on `main`. 787 tests pass
project-wide, 226 in the rooms suite (187 before, so 39 new). Zero new
analyzer issues in every file touched.

Both product decisions are answered (see "Decisions made"). Two pre-existing
bugs were confirmed by running code and are fixed here (see "Bugs found on
the way"). See "What changed" at the bottom for the file-by-file result and
the two things that still want a human's eyes.

## The problem as it actually behaves today

Pausing a habit stamps `archivedAt` on it (`GridScreen._pauseHabit` calls
the same `archive`/`toggle` path as remove). `habitListProvider` drops it
immediately. The room link is deliberately left in place, because pause
must be reversible.

So both sync paths meet a linked id they cannot resolve, and they disagree
about it:

* `syncLinkedHabitsProgress` (`rooms_notifier.dart:2274`) bails outright on
  any unresolvable id. The whole room stops syncing for that member, every
  other linked habit included.
* `syncTodayForHabit` still runs, and its stale-link branch
  (`rooms_notifier.dart:2934`, `if (habit == null) return true;`) puts the
  paused habit into today's denominator as scheduled and never green.

Net effect while a habit is paused: every day the member taps anything is
written as a partial miss, and the room-open resync that would normally
correct a day is the one thing that refuses to run.

It does not heal on resume either. After `CustomHabitsNotifier.unarchive`
the habit resolves again, `archivedAt` is cleared, `habitExistedOn` answers
true for the whole paused stretch, and the next full resync regrades those
days as ordinary misses. The pause sheet promises the habit "comes back
whenever you want"; what comes back is a run of permanent zeroes.

## Why the obvious fix is wrong

Letting the sync resolve paused habits so paused days drop out of the
scheduled set turns those days into **full credit**, not neutral ones:

* `creditFor` (`room_model.dart:829`) returns `1.0` when scheduled is 0.
  That is the weekly-quota rest-day rule and it is correct as written.
* `daysElapsedIn` (`room_model.dart:911`) subtracts only ROOM-level
  `pausedSpans`. There is no per-participant pause in the denominator.

A member with everything paused would read 100% forever, hold a perfect
room streak, show "done today" every day, count toward team perfection and
its bonus, and in a competitive room take rank 1 and `podiumPrizeFor(1)`.
Pinned in `test/features/rooms/paused_habit_room_grading_test.dart`.

## The concept the model is missing

The room already has a notion of **a day that counts for nobody**:
`RoomModel.pausedSpans`, the dead time between a room ending and a leader
extending it. Its doc comment states the rule exactly right: excluded from
both sides, not elapsed and not missed.

That concept is implemented in four places and ignored in two:

| Surface | Honours room pause |
| --- | --- |
| `RoomModel.daysElapsed` (`:411`) | yes |
| `RoomParticipant.daysElapsedIn` (`:911`) | yes |
| `RoomParticipant.daysCompleted` (`:929`) | yes |
| the sync's per-day write (`rooms_notifier.dart:2603`) | yes |
| contribution strip (`..._leaderboard_extend.dart:717`) | yes |
| **`RoomParticipant.currentStreak` (`:981`)** | **no** |
| **participant calendar (`..._participant_calendar.dart:69`)** | **no** |

Habit pause is a second source of the same kind of day, this time
per-participant. The work is to name the concept once and route every
scoring surface through it, which fixes the two gaps above at the same
time.

## Storage

New field on the participant doc:

```dart
/// habitId -> inclusive date-key spans this habit was PAUSED for this
/// participant, in this room. The room's own record of days it must not
/// grade, in the same spirit as habitRules: what the room observed, frozen,
/// immune to what the habit looks like later.
final Map<String, List<({String from, String to})>> habitPausedSpans;
```

Why the room keeps its own copy instead of asking the habit:

1. **Custom habits destroy the evidence on resume.**
   `CustomHabitsNotifier.unarchive` (`custom_habits_notifier.dart:472`)
   clears `archivedAt` and keeps `createdAt`, deliberately. Catalog habits
   keep closed stints in `catalogStintHistory`; custom habits keep nothing.
   A habit-derived answer would silently flip every paused day back to a
   miss the moment someone resumes, and only for custom habits. Room scores
   must not depend on which kind of habit a member happened to link.
2. **It is the `habitRules` pattern.** Same reason editing a habit no
   longer re-grades finished history.
3. **Single-writer.** It lives on the doc only this member's device writes.

Why keyed by habitId rather than a flat set of dead date keys: partial
pause. With two linked habits, pausing one should reduce that day's
denominator to 1, not kill the day. Only a day where *every* counted habit
is paused is dead. A flat set cannot express that, and would need
rewriting whenever a member adds or removes a link.

## Who writes it, and when

**At sync time, not at pause time.** This is the crux, and it is where the
reverted unlink-on-pause attempt went wrong. `GridScreen._pauseHabit`'s own
comment records why: the room list at pause time comes from
`myLinkedRoomHabitsProvider`, which is legitimately empty on a cold start,
so a pause moments after launch reaches no rooms at all, silently and with
no dialog. An action-time write inherits that identical hole.

`syncLinkedHabitsProgress` is the right writer. It runs on room open, app
resume and after taps; it re-reads the participant doc fresh; it already
persists derived state idempotently (`habitRules`, `quotaOkWeeks`,
`lastSyncedDay`); and it is already the only place allowed to decide a
day's grade.

Two changes inside it:

**Lookup source.** Build `habitById` from `allHabitsEverProvider` rather
than `habitListProvider`. That provider already emits one template per
stint with `createdAt`/`archivedAt` stamped, and commit `3ff960b` fixed the
paused-preset `createdAt` that would otherwise have given a paused preset
no lower bound.

**Three states per habit per day, not two:**

* **live**: resolves, and `habitExistedOn` is true. Grade as today.
* **paused**: resolves only as a paused stint covering that day. Record in
  `habitPausedSpans`, and leave it out of that day's scheduled count.
* **unresolvable**: no template at all, from any stint. The existing bail
  at `rooms_notifier.dart:2274` stands untouched. That guard is the only
  thing standing between the app and the exploit above, and this design
  does not weaken it.

The sync may only ever **extend** a stored span, never shorten or delete
one, and never past `room.lastCountedDay`. A resume then leaves the span
closed at the last day the room actually watched the pause. Paused days no
sync ever saw fall outside the span and grade as misses: the conservative
direction, and the same "the room can only vouch for days it was watching"
rule `lastSyncedDay` already encodes.

`syncTodayForHabit` needs the matching change to its stale-link branch, so
one tap and the next full resync cannot disagree about whether today was
even due.

## The scoring changes

One predicate, added to `RoomParticipant`, and nothing anywhere re-derives
it:

```dart
bool isHabitPausedOn(String habitId, String dateKey);

/// This day counted for nobody: the room was not running, or every habit
/// this participant is graded on was paused.
bool isDeadDayIn(RoomModel room, String dateKey);
```

Then:

* `daysElapsedIn`, `daysCompleted`: ask `isDeadDayIn` instead of
  `room.isPausedOn`. Both sides drop the day, as they already do for a room
  pause.
* `currentStreak`: a dead day becomes transparent, skipped and walked
  through, neither keeping nor breaking. This is also the fix for bug 1
  below.
* `creditFor`, `isFullyDone`, `isRestDay`: **unchanged**. The rest-day rule
  stays exactly as pinned. A dead day is excluded before these are ever
  consulted, so scoring never learns a new special case.
* `teamProgressRatio` / `teamMaxPossibleDays`: the ceiling has to become the
  sum of each participant's own `daysElapsedIn`, not
  `participants.length * daysElapsed`, because `daysElapsed` has no
  participant to ask. That also fixes an existing inconsistency: today a
  late joiner already drags the team percentage below every row shown under
  it.
* `teamCompletedToday`: a participant whose day is dead is excluded from the
  `every`, rather than counted as done or allowed to block the team.
* contribution strip and participant calendar: both ask `isDeadDayIn` and
  paint the same blank, so the two surfaces stop contradicting each other
  about the same day.
* `didCompleteAnythingOn`: unchanged, already honest.

## Bugs found on the way

Both are pre-existing, both are about room-level pause, both are fixed by
routing everything through the one predicate. Neither needs the new field.

**1. Extending a room silently resets everyone's room streak.**
Measured, not inferred. Ten-day room, member perfect every running day,
three-day paused span in the middle (exactly what `extendRoom` writes):

```
streak, no pause, all days done        = 10
streak, paused span, paused days blank = 3
daysElapsedIn (paused room)            = 7
daysCompleted (paused room)            = 7.0
progressRatio (paused room)            = 1.0
```

The percentage is correctly untouched. The streak badge is not.
`daysCompleted`/`daysElapsedIn` skip paused days, but `currentStreak` reads
`isFullyDone`, which reads counts the sync deliberately *removed* for those
days, so it sees a miss and stops. `pausedSpans`' doc comment promises an
extension leaves scores where they were; it does, except here.

**2. The participant calendar paints room-paused days as missed.**
`_fillFor`/`_statusFor` (`..._participant_calendar.dart:69,90`) never ask
`room.isPausedOn`, though the widget holds `widget.room`. The contribution
strip beside it correctly paints those days blank. Same day, two surfaces,
one says "not part of the room" and the other says "لم يُنجز".

## Decisions made

**A. A habit pause freezes the percentage, but forfeits the podium.**
Paused days count for nobody, so a member's percentage holds where they
left it, and the leaderboard row says so with a paused chip rather than
letting a frozen 100% read as ongoing perfection. A member whose counted
habits are all paused on the room's final day is skipped when podium ranks
are assigned, so `podiumPrizeFor` can never pay for a race someone stepped
out of. The number describes the days they played; the prize describes the
race.

Implementation notes for this: ranking is `widget.sorted.indexWhere(...)`
in `..._countdown_finale.dart:405`, and `sorted` comes from the same
`progressRatio` ordering the leaderboard uses. The skip belongs in the
ranking that feeds the finale, not inside `claimPodiumBonus`, so the podium
graphic and the payout agree about who placed. `claimPodiumBonus` keeps its
own guards (`room.isEnded`, `memberCount < 2`, claim-once transaction)
untouched.

**B. A dead day is transparent to a streak.**
It neither keeps nor breaks: `currentStreak` skips it and keeps walking.
Pause for a month, resume, and the streak continues from before, which is
what pause promises everywhere else in the app. Applies to both sources of
dead day, so bug 1 below is fixed by the same change rather than by a
special case.

One consequence worth stating: this is the only place where the two
decisions pull in different directions. A fully-paused member forfeits the
podium but keeps their streak badge. That is deliberate. The podium is a
prize for a competition; the streak is a record of a personal commitment
that pause was designed not to punish.

## Test plan

Existing pins stay green (`paused_habit_room_grading_test.dart`).

1. Fully-paused day drops out of both sides: `progressRatio` is unchanged by
   the pause, `daysElapsedIn` shrinks, `daysCompleted` shrinks by the same.
2. The exploit, explicitly: every habit paused for the room's whole life
   reads 0%, `isFullyDone` false, `teamIsPerfect` false, no rank-1 podium.
3. Partial pause: two habits, one paused, day's scheduled is 1, credit is
   `done/1`, day still elapses.
4. Streak transparency across a habit-paused span.
5. Streak transparency across a room-paused span (bug 1 regression).
6. Calendar and strip agree on a dead day (bug 2 regression).
7. Team ceiling is the sum of per-participant `daysElapsedIn`: a late joiner
   and a paused member no longer push the team below every visible row.
8. Sync: a span only ever extends; a resume closes it at the last observed
   day; an unresolvable id still bails with nothing written.
9. Anti-backdating: after pause then resume, back-filling a square inside
   the paused window earns nothing. The clamp at `rooms_notifier.dart:2614`
   keys off `wasObservedOn`, and a pause that empties `dailyDoneCount`
   inside the 45-day window must not switch it off.
10. Migration: field absent reads as empty, every score byte-identical to
    today.
11. Podium forfeit (decision A): a member fully paused on the room's final
    day is skipped in the ranking that feeds the finale, so the member
    below them takes that place, and `podiumPrizeFor` is never reached for
    the paused one. A member paused mid-room but active at the end still
    places normally.
12. Streak survives a forfeit (decision B against A): the same fully-paused
    member keeps their streak badge. The two decisions are allowed to
    disagree and this pins that they do.

## Explicitly not doing

* Not removing the unresolvable-id bail at `rooms_notifier.dart:2274`.
* Not changing `creditFor`'s rest-day rule.
* Not unlinking on pause.

## What changed

| File | Change |
| --- | --- |
| `room_model.dart` | `RoomParticipant.habitPausedSpans`, `isHabitPausedOn`, `isDeadDayIn`. `daysElapsedIn`, `daysCompleted`, `currentStreak`, `teamMaxPossibleDays`, `teamProgressRatio`, `teamCompletedToday` all route through the one predicate. `creditFor` / `isFullyDone` / `isRestDay` untouched. |
| `rooms_notifier.dart` | Sync reads `allHabitsEverProvider` instead of `habitListProvider`; new pass 0 records pause days; the dead-day branch writes no credit and no miss; spans persist extend-only. Fast path hands a paused habit to the full resync. New pure helpers `habitLivedOn`, `habitPausedOn`, `mergeDateKeysIntoSpans`, `podiumRanking`. Claim guards on both payouts. |
| `..._leaderboard_extend.dart` | Strip cell asks `isDeadDayIn`; a paused member's row shows a Paused chip. |
| `..._participant_calendar.dart` | Dead days draw no fill and read "Paused" instead of "Not done". |
| `..._countdown_finale.dart` | Podium and its prize both read `podiumRanking`. |
| `app_strings.dart` | `roomCalendarPausedDay`, `roomMemberPaused`. |

Three decisions worth knowing about, made while building:

**The lookup source had to distinguish "away" from "not born yet."** Both
fail `habitExistedOn`, and recording the second as a pause would pull
pre-link days out of the denominator, silently re-scoring every room where
somebody linked a habit younger than the room. `habitPausedOn` requires the
habit to have been born and put away before the day in question.

**The record is written at sync time and only ever grows.**
`CustomHabitsNotifier.unarchive` clears `archivedAt` and keeps `createdAt`,
so a resumed custom habit can no longer prove it was ever away. A catalog
habit keeps its closed stint in `catalogStintHistory` and a custom one keeps
nothing, so deriving the answer from the habit would make a member's score
depend on which kind they happened to link.

**The anti-backdating clamp needed one line.** `hasPriorRecord` was
`dailyDoneCount.isNotEmpty`, which meant "we have never graded you" only
because nothing ever emptied that map. A dead day now deletes its entry, so
it is ORed with `lastSyncedDay != null`. Without it, a member whose earned
days had all been removed would read as brand new and the clamp would switch
off entirely.

## Still wants a human's eyes

**The Paused chip in a real Arabic row.** It is an icon beside a word, so
unlike the streak badge next to it, it deliberately is NOT pinned LTR and
follows the ambient direction. That is the right call on paper and it is the
one visual thing I could not check without pausing a habit on the live
account and writing to a real shared room.

**One residual limitation, not closed.** Both payouts now refuse a claimer
who is fully paused on the room's last counted day, which shuts the obvious
hole (pause everything after day one, hold a one-day window at 100%, claim).
What it does not catch is a whole team pausing mid-room and resuming before
the end, which shrinks everyone's window without leaving anyone paused at the
finish. Closing that needs a threshold rule ("you must have played at least
N% of the room"), and inventing a number for that felt like a product call
rather than a bug fix. Pinned as a test so the behaviour is recorded rather
than assumed.
