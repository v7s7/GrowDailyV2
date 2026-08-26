part of 'room_detail_screen.dart';

class _PodiumColumn extends StatelessWidget {
  final RoomParticipant participant;
  final int rank;
  final RoomModel room;
  const _PodiumColumn({
    required this.participant,
    required this.rank,
    required this.room,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final (height, color) = switch (rank) {
      1 => (64.0, GameColors.gold),
      2 => (46.0, const Color(0xFFB9C0C7)),
      _ => (34.0, const Color(0xFFC98A5E)),
    };
    final pct = (participant.progressRatio(room) * 100).round();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (rank == 1)
          Icon(Icons.emoji_events_rounded, size: 20, color: GameColors.gold),
        const SizedBox(height: 3),
        SizedBox(
          width: 72,
          child: Text(
            participant.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: rank == 1 ? FontWeight.w800 : FontWeight.w600,
              color: gp.textPrimary,
            ),
          ),
        ),
        Text(
          '$pct%',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 64,
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withOpacity(0.18),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            border: Border.all(color: color.withOpacity(0.5), width: 0.5),
          ),
          child: Text(
            '$rank',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _RoomHeaderCard extends StatelessWidget {
  final RoomModel room;

  /// The live roster length, not [RoomModel.memberCount].
  ///
  /// That stored counter is incremented on join and decremented on leave,
  /// and the decrement swallows its own failures (see
  /// RoomsController.leaveRoom's `.catchError`), so it drifts. The lobby
  /// card one screen up already showed `participants.length` while this card
  /// showed the counter — the same room reporting two different sizes
  /// depending which card you looked at. Wherever the roster is already
  /// streamed, it is the truth; the counter stays only for the places that
  /// don't have it (the hub list, the pre-join preview).
  final int memberCount;
  const _RoomHeaderCard({required this.room, required this.memberCount});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final statusLabel = room.duration == RoomDuration.open
        ? s.roomOngoing
        : room.isEnded
            ? s.roomEnded
            : s.roomDaysLeft(room.daysRemaining);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: GameColors.gold.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                ),
                child: Text(statusLabel,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: GameColors.gold)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s.roomMemberCount(memberCount),
                  style: TextStyle(fontSize: 12, color: gp.textSec),
                ),
              ),
              Icon(Icons.tag_rounded, size: 14, color: gp.textTert),
              const SizedBox(width: 3),
              Text(room.code,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: gp.textSec)),
            ],
          ),
          // When the race actually began (or will begin, for a lobby/
          // countdown room) — the one date the header never carried: it
          // said how many days remain and nothing about where day 1 sits,
          // so reading the leaderboard strips' timeline meant arithmetic.
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.flag_rounded, size: 13, color: gp.textTert),
              const SizedBox(width: 5),
              Text(
                DateTime.now().startOfDay.isBefore(room.startDate)
                    ? s.roomStartsOn(DateFormat('d MMMM', s.isAr ? 'ar' : 'en')
                        .format(room.startDate))
                    : s.roomStartedOn(DateFormat('d MMMM', s.isAr ? 'ar' : 'en')
                        .format(room.startDate)),
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: gp.textTert),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The "everyone together" card — sits between the room header and the
/// individual leaderboard, same surface/border treatment as
/// [_RoomHeaderCard] with an [XpBar] (the same fill used for account XP)
/// standing in for a dedicated progress widget, so this reads as part of
/// the same visual family rather than a new component. Reuses
/// [RoomTeamProgress]'s pure aggregation — no new sync, no new Firestore
/// fields, just summed from what [roomParticipantsProvider] already
/// streamed in for the leaderboard below.
///
/// [RoomCompeteMode.team] rooms only — gated at the call site in
/// room_detail_screen_lobby.dart, not here. A Competitive room's whole
/// point is the individual leaderboard below; an "everyone together"
/// number sitting above it undercuts that head-to-head framing, so this
/// card (progress numbers and the bonus section alike) simply doesn't
/// exist there. [isTeamMode] below is therefore always true whenever this
/// widget is actually built — kept as an explicit check anyway (rather
/// than assumed) so this file still reads correctly on its own, without
/// having to trust the call site got the gating right.
class _TeamProgressCard extends ConsumerWidget {
  final RoomModel room;
  final List<RoomParticipant> participants;
  final RoomParticipant? mine;
  const _TeamProgressCard({
    required this.room,
    required this.participants,
    required this.mine,
  });

  /// Flat per-participant reward for [RoomCompeteMode.team]'s one-time
  /// bonus (see RoomsController.claimTeamBonus) — same ballpark as Weekly
  /// Challenge's 200-350 XP / 50-100 gold rewards, deliberately not scaled
  /// by room length/size to keep the first version simple; easy to tune
  /// later if a longer room's "everyone, every day" feels like it deserves
  /// more than a short one.
  static const int _teamBonusXp = 150;
  static const int _teamBonusGold = 75;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final ratio = room.teamProgressRatio(participants);
    final completed = room.teamDaysCompleted(participants);
    final possible = room.teamMaxPossibleDays(participants);
    final allDoneToday = room.isLive && room.teamCompletedToday(participants);
    final pct = (ratio * 100).round();

    final isTeamMode = room.competeMode == RoomCompeteMode.team;
    final isPerfect = isTeamMode && room.teamIsPerfect(participants);
    final claimed = mine?.teamBonusClaimed ?? false;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: allDoneToday ? GameColors.emerald.withOpacity(0.08) : gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(
          color:
              allDoneToday ? GameColors.emerald.withOpacity(0.35) : gp.border,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.groups_rounded, size: 16, color: GameColors.gold),
              const SizedBox(width: 6),
              Expanded(
                child: Text(s.roomTeamProgressTitle,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: gp.textPrimary)),
              ),
              Text('$pct%',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: GameColors.gold)),
            ],
          ),
          const SizedBox(height: 10),
          XpBar(progress: ratio),
          const SizedBox(height: 8),
          Text(
            s.roomTeamProgressDays(completed, possible),
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w600, color: gp.textSec),
          ),
          if (allDoneToday) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    size: 15, color: GameColors.emerald),
                const SizedBox(width: 5),
                Text(
                  s.roomTeamAllDoneToday,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: GameColors.emerald),
                ),
              ],
            ),
          ],
          if (isTeamMode) ...[
            const SizedBox(height: 10),
            Divider(height: 1, color: gp.border),
            const SizedBox(height: 10),
            if (!isPerfect)
              Row(
                children: [
                  Icon(Icons.toll_rounded, size: 14, color: GameColors.gold),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      s.roomTeamBonusHint(_teamBonusXp, _teamBonusGold),
                      style: TextStyle(
                          fontSize: 11.5, color: gp.textSec, height: 1.35),
                    ),
                  ),
                ],
              )
            else if (!claimed && mine != null)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    ref
                        .read(roomsControllerProvider)
                        .claimTeamBonus(
                          room.code,
                          mine!,
                          xp: _teamBonusXp,
                          gold: _teamBonusGold,
                        )
                        .ignore();
                  },
                  icon: const Icon(Icons.card_giftcard_rounded, size: 16),
                  label: Text(s.roomTeamBonusClaimAction),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(42),
                    backgroundColor: GameColors.gold,
                    foregroundColor: Colors.black,
                  ),
                ),
              )
            else if (claimed)
              Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      size: 15, color: GameColors.emerald),
                  const SizedBox(width: 6),
                  Text(
                    s.roomTeamBonusClaimedLabel,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: GameColors.emerald),
                  ),
                ],
              ),
          ],
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 300.ms)
        .slideY(begin: 0.05, end: 0, curve: Curves.easeOut);
  }
}

/// This account's own linked habit(s) for [room], read-only - completing
/// them happens over in Grid, this is purely a "here's what counts, and
/// whether today's done yet" status card. Also hosts the show/hide toggle
/// for whether other participants can see which specific habit(s) these
/// are (see RoomsController.toggleHideDetails) - a decision only the
/// participant themself makes, so this card only ever renders for "mine".
/// One habit chip in "Your plan", aware of which shared-plan slot it sits in
/// so it can render the three states a slot can actually be in, and offer
/// the one action that makes sense for each:
///
///  - **Counting** (the normal case): gold chip. For the room's leader in a
///    shared-plan room, a long-press withdraws it from the plan for
///    everyone (see RoomsController.removeSharedHabit) - long-press, not a
///    visible X, so a destructive plan-wide change can't happen from a
///    mis-tap on a chip this small.
///  - **Skipped by this person** (see kDeclinedSlot): muted, struck through.
///    Tapping offers to add it after all, which resolves the slot to a fresh
///    habit cloned from the plan's own template - a skip was never meant to
///    be permanent.
///  - **Withdrawn by the leader** (see RoomHabitTemplate.removedAt): muted
///    with a "Removed" note, no action. It counts for nobody now, and only
///    the leader could bring it back.
class _PlanSlotChip extends ConsumerWidget {
  final RoomModel room;
  final RoomParticipant mine;
  final int index;
  const _PlanSlotChip({
    required this.room,
    required this.mine,
    required this.index,
  });

  bool get _isSkipped =>
      index < mine.linkedHabitIds.length &&
      mine.linkedHabitIds[index] == kDeclinedSlot;

  bool get _isWithdrawn =>
      room.habitMode == RoomHabitMode.shared &&
      index < room.sharedHabits.length &&
      room.sharedHabits[index].isRemoved;

  Future<void> _undoSkip(BuildContext context, WidgetRef ref) async {
    final s = S.of(context);
    // Resolving to a brand-new habit cloned from the template, so it counts
    // against the account's habit cap exactly like the resolve sheet's own
    // "Add as new" rows already do.
    if (!canAddHabits(ref)) {
      showHabitLimitGate(context, ref);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(mine.linkedHabitNames[index]),
        content: Text(s.roomSkippedHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.roomCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.roomNewHabitBannerAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(roomsControllerProvider).resolvePlanHabit(room, index);
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final s = S.of(context);
    final name = mine.linkedHabitNames[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.roomRemoveSharedHabit),
        content: Text(s.roomRemoveSharedHabitConfirm(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.roomCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.roomRemoveSharedHabit),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(roomsControllerProvider).removeSharedHabit(room, index);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final label = mine.linkedHabitNames[index];
    final muted = _isSkipped || _isWithdrawn;
    final uid = ref.watch(authStateProvider).asData?.value?.uid;
    final canRemove = !muted &&
        room.habitMode == RoomHabitMode.shared &&
        uid != null &&
        uid == room.createdBy &&
        index < room.sharedHabits.length;

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: muted
            ? gp.textTert.withOpacity(0.12)
            : GameColors.gold.withOpacity(0.14),
        borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: muted ? gp.textTert : GameColors.gold,
              decoration: _isSkipped ? TextDecoration.lineThrough : null,
            ),
          ),
          if (muted) ...[
            const SizedBox(width: 4),
            Text(
              _isWithdrawn ? s.roomRemovedLabel : s.roomSkippedLabel,
              style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w600,
                  color: gp.textTert),
            ),
          ],
        ],
      ),
    );

    if (_isWithdrawn) return chip;
    if (_isSkipped) {
      return GestureDetector(
        onTap: () => _undoSkip(context, ref),
        child: chip,
      );
    }
    if (!canRemove) return chip;
    return GestureDetector(
      onLongPress: () {
        HapticFeedback.mediumImpact();
        _confirmRemove(context, ref);
      },
      child: chip,
    );
  }
}

/// One flexible weekly-quota habit's standing in the current grid week, for
/// [_MyPlanCard]'s per-quota line: how many of [target] are banked, and
/// whether today is a [DayDemand.owed] day — a day that cannot be skipped
/// without putting the target out of reach.
typedef _QuotaStanding = ({
  String name,
  int done,
  int target,
  bool neededToday,
});

/// The quota standings worth a line on the plan card — one per counted
/// linked habit that is a flexible weekly quota under the room's own frozen
/// rule (falling back to the habit's current settings when no rule is
/// recorded yet, the same resolution order the sync itself uses).
///
/// Reads the person's OWN Grid squares (weeklyGridProvider) — the same
/// squares the room grader reads — not the participant doc's aggregated
/// counts, which can't tell one habit's completions from another's. Empty
/// whenever the Grid is showing some other week than the current one: the
/// numbers would silently describe whichever week the person last browsed
/// to, and no line at all beats a plausible wrong one.
List<_QuotaStanding> _quotaWeekStandings(
  WidgetRef ref,
  RoomParticipant mine,
  List<IslamicHabitTemplate> myHabits,
) {
  final grid = ref.watch(weeklyGridProvider);
  if (!grid.isCurrentWeek) return const [];
  final today = DateTime.now().effectiveDay;
  final todayKey = today.toDateKey();
  final habitById = {for (final h in myHabits) h.id: h};

  final out = <_QuotaStanding>[];
  for (final id in mine.countedHabitIds) {
    final habit = habitById[id];
    if (habit == null) continue;
    final rule = mine.ruleFor(id, todayKey);
    final type = rule?.frequencyType ?? habit.frequencyType;
    final weekdays = rule?.scheduledWeekdays ?? habit.scheduledWeekdays;
    if (type != HabitFrequencyType.weekly || weekdays.isNotEmpty) continue;
    final target = rule?.frequencyTarget ?? habit.frequencyTarget;

    final days = grid.days;
    final doneIdx = {
      for (var i = 0; i < days.length; i++)
        if (grid.squareFor(id, days[i]).isGreen) i,
    };
    final demand = weeklyQuotaDemand(
      dayCount: days.length,
      doneDays: doneIdx,
      target: target,
    );
    final todayIdx = days.indexWhere((d) => d.isSameDayAs(today));
    out.add(
      (
        name: habit.localName(S.of(ref.context).isAr),
        done: doneIdx.length,
        target: target.clamp(1, days.length),
        neededToday: todayIdx >= 0 && demand[todayIdx] == DayDemand.owed,
      ),
    );
  }
  return out;
}

class _MyPlanCard extends ConsumerWidget {
  final RoomModel room;
  final RoomParticipant mine;
  const _MyPlanCard({required this.room, required this.mine});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final today = DateTime.now().effectiveDay.toDateKey();
    final todayCount = mine.dailyDoneCount[today] ?? 0;
    // Not linkedHabitIds.length - a habit with its own weekday schedule
    // that isn't scheduled today shouldn't inflate "how many were due"
    // (see RoomParticipant.scheduledCountFor's doc comment).
    final totalCount = mine.scheduledCountFor(today);
    final doneToday = mine.isFullyDone(today);
    final partialToday = todayCount > 0 && !doneToday;
    final names =
        mine.linkedHabitNames.where((n) => n.trim().isNotEmpty).toList();
    // A linked habit id that's no longer on this account's own board means
    // dailyDoneCount can never advance again for that slot
    // (syncTodayForHabit/syncLinkedHabitsProgress both drive off real Grid
    // squares, and an absent habit has none). WHY it is absent decides
    // everything the member is then told, and there are two answers, not
    // one: paused, which they chose and can undo in a tap, and deleted,
    // which they cannot. Both are purely explanations rather than
    // fix-it-here UI, but only the deleted one has no remedy to point at.
    final myHabits = ref.watch(habitListProvider);
    // Paused and deleted both leave habitListProvider, and only one of the
    // two is permanent or worth a red warning. See roomUnresolvedLinks.
    final unresolved = roomUnresolvedLinks(
      mine,
      myHabits,
      ref.watch(pausedHabitsProvider),
      isAr: s.isAr,
    );
    final pausedLinkNames = unresolved.pausedNames;
    final hasDeletedLink = unresolved.hasDeleted;
    // Whether any counted habit still grades — resolves to the active board.
    // Paused and deleted links both fall out of habitListProvider, so this is
    // false exactly when the member has nothing left counting here, which is
    // what decides between the reassuring and the standing-down hint below.
    final anyGradableLeft = roomHasGradableHabit(
        mine.countedHabitIdsIn(room), {for (final h in myHabits) h.id});
    // Habits whose live settings no longer match what this room scores them
    // by - see roomRuleMismatches for why the room deliberately keeps the
    // original rule rather than following the edit.
    final ruleMismatches = roomRuleMismatches(mine, myHabits, today);
    // One colour, decided once, so the icon and the words can never disagree
    // about what today looks like.
    final statusColor = doneToday
        ? GameColors.success
        : partialToday
            ? GameColors.gold
            : gp.textSec;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GameColors.gold.withOpacity(0.08),
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: GameColors.gold.withOpacity(0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── One line, and it answers the only urgent question ──────────
          // This card used to stack four separate rows: a "Your plan" title,
          // a small trailing "not done yet today", the habit chips, an "add
          // another habit" row and a "visible to the room" row - roughly
          // 160pt of mostly empty card in which the one thing a person opens
          // it for (am I done today?) was the smallest text on it.
          //
          // The status is the headline now, in the colour of its own answer,
          // and the title is gone: a card that says "not done yet today"
          // above your own habit does not also need to be labelled "your
          // plan". The two settings that took a row each - add another
          // habit, show/hide your habits from the room - are icon buttons on
          // this same line. Neither is information; both are things you do
          // once and forget.
          Row(
            children: [
              Icon(
                doneToday
                    ? Icons.check_circle_rounded
                    : partialToday
                        ? Icons.timelapse_rounded
                        : Icons.radio_button_unchecked_rounded,
                size: 18,
                color: statusColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  doneToday
                      ? s.roomMarkedToday
                      : partialToday
                          ? s.roomPartialToday(todayCount, totalCount)
                          : s.roomNotDoneToday,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: statusColor),
                ),
              ),
              // 'Own' mode only - a shared room has a leader-curated plan
              // and nothing for a member to add to it.
              if (room.habitMode == RoomHabitMode.own)
                _PlanIconButton(
                  icon: Icons.add_rounded,
                  color: GameColors.gold,
                  tooltip: s.roomAddAnotherHabitAction,
                  onTap: () async {
                    HapticFeedback.selectionClick();
                    final picked = await pickOwnHabitSheet(
                      context,
                      title: s.roomAddAnotherHabitPickerTitle,
                      hint: s.roomAddAnotherHabitPickerHint,
                      excludeIds: mine.linkedHabitIds,
                    );
                    if (picked == null || !context.mounted) return;
                    await ref
                        .read(roomsControllerProvider)
                        .addMyLinkedHabit(room, picked.id, picked.name);
                  },
                ),
              // 'Own' mode only, same gate as the add button above. In a
              // shared room every member runs the leader's plan, which the
              // header prints for everyone — so there is nothing this could
              // hide, and a toggle that changes nothing is worse than no
              // toggle. The names it governs are themselves only rendered
              // for own-mode rooms (see _LeaderboardRow).
              if (room.habitMode == RoomHabitMode.own)
                _PlanIconButton(
                  icon: mine.hideDetails
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: gp.textTert,
                  // The tooltip says which way the tap goes, so the icon
                  // alone never has to carry both its state and its action.
                  tooltip: mine.hideDetails
                      ? s.roomDetailsHidden
                      : s.roomDetailsVisible,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    ref
                        .read(roomsControllerProvider)
                        .toggleHideDetails(room.code, !mine.hideDetails)
                        .ignore();
                  },
                ),
            ],
          ),
          // Index-aware rather than a filtered copy of the names: each
          // chip's POSITION is what maps it back to its shared-plan slot,
          // which is exactly what the skipped/withdrawn states and the
          // leader's remove action both need (see _PlanSlotChip).
          if (names.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < mine.linkedHabitNames.length; i++)
                  if (mine.linkedHabitNames[i].trim().isNotEmpty)
                    _PlanSlotChip(room: room, mine: mine, index: i),
              ],
            ),
          ],
          // A flexible weekly quota's week-level standing ("2 of 4 this
          // week"), one line per quota habit. The headline above only
          // answers *today* — correct, but for a "4x a week, any days"
          // habit today is half the story, and the other half (how far
          // into the quota am I, and is today one of the days I can't
          // afford to skip?) previously lived nowhere on this screen. The
          // "needed today" tail comes from the same day-local verdict the
          // Grid's red squares use (weeklyQuotaDemand), so this line and
          // the Grid can never tell two different stories.
          for (final q in _quotaWeekStandings(ref, mine, myHabits)) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  q.neededToday
                      ? Icons.local_fire_department_rounded
                      : Icons.event_repeat_rounded,
                  size: 13,
                  color: q.neededToday ? GameColors.warning : gp.textTert,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    q.neededToday
                        ? '${s.roomQuotaWeekProgress(q.name, q.done, q.target)}'
                            ' · ${s.roomQuotaNeededToday}'
                        : s.roomQuotaWeekProgress(q.name, q.done, q.target),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          q.neededToday ? FontWeight.w800 : FontWeight.w600,
                      color: q.neededToday ? GameColors.warning : gp.textTert,
                    ),
                  ),
                ),
              ],
            ),
          ],
          // countedHabitCount, not names.length: a skipped slot still has a
          // name (struck through in the chips above) but contributes nothing,
          // so counting it here would promise "complete all 3" when only 2
          // can actually be completed.
          if (mine.countedHabitCount > 1) ...[
            const SizedBox(height: 8),
            Text(s.roomPlanPartialCreditHint(mine.countedHabitCount),
                style:
                    TextStyle(fontSize: 10.5, color: gp.textTert, height: 1.3)),
          ],
          // A habit counted several times a day only earns its room day once
          // the whole count is finished, which is not something the board says
          // anywhere: the square fills gradually, so two of four LOOKS like
          // progress toward the room and is worth nothing there until it is
          // four. Stated per habit, and only for the ones it applies to.
          for (final h in myHabits)
            if (h.effectiveDailyTarget > 1 &&
                mine.countedHabitIdsIn(room).contains(h.id)) ...[
              const SizedBox(height: 6),
              Text(
                s.roomCountedHabitRule(
                    h.localName(s.isAr), h.effectiveDailyTarget),
                style: TextStyle(
                    fontSize: 10.5, color: gp.textTert, height: 1.3),
              ),
            ],
          // Before the red one: a paused habit is the far more common of
          // the two, and it is the reassuring half of the message. Someone
          // with both wants to read "this one is just paused" before "this
          // one is really gone".
          if (pausedLinkNames.isNotEmpty) ...[
            const SizedBox(height: 10),
            _WarningRow(
              // The reassuring version is only true while SOMETHING is still
              // gradable — a counted habit that still resolves to the board.
              // Deciding on `pausedLinkNames.length == countedHabitCount`
              // instead got two cases wrong: a plan of one paused + one deleted
              // habit read as "not all paused" and got the calm hint though
              // nothing was gradable, and an all-paused plan of several habits
              // passed only the first name to the singular sole-hint. Asking
              // roomHasGradableHabit — the exact check grading uses — fixes
              // both, and the plural hint names every paused habit. Same split
              // as the pause dialog, see mySoleRoomHabitsProvider.
              text: anyGradableLeft
                  ? s.roomLinkedHabitPausedHint(pausedLinkNames)
                  : pausedLinkNames.length == 1
                      ? s.roomSoleLinkedHabitPausedHint(pausedLinkNames.first)
                      : s.roomLinkedHabitAllPausedHint(pausedLinkNames),
              informational: anyGradableLeft,
            ),
          ],
          if (hasDeletedLink) ...[
            const SizedBox(height: 10),
            _WarningRow(text: s.roomLinkedHabitDeletedHint),
          ],
          // Explains, rather than warns: the room holding its original rules
          // is the correct behaviour (it's what stops an edit rewriting
          // finished days), so this states what's happening and offers the
          // deliberate opt-in - it is never an error state.
          if (ruleMismatches.isNotEmpty) ...[
            const SizedBox(height: 10),
            _WarningRow(
                text: s.roomRuleChangedWarning(ruleMismatches.join(', '))),
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () async {
                  HapticFeedback.selectionClick();
                  // Captured before the await - same "don't touch context
                  // across an async gap" pattern every other confirmation
                  // in this feature uses (see _confirmExtend).
                  final messenger = ScaffoldMessenger.of(context);
                  final confirmation = s.roomRuleChangedApplied;
                  await ref
                      .read(roomsControllerProvider)
                      .relockHabitRules(room);
                  messenger.showSnackBar(SnackBar(content: Text(confirmation)));
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(s.roomRuleChangedAction,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: GameColors.gold)),
              ),
            ),
          ],
          // Shared-mode only, and only once there's actually something
          // unresolved - see RoomHabitTemplate.linkedHabitIds' own doc
          // comment on the 1:1 positional correspondence this length
          // comparison relies on: a plan grown by RoomsController.
          // addSharedHabit after this participant already joined/last
          // resolved leaves their own linkedHabitIds shorter than the
          // room's current sharedHabits, and that gap *is* the unresolved
          // count - nothing else needs to track it separately.
          if (room.habitMode == RoomHabitMode.shared &&
              mine.linkedHabitIds.length < room.sharedHabits.length) ...[
            const SizedBox(height: 10),
            _NewHabitBanner(room: room, mine: mine),
          ],
          // The add-habit and show/hide rows that used to live here are the
          // two icon buttons on the header row above.
        ],
      ),
    );
  }
}

/// Tappable prompt shown on [_MyPlanCard] once the leader's added a shared-
/// plan habit this participant hasn't linked anything to yet (see
/// RoomsController.addSharedHabit/resolvePlanHabit). Gold, not red - this
/// isn't a problem the way [_WarningRow]'s deleted-link case is, just
/// something worth a tap. Names the single newest unresolved entry (the
/// common case is exactly one) rather than a generic "you have updates" -
/// if more than one has piled up, [showResolveNewHabitsSheet] itself walks
/// through all of them once opened.
class _NewHabitBanner extends StatelessWidget {
  final RoomModel room;
  final RoomParticipant mine;
  const _NewHabitBanner({required this.room, required this.mine});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final newest = room.sharedHabits.last.name;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        HapticFeedback.selectionClick();
        showResolveNewHabitsSheet(context, room: room, mine: mine);
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: GameColors.gold.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: GameColors.gold.withOpacity(0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.fiber_new_rounded, size: 16, color: GameColors.gold),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.roomNewHabitBannerTitle(newest),
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: gp.textPrimary,
                          height: 1.3)),
                  const SizedBox(height: 2),
                  Text(s.roomNewHabitBannerBody,
                      style: TextStyle(
                          fontSize: 10.5, color: gp.textSec, height: 1.3)),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 16, color: GameColors.gold),
          ],
        ),
      ),
    );
  }
}

/// A small, square tap target for the two settings that live on
/// [_MyPlanCard]'s header row: add another habit, and show/hide your habits
/// from the room.
///
/// Each used to be a full-width row with an icon and a label — which is a lot
/// of card for something you set once and never look at again. Between them
/// they took more vertical space than the status they sat under. As icons
/// they keep a 34pt tap target, and the label moves into the tooltip, which
/// is also what a screen reader announces.
class _PlanIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;
  const _PlanIconButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}
