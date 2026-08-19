import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/app_guide_provider.dart';
import '../../../core/services/local_store_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/push_notification_service.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/coach_mark_overlay.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../models/room_model.dart';
import '../notifiers/rooms_notifier.dart';
import '../widgets/create_room_sheet.dart';
import '../widgets/join_room_sheet.dart';
import 'room_detail_screen.dart';

// Hive settings-box key for "the highest RoomModel.sharedHabits.length
// RoomsHubScreen has already fired _maybeNotifyNewSharedHabit's local
// notification for, per room code" - see that function's own doc comment.
// One shared map (code -> count) rather than one key per room, matching
// LocalStoreService's existing whole-map-per-key shape.
const _roomNotifiedHabitCountsKey = 'roomNotifiedHabitCounts';

/// Fires a local "your leader added a habit" notification for [code] at
/// most once per distinct RoomModel.sharedHabits.length - not true push
/// (see NotificationService.showRoomHabitAdded's own doc comment), so this
/// only actually runs the next time this device is open and this screen's
/// stream ticks. Without the per-count guard here, this would re-fire on
/// every single participants/room update this screen already streams
/// constantly (someone else's completion, a progress resync...), not just
/// the one moment a habit was actually added.
Future<void> _maybeNotifyNewSharedHabit({
  required String code,
  required String roomName,
  required String habitName,
  required int sharedHabitCount,
  required bool isAr,
}) async {
  final stored = await LocalStoreService.getSettingsMap(_roomNotifiedHabitCountsKey);
  final lastNotified = (stored[code] as num?)?.toInt() ?? 0;
  if (sharedHabitCount <= lastNotified) return;
  await LocalStoreService.putSettingsMap(_roomNotifiedHabitCountsKey, {
    ...stored,
    code: sharedHabitCount,
  });
  await NotificationService.instance.showRoomHabitAdded(
    roomName: roomName,
    habitName: habitName,
    isAr: isAr,
  );
}

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
    // First real Rooms touchpoint - the sensible contextual moment to ask
    // for the room-finish push permission (same "ask when it makes sense
    // in the flow" philosophy every other permission prompt in this app
    // follows), rather than at raw app boot before Rooms means anything to
    // someone. No-ops instantly for a guest anyway - see
    // PushNotificationService.registerForUser's own doc comment for why a
    // guest is simply never registered.
    if (!isGuest) {
      PushNotificationService.instance.requestPermissionAndInit();
    }

    // Second half of App Guide's discoverRooms lesson (see
    // roomsActionButtonsKeyProvider's doc comment) — only for a signed-in
    // account, since a guest never reaches the Create/Join row at all
    // (isGuest below swaps it out entirely for _GuestGate, whose own
    // "sign up" button is already the one obvious next action).
    final activeLesson = ref.watch(activeAppGuideLessonProvider);
    final showActionsCoachMark =
        !isGuest && activeLesson == AppGuideLesson.discoverRooms;
    void clearRoomsLesson() {
      if (ref.read(activeAppGuideLessonProvider) == AppGuideLesson.discoverRooms) {
        ref.read(activeAppGuideLessonProvider.notifier).state = null;
      }
    }
    // A guest lands on _GuestGate instead, with nothing left here for the
    // lesson to circle — its own "sign up" button is already the obvious
    // next step, so this counts as the lesson's natural end for a guest.
    // Without this, the flag would stay stuck on discoverRooms forever for
    // a guest (nothing else here ever clears it), re-showing Profile's
    // Rooms-row coach-mark every single time they came back to that tab.
    // Deferred a frame rather than set directly here, since mutating
    // provider state mid-build isn't safe.
    if (isGuest && activeLesson == AppGuideLesson.discoverRooms) {
      WidgetsBinding.instance.addPostFrameCallback((_) => clearRoomsLesson());
    }

    return Stack(
      children: [
        Scaffold(
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
                  key: ref.watch(roomsActionButtonsKeyProvider),
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
                        clearRoomsLesson();
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
                        clearRoomsLesson();
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
        ),
        if (showActionsCoachMark)
          CoachMarkOverlay(
            targetKey: ref.watch(roomsActionButtonsKeyProvider),
            title: s.isAr ? 'أنشئ غرفة أو انضم لواحدة' : 'Create a room or join one',
            body: s.isAr
                ? 'اختر أحد الخيارين للبدء.'
                : 'Pick either one to get started.',
            onDismiss: () => ref.read(activeAppGuideLessonProvider.notifier).state = null,
          ),
      ],
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
    final starred = ref.watch(myStarredRoomCodesProvider).valueOrNull ?? const [];

    return codes.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(
        child: Text(s.roomGenericError, style: TextStyle(color: gp.textSec)),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const _EmptyRooms();
        }
        // Starred rooms float to the top; everything else keeps whatever
        // order myRoomCodesProvider already had it in - see
        // sortStarredFirst's doc comment.
        final ordered = sortStarredFirst(list, starred.toSet());
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
          itemCount: ordered.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _RoomListTile(
            code: ordered[i],
            isStarred: starred.contains(ordered[i]),
          ),
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
  final bool isStarred;
  const _RoomListTile({required this.code, required this.isStarred});

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
    // Kept for the case it was written for — a room deleted while this
    // list is on screen — but it is NOT what heals a code that was already
    // dead when the screen opened. See the data branch below.
    ref.listen(roomProvider(code), (previous, next) {
      if (next.hasValue && next.value == null) {
        ref.read(roomsControllerProvider).forgetRoom(code);
      }
    });

    // Same per-room side-effect pattern as the forgetRoom listener above -
    // watches the participants stream (already watched for real below via
    // roomParticipantsProvider) so a shared-plan habit the leader adds
    // while this account isn't actively looking at that specific room's
    // detail screen still gets flagged here instead of only ever showing
    // up once they happen to open it (see _MyPlanCard's own in-room
    // banner for that narrower case).
    ref.listen(roomParticipantsProvider(code), (previous, next) {
      final room = ref.read(roomProvider(code)).valueOrNull;
      if (room == null ||
          room.habitMode != RoomHabitMode.shared ||
          room.sharedHabits.isEmpty) {
        return;
      }
      final uid = ref.read(authStateProvider).asData?.value?.uid;
      final mineList = next.valueOrNull?.where((p) => p.uid == uid).toList();
      if (mineList == null || mineList.isEmpty) return;
      if (mineList.first.linkedHabitIds.length >= room.sharedHabits.length) return;
      _maybeNotifyNewSharedHabit(
        code: code,
        roomName: room.name,
        habitName: room.sharedHabits.last.name,
        sharedHabitCount: room.sharedHabits.length,
        isAr: s.isAr,
      ).ignore();
    });

    return roomAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (room) {
        if (room == null) {
          // The heal that actually fires. The listener above only reports
          // CHANGES after it registers, and this provider has almost
          // always settled long before this tile builds:
          // myLinkedRoomHabitsProvider watches roomProvider for every code
          // the account has and is held alive app-wide from the first
          // frame by Grid's room-badge column. So a dead room's
          // loading -> data(null) transition happens once, early, with
          // nobody listening, and the tile then rendered an invisible
          // nothing forever without ever cleaning the code up.
          //
          // The symptom was a room count that would not come down: the
          // profile's Rooms badge counts raw codes while the hub renders
          // one tile per code, so a room its leader had deleted showed as
          // five rooms in the badge and four on the screen, permanently.
          //
          // Post-frame because this is a build method, and through a
          // controller captured now rather than a later ref.read, so it
          // stays valid if the tile is gone by then. forgetRoom is an
          // arrayRemove, so repeating it is harmless.
          final controller = ref.read(roomsControllerProvider);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            controller.forgetRoom(code);
          });
          return const SizedBox.shrink();
        }
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
                    // A personal, this-account-only pin (see
                    // RoomsController.toggleStarRoom) - floats this room to
                    // the top of _MyRooms' list (sortStarredFirst), nothing
                    // any other member of the room ever sees. Its own
                    // IconButton so the tap is consumed here, never bubbling
                    // up to the tile's own onTap navigation below.
                    IconButton(
                      tooltip: isStarred ? s.roomUnstarTooltip : s.roomStarTooltip,
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        ref
                            .read(roomsControllerProvider)
                            .toggleStarRoom(code, !isStarred);
                      },
                      icon: Icon(
                        isStarred ? Icons.star_rounded : Icons.star_border_rounded,
                        size: 20,
                        color: isStarred ? GameColors.gold : gp.textTert,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      visualDensity: VisualDensity.compact,
                      splashRadius: 20,
                    ),
                    const SizedBox(width: 4),
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
                  borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
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
        borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
    );
  }
}
