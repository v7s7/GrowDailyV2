import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/room_finale_seen_provider.dart';
import '../../../core/theme/game_theme.dart';
import '../models/room_model.dart';
import '../notifiers/room_plan_notices.dart';
import '../notifiers/rooms_notifier.dart';
import '../screens/room_detail_screen.dart';

/// Tells you your challenge finished, the next time you open the app.
///
/// A room ending used to announce itself to nobody: the podium sits on the
/// room screen and only appears if you happen to go looking. A 90-day
/// challenge could finish and stay unnoticed for days.
///
/// Deliberately not a scheduled notification. One queued for the end date
/// can't know the room was deleted, extended, or that you left — it fires
/// regardless, about a room that may not exist any more. This asks the
/// question at open time instead, against live data
/// ([unseenFinishedRoomsProvider]), so a room that isn't there simply has
/// nothing to say.
///
/// Renders nothing itself. Mount it once, anywhere below the app's providers
/// and above a Navigator (see main.dart's _OnboardingOrGrid).
///
/// Since 2026-09-22 it also tells a member when their leader removed a habit
/// from the plan, or brought one back ([roomPlanNoticesProvider]): Aziz
/// wanted a popup on open rather than a push. Same one-at-a-time rule, so a
/// finale and a plan change never stack.
class RoomFinaleAnnouncer extends ConsumerStatefulWidget {
  final Widget child;
  const RoomFinaleAnnouncer({super.key, required this.child});

  @override
  ConsumerState<RoomFinaleAnnouncer> createState() =>
      _RoomFinaleAnnouncerState();
}

class _RoomFinaleAnnouncerState extends ConsumerState<RoomFinaleAnnouncer> {
  ProviderSubscription<List<RoomModel>>? _sub;
  ProviderSubscription<List<RoomPlanNotice>>? _planSub;

  @override
  void initState() {
    super.initState();
    // listenManual with fireImmediately, not a listen() inside build: a room
    // that finished while the app was closed is already in the provider by
    // the time this mounts, so waiting for a *change* would announce nothing.
    _sub = ref.listenManual<List<RoomModel>>(
      unseenFinishedRoomsProvider,
      (previous, next) {
        if (next.isEmpty) return;
        // After the frame — this can fire while the provider graph is still
        // settling, and pushing a route mid-build throws.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _announce(next.first);
        });
      },
      fireImmediately: true,
    );
    _planSub = ref.listenManual<List<RoomPlanNotice>>(
      roomPlanNoticesProvider,
      (previous, next) {
        if (next.isEmpty) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _announcePlanChange().ignore();
        });
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _sub?.close();
    _planSub?.close();
    super.dispose();
  }

  /// The first plan change this device has not shown yet, if any. Checked
  /// against the persisted record at the moment of showing, so a change
  /// seen once never pops up again, and the next one waits its turn behind
  /// whatever dialog is already up.
  Future<void> _announcePlanChange() async {
    if (_showing || !mounted) return;
    final pending = ref.read(roomPlanNoticesProvider);
    if (pending.isEmpty) return;
    _showing = true;
    try {
      await loadRoomPlanNoticesSeen(ref);
      final seen = ref.read(roomPlanNoticesSeenProvider);
      final notice = pending.where((n) => !seen.contains(n.key)).firstOrNull;
      if (notice == null || !mounted) return;
      HapticFeedback.lightImpact();
      final open = await _showPlanChangeDialog(context, notice);
      // Seen either way, like the finale: "OK" means "I know", and the room
      // shows the plan as it now stands whenever they look. Recorded before
      // the room is opened, so a push-and-pop cannot show it twice. After an
      // await, so only while this is still mounted: ref on a disposed state
      // throws.
      if (!mounted) return;
      markRoomPlanNoticeSeen(ref, notice.key);
      if (open == true && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RoomDetailScreen(code: notice.room.code),
          ),
        );
      }
    } finally {
      _showing = false;
    }
    // Another change may be waiting (two habits removed at once), or a
    // finale that arrived while this was up: one more pass, each still one
    // at a time.
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final finished = ref.read(unseenFinishedRoomsProvider);
        if (finished.isNotEmpty) {
          _announce(finished.first);
          return;
        }
        _announcePlanChange().ignore();
      });
    }
  }

  /// One at a time, and never while another is already up. The provider can
  /// legitimately hold several finished rooms (you can be in more than one),
  /// and stacking dialogs on top of each other is not an announcement, it's
  /// an ambush — the next one gets its turn on the next open.
  bool _showing = false;

  Future<void> _announce(RoomModel room) async {
    if (_showing || !mounted) return;
    _showing = true;
    HapticFeedback.mediumImpact();
    final open = await _showFinaleDialog(context, room);
    // Marked seen either way. "Not now" means "I know it finished", not
    // "ask me again every launch" — the room's own finale card is still
    // there whenever they want it.
    await markRoomFinaleSeen(ref, room.code);
    if (!mounted) {
      _showing = false;
      return;
    }
    if (open == true) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => RoomDetailScreen(code: room.code)),
      );
    }
    if (mounted) {
      _showing = false;
      // A plan change that arrived while the finale was up gets its turn.
      _announcePlanChange().ignore();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Returns true if they chose to open the room, false/null otherwise.
Future<bool?> _showFinaleDialog(BuildContext context, RoomModel room) {
  final s = S.of(context);
  final gp = context.gp;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: gp.surfaceHigh,
      icon: Icon(Icons.emoji_events_rounded, color: context.gp.goldInk, size: 32),
      title: Text(
        s.roomEndedTitle,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: gp.textPrimary,
        ),
      ),
      content: Text(
        s.roomFinaleDialogBody(room.name),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13.5, height: 1.5, color: gp.textSec),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(s.roomFinaleDismiss,
              style: TextStyle(color: gp.textTert)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: GameColors.gold,
            foregroundColor: GameColors.onGold,
          ),
          child: Text(s.roomFinaleShow),
        ),
      ],
    ),
  );
}

/// The plan-change popup. Returns true if they chose to open the room.
///
/// Says what changed, from when, and, for a removal, that their earlier days
/// are kept and (if they had it linked) that the habit stays in their own
/// list. Stated as facts, no blame and no verdict (see reminder_copy.dart's
/// rule), because nothing here is anything the member did.
Future<bool?> _showPlanChangeDialog(
  BuildContext context,
  RoomPlanNotice notice,
) {
  final s = S.of(context);
  final gp = context.gp;
  final removed = notice.kind == RoomPlanNoticeKind.removed;
  final body = removed
      ? [
          notice.countsToday
              ? s.roomPlanNoticeRemovedToday(notice.habitName, notice.room.name)
              : s.roomPlanNoticeRemoved(notice.habitName, notice.room.name),
          notice.hadLinked
              ? s.roomPlanNoticeKeptHabit
              : s.roomPlanNoticeDaysKept,
        ].join('\n\n')
      : s.roomPlanNoticeRestored(notice.habitName);
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: gp.surfaceHigh,
      icon: Icon(
        removed
            ? Icons.playlist_remove_rounded
            : Icons.playlist_add_check_rounded,
        color: context.gp.goldInk,
        size: 30,
      ),
      title: Text(
        s.roomPlanNoticeTitle,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: gp.textPrimary,
        ),
      ),
      content: Text(
        body,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13.5, height: 1.5, color: gp.textSec),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            s.roomPlanNoticeOpenRoom,
            style: TextStyle(color: gp.textTert),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, false),
          style: FilledButton.styleFrom(
            backgroundColor: GameColors.gold,
            foregroundColor: GameColors.onGold,
          ),
          child: Text(s.roomPlanNoticeOk),
        ),
      ],
    ),
  );
}
