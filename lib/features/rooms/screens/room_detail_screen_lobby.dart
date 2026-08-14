part of 'room_detail_screen.dart';


class _RoomBody extends ConsumerWidget {
  final RoomModel room;
  final void Function(RoomModel, RoomParticipant?) onSyncIfNeeded;
  final Future<void> Function(RoomModel, RoomParticipant?) onManualSync;
  final VoidCallback onLeave;
  final VoidCallback onDelete;
  final VoidCallback onExtend;
  final RoomParticipant? Function(List<RoomParticipant>) mineOf;

  const _RoomBody({
    required this.room,
    required this.onSyncIfNeeded,
    required this.onManualSync,
    required this.onLeave,
    required this.onDelete,
    required this.onExtend,
    required this.mineOf,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final uid = ref.watch(authStateProvider).asData?.value?.uid;
    final isLeader = uid != null && uid == room.createdBy;
    final participantsAsync = ref.watch(roomParticipantsProvider(room.code));
    // Needed up here (not just inside the `data:` branch below) so the
    // app-bar's mute toggle can show the right label/icon before the list
    // itself has necessarily rendered - null only very briefly, while
    // participantsAsync is still loading, in which case the toggle just
    // isn't shown yet (see the AppBar's own `if (mine != null)` below).
    final mine = participantsAsync.valueOrNull == null
        ? null
        : mineOf(participantsAsync.valueOrNull!);
    // Rooms Alive Phase 1 — live in-app celebrations for a teammate
    // finishing today or joining while you're looking at this room. See
    // registerRoomReactions' own doc comment (room_reactions.dart).
    registerRoomReactions(context, ref, room);

    return Scaffold(
      backgroundColor: gp.bg,
      appBar: AppBar(
        backgroundColor: gp.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(room.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: gp.textPrimary)),
        actions: [
          // Only offered once this account's own participant doc is known -
          // see [mine]'s own doc comment above for the one brief window
          // (still loading) where it's null. A standalone icon rather than
          // a 3-dot menu item: mute/unmute is the one control here worth
          // reaching in a single tap, not two.
          if (mine != null)
            IconButton(
              icon: Icon(mine.notificationsMuted
                  ? Icons.notifications_off_rounded
                  : Icons.notifications_active_rounded),
              tooltip: mine.notificationsMuted
                  ? s.roomUnmuteAction
                  : s.roomMuteAction,
              onPressed: () => _toggleMute(context, ref, room, mine),
            ),
          IconButton(
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: s.roomShareAction,
            onPressed: () {
              HapticFeedback.selectionClick();
              ShareService.shareText(
                context,
                s.roomShareMessage(room.name, room.code),
              );
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'leave') onLeave();
              if (value == 'delete') onDelete();
              if (value == 'extend') onExtend();
              if (value == 'addHabit') _addHabitToPlan(context, ref, room);
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'leave', child: Text(s.roomLeaveAction)),
              // Only offered for a fixed-length room - an open-ended one
              // never locks in the first place, so there's nothing to
              // extend. Available whether or not the room has ended yet,
              // not just after - a leader running low on time shouldn't
              // have to wait for the countdown to actually hit zero before
              // being able to add more.
              if (isLeader && room.duration == RoomDuration.fixed)
                PopupMenuItem(value: 'extend', child: Text(s.roomExtendAction)),
              // Shared mode only - 'own' mode has no leader-curated plan to
              // add to in the first place (every participant, leader
              // included, already has their own always-open "Add another
              // habit" on _MyPlanCard instead - see addMyLinkedHabit).
              if (isLeader && room.habitMode == RoomHabitMode.shared)
                PopupMenuItem(
                    value: 'addHabit', child: Text(s.roomAddHabitAction)),
              if (isLeader)
                PopupMenuItem(
                  value: 'delete',
                  child: Text(s.roomDeleteAction,
                      style: const TextStyle(color: GameColors.error)),
                ),
            ],
          ),
        ],
      ),
      body: participantsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Text(s.roomGenericError, style: TextStyle(color: gp.textSec)),
        ),
        data: (participants) {
          final mine = mineOf(participants);
          onSyncIfNeeded(room, mine);
          final sorted = [...participants]
            ..sort((a, b) => b.progressRatio(room).compareTo(a.progressRatio(room)));

          return RefreshIndicator(
            onRefresh: () => onManualSync(room, mine),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                // Lifecycle banners come first — they're the answer to
                // "what is this room doing right now?".
                if (room.isLobby) ...[
                  _LobbyCard(
                    room: room,
                    isLeader: isLeader,
                    memberCount: participants.length,
                  ),
                  const SizedBox(height: 14),
                ] else if (room.isCountingDown) ...[
                  _CountdownCard(),
                  const SizedBox(height: 14),
                ] else if (room.isEnded) ...[
                  _FinaleCard(
                    sorted: sorted,
                    room: room,
                    mine: mine,
                    isLeader: isLeader,
                    onExtend: onExtend,
                  ),
                  const SizedBox(height: 14),
                ],
                _RoomHeaderCard(room: room, memberCount: participants.length),
                // Team-wide combined goal, alongside (not instead of) the
                // individual leaderboard below — see RoomTeamProgress's doc
                // comment. Team mode only: a Competitive room's leaderboard
                // is the whole point, and an "everyone together" number
                // sitting above it undercuts the head-to-head framing the
                // leader chose at creation (see RoomCompeteMode's doc
                // comment) — so this card doesn't exist there at all, not
                // even the non-bonus progress numbers. Solo "rooms"
                // (waiting for others, or everyone else left) skip this
                // too: a team of one is just the leaderboard's own top row,
                // nothing new to say here.
                if (!room.isLobby &&
                    participants.length > 1 &&
                    room.competeMode == RoomCompeteMode.team) ...[
                  const SizedBox(height: 14),
                  _TeamProgressCard(room: room, participants: participants, mine: mine),
                ],
                if (mine != null && mine.linkedHabitIds.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _MyPlanCard(room: room, mine: mine),
                ],
                const SizedBox(height: 14),
                _LeaderboardList(sorted: sorted, room: room, myUid: uid),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Leader-only, 'shared'-mode-only: opens [pickOwnHabitSheet] to choose one
/// of the leader's own habits, then hands it straight to RoomsController.
/// addSharedHabit - no separate confirm step, matching AddTaskSheet's own
/// "picking is the confirmation" pattern. A plain top-level function (not a
/// _RoomBody method) since _RoomBody is stateless and this needs nothing
/// from its instance beyond what's already passed in.
Future<void> _addHabitToPlan(
  BuildContext context,
  WidgetRef ref,
  RoomModel room,
) async {
  final s = S.of(context);
  final uid = ref.read(authStateProvider).asData?.value?.uid;
  final myParticipant = ref
      .read(roomParticipantsProvider(room.code))
      .valueOrNull
      ?.where((p) => p.uid == uid);
  final mineHabitIds = myParticipant != null && myParticipant.isNotEmpty
      ? myParticipant.first.linkedHabitIds
      : const <String>[];
  final picked = await pickOwnHabitSheet(
    context,
    title: s.roomAddHabitPickerTitle,
    hint: s.roomAddHabitPickerHint,
    excludeIds: mineHabitIds,
    isSharedTemplate: true,
  );
  if (picked == null || !context.mounted) return;
  await ref.read(roomsControllerProvider).addSharedHabit(room, picked.id);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(s.roomHabitAddedConfirmation(picked.name))),
  );
}

/// Flips this account's own [RoomParticipant.notificationsMuted] for [room]
/// and confirms with a snackbar - the room-finish push's one per-room
/// override (see RoomsController.setRoomMuted's doc comment). A plain
/// top-level function for the same reason [_addHabitToPlan] is one.
Future<void> _toggleMute(
  BuildContext context,
  WidgetRef ref,
  RoomModel room,
  RoomParticipant mine,
) async {
  final s = S.of(context);
  HapticFeedback.selectionClick();
  final next = !mine.notificationsMuted;
  await ref.read(roomsControllerProvider).setRoomMuted(room.code, next);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content:
          Text(next ? s.roomMutedConfirmation : s.roomUnmutedConfirmation),
    ),
  );
}

/// The gathering state: who's in, and — for the leader only — the controls
/// to pick exactly when it begins. Two very different looks depending on
/// whether a moment's been picked yet: calm emerald "come gather" framing
/// before ([_EmptyLobbyCard]), the same gold "something's about to happen"
/// framing every other countdown on this screen already uses, after (see
/// [_ScheduledLobbyCard]). Stateful now (it used to be a plain
/// ConsumerWidget) purely to drive the live per-second countdown and the
/// client-side auto-start check — see [_LobbyCardState._onTick].
class _LobbyCard extends ConsumerStatefulWidget {
  final RoomModel room;
  final bool isLeader;
  final int memberCount;
  const _LobbyCard({
    required this.room,
    required this.isLeader,
    required this.memberCount,
  });

  @override
  ConsumerState<_LobbyCard> createState() => _LobbyCardState();
}

class _LobbyCardState extends ConsumerState<_LobbyCard> {
  Timer? _ticker;
  // Guards against re-sending RoomsController.autoStartIfDue's write on
  // every remaining tick while this device waits for its own write to
  // round-trip back through roomProvider's stream — without this, a slow
  // connection could fire the same write several times in the second or
  // two before the snapshot updates and widget.room.isLobby finally flips.
  bool _autoStartRequested = false;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _LobbyCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A freshly picked or changed moment needs a fresh countdown and a
    // fresh chance to auto-start — reusing the old timer as-is would keep
    // counting down to whatever was picked first.
    if (oldWidget.room.scheduledStartAt != widget.room.scheduledStartAt) {
      _autoStartRequested = false;
      _syncTicker();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _syncTicker() {
    _ticker?.cancel();
    _ticker = null;
    if (widget.room.scheduledStartAt == null) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    // Check right away too, rather than waiting a full second — covers
    // reopening this screen after the moment already passed while nobody
    // else's device happened to be watching at the time.
    _onTick();
  }

  void _onTick() {
    if (!mounted) return;
    if (widget.room.scheduledStartDue && !_autoStartRequested) {
      _autoStartRequested = true;
      ref.read(roomsControllerProvider).autoStartIfDue(widget.room).ignore();
    }
    setState(() {}); // Repaints the countdown digits for the new second.
  }

  Future<void> _openScheduleSheet() async {
    HapticFeedback.selectionClick();
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _ScheduleStartSheet(),
    );
    if (picked == null || !mounted) return;
    HapticFeedback.mediumImpact();
    await ref.read(roomsControllerProvider).scheduleStart(widget.room, picked);
  }

  Future<void> _confirmStartNow() async {
    HapticFeedback.mediumImpact();
    final s = S.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.roomStartConfirmTitle),
        content: Text(s.roomStartConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.habitDeleteLinkedRoomCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: GameColors.emerald,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.roomStartAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    HapticFeedback.heavyImpact();
    await ref.read(roomsControllerProvider).startRoom(widget.room);
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    if (room.scheduledStartAt == null) {
      return _EmptyLobbyCard(
        memberCount: widget.memberCount,
        isLeader: widget.isLeader,
        onPickTime: _openScheduleSheet,
      );
    }
    return _ScheduledLobbyCard(
      scheduledStartAt: room.scheduledStartAt!,
      isLeader: widget.isLeader,
      onChangeTime: _openScheduleSheet,
      onStartNow: _confirmStartNow,
    );
  }
}

/// Before a start time is picked: who's in, and — leader only — the CTA
/// that opens [_ScheduleStartSheet]. Everyone else now gets an explicit
/// "waiting on the leader" line instead of the banner simply trailing off
/// with nothing else on screen.
class _EmptyLobbyCard extends StatelessWidget {
  final int memberCount;
  final bool isLeader;
  final VoidCallback onPickTime;
  const _EmptyLobbyCard({
    required this.memberCount,
    required this.isLeader,
    required this.onPickTime,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GameColors.emerald.withOpacity(gp.dark ? 0.10 : 0.08),
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: GameColors.emerald.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.groups_rounded,
                  size: 20, color: GameColors.emerald),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s.roomLobbyBanner(memberCount),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: gp.textPrimary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isLeader ? s.roomLobbyLeaderHint : s.roomWaitingForLeaderSchedule,
            style: TextStyle(fontSize: 12, color: gp.textSec, height: 1.4),
          ),
          if (isLeader) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: GameColors.emerald,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: onPickTime,
                icon: const Icon(Icons.schedule_rounded, size: 20),
                label: Text(
                  s.roomPickStartTimeAction,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Once the leader's picked a moment: a live, ticking, gamified countdown
/// every member watches update in real time. "Synced" purely because it's
/// recomputed fresh from the same Firestore-streamed [scheduledStartAt] on
/// every device each second (via _LobbyCardState's Timer) — the countdown
/// value itself is never written anywhere, only the target moment is.
class _ScheduledLobbyCard extends StatelessWidget {
  final DateTime scheduledStartAt;
  final bool isLeader;
  final VoidCallback onChangeTime;
  final VoidCallback onStartNow;
  const _ScheduledLobbyCard({
    required this.scheduledStartAt,
    required this.isLeader,
    required this.onChangeTime,
    required this.onStartNow,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    var remaining = scheduledStartAt.difference(DateTime.now());
    if (remaining.isNegative) remaining = Duration.zero;
    final days = remaining.inDays;
    final hours = remaining.inHours % 24;
    final minutes = remaining.inMinutes % 60;
    final seconds = remaining.inSeconds % 60;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: GameColors.gold.withOpacity(gp.dark ? 0.10 : 0.08),
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: GameColors.gold.withOpacity(0.35)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bolt_rounded, size: 15, color: GameColors.gold)
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .fadeIn(duration: 700.ms, begin: 0.4),
              const SizedBox(width: 6),
              Text(
                s.roomCountdownTitle,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: gp.textPrimary,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Pinned to LTR regardless of app locale: a countdown's box order
          // (Days→Hours→Min→Sec, left to right) is a numeric/clock
          // convention, not translated text — under Arabic's RTL, a plain
          // Row mirrors the whole sequence (Sec first, Days last visually),
          // which reads as backwards rather than "translated". Only this
          // Row is pinned; each _CountdownBox's own label text still renders
          // in Arabic normally.
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (days > 0) ...[
                  _CountdownBox(value: days, label: s.roomCountdownDaysLabel),
                  const SizedBox(width: 8),
                ],
                _CountdownBox(value: hours, label: s.roomCountdownHoursLabel),
                const SizedBox(width: 8),
                _CountdownBox(value: minutes, label: s.roomCountdownMinLabel),
                const SizedBox(width: 8),
                _CountdownBox(value: seconds, label: s.roomCountdownSecLabel),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            s.roomCountdownAt(_formatScheduledMoment(scheduledStartAt, s.isAr)),
            style: TextStyle(
                fontSize: 12, color: gp.textSec, fontWeight: FontWeight.w600),
          ),
          if (isLeader) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    onChangeTime();
                  },
                  child: Text(s.roomChangeTimeAction),
                ),
                Container(
                  width: 1,
                  height: 14,
                  color: gp.border,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                ),
                TextButton(
                  onPressed: onStartNow,
                  child: Text(s.roomStartNowAction),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
