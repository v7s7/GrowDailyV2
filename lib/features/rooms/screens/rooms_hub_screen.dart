import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../models/room_model.dart';
import '../notifiers/rooms_notifier.dart';
import '../widgets/create_room_sheet.dart';
import '../widgets/join_room_sheet.dart';
import 'room_detail_screen.dart';

/// Entry point pushed from Profile's "Rooms" row - lists every room this
/// account belongs to and offers Create/Join. Deliberately its own pushed
/// screen rather than a new bottom-nav tab (see the Profile row's own doc
/// comment) - Rooms is an occasional, opt-in feature, not something that
/// needs permanent nav-bar real estate next to Grid/Matrix/Focus/Profile.
class RoomsHubScreen extends ConsumerWidget {
  const RoomsHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final isGuest = ref.watch(guestModeProvider);

    return Scaffold(
      backgroundColor: gp.bg,
      appBar: AppBar(
        backgroundColor: gp.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(s.roomsTitle,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800, color: gp.textPrimary)),
      ),
      body: isGuest ? const _GuestGate() : const _MyRooms(),
      // Join promoted from a bare AppBar icon to a full button, matching
      // Create's own size/shape/prominence - both are equally "start
      // something with a room" actions, so neither should read as more
      // secondary than the other just because one used to be a plain
      // icon. Colored opposite on purpose (Create = colorScheme.primary/
      // gold, Join = colorScheme.secondary/xpBlue - both already-defined
      // theme roles, not new arbitrary colors) so the two stay visually
      // distinguishable at a glance despite being the same shape.
      floatingActionButton: isGuest
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.extended(
                  // Distinct, explicit heroTags required - two default-
                  // tagged FloatingActionButtons on the same route would
                  // hit Flutter's "multiple heroes share the same tag"
                  // assertion the moment this screen builds.
                  heroTag: 'roomsJoinFab',
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  foregroundColor: Theme.of(context).colorScheme.onSecondary,
                  onPressed: () async {
                    final code = await showJoinRoomSheet(context, ref);
                    if (code != null && context.mounted) {
                      Navigator.push(context,
                          MaterialPageRoute(builder: (_) => RoomDetailScreen(code: code)));
                    }
                  },
                  icon: const Icon(Icons.tag_rounded),
                  label: Text(s.roomJoinAction),
                ),
                const SizedBox(width: 12),
                FloatingActionButton.extended(
                  heroTag: 'roomsCreateFab',
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  onPressed: () async {
                    final code = await showCreateRoomSheet(context, ref);
                    if (code != null && context.mounted) {
                      Navigator.push(context,
                          MaterialPageRoute(builder: (_) => RoomDetailScreen(code: code)));
                    }
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: Text(s.roomCreateAction),
                ),
              ],
            ),
    );
  }
}

class _GuestGate extends ConsumerWidget {
  const _GuestGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: GameColors.gold.withOpacity(0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.emoji_events_rounded, size: 30, color: GameColors.gold),
            ),
            const SizedBox(height: 16),
            Text(
              s.roomGuestGateTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: gp.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              s.roomGuestGateBody,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: gp.textSec, height: 1.4),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                HapticFeedback.selectionClick();
                setGuestMode(ref, false);
                Navigator.of(context).popUntil((r) => r.isFirst);
              },
              child: Text(s.roomGuestGateAction),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyRooms extends ConsumerWidget {
  const _MyRooms();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final codes = ref.watch(myRoomCodesProvider);

    return codes.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(
        child: Text(s.roomGenericError, style: TextStyle(color: gp.textSec)),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const _EmptyRooms();
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _RoomListTile(code: list[i]),
        );
      },
    );
  }
}

class _EmptyRooms extends StatelessWidget {
  const _EmptyRooms();

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.groups_rounded, size: 48, color: gp.textTert),
            const SizedBox(height: 14),
            Text(
              s.roomsEmptyTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15.5, fontWeight: FontWeight.w800, color: gp.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              s.roomsEmptyBody,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: gp.textSec, height: 1.4),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 350.ms);
  }
}

class _RoomListTile extends ConsumerWidget {
  final String code;
  const _RoomListTile({required this.code});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final roomAsync = ref.watch(roomProvider(code));

    // Self-healing: a room this account used to belong to can vanish (the
    // leader deleted it) - once we see that for certain (loaded, not just
    // still-loading), quietly drop the dead code from this account's own
    // list instead of leaving a tile that can never open. See
    // RoomsController.forgetRoom's doc comment.
    ref.listen(roomProvider(code), (previous, next) {
      if (next.hasValue && next.value == null) {
        ref.read(roomsControllerProvider).forgetRoom(code);
      }
    });

    return roomAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (room) {
        if (room == null) return const SizedBox.shrink();
        final uid = ref.watch(authStateProvider).asData?.value?.uid;
        final participants = ref.watch(roomParticipantsProvider(code)).valueOrNull;
        final mine = participants?.where((p) => p.uid == uid);
        final myRatio =
            mine != null && mine.isNotEmpty ? mine.first.progressRatio(room) : 0.0;

        return InkWell(
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => RoomDetailScreen(code: code)));
          },
          child: Container(
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
                    Expanded(
                      child: Text(
                        room.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w800, color: gp.textPrimary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusPill(room: room, s: s),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  s.roomMemberCount(room.memberCount),
                  style: TextStyle(fontSize: 11.5, color: gp.textSec),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: LinearProgressIndicator(
                    value: myRatio,
                    backgroundColor: gp.border,
                    valueColor: AlwaysStoppedAnimation(GameColors.gold),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  final RoomModel room;
  final S s;
  const _StatusPill({required this.room, required this.s});

  @override
  Widget build(BuildContext context) {
    // Lifecycle first: a lobby/countdown room isn't "N days left" of
    // anything yet — say what it's actually doing. A lobby with a picked
    // start time gets its own compact "starts in ___" (see
    // formatCompactRemaining) instead of the generic Lobby label, so this
    // list already hints at the live countdown RoomDetailScreen shows in
    // full.
    final scheduledAt = room.scheduledStartAt;
    final label = room.isLobby
        ? (scheduledAt != null
            ? s.roomStartsInCompact(formatCompactRemaining(
                scheduledAt.difference(DateTime.now()),
                isAr: s.isAr,
              ))
            : s.roomLobbyPill)
        : room.isCountingDown
            ? s.roomStartsTomorrowPill
            : room.duration == RoomDuration.open
                ? s.roomOngoing
                : room.isEnded
                    ? s.roomEnded
                    : s.roomDaysLeft(room.daysRemaining);
    final color = room.isLobby ? GameColors.emerald : GameColors.gold;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
    );
  }
}
