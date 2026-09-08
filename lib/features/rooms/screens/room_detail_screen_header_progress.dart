part of 'room_detail_screen.dart';

class _PodiumColumn extends StatelessWidget {
  final RoomParticipant participant;
  final int rank;

  /// Whether this column shares its place with another. Same job as
  /// _LeaderboardRow's own sharedPlace: it names the tie for anyone who
  /// cannot see that two columns are the same height.
  final bool sharedPlace;
  final RoomModel room;
  const _PodiumColumn({
    required this.participant,
    required this.rank,
    required this.sharedPlace,
    required this.room,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    // Height and colour both come from the member's own place, so two
    // members who finished level get two identical gold columns rather
    // than a tall winner and a short runner-up chosen by uid order. See
    // RoomLeaderboard.standings.
    final (height, color) = switch (rank) {
      1 => (64.0, GameColors.gold),
      2 => (46.0, const Color(0xFFB9C0C7)),
      _ => (34.0, const Color(0xFFC98A5E)),
    };
    final pct = (participant.progressRatio(room) * 100).round();
    // The plinth keeps the medal's true metal; the two labels take its ink.
    // All three metals are pale on a light surface - gold measured 2.03:1
    // here on device - and silver and bronze are no better, so this goes
    // through the generic primitive rather than the accent-only tokens.
    final ink = gp.ink(color);
    // One finisher, one stop, spoken in the order they finished.
    //
    // Two separate problems, and a tie made both worse. The column's four
    // pieces (cup, name, percent, plinth number) were four unrelated stops,
    // so the plinth's bare "2" arrived detached from the name it belongs
    // to; MergeSemantics makes the column one announcement. And the visual
    // order is second, first, third, the classic silhouette, which
    // semantics traversal reads geometrically, so the runner-up was
    // announced before the winner; the sort key restores the podium's own
    // order without moving a pixel. On a shared first the old behaviour put
    // two "tied for first place" labels either side of a name that belonged
    // to neither of them.
    return Semantics(
      sortKey: OrdinalSortKey(rank.toDouble()),
      child: MergeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (rank == 1)
              Icon(
                Icons.emoji_events_rounded,
                size: 20,
                color: context.gp.goldInk,
                semanticLabel:
                    sharedPlace ? s.roomPlaceFirstTied : s.roomPlaceFirst,
              ),
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
                color: ink,
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
                // Only for the places without a cup above them: on a shared
                // first the icon has already said it, and saying it twice
                // inside one merged announcement is worse than not saying it.
                semanticsLabel:
                    sharedPlace && rank > 1 ? s.roomPlaceTied(rank) : null,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: ink,
                ),
              ),
            ),
          ],
        ),
      ),
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
                        color: context.gp.goldInk)),
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
/// The hero of a team room (RoomCompeteMode.team): today's roster, the
/// team streak, the days won together, and the next milestone with its
/// prize. Replaces the old team card, whose one bonus asked for every
/// member perfect over the whole room and was never paid in practice; the
/// rules it draws are RoomTeamProgress's team-day rules.
///
/// Faces first, on purpose. The daily question in a team room is "who is
/// still to go", and a row of avatars with a green tick answers it before
/// any number does. Under it, one status line, then the numbers.
///
/// Renders for an ended room too (the milestones stay claimable after the
/// end), minus the today line, which has nothing to say once the last day
/// is final.
class _TeamDayCard extends ConsumerWidget {
  final RoomModel room;
  final List<RoomParticipant> participants;
  final RoomParticipant? mine;
  const _TeamDayCard({
    required this.room,
    required this.participants,
    required this.mine,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final today = room.lastCountedDay;
    final todayKey = today.toDateKey();
    final counted = [
      for (final p in participants)
        if (room.memberCountsOn(p, todayKey, today)) p,
    ];
    final waiting = [
      for (final p in counted)
        if (!p.isFullyDone(todayKey)) p,
    ];
    final wonToday = counted.isNotEmpty && waiting.isEmpty;
    final streak = room.teamStreak(participants);
    final days = room.teamDays(participants);
    final ratio =
        days.counted == 0 ? 0.0 : (days.won / days.counted).clamp(0.0, 1.0);
    final pct = (ratio * 100).round();

    // Milestones, for THIS member: the first unclaimed one is either
    // reached (claimable) or the next target. teamBestStreakWith is the
    // tenure guard; see its doc comment.
    final me = mine;
    final best = me == null ? 0 : room.teamBestStreakWith(me, participants);
    final mine_ = me == null ? 0 : room.teamStreakWith(me, participants);
    final claims = me?.teamStreakClaims ?? const <int>[];
    int? claimable;
    int? next;
    for (final m in RoomTeamProgress.teamMilestones) {
      if (claims.contains(m)) continue;
      if (best >= m) {
        claimable = m;
      } else {
        next = m;
      }
      break;
    }
    final lastClaimed =
        claims.isEmpty ? null : claims.reduce((a, b) => a > b ? a : b);

    // The ranked list already hides blocked members; the roster does the
    // same so a person someone blocked is not smiling at them from here.
    final blocked = ref.watch(blockedMembersProvider);
    final roster = [
      for (final p in participants)
        if (!blocked.contains(p.uid)) p,
    ];

    final String? statusText;
    final Color statusColor;
    if (!room.isLive || counted.isEmpty) {
      statusText = null;
      statusColor = gp.textSec;
    } else if (wonToday) {
      statusText = s.roomTeamDayWon;
      statusColor = GameColors.emerald;
    } else if (waiting.length == counted.length) {
      statusText = s.roomTeamNobodyYet;
      statusColor = GameColors.gold;
    } else if (waiting.length == 1) {
      statusText = s.roomTeamWaitingOn(waiting.single.displayName);
      statusColor = GameColors.gold;
    } else {
      statusText = s.roomTeamWaitingCount(waiting.length);
      statusColor = GameColors.gold;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(
          color: wonToday && room.isLive
              ? GameColors.emerald.withOpacity(0.35)
              : gp.border,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.groups_rounded, size: 18, color: context.gp.goldInk),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.roomTeamDayTitle,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: gp.textPrimary,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: GameColors.gold.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.local_fire_department_rounded,
                        size: 14, color: context.gp.goldInk),
                    const SizedBox(width: 4),
                    Text(
                      s.roomTeamStreakPill(streak),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: context.gp.goldInk,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _FacesRow(
            room: room,
            roster: roster,
            meUid: me?.uid,
            todayKey: todayKey,
            today: today,
          ),
          if (statusText != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.10),
                borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
              ),
              child: Row(
                children: [
                  Icon(
                    wonToday
                        ? Icons.check_circle_rounded
                        : Icons.schedule_rounded,
                    size: 15,
                    color: statusColor,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  s.roomTeamDaysWon(days.won, days.counted),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: gp.textSec,
                  ),
                ),
              ),
              Text(
                '$pct%',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: context.gp.goldInk,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          XpBar(progress: ratio),
          if (me != null) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: gp.border),
            const SizedBox(height: 10),
            _MilestoneRow(
              claimable: claimable,
              next: next,
              lastClaimed: lastClaimed,
              current: mine_,
              onClaim: claimable == null
                  ? null
                  : () {
                      HapticFeedback.mediumImpact();
                      ref
                          .read(roomsControllerProvider)
                          .claimTeamStreakBonus(room.code, me, claimable!)
                          .ignore();
                    },
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

/// One face on the team card: the member's character (or a silhouette
/// initial when their character is unknown), ringed green with a tick once
/// today is done, plain while they are still to go, dimmed when today asks
/// nothing of them (stood down, or not yet joined by then).
class _RosterFace extends StatelessWidget {
  final RoomParticipant participant;
  final bool done;
  final bool excused;
  final bool isYou;

  /// Avatar only, 36pt and no name under it, for a list row that names the
  /// person itself (the members sheet).
  final bool compact;
  const _RosterFace({
    required this.participant,
    required this.done,
    required this.excused,
    required this.isYou,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final character = CharacterCatalog.findById(participant.characterId);
    final accessory = AccessoryCatalog.findById(participant.accessoryId);
    final ring = done
        ? GameColors.emerald
        : excused
            ? gp.border
            : gp.textTert;
    final name = participant.displayName.trim();
    final s = S.of(context);
    final shown = isYou ? s.roomYouLabel : name;
    final size = compact ? 36.0 : 48.0;
    final avatar = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: gp.surfaceHL,
            shape: BoxShape.circle,
            border: Border.all(color: ring, width: done ? 2 : 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.bottomCenter,
          child: character == null
              ? Center(
                  child: Text(
                    name.isEmpty ? '?' : name.characters.first,
                    style: TextStyle(
                      fontSize: compact ? 13 : 15,
                      fontWeight: FontWeight.w700,
                      color: gp.textPrimary,
                    ),
                  ),
                )
              : CharacterAvatar(
                  character: character,
                  accessory: accessory,
                  height: compact ? 33 : 44,
                ),
        ),
        if (done)
          PositionedDirectional(
            bottom: -2,
            end: -2,
            child: Container(
              width: compact ? 15 : 18,
              height: compact ? 15 : 18,
              decoration: BoxDecoration(
                color: GameColors.emerald,
                shape: BoxShape.circle,
                border: Border.all(color: gp.surface, width: 2),
              ),
              child: Icon(Icons.check_rounded,
                  size: compact ? 9 : 11, color: Colors.black),
            ),
          ),
      ],
    );
    return Semantics(
      // The tick and the ring are the whole message, and neither speaks.
      label: '$shown، ${done ? s.roomFaceDone : excused ? s.roomFaceExcused : s.roomFaceWaiting}',
      excludeSemantics: true,
      child: Opacity(
        opacity: excused ? 0.55 : 1,
        child: compact
            ? avatar
            : SizedBox(
                width: 56,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    avatar,
                    const SizedBox(height: 5),
                    Text(
                      shown,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isYou ? FontWeight.w700 : FontWeight.w500,
                        color: done ? gp.textPrimary : gp.textSec,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// The card's last row: the next milestone and its prize, a Claim button
/// the moment one is reached, and "every reward claimed" once the three
/// are gone. One row for all three states so the card never jumps height
/// when a milestone lands.
class _MilestoneRow extends StatelessWidget {
  final int? claimable;
  final int? next;
  final int? lastClaimed;

  /// This member's current run (RoomTeamProgress.teamStreakWith), which is
  /// what the next milestone is counted down from.
  final int current;
  final VoidCallback? onClaim;
  const _MilestoneRow({
    required this.claimable,
    required this.next,
    required this.lastClaimed,
    required this.current,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final String title;
    final String sub;
    if (claimable != null) {
      final prize = RoomTeamProgress.teamMilestonePrize(claimable!);
      title = s.roomTeamMilestoneReached(claimable!);
      sub = s.roomTeamMilestonePrize(prize.xp, prize.gold);
    } else if (next != null) {
      final prize = RoomTeamProgress.teamMilestonePrize(next!);
      title = lastClaimed == null
          ? s.roomTeamNextMilestone(next!)
          : s.roomTeamMilestoneClaimed(lastClaimed!);
      final toGo = (next! - current).clamp(1, next!);
      sub = lastClaimed == null
          ? '${s.roomTeamDaysToGo(toGo)}. ${s.roomTeamMilestonePrize(prize.xp, prize.gold)}'
          : '${s.roomTeamNextMilestone(next!)}. ${s.roomTeamMilestonePrize(prize.xp, prize.gold)}';
    } else {
      title = s.roomTeamAllMilestonesDone;
      sub = s.roomTeamMilestoneClaimed(lastClaimed ?? 30);
    }
    return Row(
      children: [
        Icon(Icons.card_giftcard_rounded, size: 20, color: context.gp.goldInk),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: gp.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                sub,
                style: TextStyle(fontSize: 11.5, color: gp.textSec, height: 1.3),
              ),
            ],
          ),
        ),
        if (onClaim != null) ...[
          const SizedBox(width: 10),
          FilledButton(
            onPressed: onClaim,
            style: FilledButton.styleFrom(
              backgroundColor: GameColors.gold,
              foregroundColor: GameColors.onGold,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: Text(s.roomTeamClaimAction),
          ),
        ],
      ],
    );
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
              color: muted ? gp.textTert : context.gp.goldInk,
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
    final collapsed = ref.watch(roomPlanCollapsedProvider);
    final todayCount = mine.dailyDoneCount[today] ?? 0;
    // Not linkedHabitIds.length - a habit with its own weekday schedule
    // that isn't scheduled today shouldn't inflate "how many were due"
    // (see RoomParticipant.scheduledCountFor's doc comment).
    final totalCount = mine.scheduledCountFor(today);
    // Every counted habit paused, so the room is not asking for anything
    // today (see RoomParticipant.standDownDays). Taken before done/partial
    // because both of those are computed from counts a stand-down day
    // deliberately does not have: isFullyDone is false on such a day, which
    // would otherwise land it on the "not done yet today" headline and put
    // the card in direct contradiction with the paused hint underneath it.
    final stoodDownToday = mine.isStoodDownOn(today);
    final doneToday = mine.isFullyDone(today);
    final partialToday = todayCount > 0 && !doneToday && !stoodDownToday;
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
    final statusColor = stoodDownToday
        ? gp.textTert
        : doneToday
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
              // partialToday already excludes stoodDown and done (see where it
              // is computed), so it can lead. It was the last clock face left
              // in the app after the Grid's جزئي square became a half-filled
              // one — and on a line that says "2 of 4 today" a clock was the
              // wrong picture twice over.
              if (partialToday)
                HalfFullMark(size: 18, color: statusColor)
              else
                Icon(
                  stoodDownToday
                      ? Icons.pause_circle_outline_rounded
                      : doneToday
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                  size: 18,
                  color: statusColor,
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  stoodDownToday
                      ? s.roomStoodDownToday
                      : doneToday
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
              // Folds the card to this status line (remembered on the
              // device): the habits and week lines are detail once you know
              // your plan; the line is what you check.
              _PlanIconButton(
                icon: collapsed
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.keyboard_arrow_up_rounded,
                color: gp.textTert,
                tooltip:
                    collapsed ? s.roomTeamRankingShow : s.roomTeamRankingHide,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setRoomPlanCollapsed(ref, !collapsed);
                },
              ),
            ],
          ),
          if (!collapsed) ...[
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
                  color: q.neededToday ? context.gp.warningInk : gp.textTert,
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
                      color: q.neededToday ? context.gp.warningInk : gp.textTert,
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
                  messenger.showOne(SnackBar(content: Text(confirmation)));
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
                        color: context.gp.goldInk)),
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
            Icon(Icons.fiber_new_rounded, size: 16, color: context.gp.goldInk),
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
            Icon(Icons.chevron_right_rounded, size: 16, color: context.gp.goldInk),
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

/// Today in a competitive room, in faces: who has finished and who is
/// still to go. The same _RosterFace the Team Day card uses, so the two
/// modes read the day the same way; here it sits above the ranked list
/// rather than replacing it, because the race is still the point.
/// Public (not underscored) so a widget test can pump it with a fake
/// roster: the room screen needs a live Firestore stream.
class RoomTodayCard extends ConsumerWidget {
  final RoomModel room;
  final List<RoomParticipant> participants;
  final RoomParticipant? mine;
  const RoomTodayCard({
    super.key,
    required this.room,
    required this.participants,
    required this.mine,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final today = room.lastCountedDay;
    final todayKey = today.toDateKey();
    final blocked = ref.watch(blockedMembersProvider);
    final roster = [
      for (final p in participants)
        if (!blocked.contains(p.uid)) p,
    ];
    final counted = [
      for (final p in roster)
        if (room.memberCountsOn(p, todayKey, today)) p,
    ];
    final done = counted.where((p) => p.isFullyDone(todayKey)).length;
    final allDone = counted.isNotEmpty && done == counted.length;
    // Folds to its header line on a tap (remembered on the device): the
    // count stays readable either way, the faces are the detail.
    final collapsed = ref.watch(roomTodayCollapsedProvider);
    return Material(
      color: gp.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        side: BorderSide(
          color: allDone && room.isLive
              ? GameColors.emerald.withOpacity(0.35)
              : gp.border,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setRoomTodayCollapsed(ref, !collapsed);
            },
            child: Padding(
              padding: EdgeInsets.fromLTRB(14, 14, 14, collapsed ? 14 : 12),
              child: Row(
                children: [
                  Icon(Icons.today_rounded, size: 16, color: gp.textSec),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.navToday,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: gp.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    s.roomTodayFinished(done, counted.length),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: allDone ? context.gp.emeraldInk : gp.textSec,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Semantics(
                    label: collapsed
                        ? s.roomTeamRankingShow
                        : s.roomTeamRankingHide,
                    child: Icon(
                      collapsed
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_up_rounded,
                      size: 18,
                      color: gp.textTert,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!collapsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: _FacesRow(
                room: room,
                roster: roster,
                meUid: mine?.uid,
                todayKey: todayKey,
                today: today,
              ),
            ),
        ],
      ),
    );
  }
}

/// How many faces a card draws in its one row.
const int kRoomFacesPerRow = 5;

/// Everyone when they fit the row; otherwise one fewer than a row, and the
/// last slot counts the rest. Public for the test.
({int shown, int hidden}) roomFacesSplit(int count,
    {int perRow = kRoomFacesPerRow}) {
  if (count <= perRow) return (shown: count, hidden: 0);
  return (shown: perRow - 1, hidden: count - (perRow - 1));
}

/// Today's faces in ONE row. Past [kRoomFacesPerRow] the last slot becomes
/// a +N circle and the row opens a sheet with everyone. A second row of
/// faces was the card growing to fit the room rather than the reader
/// (Aziz, 2026-09-06); the sheet is where a big room's full list lives.
class _FacesRow extends StatelessWidget {
  final RoomModel room;
  final List<RoomParticipant> roster;
  final String? meUid;
  final String todayKey;
  final DateTime today;
  const _FacesRow({
    required this.room,
    required this.roster,
    required this.meUid,
    required this.todayKey,
    required this.today,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final split = roomFacesSplit(roster.length);
    final shown = roster.take(split.shown).toList();
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, p) in shown.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          _RosterFace(
            participant: p,
            done: p.isFullyDone(todayKey),
            excused: !room.memberCountsOn(p, todayKey, today),
            isYou: p.uid == meUid,
          ),
        ],
        if (split.hidden > 0) ...[
          const SizedBox(width: 8),
          _MoreFacesCircle(count: split.hidden),
        ],
      ],
    );
    if (split.hidden == 0) return row;
    return Semantics(
      button: true,
      label: s.roomFacesMore(split.hidden),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          HapticFeedback.selectionClick();
          showTodayMembersSheet(
            context,
            room: room,
            roster: roster,
            meUid: meUid,
            todayKey: todayKey,
            today: today,
          );
        },
        child: row,
      ),
    );
  }
}

/// The +N slot at the end of a full faces row.
class _MoreFacesCircle extends StatelessWidget {
  final int count;
  const _MoreFacesCircle({required this.count});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return ExcludeSemantics(
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: gp.surfaceHL,
                shape: BoxShape.circle,
                border: Border.all(color: gp.textTert, width: 1.5),
              ),
              child: Text(
                '+$count',
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: gp.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              s.roomFacesAll,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: gp.textSec),
            ),
          ],
        ),
      ),
    );
  }
}

/// Everyone in the room and where they stand today, for rooms too big for
/// one row of faces.
Future<void> showTodayMembersSheet(
  BuildContext context, {
  required RoomModel room,
  required List<RoomParticipant> roster,
  required String? meUid,
  required String todayKey,
  required DateTime today,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (_) => _TodayMembersSheet(
      room: room,
      roster: roster,
      meUid: meUid,
      todayKey: todayKey,
      today: today,
    ),
  );
}

class _TodayMembersSheet extends StatelessWidget {
  final RoomModel room;
  final List<RoomParticipant> roster;
  final String? meUid;
  final String todayKey;
  final DateTime today;
  const _TodayMembersSheet({
    required this.room,
    required this.roster,
    required this.meUid,
    required this.todayKey,
    required this.today,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final counted = [
      for (final p in roster)
        if (room.memberCountsOn(p, todayKey, today)) p,
    ];
    final done = counted.where((p) => p.isFullyDone(todayKey)).length;
    final maxHeight = MediaQuery.of(context).size.height * 0.8;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: gp.surfaceHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: gp.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
            child: Row(
              children: [
                Icon(Icons.today_rounded, size: 18, color: gp.textSec),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.navToday,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: gp.textPrimary,
                    ),
                  ),
                ),
                Text(
                  s.roomTodayFinished(done, counted.length),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: gp.textSec,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(
                  20, 6, 20, 24 + MediaQuery.of(context).padding.bottom),
              itemCount: roster.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: gp.border),
              itemBuilder: (context, i) {
                final p = roster[i];
                final isDone = p.isFullyDone(todayKey);
                final excused = !room.memberCountsOn(p, todayKey, today);
                final status = isDone
                    ? s.roomFaceDone
                    : excused
                        ? s.roomFaceExcused
                        : s.roomFaceWaiting;
                final color = isDone
                    ? GameColors.emerald
                    : excused
                        ? gp.textTert
                        : gp.textSec;
                final name =
                    p.uid == meUid ? s.roomYouLabel : p.displayName.trim();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      _RosterFace(
                        participant: p,
                        done: isDone,
                        excused: excused,
                        isYou: p.uid == meUid,
                        compact: true,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: gp.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        status,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A live room with one member in it. The code IS the screen: shown big,
/// with Copy and Share, the same two actions the create sheet offered a
/// moment ago, because the first thing a leader does after creating a room
/// is realise nobody is in it yet.
/// Public (not underscored) so a widget test can pump it on its own: the
/// room screen needs a live Firestore stream, and this card is the only
/// part of it a one-member room shows that the shared-room trace cannot
/// reach.
class RoomInviteCard extends StatelessWidget {
  final RoomModel room;
  const RoomInviteCard({super.key, required this.room});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: GameColors.gold.withOpacity(0.35), width: 0.75),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.group_add_rounded, size: 18, color: context.gp.goldInk),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.roomSoloTitle,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: gp.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            s.roomShareCode,
            style: TextStyle(fontSize: 12, color: gp.textSec, height: 1.35),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: GameColors.gold.withOpacity(0.10),
              borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
              border: Border.all(color: GameColors.gold.withOpacity(0.35)),
            ),
            child: Text(
              room.code,
              textAlign: TextAlign.center,
              // The code is Latin letters either way; pinned LTR so Arabic
              // shaping never reorders it.
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: 4,
                color: context.gp.goldInk,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    Clipboard.setData(ClipboardData(text: room.code));
                    ScaffoldMessenger.of(context).showOne(
                      SnackBar(content: Text(s.roomCodeCopied)),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: Text(s.roomCopyAction),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    // See the finale's extend button: a local override has
                    // to take the ink itself, the theme cannot reach it.
                    foregroundColor: gp.goldInk,
                    side: BorderSide(
                      color: gp.dark
                          ? GameColors.gold.withValues(alpha: 0.55)
                          : gp.goldEdge,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    AnalyticsService.instance.track('room_code_shared',
                        props: {'surface': 'room_header'});
                    ShareService.shareText(
                      context,
                      s.roomShareMessage(room.name, room.code),
                    );
                  },
                  icon: const Icon(Icons.ios_share_rounded, size: 16),
                  label: Text(s.roomShareAction),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    backgroundColor: GameColors.gold,
                    foregroundColor: GameColors.onGold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
