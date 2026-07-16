import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../../character/models/accessory.dart';
import '../../character/models/character_option.dart';
import '../../character/widgets/character_avatar.dart';
import '../../grid/screens/monthly_heatmap_screen.dart' show heatColor;
import '../../habits/notifiers/custom_habits_notifier.dart'
    show habitListProvider;
import '../models/room_model.dart';
import '../notifiers/rooms_notifier.dart';

/// The leaderboard - pushed for a single room, whether just-created (from
/// CreateRoomSheet), just-joined (from JoinRoomSheet), or tapped from
/// RoomsHubScreen's list. Every number on screen (RoomModel + every
/// RoomParticipant) streams live via roomProvider/roomParticipantsProvider,
/// so completions from other members show up here without any manual
/// refresh - pull-to-refresh only exists to trigger this device's own
/// linked-habit resync on demand (see [_syncIfNeeded]). Every linked habit
/// in both habit modes is a real habit in each participant's own Grid now
/// (see room_model.dart's top-of-file doc), so there's no separate manual
/// "mark done" action anywhere on this screen - completing it in Grid is
/// what moves this room's leaderboard.
class RoomDetailScreen extends ConsumerStatefulWidget {
  final String code;
  const RoomDetailScreen({super.key, required this.code});

  @override
  ConsumerState<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends ConsumerState<RoomDetailScreen> {
  // Guards syncLinkedHabitsProgress to once per screen visit - without this,
  // every rebuild triggered by the sync's own write (the participants
  // stream updates right after) would trigger another sync, forever.
  bool _hasAutoSynced = false;

  String? get _uid => ref.read(authStateProvider).asData?.value?.uid;

  RoomParticipant? _mine(List<RoomParticipant> participants) {
    final uid = _uid;
    if (uid == null) return null;
    final mine = participants.where((p) => p.uid == uid);
    return mine.isEmpty ? null : mine.first;
  }

  Future<void> _syncProgress(RoomModel room, RoomParticipant? mine) async {
    if (mine == null || mine.linkedHabitIds.isEmpty) return;
    await ref.read(roomsControllerProvider).syncLinkedHabitsProgress(room);
  }

  void _syncIfNeeded(RoomModel room, RoomParticipant? mine) {
    if (_hasAutoSynced) return;
    if (mine == null || mine.linkedHabitIds.isEmpty) return;
    _hasAutoSynced = true;
    _syncProgress(room, mine);
  }

  Future<void> _confirmLeave(RoomModel room) async {
    final s = S.of(context);
    // Leader leaving is a meaningfully different outcome (leadership
    // handoff, or room deletion if they're the last one left - see
    // RoomsController.leaveRoom) - worth a different confirm body so it's
    // never a surprise, not just a generic "leave" prompt regardless of
    // role.
    final isLeader = _uid != null && _uid == room.createdBy;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.roomLeaveConfirmTitle),
        content: Text(
            isLeader ? s.roomLeaveConfirmBodyLeader : s.roomLeaveConfirmBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.roomLeaveConfirmCancel)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: GameColors.error),
            child: Text(s.roomLeaveAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(roomsControllerProvider).leaveRoom(room);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _confirmDelete(RoomModel room) async {
    final s = S.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.roomDeleteConfirmTitle),
        content: Text(s.roomDeleteConfirmBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.roomLeaveConfirmCancel)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: GameColors.error),
            child: Text(s.roomDeleteAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(roomsControllerProvider).deleteRoom(room);
    if (mounted) Navigator.pop(context);
  }

  /// Leader-only: opens [_ExtendRoomSheet] and, once a length is picked,
  /// hands it straight to RoomsController.extendRoom - no separate confirm
  /// step, since picking a length *is* the confirmation (same one-tap
  /// pattern CreateRoomSheet's own duration chips already use). A null
  /// result means the sheet was dismissed without picking anything, not
  /// "extend to no end date" - see [_ExtendRoomSheet]'s doc comment for how
  /// that case is told apart from a genuine open-ended pick.
  Future<void> _confirmExtend(RoomModel room) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _ExtendRoomSheet(),
    );
    if (picked == null || !mounted) return;
    await ref
        .read(roomsControllerProvider)
        .extendRoom(room, picked == 0 ? null : picked);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(S.of(context).roomExtended)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final roomAsync = ref.watch(roomProvider(widget.code));

    return roomAsync.when(
      loading: () => Scaffold(
        backgroundColor: gp.bg,
        appBar: AppBar(backgroundColor: gp.bg, surfaceTintColor: Colors.transparent),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Scaffold(
        backgroundColor: gp.bg,
        appBar: AppBar(backgroundColor: gp.bg, surfaceTintColor: Colors.transparent),
        body: Center(child: Text(s.roomGenericError, style: TextStyle(color: gp.textSec))),
      ),
      data: (room) {
        if (room == null) {
          return Scaffold(
            backgroundColor: gp.bg,
            appBar: AppBar(backgroundColor: gp.bg, surfaceTintColor: Colors.transparent),
            body: Center(
              child: Text(s.roomGoneMessage,
                  textAlign: TextAlign.center, style: TextStyle(color: gp.textSec)),
            ),
          );
        }
        return _RoomBody(
          room: room,
          onSyncIfNeeded: _syncIfNeeded,
          onManualSync: _syncProgress,
          onLeave: () => _confirmLeave(room),
          onDelete: () => _confirmDelete(room),
          onExtend: () => _confirmExtend(room),
          mineOf: _mine,
        );
      },
    );
  }
}

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
          IconButton(
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: s.roomShareAction,
            onPressed: () {
              HapticFeedback.selectionClick();
              SharePlus.instance
                  .share(ShareParams(text: s.roomShareMessage(room.name, room.code)));
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'leave') onLeave();
              if (value == 'delete') onDelete();
              if (value == 'extend') onExtend();
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
                _RoomHeaderCard(room: room),
                if (mine != null && mine.linkedHabitIds.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _MyPlanCard(room: room, mine: mine),
                ],
                const SizedBox(height: 14),
                ...List.generate(sorted.length, (i) {
                  final p = sorted[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _LeaderboardRow(
                      rank: i + 1,
                      participant: p,
                      room: room,
                      isYou: p.uid == uid,
                      isLeader: p.uid == room.createdBy,
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RoomHeaderCard extends StatelessWidget {
  final RoomModel room;
  const _RoomHeaderCard({required this.room});

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
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: GameColors.gold.withOpacity(0.14),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(statusLabel,
                style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w700, color: GameColors.gold)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              s.roomMemberCount(room.memberCount),
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
    );
  }
}

/// This account's own linked habit(s) for [room], read-only - completing
/// them happens over in Grid, this is purely a "here's what counts, and
/// whether today's done yet" status card. Also hosts the show/hide toggle
/// for whether other participants can see which specific habit(s) these
/// are (see RoomsController.toggleHideDetails) - a decision only the
/// participant themself makes, so this card only ever renders for "mine".
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
    final names = mine.linkedHabitNames.where((n) => n.trim().isNotEmpty).toList();
    // A linked habit id that's no longer in this account's own Grid means
    // it was deleted there after being linked here - dailyDoneCount can
    // never advance again for that slot (syncTodayForHabit/
    // syncLinkedHabitsProgress both drive off real Grid squares, and a
    // deleted habit has none). There's deliberately no per-slot "pick a
    // replacement" control for this - leaving and rejoining already gives a
    // clean way to re-link from scratch (see RoomsController.leaveRoom/
    // joinRoom), so this is purely an explanation, not a fix-it-here UI.
    final myHabitIds = ref.watch(habitListProvider).map((h) => h.id).toSet();
    final hasDeletedLink = mine.linkedHabitIds
        .any((id) => !myHabitIds.contains(id));

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
          Row(
            children: [
              Expanded(
                child: Text(s.roomMyPlanTitle,
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800, color: gp.textPrimary)),
              ),
              Icon(
                doneToday
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 16,
                color: doneToday
                    ? GameColors.success
                    : partialToday
                        ? GameColors.gold
                        : gp.textTert,
              ),
              const SizedBox(width: 5),
              Text(
                doneToday
                    ? s.roomMarkedToday
                    : partialToday
                        ? s.roomPartialToday(todayCount, totalCount)
                        : s.roomNotDoneToday,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: doneToday
                        ? GameColors.success
                        : partialToday
                            ? GameColors.gold
                            : gp.textSec),
              ),
            ],
          ),
          if (names.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final name in names) _Tag(label: name, color: GameColors.gold),
              ],
            ),
          ],
          if (names.length > 1) ...[
            const SizedBox(height: 8),
            Text(s.roomPlanPartialCreditHint(names.length),
                style: TextStyle(fontSize: 10.5, color: gp.textTert, height: 1.3)),
          ],
          if (hasDeletedLink) ...[
            const SizedBox(height: 10),
            _WarningRow(text: s.roomLinkedHabitDeletedHint),
          ],
          const SizedBox(height: 10),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              HapticFeedback.selectionClick();
              ref
                  .read(roomsControllerProvider)
                  .toggleHideDetails(room.code, !mine.hideDetails)
                  .ignore();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    mine.hideDetails
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    size: 14,
                    color: gp.textTert,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    mine.hideDetails ? s.roomDetailsHidden : s.roomDetailsVisible,
                    style: TextStyle(fontSize: 11, color: gp.textTert),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact horizontal contribution strip for one participant, reusing the
/// exact same [heatColor] tiers the main Grid heatmap screen uses so the
/// visual language matches everywhere green history shows up. Each cell's
/// shade is proportional to that day's credit (see RoomParticipant.
/// creditFor) rather than plain binary - a day with only some linked
/// habits done shows a visibly lighter partial shade instead of looking
/// identical to a day with none done, so multi-habit progress reads at a
/// glance instead of only ever showing as all-or-nothing. Capped at the
/// most recent [_maxDays] so a long-running or open-ended room never
/// renders an unbounded row of cells.
class _MiniHeatmapStrip extends StatelessWidget {
  final RoomModel room;
  final RoomParticipant participant;
  const _MiniHeatmapStrip({required this.room, required this.participant});

  static const int _maxDays = 30;
  static const double _cell = 9;
  static const double _gap = 2.5;

  /// 0 (empty) or 1-4 ([heatColor]'s tiers) for a day's [credit]. Rounds
  /// any nonzero credit *up* to at least the lightest tier rather than
  /// down toward empty, so a single habit done out of several always shows
  /// as visibly different from a day with nothing done at all.
  static int _levelFor(double credit) {
    if (credit <= 0) return 0;
    return (credit * 4).ceil().clamp(1, 4);
  }

  @override
  Widget build(BuildContext context) {
    final dark = context.gp.dark;
    final totalDays = room.daysElapsed.clamp(1, _maxDays);
    final last = room.lastCountedDay;
    final days = List.generate(
      totalDays,
      (i) => last.subtract(Duration(days: totalDays - 1 - i)),
    );
    return SizedBox(
      height: _cell,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        physics: const ClampingScrollPhysics(),
        child: Row(
          children: [
            for (final day in days)
              Padding(
                padding: const EdgeInsets.only(right: _gap),
                child: Container(
                  width: _cell,
                  height: _cell,
                  decoration: BoxDecoration(
                    color: heatColor(
                        _levelFor(participant.creditFor(day.toDateKey())), dark),
                    borderRadius: BorderRadius.circular(2.5),
                    // isRealToday, not isToday: purely the "today" marker —
                    // see DateTimeGameExt.isRealToday's doc comment.
                    border: day.isRealToday
                        ? Border.all(color: GameColors.gold, width: 1)
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  final int rank;
  final RoomParticipant participant;
  final RoomModel room;
  final bool isYou;
  final bool isLeader;

  const _LeaderboardRow({
    required this.rank,
    required this.participant,
    required this.room,
    required this.isYou,
    required this.isLeader,
  });

  Color? get _medalColor => switch (rank) {
        1 => GameColors.gold,
        2 => const Color(0xFFB0B7C3),
        3 => const Color(0xFFC98A4B),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final ratio = participant.progressRatio(room);
    final character = CharacterCatalog.findByIdOrDefault(participant.characterId);
    final accessory = AccessoryCatalog.findById(participant.accessoryId);
    final medalColor = _medalColor;
    final showDetails = isYou || !participant.hideDetails;
    final streak = participant.currentStreak(room);
    final names =
        participant.linkedHabitNames.where((n) => n.trim().isNotEmpty).toList();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isYou ? GameColors.gold.withOpacity(0.06) : gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(
          color: isYou ? GameColors.gold.withOpacity(0.35) : gp.border,
          width: isYou ? 1 : 0.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: rank == 1
                  ? Icon(Icons.emoji_events_rounded, size: 20, color: GameColors.gold)
                  : Text(
                      '$rank',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: medalColor ?? gp.textTert,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 6),
          CharacterAvatar(character: character, accessory: accessory, height: 42),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        participant.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w800, color: gp.textPrimary),
                      ),
                    ),
                    if (isYou) ...[
                      const SizedBox(width: 6),
                      _Tag(label: s.roomYouLabel, color: GameColors.gold),
                    ],
                    if (isLeader) ...[
                      const SizedBox(width: 6),
                      _Tag(label: s.roomLeaderLabel, color: gp.textSec),
                    ],
                  ],
                ),
                if (showDetails && names.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    names.join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: gp.textSec),
                  ),
                ],
                const SizedBox(height: 7),
                _MiniHeatmapStrip(room: room, participant: participant),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(100),
                        child: LinearProgressIndicator(
                          value: ratio,
                          backgroundColor: gp.border,
                          valueColor: AlwaysStoppedAnimation(medalColor ?? GameColors.gold),
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Visible regardless of hideDetails, same as the heatmap
                    // and progress bar above - it's a count, not which habit
                    // is behind it, so there's nothing to hide here.
                    if (streak >= 1) ...[
                      Icon(Icons.local_fire_department_rounded,
                          size: 12, color: GameColors.iconStreak),
                      const SizedBox(width: 2),
                      Text(
                        '$streak',
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: GameColors.iconStreak),
                      ),
                      const SizedBox(width: 7),
                    ],
                    Text(
                      s.roomDayCount(participant.daysCompleted(room), room.daysElapsed),
                      style: TextStyle(fontSize: 10.5, color: gp.textTert),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('${(ratio * 100).round()}%',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: gp.textPrimary)),
          ),
        ],
      ),
    );
  }
}

/// Small inline warning row - see [_MyPlanCard]'s hasDeletedLink check, the
/// only current user of this.
class _WarningRow extends StatelessWidget {
  final String text;
  const _WarningRow({required this.text});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: GameColors.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: GameColors.error.withOpacity(0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 15, color: GameColors.error),
          const SizedBox(width: 7),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 11, color: gp.textSec, height: 1.35)),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  const _Tag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

/// Leader-only sheet for picking a fresh length for a fixed-duration room -
/// same 7/14/30/90/open-ended choices CreateRoomSheet's own duration chips
/// offer, so extending feels like the same decision as creating one, not a
/// new control to learn. Pops the picked length in days, or 0 for
/// open-ended (never a real day count, so it's a safe stand-in) - popping
/// plain `null` is reserved for "dismissed without picking anything" (the
/// default result of swiping the sheet away), which
/// _RoomDetailScreenState._confirmExtend relies on to tell "chose
/// open-ended" and "changed their mind" apart.
class _ExtendRoomSheet extends StatelessWidget {
  const _ExtendRoomSheet();

  static const List<int> _dayOptions = [7, 14, 30, 90];

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
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
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: gp.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(s.roomExtendTitle,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: gp.textPrimary)),
            const SizedBox(height: 6),
            Text(s.roomExtendBody,
                style: TextStyle(fontSize: 12.5, color: gp.textSec, height: 1.35)),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final days in _dayOptions)
                  _ExtendOptionChip(
                    label: s.daysCount(days),
                    onTap: () => Navigator.pop(context, days),
                  ),
                _ExtendOptionChip(
                  label: s.roomDurationOpenEnded,
                  onTap: () => Navigator.pop(context, 0),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ExtendOptionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ExtendOptionChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return InkWell(
      borderRadius: BorderRadius.circular(100),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: gp.surface,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: gp.border, width: 0.8),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: gp.textPrimary)),
      ),
    );
  }
}
