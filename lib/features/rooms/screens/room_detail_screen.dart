import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// hide TextDirection: intl's own TextDirection enum (LTR/RTL/UNKNOWN) would
// otherwise collide with dart:ui/material's TextDirection (ltr/rtl) the
// moment either is referenced unqualified anywhere in this library (this
// file's part files included) - DateFormat and everything else this file
// uses from intl are unaffected.
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/room_finale_seen_provider.dart';
import '../../../core/services/push_notification_service.dart';
import '../../../core/services/share_service.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/calendar_month_scaffold.dart';
import '../../../shared/widgets/habit_limit_gate.dart';
import '../../../shared/widgets/victory_burst.dart';
import '../../../shared/widgets/xp_bar.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../../character/models/accessory.dart';
import '../../character/models/character_option.dart';
import '../../character/models/prestige_tier.dart';
import '../../character/widgets/character_avatar.dart';
import '../../character/widgets/prestige_mark.dart';
import '../../grid/notifiers/weekly_grid_notifier.dart' show weeklyGridProvider;
import '../../grid/screens/monthly_heatmap_screen.dart' show heatColor;
import '../../habits/catalog/islamic_habit_catalog.dart'
    show IslamicHabitTemplate;
import '../../habits/models/habit_model.dart' show HabitFrequencyType;
import '../../habits/models/weekly_quota_plan.dart';
import '../../habits/notifiers/custom_habits_notifier.dart'
    show habitListProvider, canAddHabits;
import '../models/room_model.dart';
import '../notifiers/room_moderation.dart';
import '../notifiers/rooms_notifier.dart';
import '../widgets/pick_own_habit_sheet.dart';
import '../widgets/report_member_sheet.dart';
import '../widgets/resolve_new_shared_habits_sheet.dart';
import '../widgets/room_reactions.dart';

part 'room_detail_screen_countdown_finale.dart';
part 'room_detail_screen_header_progress.dart';
part 'room_detail_screen_leaderboard_extend.dart';
part 'room_detail_screen_lobby.dart';
part 'room_detail_screen_participant_calendar.dart';

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

  @override
  void initState() {
    super.initState();
    // Tells PushNotificationService which room this device is actively
    // looking at, so a foreground room-finish push about *this* room is
    // skipped instead of duplicating room_reactions.dart's own in-app
    // reaction for the same moment - see that service's
    // currentlyOpenRoomCode doc comment.
    PushNotificationService.instance.currentlyOpenRoomCode = widget.code;
  }

  @override
  void dispose() {
    // Only clear it if it's still this room - if RoomDetailScreen A pushed
    // RoomDetailScreen B (not a real flow today, but cheap to guard
    // against), B's dispose firing after A's shouldn't blank out A's own
    // still-current code.
    if (PushNotificationService.instance.currentlyOpenRoomCode == widget.code) {
      PushNotificationService.instance.currentlyOpenRoomCode = null;
    }
    super.dispose();
  }

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
          isLeader ? s.roomLeaveConfirmBodyLeader : s.roomLeaveConfirmBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.roomLeaveConfirmCancel),
          ),
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
            child: Text(s.roomLeaveConfirmCancel),
          ),
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

    // For a room that has already FINISHED, ask when counting should pick up
    // again. Everything between the old ending and that day is recorded as a
    // pause and excluded from every score (RoomModel.pausedSpans), so a room
    // revived after a fortnight costs nobody the fourteen misses it used to.
    // Skipped entirely for a room still running — there is no gap to place.
    DateTime? resumeFrom;
    if (room.isEnded) {
      final today = DateTime.now().effectiveDay;
      resumeFrom = await showDatePicker(
        context: context,
        initialDate: today,
        firstDate: today,
        lastDate: today.add(const Duration(days: 365)),
        helpText: S.of(context).roomExtendResumeTitle,
      );
      // Backing out of the date step cancels the whole extension rather than
      // silently defaulting to today — the leader was mid-decision.
      if (resumeFrom == null || !mounted) return;
    }

    await ref
        .read(roomsControllerProvider)
        .extendRoom(room, picked == 0 ? null : picked, resumeFrom: resumeFrom);
    // This room is about to have a *second* ending, and the finale announcer
    // only ever fires once per room code (see markRoomFinaleSeen). Without
    // this, extending a room that already finished means its next finish is
    // announced to nobody — the whole point of extending is that the ending
    // still matters. Safe when the room hadn't ended yet: the code simply
    // isn't in the set and this is a no-op.
    await clearRoomFinaleSeen(ref, room.code);
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
        appBar: AppBar(
          backgroundColor: gp.bg,
          surfaceTintColor: Colors.transparent,
        ),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Scaffold(
        backgroundColor: gp.bg,
        appBar: AppBar(
          backgroundColor: gp.bg,
          surfaceTintColor: Colors.transparent,
        ),
        body: Center(
          child: Text(s.roomGenericError, style: TextStyle(color: gp.textSec)),
        ),
      ),
      data: (room) {
        if (room == null) {
          return Scaffold(
            backgroundColor: gp.bg,
            appBar: AppBar(
              backgroundColor: gp.bg,
              surfaceTintColor: Colors.transparent,
            ),
            body: Center(
              child: Text(
                s.roomGoneMessage,
                textAlign: TextAlign.center,
                style: TextStyle(color: gp.textSec),
              ),
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
