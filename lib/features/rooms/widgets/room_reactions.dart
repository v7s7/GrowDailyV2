import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/victory_burst.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../models/room_model.dart';
import '../notifiers/rooms_notifier.dart';
import '../../../shared/widgets/app_snackbar.dart';

/// Rooms Alive, Phase 1 (client-side only, in-app - see the bottom of this
/// doc comment for Phase 2, real push, which now also exists). Turns
/// [roomParticipantsProvider]'s
/// already-live Firestore stream (no new infra — RoomDetailScreen was
/// already re-rendering on every teammate's update) into two in-the-moment
/// reactions: a teammate finishing today's linked habit(s) while you're
/// looking at the room, and a teammate joining mid-session. Both are
/// edge-triggered off a snapshot diff, the same prev/next shape
/// registerDashboardReactions (dashboard/widgets/reaction_overlays.dart)
/// already uses for level-ups/achievements/streak milestones — this is
/// that exact pattern applied to a Room instead of the Dashboard.
///
/// Session-scoped, not persisted, and needs no manual "first load" guard:
/// ref.listen's `prev` is the stream's *previous* AsyncValue, which is
/// still AsyncLoading (not AsyncData) on the very first real emission —
/// `prev?.asData?.value` is therefore null for exactly that one call, and
/// the early return below skips it. So the first time this ever reaches the
/// diff loop, both snapshots are already real data, meaning "3 people
/// already done today" on room-open can never misfire as three fresh
/// celebrations — only a change *after* that point celebrates.
///
/// Call once from the room detail screen's build (see _RoomBody in
/// room_detail_screen_lobby.dart) — ref.listen is safe to call on every
/// build, same as registerDashboardReactions already is from GridScreen/
/// DashboardScreen; Riverpod only actually attaches the listener once per
/// element.
///
/// Phase 2, now built: the finish moment (not the join moment - that one's
/// still in-app only) also reaches you as a real push when the app is
/// closed, via firebase_messaging + functions/index.js's notifyRoomFinish
/// Callable function - called directly by RoomsController the instant this
/// device's own write flips allDoneToday to true (not a Firestore trigger
/// watching for that write - see index.js's own doc comment for why that
/// approach had to be abandoned) - see PushNotificationService's own doc
/// comment for the client half, and
/// NotificationSettings.roomActivityEnabled for the Settings toggle/quiet-
/// hours handling. This file's in-app reaction and that push are two
/// independent mechanisms for the same underlying event, deliberately not
/// unified: whoever's already looking at this exact room gets the instant,
/// no-server-round-trip version here; everyone else in the room gets the
/// push instead (see PushNotificationService.currentlyOpenRoomCode, which
/// suppresses the push specifically for whoever this file is already
/// covering).
void registerRoomReactions(
  BuildContext context,
  WidgetRef ref,
  RoomModel room,
) {
  ref.listen<AsyncValue<List<RoomParticipant>>>(
    roomParticipantsProvider(room.code),
    (prev, next) {
      final prevList = prev?.asData?.value;
      final nextList = next.asData?.value;
      if (prevList == null || nextList == null) return;

      final myUid = ref.read(authStateProvider).asData?.value?.uid;
      final prevByUid = {for (final p in prevList) p.uid: p};
      final todayKey = DateTime.now().effectiveDay.toDateKey();

      for (final p in nextList) {
        // Your own completion already gets its own confetti from
        // registerDashboardReactions the instant you tap the habit — a
        // second burst here for the same action would be a duplicate, not
        // a new celebration.
        if (p.uid == myUid) continue;

        final before = prevByUid[p.uid];
        if (before == null) {
          HapticFeedback.selectionClick();
          _showRoomReactionSnackBar(
            context,
            icon: Icons.person_add_alt_1_rounded,
            color: GameColors.iconXp,
            text: S.of(context).roomReactionJoined(p.displayName),
          );
          continue;
        }

        // isFullyDone alone isn't enough: it's trivially true on a day
        // nothing was scheduled, so a teammate whose weekly quota is already
        // met (their remaining days become excused rest days - see
        // weeklyQuotaScheduledDays) would set off a fresh "finished!" burst
        // on each of them, for a day they did nothing. The celebration has
        // to mean they actually did something.
        final wasDone = before.isFullyDone(todayKey);
        final isDoneNow = p.isFullyDone(todayKey);
        if (isDoneNow && !wasDone && p.didCompleteAnythingOn(todayKey)) {
          HapticFeedback.mediumImpact();
          final size = MediaQuery.of(context).size;
          showVictoryBurst(
            context,
            Offset(size.width / 2, size.height * 0.3),
            particleCount: 12,
          );
          _showRoomReactionSnackBar(
            context,
            icon: Icons.local_fire_department_rounded,
            color: GameColors.emerald,
            text: S.of(context).roomReactionFinished(p.displayName),
          );
        }
      }
    },
  );
}

// Named to match reaction_overlays.dart's showLevelUpSnackBar/
// showPerfectDaySnackBar/showStreakFreezeProtectedSnackBar convention —
// this codebase calls the widget a SnackBar everywhere else; "Toast" is
// Android terminology this Flutter app doesn't otherwise use.
void _showRoomReactionSnackBar(
  BuildContext context, {
  required IconData icon,
  required Color color,
  required String text,
}) {
  final gp = context.gp;
  ScaffoldMessenger.of(context).showOne(
    SnackBar(
      content: Row(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: gp.textPrimary),
            ),
          ),
        ],
      ),
      backgroundColor: gp.surfaceHigh,
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GameSpacing.buttonRadius)),
    ),
  );
}
